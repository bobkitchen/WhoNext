import Foundation
import AVFoundation
import Accelerate

// Import FluidAudio for embedding extraction (selective imports to avoid type conflicts)
import class FluidAudio.DiarizerManager
import struct FluidAudio.DiarizerConfig
import struct FluidAudio.DiarizerModels

/// Online centroid-based speaker clustering engine.
///
/// Replaces agglomerative hierarchical clustering (AHC) with a streaming approach
/// inspired by NeMo's online diarization:
///
/// - Maintains per-speaker centroids updated with exponential moving average
/// - New segment → compare to K centroids (O(K), not O(N²) like AHC)
/// - Calendar attendee count → hard cap on max speakers
/// - Periodic re-clustering every 60s merges over-split speakers
/// - Minimum 1.5s segment length before extracting embeddings
///
/// Key advantages over AHC:
/// - O(K) per segment vs O(N²) for AHC — scales to long meetings
/// - Exponential moving average adapts to voice drift naturally
/// - Max speaker cap prevents phantom speaker multiplication
/// - Re-clustering corrects early errors without full rebuild
@MainActor
final class CentroidClusterer: ObservableObject, DiarizationEngine {

    // MARK: - Published State

    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0
    @Published private(set) var userSpeakerId: String?
    @Published var isProcessing = false
    @Published var lastError: Error?

    // MARK: - Configuration

    /// Cosine similarity threshold for assigning to existing centroid
    private let assignmentThreshold: Float

    /// Cosine similarity threshold for merging centroids during re-clustering
    private let mergeThreshold: Float

    /// Hard cap on number of speakers (from calendar attendee count)
    private let maxSpeakers: Int

    /// Exponential moving average factor for centroid updates (0.9 = slow adaptation)
    private let emaAlpha: Float = 0.9

    /// Minimum segment duration (seconds) for reliable embedding extraction
    private let minSegmentDuration: Float = 1.5

    /// Re-clustering interval in seconds
    private let reClusterInterval: TimeInterval = 60.0

    // MARK: - Speaker State

    /// Per-speaker centroids (speaker ID → embedding centroid)
    private var centroids: [String: [Float]] = [:]

    /// Per-speaker cumulative speaking time
    private var speakingTimes: [String: Float] = [:]

    /// Per-speaker segment count
    private var segmentCounts: [String: Int] = [:]

    /// Next speaker ID counter
    private var nextSpeakerId = 1

    /// Known/anchored speakers that cannot be re-assigned
    private var anchoredSpeakers: Set<String> = []

    // MARK: - Segment History

    /// All assigned segments for result reporting
    private var allSegments: [TimedSpeakerSegment] = []

    // MARK: - Embedding Extraction

    /// FluidAudio diarizer for embedding extraction from raw audio
    private var diarizerManager: DiarizerManager?
    private var isInitialized = false

    // MARK: - Audio Accumulation

    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0
    private let chunkDuration: TimeInterval = 10.0
    private var streamPosition: TimeInterval = 0.0

    /// Resampling converter
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // MARK: - Re-clustering

    private var lastReClusterTime: TimeInterval = 0

    // MARK: - Logging

    private var logCounter = 0
    private let logInterval = 3

    // MARK: - Init

    init(assignmentThreshold: Float = 0.55,
         mergeThreshold: Float = 0.70,
         maxSpeakers: Int? = nil) {
        self.assignmentThreshold = assignmentThreshold
        self.mergeThreshold = mergeThreshold
        self.maxSpeakers = maxSpeakers ?? 8

        debugLog("[CentroidClusterer] Initialized: assignThreshold=\(assignmentThreshold), mergeThreshold=\(mergeThreshold), maxSpeakers=\(self.maxSpeakers)")
    }

    // MARK: - DiarizationEngine Protocol

    func initialize() async throws {
        guard !isInitialized else { return }

        debugLog("[CentroidClusterer] Initializing FluidAudio for embedding extraction...")

        do {
            let config = DiarizerConfig()
            diarizerManager = DiarizerManager(config: config)
            let models = try await DiarizerModels.load()
            diarizerManager?.initialize(models: models)
            isInitialized = true
            debugLog("[CentroidClusterer] Initialized successfully")
        } catch {
            debugLog("[CentroidClusterer] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isInitialized else { return }

        guard let floatSamples = convertBufferToFloatArray(buffer) else { return }

        audioBuffer.append(contentsOf: floatSamples)

        let chunkSamples = Int(sampleRate * Float(chunkDuration))

        while audioBuffer.count >= chunkSamples {
            let chunk = Array(audioBuffer.prefix(chunkSamples))
            audioBuffer = Array(audioBuffer.dropFirst(chunkSamples))

            await processChunk(chunk, at: streamPosition)
            streamPosition += chunkDuration
        }
    }

    func finishProcessing() async -> DiarizationResult? {
        guard isInitialized else { return nil }

        // Process remaining audio
        if !audioBuffer.isEmpty {
            let minSamples = Int(sampleRate * minSegmentDuration)
            if audioBuffer.count >= minSamples {
                await processChunk(audioBuffer, at: streamPosition)
            }
            audioBuffer.removeAll()
        }

        debugLog("[CentroidClusterer] Finalized: \(centroids.count) speakers, \(allSegments.count) segments")
        return lastResult
    }

    func matchAgainstCache(embedding: [Float]) -> String? {
        guard !centroids.isEmpty else { return nil }

        var bestId: String?
        var bestSim: Float = -1

        for (id, centroid) in centroids {
            let sim = cosineSimilarity(embedding, centroid)
            if sim > bestSim {
                bestSim = sim
                bestId = id
            }
        }

        if let id = bestId, bestSim >= assignmentThreshold {
            return id
        }
        return nil
    }

    func preloadKnownSpeakers(_ knownSpeakers: [(id: String, name: String, embedding: [Float])]) {
        for speaker in knownSpeakers where !speaker.embedding.isEmpty {
            centroids[speaker.id] = speaker.embedding
            speakingTimes[speaker.id] = 0
            segmentCounts[speaker.id] = 0
            anchoredSpeakers.insert(speaker.id)
            debugLog("[CentroidClusterer] Pre-loaded known speaker: \(speaker.name) (\(speaker.id))")
        }
    }

    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]? {
        let sourceEmbedding = centroids[sourceId]

        // Merge centroids
        if let srcEmb = centroids[sourceId], let dstEmb = centroids[destinationId] {
            let srcTime = speakingTimes[sourceId] ?? 0
            let dstTime = speakingTimes[destinationId] ?? 0
            let totalTime = srcTime + dstTime
            if totalTime > 0 {
                let srcWeight = srcTime / totalTime
                let dstWeight = dstTime / totalTime
                centroids[destinationId] = zip(srcEmb, dstEmb).map { $0 * srcWeight + $1 * dstWeight }
            }
            speakingTimes[destinationId] = totalTime
        }

        centroids.removeValue(forKey: sourceId)
        speakingTimes.removeValue(forKey: sourceId)
        segmentCounts.removeValue(forKey: sourceId)

        // Update segments
        allSegments = allSegments.map { seg in
            guard seg.speakerId == sourceId else { return seg }
            return TimedSpeakerSegment(
                speakerId: destinationId,
                embedding: seg.embedding,
                startTimeSeconds: seg.startTimeSeconds,
                endTimeSeconds: seg.endTimeSeconds,
                qualityScore: seg.qualityScore
            )
        }

        updatePublishedState()
        debugLog("[CentroidClusterer] Merged speaker '\(sourceId)' → '\(destinationId)'")
        return sourceEmbedding
    }

    func reset() {
        centroids.removeAll()
        speakingTimes.removeAll()
        segmentCounts.removeAll()
        anchoredSpeakers.removeAll()
        allSegments.removeAll()
        audioBuffer.removeAll()
        nextSpeakerId = 1
        streamPosition = 0
        lastReClusterTime = 0
        lastResult = nil
        lastError = nil
        isProcessing = false
        currentSpeakers.removeAll()
        totalSpeakerCount = 0
        userSpeakerId = nil
        logCounter = 0
        resamplingConverter = nil
        resamplingSourceFormat = nil

        if let dm = diarizerManager {
            dm.cleanup()
        }

        debugLog("[CentroidClusterer] Reset")
    }

    // MARK: - Core Processing

    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let diarizer = diarizerManager else { return }

        do {
            let startTime = Date()

            // Use FluidAudio to segment the chunk and extract per-segment embeddings
            let fluidResult = try diarizer.performCompleteDiarization(
                audioSamples,
                sampleRate: Int(sampleRate),
                atTime: position
            )

            let processingTime = Date().timeIntervalSince(startTime)

            // For each segment with a valid embedding, assign to centroid
            for seg in fluidResult.segments {
                let segDuration = seg.endTimeSeconds - seg.startTimeSeconds

                // Skip short segments — embeddings are unreliable below minimum duration
                guard segDuration >= minSegmentDuration else { continue }
                guard !seg.embedding.isEmpty else { continue }

                let assignedId = assignToCentroid(embedding: seg.embedding, duration: segDuration)

                let assignedSegment = TimedSpeakerSegment(
                    speakerId: assignedId,
                    embedding: seg.embedding,
                    startTimeSeconds: seg.startTimeSeconds,
                    endTimeSeconds: seg.endTimeSeconds,
                    qualityScore: seg.qualityScore
                )
                allSegments.append(assignedSegment)
            }

            // Cap segment history
            if allSegments.count > 2000 {
                allSegments = Array(allSegments.suffix(1500))
            }

            // Periodic re-clustering to merge over-split speakers
            if position - lastReClusterTime >= reClusterInterval {
                performReCluster()
                lastReClusterTime = position
            }

            // Logging
            logCounter += 1
            if logCounter >= logInterval {
                logCounter = 0
                debugLog("[CentroidClusterer] Chunk at \(String(format: "%.1f", position))s in \(String(format: "%.2f", processingTime))s — \(centroids.count) speakers")
            }

            // Diagnostics
            let rawIds = Array(centroids.keys).sorted()
            DiarizationDiagnostics.shared.logRawDiarizationOutput(
                chunkPosition: position,
                rawSpeakerCount: centroids.count,
                rawSpeakerIds: rawIds,
                segmentCount: allSegments.count,
                speakerDatabase: centroids
            )
            DiarizationDiagnostics.shared.counters.diarizationChunksProcessed += 1

            updatePublishedState()

        } catch {
            debugLog("[CentroidClusterer] Chunk processing failed: \(error)")
            lastError = error
        }
    }

    // MARK: - Centroid Assignment

    /// Assign an embedding to the nearest centroid, or create a new one.
    /// Returns the speaker ID assigned.
    private func assignToCentroid(embedding: [Float], duration: Float) -> String {
        // Find nearest existing centroid
        var bestId: String?
        var bestSim: Float = -1

        for (id, centroid) in centroids {
            let sim = cosineSimilarity(embedding, centroid)
            if sim > bestSim {
                bestSim = sim
                bestId = id
            }
        }

        // Assign to existing centroid if similarity exceeds threshold
        if let id = bestId, bestSim >= assignmentThreshold {
            // Update centroid with exponential moving average
            if var centroid = centroids[id] {
                for i in 0..<centroid.count {
                    centroid[i] = emaAlpha * centroid[i] + (1 - emaAlpha) * embedding[i]
                }
                // L2 normalize after update
                centroids[id] = l2Normalize(centroid)
            }
            speakingTimes[id, default: 0] += duration
            segmentCounts[id, default: 0] += 1
            return id
        }

        // Create new speaker if under the cap
        if centroids.count < maxSpeakers {
            let newId = "speaker_\(nextSpeakerId)"
            nextSpeakerId += 1
            centroids[newId] = l2Normalize(embedding)
            speakingTimes[newId] = duration
            segmentCounts[newId] = 1
            debugLog("[CentroidClusterer] New speaker: \(newId) (total: \(centroids.count), similarity to nearest: \(String(format: "%.3f", bestSim)))")
            return newId
        }

        // At speaker cap: force-assign to nearest centroid
        if let id = bestId {
            if var centroid = centroids[id] {
                for i in 0..<centroid.count {
                    centroid[i] = emaAlpha * centroid[i] + (1 - emaAlpha) * embedding[i]
                }
                centroids[id] = l2Normalize(centroid)
            }
            speakingTimes[id, default: 0] += duration
            segmentCounts[id, default: 0] += 1
            return id
        }

        // Fallback (should never happen)
        return "speaker_0"
    }

    // MARK: - Re-Clustering

    /// Merge centroids that have become too similar (over-split correction).
    private func performReCluster() {
        let ids = Array(centroids.keys).sorted()
        var mergedPairs: [(String, String)] = []

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let id1 = ids[i]
                let id2 = ids[j]

                // Don't merge two different anchored speakers
                if anchoredSpeakers.contains(id1) && anchoredSpeakers.contains(id2) { continue }

                guard let c1 = centroids[id1], let c2 = centroids[id2] else { continue }

                let sim = cosineSimilarity(c1, c2)
                if sim >= mergeThreshold {
                    // Merge smaller into larger (by speaking time)
                    let time1 = speakingTimes[id1] ?? 0
                    let time2 = speakingTimes[id2] ?? 0
                    if time1 >= time2 {
                        mergedPairs.append((id2, id1))  // merge id2 into id1
                    } else {
                        mergedPairs.append((id1, id2))  // merge id1 into id2
                    }
                }
            }
        }

        for (source, dest) in mergedPairs {
            guard centroids[source] != nil else { continue }  // Already merged
            _ = mergeCacheSpeakers(sourceId: source, destinationId: dest)
        }

        if !mergedPairs.isEmpty {
            debugLog("[CentroidClusterer] Re-clustering: merged \(mergedPairs.count) speaker pair(s), \(centroids.count) speakers remain")
        }
    }

    // MARK: - State Update

    private func updatePublishedState() {
        totalSpeakerCount = centroids.count
        currentSpeakers = Array(centroids.keys).sorted()

        let result = DiarizationResult(
            segments: allSegments,
            speakerEmbeddings: centroids.isEmpty ? nil : centroids
        )

        identifyUserSpeaker(in: result)
        lastResult = result
    }

    private func identifyUserSpeaker(in result: DiarizationResult) {
        guard UserProfile.shared.hasVoiceProfile,
              let userEmb = UserProfile.shared.voiceEmbedding else { return }
        guard userSpeakerId == nil else { return }

        for (id, centroid) in centroids {
            let sim = cosineSimilarity(userEmb, centroid)
            if sim >= 0.6 {
                userSpeakerId = id
                debugLog("[CentroidClusterer] ✅ IDENTIFIED USER as \(id) (similarity: \(String(format: "%.3f", sim)))")
                break
            }
        }
    }

    // MARK: - Math Utilities

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA * normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    private func l2Normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    // MARK: - Audio Conversion

    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate

        // Fast path: already 16kHz mono
        if abs(sourceSampleRate - Double(sampleRate)) < 1.0 {
            var samples = [Float](repeating: 0, count: frameCount)
            if channelCount == 1 {
                memcpy(&samples, channelData[0], frameCount * MemoryLayout<Float>.size)
            } else {
                for frame in 0..<frameCount {
                    var sample: Float = 0.0
                    for channel in 0..<channelCount {
                        sample += channelData[channel][frame]
                    }
                    samples[frame] = sample / Float(channelCount)
                }
            }
            return samples
        }

        // Resampling path
        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let sourceMonoFormat = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1),
              let sourceMonoBuffer = AVAudioPCMBuffer(pcmFormat: sourceMonoFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        sourceMonoBuffer.frameLength = AVAudioFrameCount(frameCount)
        if let monoData = sourceMonoBuffer.floatChannelData {
            if channelCount == 1 {
                memcpy(monoData[0], channelData[0], frameCount * MemoryLayout<Float>.size)
            } else {
                for frame in 0..<frameCount {
                    var sample: Float = 0.0
                    for channel in 0..<channelCount {
                        sample += channelData[channel][frame]
                    }
                    monoData[0][frame] = sample / Float(channelCount)
                }
            }
        }

        if resamplingConverter == nil || resamplingSourceFormat?.sampleRate != sourceSampleRate {
            resamplingConverter = AVAudioConverter(from: sourceMonoFormat, to: targetFormat)
            resamplingSourceFormat = sourceMonoFormat
        }
        guard let converter = resamplingConverter else { return nil }

        let ratio = Double(sampleRate) / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceMonoBuffer
        }

        guard status != .error, error == nil, let outputData = outputBuffer.floatChannelData else {
            return nil
        }

        let outputCount = Int(outputBuffer.frameLength)
        var samples = [Float](repeating: 0, count: outputCount)
        memcpy(&samples, outputData[0], outputCount * MemoryLayout<Float>.size)
        return samples
    }
}
