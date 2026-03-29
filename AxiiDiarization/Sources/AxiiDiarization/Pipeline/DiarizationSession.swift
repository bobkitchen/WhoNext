import Foundation
import Accelerate
import os

private let diarizationLog = Logger(subsystem: "com.axii.diarization", category: "session")

/// Core streaming orchestrator: accumulates audio, runs inference, clusters speakers.
///
/// Pipeline per `process()` / `finalize()`:
/// 1. Mel spectrogram on accumulated audio
/// 2. Sortformer inference → per-frame speaker probabilities
/// 3. Segment detection + merging
/// 4. For each segment: slice audio → fbank → WeSpeaker → embedding
/// 5. Cluster embeddings → speaker assignments
/// 6. Match against known speakers (guided diarization)
/// 7. Apply pin overrides
/// 8. Return `[DiarizationSegment]` with stable speaker IDs
public final class DiarizationSession {

    // MARK: - Properties

    private let pipeline: DiarizationPipeline
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000.0

    // Known speakers for guided diarization
    private var knownSpeakers: [any SpeakerProfile]

    // Pin overrides: (start, end) → speakerProfile
    private var pinOverrides: [(start: Double, end: Double, profile: any SpeakerProfile)] = []

    // Clustering state preserved across calls for stable IDs
    private var clusteringState = SpeakerClustering()
    private var speakerMatcher: SpeakerMatcher

    // Track enriched embeddings per known speaker
    private var enrichedEmbeddingsMap: [String: [[Float]]] = [:]

    // Sliding window: track how much audio we've already processed with Sortformer
    private var processedMelFrameCount: Int = 0
    private var allEmbeddings: [(segment: SegmentMerger.MergedSegment, embedding: [Float])] = []

    // MARK: - Init

    init(pipeline: DiarizationPipeline, knownSpeakers: [any SpeakerProfile]) {
        self.pipeline = pipeline
        self.knownSpeakers = knownSpeakers
        self.speakerMatcher = SpeakerMatcher(
            knownSpeakers: knownSpeakers,
            threshold: pipeline.clusteringThreshold
        )
    }

    // MARK: - Public API

    /// Append audio samples (16 kHz mono Float).
    public func addAudio(_ samples: [Float]) {
        audioBuffer.append(contentsOf: samples)
    }

    /// Incremental processing: re-clusters globally, returns stable speaker IDs.
    public func process() throws -> AxiiDiarizationResult {
        try runPipeline(isFinal: false)
    }

    /// Final processing: flushes any remaining audio and returns definitive results.
    public func finalize() throws -> AxiiDiarizationResult {
        try runPipeline(isFinal: true)
    }

    /// Pin specific time ranges to a known speaker (for merge operations).
    public func pinSegments(_ timeRanges: [(start: Double, end: Double)], toSpeaker: any SpeakerProfile) {
        for range in timeRanges {
            pinOverrides.append((start: range.start, end: range.end, profile: toSpeaker))
        }
    }

    /// Reprocess after pin changes — runs the full pipeline again.
    public func reprocess() throws -> AxiiDiarizationResult {
        try runPipeline(isFinal: false)
    }

    /// Match an embedding against the session's discovered + known speakers.
    public func matchSpeaker(embedding: [Float], threshold: Float) -> (any SpeakerProfile)? {
        speakerMatcher.match(embedding: embedding, threshold: threshold)
    }

    /// Get all embeddings collected for a known speaker during this session.
    public func enrichedEmbeddings(for profile: any SpeakerProfile) -> [[Float]]? {
        let embs = enrichedEmbeddingsMap[profile.id]
        return (embs?.isEmpty ?? true) ? nil : embs
    }

    // MARK: - Core Pipeline

    private func runPipeline(isFinal: Bool) throws -> AxiiDiarizationResult {
        let totalSamples = audioBuffer.count
        let audioDuration = Double(totalSamples) / sampleRate
        guard totalSamples >= Int(sampleRate * 0.5) else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 1: Generate mel spectrogram for Sortformer
        let allMelFrames = MelSpectrogram.compute(audioBuffer, sampleRate: sampleRate)
        guard !allMelFrames.isEmpty else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 2: Sortformer inference — sliding window optimization
        // Only process NEW mel frames since last call (unless final)
        let maxFrames = SortformerModel.maxInputFrames
        let hopSeconds = 160.0 / sampleRate  // 0.01s per mel frame
        let downsample = SortformerModel.downsampleFactor  // 8
        let outputFrameStep = hopSeconds * Double(downsample)  // 0.08s per output frame

        // For sliding window: start from where we left off, with overlap for boundary accuracy
        let overlapFrames = isFinal ? 0 : min(maxFrames / 2, processedMelFrameCount)
        let startFrame = isFinal ? 0 : max(0, processedMelFrameCount - overlapFrames)

        var newProbabilities: [[Float]] = []
        var windowOffset = startFrame

        while windowOffset < allMelFrames.count {
            let windowEnd = min(windowOffset + maxFrames, allMelFrames.count)
            let windowFrames = Array(allMelFrames[windowOffset..<windowEnd])

            let windowProbs = try pipeline.sortformerModel.predict(melFrames: windowFrames)
            newProbabilities.append(contentsOf: windowProbs)

            windowOffset += maxFrames
        }

        // Update processed frame count for next call
        if !isFinal {
            processedMelFrameCount = allMelFrames.count
        }

        guard !newProbabilities.isEmpty else {
            return AxiiDiarizationResult(segments: [])
        }

        // Diagnostic: Log Sortformer channel activity
        if !newProbabilities.isEmpty {
            let numChannels = newProbabilities[0].count
            var channelMaxes = [Float](repeating: 0, count: numChannels)
            var channelActiveFrames = [Int](repeating: 0, count: numChannels)
            for frame in newProbabilities {
                for ch in 0..<min(numChannels, frame.count) {
                    channelMaxes[ch] = max(channelMaxes[ch], frame[ch])
                    if frame[ch] >= 0.25 { channelActiveFrames[ch] += 1 }
                }
            }
            let channelReport = (0..<numChannels).map { ch in
                "ch\(ch): max=\(String(format: "%.2f", channelMaxes[ch])) active=\(channelActiveFrames[ch])/\(newProbabilities.count)"
            }.joined(separator: ", ")
            diarizationLog.info("[Sortformer] \(audioDuration, format: .fixed(precision: 1))s audio, \(newProbabilities.count) frames | \(channelReport)")
        }

        // Step 3: Detect segments via hysteresis thresholding
        // Use lower onset (0.25) to detect secondary speakers in mono mixed audio
        let startTimeOffset = isFinal ? 0.0 : Double(startFrame) * hopSeconds
        let rawSegments = SegmentDetector.detect(
            probabilities: newProbabilities,
            frameStep: outputFrameStep,
            onsetThreshold: 0.25,
            offsetThreshold: 0.65
        )

        // Diagnostic: Log raw segments per channel
        var segsByChannel: [Int: Int] = [:]
        for seg in rawSegments { segsByChannel[seg.speakerChannel, default: 0] += 1 }
        diarizationLog.info("[SegDetect] \(rawSegments.count) raw segments | by channel: \(segsByChannel.sorted(by: { $0.key < $1.key }).map { "ch\($0.key)=\($0.value)" }.joined(separator: ", "))")

        // Step 4: Merge segments (padding, min duration, gap merge)
        let mergedSegments = SegmentMerger.merge(
            rawSegments,
            padding: 0.2,
            minDuration: 0.3,
            maxGap: 0.5
        )

        // Diagnostic: Log merged segments per channel
        var mergedByChannel: [Int: Int] = [:]
        for seg in mergedSegments { mergedByChannel[seg.speakerChannel, default: 0] += 1 }
        diarizationLog.info("[SegMerge] \(mergedSegments.count) merged segments | by channel: \(mergedByChannel.sorted(by: { $0.key < $1.key }).map { "ch\($0.key)=\($0.value)" }.joined(separator: ", "))")

        // Step 5: Extract WeSpeaker embeddings for new segments
        var newSegmentEmbeddings: [(segment: SegmentMerger.MergedSegment, embedding: [Float])] = []

        for seg in mergedSegments {
            // Adjust segment times for sliding window offset
            let adjustedStart = seg.start + startTimeOffset
            let adjustedEnd = seg.end + startTimeOffset
            let adjustedSeg = SegmentMerger.MergedSegment(
                speakerChannel: seg.speakerChannel,
                start: adjustedStart,
                end: adjustedEnd
            )

            let startSample = Int(adjustedStart * sampleRate)
            let endSample = min(Int(adjustedEnd * sampleRate), totalSamples)
            guard endSample > startSample else { continue }

            let segmentAudio = Array(audioBuffer[startSample..<endSample])

            // Need at least 0.4s of audio for a meaningful embedding
            guard segmentAudio.count >= Int(sampleRate * 0.4) else { continue }

            let fbank = FbankFeatures.compute(segmentAudio, sampleRate: sampleRate)
            guard !fbank.isEmpty else { continue }

            if let embedding = try? pipeline.wespeakerModel.predict(fbankFrames: fbank) {
                newSegmentEmbeddings.append((segment: adjustedSeg, embedding: embedding))
            }
        }

        // For incremental calls, accumulate embeddings; for final, use all
        if isFinal {
            allEmbeddings = newSegmentEmbeddings
        } else {
            allEmbeddings.append(contentsOf: newSegmentEmbeddings)
            // Cap to prevent unbounded growth (keep most recent)
            let maxEmbeddings = 500
            if allEmbeddings.count > maxEmbeddings {
                allEmbeddings = Array(allEmbeddings.suffix(maxEmbeddings))
            }
        }

        let segmentEmbeddings = allEmbeddings

        guard !segmentEmbeddings.isEmpty else {
            diarizationLog.warning("[Pipeline] No embeddings extracted from \(mergedSegments.count) merged segments")
            return AxiiDiarizationResult(segments: [])
        }

        // Diagnostic: Log inter-embedding similarities
        let embeddings = segmentEmbeddings.map { $0.embedding }
        if embeddings.count >= 2 {
            var sims: [Float] = []
            for i in 0..<min(embeddings.count, 20) {
                for j in (i+1)..<min(embeddings.count, 20) {
                    sims.append(cosineSimilarity(embeddings[i], embeddings[j]))
                }
            }
            if !sims.isEmpty {
                let minSim = sims.min() ?? 0
                let maxSim = sims.max() ?? 0
                let avgSim = sims.reduce(0, +) / Float(sims.count)
                diarizationLog.info("[Embeddings] \(embeddings.count) total | similarity min=\(String(format: "%.3f", minSim)) max=\(String(format: "%.3f", maxSim)) avg=\(String(format: "%.3f", avgSim))")
            }
        } else {
            diarizationLog.info("[Embeddings] Only \(embeddings.count) embedding(s) — cannot compute similarity")
        }

        // Step 6: Cluster embeddings → speaker assignments
        let clusterLabels = clusteringState.cluster(
            embeddings: embeddings,
            threshold: pipeline.clusteringThreshold
        )

        // Diagnostic: Log clustering result
        let uniqueClusters = Set(clusterLabels)
        var clusterSizes: [Int: Int] = [:]
        for label in clusterLabels { clusterSizes[label, default: 0] += 1 }
        diarizationLog.info("[Clustering] \(uniqueClusters.count) clusters from \(embeddings.count) embeddings | sizes: \(clusterSizes.sorted(by: { $0.key < $1.key }).map { "c\($0.key)=\($0.value)" }.joined(separator: ", "))")

        // Step 7: Match clusters against known speakers
        var clusterEmbeddings: [Int: [[Float]]] = [:]
        for (idx, label) in clusterLabels.enumerated() {
            clusterEmbeddings[label, default: []].append(embeddings[idx])
        }

        // Compute centroids per cluster
        var clusterCentroids: [Int: [Float]] = [:]
        for (label, embs) in clusterEmbeddings {
            clusterCentroids[label] = centroid(embs)
        }

        // Map cluster labels to speaker IDs + identification
        var clusterToSpeaker: [Int: (id: String, identification: SpeakerIdentification, embedding: [Float]?)] = [:]
        for (label, center) in clusterCentroids {
            if let match = speakerMatcher.matchCluster(centroid: center, threshold: pipeline.clusteringThreshold) {
                clusterToSpeaker[label] = (
                    id: match.id,
                    identification: .autoMatched(speakerID: match.id, confidence: match.confidence),
                    embedding: center
                )
                // Collect enriched embeddings for known speakers
                if let embs = clusterEmbeddings[label] {
                    enrichedEmbeddingsMap[match.id, default: []].append(contentsOf: embs)
                }
            } else {
                let speakerId = "speaker_\(label)"
                clusterToSpeaker[label] = (
                    id: speakerId,
                    identification: .unknown,
                    embedding: center
                )
            }
        }

        // Step 8: Build output segments, applying pin overrides
        var resultSegments: [DiarizationSegment] = []

        for (idx, (seg, _)) in segmentEmbeddings.enumerated() {
            let label = clusterLabels[idx]

            // Check for pin override
            if let pinOverride = findPinOverride(for: seg.start, end: seg.end) {
                let speaker = Speaker(id: pinOverride.id, embedding: embeddings[idx])
                resultSegments.append(DiarizationSegment(
                    start: seg.start,
                    end: seg.end,
                    speaker: speaker,
                    identification: .pinned(speakerID: pinOverride.id)
                ))
                continue
            }

            if let info = clusterToSpeaker[label] {
                let speaker = Speaker(id: info.id, embedding: embeddings[idx])
                resultSegments.append(DiarizationSegment(
                    start: seg.start,
                    end: seg.end,
                    speaker: speaker,
                    identification: info.identification
                ))
            }
        }

        // Sort by start time
        resultSegments.sort { $0.start < $1.start }

        // Update speaker matcher with discovered clusters
        for (label, center) in clusterCentroids {
            if let info = clusterToSpeaker[label], case .unknown = info.identification {
                speakerMatcher.registerDiscoveredSpeaker(id: info.id, embedding: center)
            }
        }

        return AxiiDiarizationResult(segments: resultSegments)
    }

    // MARK: - Helpers

    private func findPinOverride(for start: Double, end: Double) -> (any SpeakerProfile)? {
        // A segment is pinned if any pin override covers > 50% of it
        let segDuration = end - start
        guard segDuration > 0 else { return nil }

        for pin in pinOverrides {
            let overlapStart = max(start, pin.start)
            let overlapEnd = min(end, pin.end)
            let overlap = max(0, overlapEnd - overlapStart)
            if overlap / segDuration > 0.5 {
                return pin.profile
            }
        }
        return nil
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func centroid(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        let dim = first.count
        var sum = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            for i in 0..<min(dim, emb.count) {
                sum[i] += emb[i]
            }
        }
        let n = Float(embeddings.count)
        var result = sum.map { $0 / n }
        // L2-normalize the centroid
        var norm: Float = 0
        vDSP_dotpr(result, 1, result, 1, &norm, vDSP_Length(dim))
        norm = sqrt(norm)
        if norm > 0 {
            vDSP_vsdiv(result, 1, &norm, &result, 1, vDSP_Length(dim))
        }
        return result
    }
}
