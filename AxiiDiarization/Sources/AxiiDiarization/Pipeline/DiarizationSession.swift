import Foundation
import Accelerate

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
        guard totalSamples >= Int(sampleRate * 0.5) else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 1: Generate mel spectrogram for Sortformer
        let allMelFrames = MelSpectrogram.compute(audioBuffer, sampleRate: sampleRate)
        guard !allMelFrames.isEmpty else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 2: Sortformer inference in windows of maxInputFrames (1024)
        // Each mel frame = hop/SR = 160/16000 = 0.01s, so 1024 frames = 10.24s
        let maxFrames = SortformerModel.maxInputFrames
        let hopSeconds = 160.0 / sampleRate  // 0.01s per mel frame
        let downsample = SortformerModel.downsampleFactor  // 8
        let outputFrameStep = hopSeconds * Double(downsample)  // 0.08s per output frame

        var allProbabilities: [[Float]] = []
        var windowOffset = 0

        while windowOffset < allMelFrames.count {
            let windowEnd = min(windowOffset + maxFrames, allMelFrames.count)
            let windowFrames = Array(allMelFrames[windowOffset..<windowEnd])

            let windowProbs = try pipeline.sortformerModel.predict(melFrames: windowFrames)
            allProbabilities.append(contentsOf: windowProbs)

            windowOffset += maxFrames
        }

        guard !allProbabilities.isEmpty else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 3: Detect segments via hysteresis thresholding
        let rawSegments = SegmentDetector.detect(
            probabilities: allProbabilities,
            frameStep: outputFrameStep,
            onsetThreshold: 0.4,
            offsetThreshold: 0.6
        )

        // Step 4: Merge segments (padding, min duration, gap merge)
        let mergedSegments = SegmentMerger.merge(
            rawSegments,
            padding: 0.2,
            minDuration: 0.25,
            maxGap: 0.5
        )

        // Step 5: Extract WeSpeaker embeddings for each segment
        var segmentEmbeddings: [(segment: SegmentMerger.MergedSegment, embedding: [Float])] = []

        for seg in mergedSegments {
            let startSample = Int(seg.start * sampleRate)
            let endSample = min(Int(seg.end * sampleRate), totalSamples)
            guard endSample > startSample else { continue }

            let segmentAudio = Array(audioBuffer[startSample..<endSample])

            // Need at least 0.4s of audio for a meaningful embedding
            guard segmentAudio.count >= Int(sampleRate * 0.4) else { continue }

            let fbank = FbankFeatures.compute(segmentAudio, sampleRate: sampleRate)
            guard !fbank.isEmpty else { continue }

            if let embedding = try? pipeline.wespeakerModel.predict(fbankFrames: fbank) {
                segmentEmbeddings.append((segment: seg, embedding: embedding))
            }
        }

        guard !segmentEmbeddings.isEmpty else {
            return AxiiDiarizationResult(segments: [])
        }

        // Step 6: Cluster embeddings → speaker assignments
        let embeddings = segmentEmbeddings.map { $0.embedding }
        let clusterLabels = clusteringState.cluster(
            embeddings: embeddings,
            threshold: pipeline.clusteringThreshold
        )

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
