import Foundation
@preconcurrency import AVFoundation

// Selective SpeakerKit imports — avoid importing DiarizationResult
// which conflicts with WhoNext's bridge type of the same name.
import class SpeakerKit.SpeakerKit
import class SpeakerKit.SpeakerKitConfig
import class SpeakerKit.PyannoteConfig

/// Diarization backend using WhisperKit's SpeakerKit (Pyannote v4 segmentation + CoreML).
///
/// Key advantages:
/// - Pyannote v4 segmentation (latest, most accurate)
/// - CoreML-based — fully on-device, no MLX dependency
/// - Ships with WhisperKit — no extra dependency
/// - MIT licensed
///
/// Limitations vs FluidAudio:
/// - Does NOT expose speaker embeddings (no voice enrollment support)
/// - `matchAgainstCache()` and `preloadKnownSpeakers()` are no-ops
@MainActor
final class SpeakerKitDiarizationBackend: ObservableObject, DiarizationEngine {

    // MARK: - Published State

    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0
    @Published private(set) var userSpeakerId: String?
    @Published var isProcessing = false
    @Published var lastError: Error?

    // MARK: - Pipeline State

    private var speakerKit: SpeakerKit?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    /// Cached converter for resampling to 16kHz
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // Configuration
    private let maxSpeakers: Int?

    // Chunk management — SpeakerKit processes whole arrays, so we accumulate
    // larger chunks for better clustering accuracy
    private let chunkDuration: TimeInterval = 30.0
    private var streamPosition: TimeInterval = 0.0
    private var allSegments: [TimedSpeakerSegment] = []

    // Logging
    private var logCounter = 0
    private let logInterval = 3

    // MARK: - Init

    init(clusteringThreshold: Float = 0.715,
         maxSpeakers: Int? = nil) {
        self.maxSpeakers = maxSpeakers

        debugLog("[SpeakerKitBackend] Initialized:")
        debugLog("   - Max speakers: \(maxSpeakers.map(String.init) ?? "auto")")
    }

    // MARK: - Setup

    func initialize() async throws {
        guard !isInitialized else {
            debugLog("[SpeakerKitBackend] Already initialized")
            return
        }

        debugLog("[SpeakerKitBackend] Initializing SpeakerKit (Pyannote v4 CoreML)...")

        do {
            let config = PyannoteConfig()
            speakerKit = try await SpeakerKit(config)

            // Ensure models are downloaded and loaded
            try await speakerKit?.ensureModelsLoaded()

            isInitialized = true
            debugLog("[SpeakerKitBackend] Pipeline initialized — Pyannote v4 segmentation via CoreML")
        } catch {
            debugLog("[SpeakerKitBackend] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Audio Processing

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isInitialized else { return }

        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            debugLog("[SpeakerKitBackend] Failed to convert audio buffer")
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
        guard let speakerKit = speakerKit else { return }

        let startTime = Date()

        do {
            // SpeakerKit.diarize returns SpeakerKit.DiarizationResult (not ours)
            let skResult = try await speakerKit.diarize(audioArray: audioSamples)

            let processingTime = Date().timeIntervalSince(startTime)

            // Convert SpeakerKit segments to WhoNext TimedSpeakerSegments.
            // SpeakerSegment has: speaker (SpeakerInfo), startTime (Float), endTime (Float)
            // SpeakerInfo is: .noMatch, .speakerId(Int), .multiple([Int])
            let bridgeSegments = skResult.segments.compactMap { seg -> TimedSpeakerSegment? in
                let speakerLabel: String
                switch seg.speaker {
                case .speakerId(let id):
                    speakerLabel = "speaker_\(id)"
                case .multiple(let ids):
                    // Overlapping speech — attribute to first speaker
                    guard let first = ids.first else { return nil }
                    speakerLabel = "speaker_\(first)"
                case .noMatch:
                    speakerLabel = "speaker_unknown"
                @unknown default:
                    speakerLabel = "speaker_unknown"
                }

                return TimedSpeakerSegment(
                    speakerId: speakerLabel,
                    embedding: [],  // SpeakerKit doesn't expose embeddings
                    startTimeSeconds: Float(position) + seg.startTime,
                    endTimeSeconds: Float(position) + seg.endTime,
                    qualityScore: 1.0
                )
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
                debugLog("[SpeakerKitBackend] Chunk at \(String(format: "%.1f", position))s in \(String(format: "%.2f", processingTime))s — \(uniqueSpeakers.count) speakers, \(bridgeSegments.count) new segments")
            }

            // Diagnostic event
            let rawIds = Array(uniqueSpeakers).sorted()
            DiarizationDiagnostics.shared.logRawDiarizationOutput(
                chunkPosition: position,
                rawSpeakerCount: uniqueSpeakers.count,
                rawSpeakerIds: rawIds,
                segmentCount: allSegments.count,
                speakerDatabase: nil  // No embeddings available from SpeakerKit
            )
            DiarizationDiagnostics.shared.counters.diarizationChunksProcessed += 1

            // Update published state
            let diarResult = DiarizationResult(
                segments: allSegments,
                speakerEmbeddings: nil  // SpeakerKit doesn't expose embeddings
            )

            lastResult = diarResult
            currentSpeakers = Array(uniqueSpeakers).sorted()

        } catch {
            debugLog("[SpeakerKitBackend] Chunk processing failed: \(error)")
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

        debugLog("[SpeakerKitBackend] Finalized: \(totalSpeakerCount) speakers, \(allSegments.count) segments")
        return lastResult
    }

    // MARK: - Speaker Management (limited — SpeakerKit doesn't expose embeddings)

    func matchAgainstCache(embedding: [Float]) -> String? {
        // SpeakerKit doesn't expose speaker embeddings, so cache matching is unavailable.
        return nil
    }

    func preloadKnownSpeakers(_ knownSpeakers: [(id: String, name: String, embedding: [Float])]) {
        // SpeakerKit doesn't support pre-loading known speakers.
        if !knownSpeakers.isEmpty {
            debugLog("[SpeakerKitBackend] preloadKnownSpeakers called with \(knownSpeakers.count) speakers — not supported by SpeakerKit (no embedding API)")
        }
    }

    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]? {
        // Merge segments locally (relabel source → destination)
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

        debugLog("[SpeakerKitBackend] Merged speaker '\(sourceId)' -> '\(destinationId)'")
        return nil  // No embeddings to return
    }

    // MARK: - Reset

    func reset() {
        audioBuffer.removeAll()
        allSegments.removeAll()
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

        Task {
            await speakerKit?.unloadModels()
        }

        debugLog("[SpeakerKitBackend] Reset complete")
    }

    // MARK: - Private Helpers

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
