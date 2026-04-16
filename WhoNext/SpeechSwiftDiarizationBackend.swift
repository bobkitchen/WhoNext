import Foundation
@preconcurrency import AVFoundation

// Selective SpeechVAD imports — avoid importing DiarizationResult and DiarizedSegment
// which conflict with WhoNext's bridge types of the same name.
import class SpeechVAD.PyannoteDiarizationPipeline
import struct SpeechVAD.DiarizationConfig
import class SpeechVAD.WeSpeakerModel
import enum SpeechVAD.WeSpeakerEngine

/// Diarization backend using speech-swift's PyannoteDiarizationPipeline + WeSpeaker.
///
/// Key advantages over other backends:
/// - Pyannote v4 segmentation (latest, most accurate)
/// - WeSpeaker 256-dim speaker embeddings for voice enrollment
/// - extractSpeaker() — find a specific person's segments by reference voice
/// - CoreML embedding engine (Neural Engine, frees GPU)
/// - MLX segmentation engine (GPU-accelerated via Metal)
///
/// Full feature set:
/// - matchAgainstCache: ✅ (via WeSpeaker cosine similarity)
/// - preloadKnownSpeakers: ✅ (stores reference embeddings)
/// - mergeCacheSpeakers: ✅ (relabels segments + merges embeddings)
@MainActor
final class SpeechSwiftDiarizationBackend: ObservableObject, DiarizationEngine {

    // MARK: - Published State

    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0
    @Published private(set) var userSpeakerId: String?
    @Published var isProcessing = false
    @Published var lastError: Error?

    // MARK: - Pipeline State

    private var pipeline: PyannoteDiarizationPipeline?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    /// Cached converter for resampling to 16kHz
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // Configuration
    private let clusteringThreshold: Float
    private let maxSpeakers: Int?
    private let embeddingEngine: WeSpeakerEngine

    // Chunk management — larger chunks give better clustering accuracy
    private let chunkDuration: TimeInterval = 30.0
    private var streamPosition: TimeInterval = 0.0
    private var allSegments: [TimedSpeakerSegment] = []
    private var allSpeakerEmbeddings: [String: [Float]] = [:]

    // Known speaker cache for voice matching
    private var knownSpeakers: [(id: String, name: String, embedding: [Float])] = []

    // Logging
    private var logCounter = 0
    private let logInterval = 3

    // MARK: - Init

    init(clusteringThreshold: Float = 0.715,
         maxSpeakers: Int? = nil,
         embeddingEngine: WeSpeakerEngine = .coreml) {
        self.clusteringThreshold = clusteringThreshold
        self.maxSpeakers = maxSpeakers
        self.embeddingEngine = embeddingEngine

        debugLog("[SpeechSwiftBackend] Initialized:")
        debugLog("   - Clustering threshold: \(clusteringThreshold)")
        debugLog("   - Max speakers: \(maxSpeakers.map(String.init) ?? "auto")")
        debugLog("   - Embedding engine: \(embeddingEngine)")
    }

    // MARK: - Setup

    func initialize() async throws {
        guard !isInitialized else {
            debugLog("[SpeechSwiftBackend] Already initialized")
            return
        }

        debugLog("[SpeechSwiftBackend] Initializing Pyannote v4 + WeSpeaker pipeline...")

        do {
            // Load Pyannote segmentation (MLX) + WeSpeaker embedding (CoreML by default)
            // Models are auto-downloaded from HuggingFace on first use, then cached.
            pipeline = try await PyannoteDiarizationPipeline.fromPretrained(
                embeddingEngine: embeddingEngine
            )

            isInitialized = true
            debugLog("[SpeechSwiftBackend] Pipeline initialized — Pyannote v4 (MLX) + WeSpeaker (\(embeddingEngine))")
        } catch {
            debugLog("[SpeechSwiftBackend] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Audio Processing

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isInitialized else { return }

        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            debugLog("[SpeechSwiftBackend] Failed to convert audio buffer")
            return
        }

        audioBuffer.append(contentsOf: floatSamples)

        let chunkSamples = Int(sampleRate * Float(chunkDuration))

        while audioBuffer.count >= chunkSamples {
            let chunk = Array(audioBuffer.prefix(chunkSamples))
            audioBuffer = Array(audioBuffer.dropFirst(chunkSamples))

            await processChunk(chunk, at: streamPosition)
            streamPosition += chunkDuration
        }
    }

    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let pipeline = pipeline else { return }

        let startTime = Date()
        let threshold = clusteringThreshold

        // PyannoteDiarizationPipeline.diarize() is synchronous and CPU/GPU-intensive.
        // Dispatch off main actor to avoid blocking UI.
        let config = DiarizationConfig(clusteringThreshold: threshold)
        let sampleRateInt = Int(sampleRate)

        let chunkResult: (segments: [(speakerId: Int, startTime: Float, endTime: Float)],
                          numSpeakers: Int,
                          speakerEmbeddings: [[Float]])

        chunkResult = await Task.detached(priority: .userInitiated) {
            // speech-swift returns its own DiarizationResult type (AudioCommon.DiarizationResult)
            // We destructure it here to avoid bringing the conflicting type onto MainActor.
            let result = pipeline.diarize(
                audio: audioSamples,
                sampleRate: sampleRateInt,
                config: config
            )

            let segments = result.segments.map { seg in
                (speakerId: seg.speakerId, startTime: seg.startTime, endTime: seg.endTime)
            }

            return (segments: segments,
                    numSpeakers: result.numSpeakers,
                    speakerEmbeddings: result.speakerEmbeddings)
        }.value

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert to WhoNext TimedSpeakerSegment bridge types.
        // speech-swift uses Int speaker IDs (0-based); we convert to "speaker_N" strings.
        let bridgeSegments = chunkResult.segments.map { seg in
            let speakerLabel = "speaker_\(seg.speakerId)"

            // Attach the speaker's embedding if available
            let embedding: [Float]
            if seg.speakerId < chunkResult.speakerEmbeddings.count {
                embedding = chunkResult.speakerEmbeddings[seg.speakerId]
            } else {
                embedding = []
            }

            return TimedSpeakerSegment(
                speakerId: speakerLabel,
                embedding: embedding,
                startTimeSeconds: Float(position) + seg.startTime,
                endTimeSeconds: Float(position) + seg.endTime,
                qualityScore: 1.0
            )
        }

        // Store per-speaker embeddings
        for (idx, emb) in chunkResult.speakerEmbeddings.enumerated() {
            let label = "speaker_\(idx)"
            allSpeakerEmbeddings[label] = emb
        }

        // Accumulate segments
        allSegments.append(contentsOf: bridgeSegments)

        // Cap segment history
        if allSegments.count > 2000 {
            allSegments = Array(allSegments.suffix(1500))
        }

        let uniqueSpeakers = Set(allSegments.map { $0.speakerId })
        totalSpeakerCount = uniqueSpeakers.count

        // Logging
        logCounter += 1
        if logCounter >= logInterval {
            logCounter = 0
            debugLog("[SpeechSwiftBackend] Chunk at \(String(format: "%.1f", position))s in \(String(format: "%.2f", processingTime))s — \(chunkResult.numSpeakers) speakers, \(bridgeSegments.count) segments, \(chunkResult.speakerEmbeddings.count) embeddings")
        }

        // Diagnostic event
        let rawIds = Array(uniqueSpeakers).sorted()
        DiarizationDiagnostics.shared.logRawDiarizationOutput(
            chunkPosition: position,
            rawSpeakerCount: uniqueSpeakers.count,
            rawSpeakerIds: rawIds,
            segmentCount: allSegments.count,
            speakerDatabase: allSpeakerEmbeddings.isEmpty ? nil : allSpeakerEmbeddings
        )
        DiarizationDiagnostics.shared.counters.diarizationChunksProcessed += 1

        // Update published state
        let diarResult = DiarizationResult(
            segments: allSegments,
            speakerEmbeddings: allSpeakerEmbeddings.isEmpty ? nil : allSpeakerEmbeddings
        )

        identifyUserSpeaker(in: diarResult)
        lastResult = diarResult
        currentSpeakers = Array(uniqueSpeakers).sorted()
    }

    // MARK: - Finish Processing

    func finishProcessing() async -> DiarizationResult? {
        guard isInitialized else { return nil }

        // Process remaining buffered audio
        if !audioBuffer.isEmpty {
            let minSamples = Int(sampleRate * 3.0)
            if audioBuffer.count >= minSamples {
                await processChunk(audioBuffer, at: streamPosition)
            }
            audioBuffer.removeAll()
        }

        debugLog("[SpeechSwiftBackend] Finalized: \(totalSpeakerCount) speakers, \(allSegments.count) segments, \(allSpeakerEmbeddings.count) embeddings")
        return lastResult
    }

    // MARK: - Speaker Management (full support via WeSpeaker embeddings)

    func matchAgainstCache(embedding: [Float]) -> String? {
        guard !embedding.isEmpty else { return nil }

        // Compare against all known speaker embeddings using cosine similarity
        var bestMatch: String?
        var bestSimilarity: Float = -1.0
        let threshold: Float = 0.65  // Cosine similarity threshold for a positive match

        for (speakerId, speakerEmb) in allSpeakerEmbeddings {
            guard !speakerEmb.isEmpty else { continue }
            let similarity = WeSpeakerModel.cosineSimilarity(embedding, speakerEmb)
            if similarity > threshold && similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = speakerId
            }
        }

        if let match = bestMatch {
            debugLog("[SpeechSwiftBackend] Cache match: \(match) (similarity: \(String(format: "%.3f", bestSimilarity)))")
        }
        return bestMatch
    }

    func preloadKnownSpeakers(_ speakers: [(id: String, name: String, embedding: [Float])]) {
        knownSpeakers = speakers.filter { !$0.embedding.isEmpty }

        if !knownSpeakers.isEmpty {
            // Pre-populate the embeddings cache so matchAgainstCache works immediately
            for speaker in knownSpeakers {
                allSpeakerEmbeddings[speaker.id] = speaker.embedding
            }
            debugLog("[SpeechSwiftBackend] Pre-loaded \(knownSpeakers.count) known speakers with voice embeddings")
        }
    }

    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]? {
        let sourceEmbedding = allSpeakerEmbeddings[sourceId]

        // Relabel segments
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

        // Merge embeddings: average the two if both exist
        if let srcEmb = allSpeakerEmbeddings[sourceId],
           let dstEmb = allSpeakerEmbeddings[destinationId],
           srcEmb.count == dstEmb.count {
            let merged = zip(srcEmb, dstEmb).map { ($0 + $1) / 2.0 }
            allSpeakerEmbeddings[destinationId] = merged
        }

        allSpeakerEmbeddings.removeValue(forKey: sourceId)
        currentSpeakers.removeAll { $0 == sourceId }
        totalSpeakerCount = Set(allSegments.map { $0.speakerId }).count

        debugLog("[SpeechSwiftBackend] Merged speaker '\(sourceId)' -> '\(destinationId)'")
        return sourceEmbedding
    }

    // MARK: - Reset

    func reset() {
        audioBuffer.removeAll()
        allSegments.removeAll()
        allSpeakerEmbeddings.removeAll()
        knownSpeakers.removeAll()
        lastResult = nil
        lastError = nil
        isProcessing = false
        streamPosition = 0.0
        currentSpeakers.removeAll()
        totalSpeakerCount = 0
        userSpeakerId = nil
        logCounter = 0
        resamplingConverter = nil
        resamplingSourceFormat = nil

        debugLog("[SpeechSwiftBackend] Reset complete")
    }

    // MARK: - Private Helpers

    private func identifyUserSpeaker(in result: DiarizationResult) {
        guard UserProfile.shared.hasVoiceProfile,
              let userEmb = UserProfile.shared.voiceEmbedding else { return }
        guard userSpeakerId == nil else { return }

        // Match user's voice profile against detected speaker embeddings
        for (speakerId, speakerEmb) in allSpeakerEmbeddings {
            guard !speakerEmb.isEmpty else { continue }
            let similarity = WeSpeakerModel.cosineSimilarity(userEmb, speakerEmb)
            if similarity > 0.7 {
                userSpeakerId = speakerId
                debugLog("[SpeechSwiftBackend] IDENTIFIED USER as \(speakerId) (cosine similarity: \(String(format: "%.3f", similarity)))")
                break
            }
        }
    }

    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate

        // Fast path: already 16kHz
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
