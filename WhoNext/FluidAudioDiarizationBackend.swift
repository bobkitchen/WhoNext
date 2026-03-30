import Foundation
@preconcurrency import AVFoundation

// Selective FluidAudio imports — avoid importing DiarizationResult and TimedSpeakerSegment
// which conflict with WhoNext's bridge types of the same name.
// The FluidAudio module has a struct named `FluidAudio` that shadows the module name,
// so we can't use `FluidAudio.X` syntax — instead we import only what we need.
import class FluidAudio.DiarizerManager
import struct FluidAudio.DiarizerConfig
import struct FluidAudio.DiarizerModels
import class FluidAudio.Speaker

/// Diarization backend using FluidAudio's DiarizerManager (pyannote segmentation + WeSpeaker embeddings).
///
/// Key advantages over AxiiDiarization's AHC:
/// - 3-second minimum before registering new speaker (prevents phantom speakers)
/// - Exponential moving average for embedding updates (handles voice drift)
/// - Battle-tested pyannote segmentation model
/// - Speaker enrollment for known voices
@MainActor
final class FluidAudioDiarizationBackend: ObservableObject, DiarizationEngine {

    // MARK: - Published State

    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0
    @Published private(set) var userSpeakerId: String?
    @Published var isProcessing = false
    @Published var lastError: Error?

    // MARK: - Private State

    private var diarizerManager: DiarizerManager?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    /// Cached converter for resampling to 16kHz
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // Configuration
    private let clusteringThreshold: Float
    private let maxSpeakers: Int?

    // Chunk management
    private let chunkDuration: TimeInterval = 10.0
    private var streamPosition: TimeInterval = 0.0
    private var allSegments: [TimedSpeakerSegment] = []
    private var allSpeakerEmbeddings: [String: [Float]] = [:]

    // Logging
    private var logCounter = 0
    private let logInterval = 3

    // MARK: - Init

    init(clusteringThreshold: Float = 0.7,
         maxSpeakers: Int? = nil) {
        self.clusteringThreshold = clusteringThreshold
        self.maxSpeakers = maxSpeakers

        debugLog("🎙️ [FluidAudioBackend] Initialized:")
        debugLog("   - Clustering threshold: \(clusteringThreshold)")
        debugLog("   - Max speakers: \(maxSpeakers.map(String.init) ?? "auto")")
    }

    // MARK: - Setup

    func initialize() async throws {
        guard !isInitialized else {
            debugLog("✅ [FluidAudioBackend] Already initialized")
            return
        }

        debugLog("🔄 [FluidAudioBackend] Initializing FluidAudio diarizer...")

        do {
            var config = DiarizerConfig()
            config.clusteringThreshold = clusteringThreshold
            config.minSpeechDuration = 1.0
            config.minEmbeddingUpdateDuration = 2.0
            config.minSilenceGap = 0.5
            config.chunkDuration = Float(chunkDuration)
            if let max = maxSpeakers {
                config.numClusters = max
            }

            diarizerManager = DiarizerManager(config: config)

            // Download/load pyannote segmentation + WeSpeaker embedding models
            let models = try await DiarizerModels.load()
            diarizerManager?.initialize(models: models)

            isInitialized = true
            debugLog("✅ [FluidAudioBackend] FluidAudio diarizer initialized")
        } catch {
            debugLog("❌ [FluidAudioBackend] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Audio Processing

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isInitialized else { return }

        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            debugLog("⚠️ [FluidAudioBackend] Failed to convert audio buffer")
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
        guard let diarizer = diarizerManager else { return }

        do {
            let startTime = Date()

            // FluidAudio's performCompleteDiarization returns FluidAudio.DiarizationResult
            // (type inferred — we don't import it by name to avoid conflict with WhoNext's type)
            let fluidResult = try diarizer.performCompleteDiarization(
                audioSamples,
                sampleRate: Int(sampleRate),
                atTime: position
            )

            let processingTime = Date().timeIntervalSince(startTime)

            // Convert FluidAudio segments to WhoNext bridge types.
            // fluidResult.segments contains FluidAudio.TimedSpeakerSegment values;
            // we map them to WhoNext's TimedSpeakerSegment (the only one in scope).
            let bridgeSegments = fluidResult.segments.map { seg in
                TimedSpeakerSegment(
                    speakerId: seg.speakerId,
                    embedding: seg.embedding,
                    startTimeSeconds: seg.startTimeSeconds,
                    endTimeSeconds: seg.endTimeSeconds,
                    qualityScore: seg.qualityScore
                )
            }

            // Accumulate segments
            allSegments.append(contentsOf: bridgeSegments)

            // Cap segment history
            if allSegments.count > 2000 {
                allSegments = Array(allSegments.suffix(1500))
            }

            // Build speaker embeddings map
            if let db = fluidResult.speakerDatabase {
                for (id, emb) in db {
                    allSpeakerEmbeddings[id] = emb
                }
            }

            let uniqueSpeakers = Set(allSegments.map { $0.speakerId })
            totalSpeakerCount = uniqueSpeakers.count

            // Logging
            logCounter += 1
            if logCounter >= logInterval {
                logCounter = 0
                debugLog("[FluidAudioBackend] Chunk at \(String(format: "%.1f", position))s in \(String(format: "%.2f", processingTime))s — \(uniqueSpeakers.count) speakers, \(bridgeSegments.count) new segments")
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
            let result = DiarizationResult(
                segments: allSegments,
                speakerEmbeddings: allSpeakerEmbeddings.isEmpty ? nil : allSpeakerEmbeddings
            )

            identifyUserSpeaker(in: result)
            lastResult = result
            currentSpeakers = Array(uniqueSpeakers).sorted()

        } catch {
            debugLog("❌ [FluidAudioBackend] Chunk processing failed: \(error)")
            lastError = error
        }
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

        debugLog("✅ [FluidAudioBackend] Finalized: \(totalSpeakerCount) speakers, \(allSegments.count) segments")
        return lastResult
    }

    // MARK: - Speaker Management

    func matchAgainstCache(embedding: [Float]) -> String? {
        guard let diarizer = diarizerManager else { return nil }
        guard diarizer.validateEmbedding(embedding) else { return nil }

        // Use FluidAudio's speaker manager to find a match
        if let match = diarizer.speakerManager.assignSpeaker(
            embedding,
            speechDuration: 1.0,
            confidence: 0.8
        ) {
            return match.id
        }
        return nil
    }

    func preloadKnownSpeakers(_ knownSpeakers: [(id: String, name: String, embedding: [Float])]) {
        guard let diarizer = diarizerManager else { return }

        let speakers = knownSpeakers.compactMap { info -> Speaker? in
            guard !info.embedding.isEmpty else { return nil }
            return Speaker(
                id: info.id,
                name: info.name,
                currentEmbedding: info.embedding,
                isPermanent: true
            )
        }

        guard !speakers.isEmpty else { return }

        diarizer.initializeKnownSpeakers(speakers)
        debugLog("🎯 [FluidAudioBackend] Pre-loaded \(speakers.count) known speakers")
    }

    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]? {
        // Get source embedding before merge
        let sourceEmbedding = allSpeakerEmbeddings[sourceId]

        // Update local segments
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

        currentSpeakers.removeAll { $0 == sourceId }
        totalSpeakerCount = Set(allSegments.map { $0.speakerId }).count
        allSpeakerEmbeddings.removeValue(forKey: sourceId)

        debugLog("🔗 [FluidAudioBackend] Merged speaker '\(sourceId)' → '\(destinationId)'")
        return sourceEmbedding
    }

    // MARK: - Reset

    func reset() {
        audioBuffer.removeAll()
        allSegments.removeAll()
        allSpeakerEmbeddings.removeAll()
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

        // Clean up diarizer state
        if isInitialized, let dm = diarizerManager {
            dm.cleanup()
        }

        debugLog("🔄 [FluidAudioBackend] Reset complete")
    }

    // MARK: - Private Helpers

    private func identifyUserSpeaker(in result: DiarizationResult) {
        guard UserProfile.shared.hasVoiceProfile,
              UserProfile.shared.voiceEmbedding != nil else { return }
        guard userSpeakerId == nil else { return }

        for segment in result.segments {
            let (matches, confidence) = UserProfile.shared.matchesUserVoice(segment.embedding)
            if matches {
                userSpeakerId = segment.speakerId
                debugLog("🎤 [FluidAudioBackend] ✅ IDENTIFIED USER as speaker \(segment.speakerId) (confidence: \(String(format: "%.1f%%", confidence * 100)))")
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
