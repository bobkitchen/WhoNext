import Foundation
import AVFoundation
#if canImport(AxiiDiarization)
import AxiiDiarization
#endif

/// Manages speaker diarization using AxiiDiarization framework.
///
/// AxiiDiarization provides:
/// - True streaming via `DiarizationSession.addAudio()` + `process()`
/// - Global re-clustering with stable speaker IDs (no SpeakerCache needed)
/// - Speaker profile pinning for guided diarization
/// - 5.3% DER on VoxConverse
///
/// The public API surface is preserved for drop-in compatibility with
/// SimpleRecordingEngine, RecordingWindow, VoiceTrainingRecorder, etc.
#if canImport(AxiiDiarization)
@MainActor
class DiarizationManager: ObservableObject {

    // MARK: - Properties

    private var pipeline: DiarizationPipeline?
    private var session: DiarizationSession?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    /// Cached converter for proper anti-aliased resampling to 16kHz
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // Configuration
    private let clusteringThreshold: Float
    private let maxSpeakers: Int?
    private let windowDuration: Float
    @Published var isEnabled: Bool = true
    @Published var enableRealTimeProcessing: Bool = false

    // State
    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var processingProgress: Double = 0.0

    // Results
    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0
    @Published private(set) var userSpeakerId: String?

    // Chunk management for streaming
    private let chunkDuration: TimeInterval = 10.0
    private var streamPosition: TimeInterval = 0.0
    private var allSegments: [TimedSpeakerSegment] = []

    // Known speaker profiles for guided diarization
    private var knownSpeakerProfiles: [WhoNextSpeakerProfile] = []

    // Post-processing configuration
    private let minSegmentDuration: Float = 0.5

    /// Periodic log counter
    private var logCounter = 0
    private let logInterval = 3  // Log every Nth chunk

    // MARK: - Initialization

    init(isEnabled: Bool = true,
         enableRealTimeProcessing: Bool = false,
         clusteringThreshold: Float = 0.5,
         maxSpeakers: Int? = nil,
         minSpeechDuration: Float = 1.0) {

        self.clusteringThreshold = clusteringThreshold
        self.maxSpeakers = maxSpeakers
        self.windowDuration = 10.0
        self.isEnabled = isEnabled
        self.enableRealTimeProcessing = enableRealTimeProcessing

        debugLog("🎙️ [DiarizationManager] Initialized (AxiiDiarization):")
        debugLog("   - Clustering threshold: \(clusteringThreshold)")
        debugLog("   - Window duration: \(windowDuration)s")
        debugLog("   - Max speakers: \(maxSpeakers.map(String.init) ?? "auto")")
        debugLog("   - Real-time processing: \(enableRealTimeProcessing)")
    }

    // MARK: - Configuration

    var currentThreshold: Float { clusteringThreshold }

    // MARK: - Guided Diarization (Known Speaker Pre-Loading)

    /// Pre-load known speakers for guided diarization.
    /// Profiles are stored and passed to the session on creation/reset.
    func preloadKnownSpeakers(_ knownSpeakers: [(id: String, name: String, embedding: [Float])]) {
        let profiles = knownSpeakers.compactMap { info -> WhoNextSpeakerProfile? in
            guard !info.embedding.isEmpty else { return nil }
            return WhoNextSpeakerProfile(id: info.id, name: info.name, embeddings: [info.embedding])
        }

        guard !profiles.isEmpty else {
            debugLog("⚠️ [DiarizationManager] No valid speakers to preload")
            return
        }

        knownSpeakerProfiles = profiles

        // If session already exists, recreate with known speakers
        if let pipe = pipeline {
            session = pipe.createSession(knownSpeakers: profiles)
            debugLog("🎯 [DiarizationManager] Recreated session with \(profiles.count) known speakers")
        }

        debugLog("🎯 [DiarizationManager] Pre-loaded \(profiles.count) known speakers: \(profiles.map { $0.name })")
    }

    // MARK: - Setup

    /// Initialize the diarization pipeline and download models if needed.
    func initialize() async throws {
        guard isEnabled else {
            debugLog("⚠️ [DiarizationManager] Diarization is disabled")
            return
        }
        guard !isInitialized else {
            debugLog("✅ [DiarizationManager] Already initialized, skipping")
            return
        }
        debugLog("🔄 [DiarizationManager] Initializing AxiiDiarization pipeline...")

        do {
            // Locate CoreML model files bundled in the app
            guard let sortformerPath = Bundle.main.path(forResource: "sortformer_v2_1", ofType: "mlmodelc"),
                  let embPath = Bundle.main.path(forResource: "wespeaker_resnet34", ofType: "mlmodelc") else {
                throw DiarizationError.initializationFailed("CoreML model files not found in bundle")
            }

            pipeline = try DiarizationPipeline(
                sortformerModelPath: sortformerPath,
                embModelPath: embPath,
                windowDuration: Double(windowDuration),
                clusteringThreshold: clusteringThreshold
            )

            // Create session (with known speakers if available)
            if knownSpeakerProfiles.isEmpty {
                session = pipeline?.createSession()
            } else {
                session = pipeline?.createSession(knownSpeakers: knownSpeakerProfiles)
            }

            isInitialized = true
            debugLog("✅ [DiarizationManager] AxiiDiarization pipeline initialized")
        } catch {
            debugLog("❌ [DiarizationManager] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Audio Processing

    /// Process an audio buffer for diarization.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isEnabled, isInitialized else { return }

        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            debugLog("⚠️ [DiarizationManager] Failed to convert audio buffer")
            return
        }

        audioBuffer.append(contentsOf: floatSamples)

        let chunkSamples = Int(sampleRate * Float(chunkDuration))

        while audioBuffer.count >= chunkSamples {
            let chunk = Array(audioBuffer.prefix(chunkSamples))
            audioBuffer = Array(audioBuffer.dropFirst(chunkSamples))

            if enableRealTimeProcessing {
                await processChunk(chunk, at: streamPosition)
                streamPosition += chunkDuration
            }
        }
    }

    /// Process a single chunk of audio through the Axii session.
    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let activeSession = session else { return }

        do {
            let startTime = Date()

            // Feed audio to the session — Axii accumulates internally
            activeSession.addAudio(audioSamples)

            // Incremental processing: re-clusters globally, returns stable speaker IDs
            let axiiResult = try activeSession.process()
            let processingTime = Date().timeIntervalSince(startTime)

            // Convert Axii segments to WhoNext bridge types
            let bridgeSegments = axiiResult.segments.map { seg -> TimedSpeakerSegment in
                let speakerId = mapAxiiSpeakerId(seg)
                let embedding = seg.speaker.embedding ?? []
                return TimedSpeakerSegment(
                    speakerId: speakerId,
                    embedding: embedding,
                    startTimeSeconds: Float(seg.start),
                    endTimeSeconds: Float(seg.end),
                    qualityScore: confidenceScore(for: seg.identification)
                )
            }

            // Build speaker embeddings map
            var speakerEmbeddings: [String: [Float]] = [:]
            for seg in axiiResult.segments {
                let spkId = mapAxiiSpeakerId(seg)
                if let emb = seg.speaker.embedding, !emb.isEmpty, speakerEmbeddings[spkId] == nil {
                    speakerEmbeddings[spkId] = emb
                }
            }

            // Post-process: merge short segments, smooth rapid switches
            let smoothed = postProcessSegments(bridgeSegments)
            allSegments = smoothed

            // Cap segment history
            if allSegments.count > 5000 {
                allSegments = Array(allSegments.suffix(4000))
            }

            let uniqueSpeakers = Set(smoothed.map { $0.speakerId })
            totalSpeakerCount = uniqueSpeakers.count

            // Diagnostic logging
            logCounter += 1
            if logCounter >= logInterval {
                logCounter = 0
                debugLog("[DiarizationManager] Processed chunk at \(String(format: "%.1f", position))s in \(String(format: "%.2f", processingTime))s — \(uniqueSpeakers.count) speakers, \(smoothed.count) segments")
            }

            // Diagnostic event
            let rawIds = Array(uniqueSpeakers).sorted()
            DiarizationDiagnostics.shared.logRawDiarizationOutput(
                chunkPosition: position,
                rawSpeakerCount: uniqueSpeakers.count,
                rawSpeakerIds: rawIds,
                segmentCount: smoothed.count,
                speakerDatabase: speakerEmbeddings.isEmpty ? nil : speakerEmbeddings
            )
            DiarizationDiagnostics.shared.counters.diarizationChunksProcessed += 1

            // Update published state
            let result = DiarizationResult(
                segments: allSegments,
                speakerEmbeddings: speakerEmbeddings.isEmpty ? nil : speakerEmbeddings
            )

            identifyUserSpeaker(in: result)
            lastResult = result
            currentSpeakers = Array(uniqueSpeakers).sorted()

        } catch {
            debugLog("❌ [DiarizationManager] Chunk processing failed: \(error)")
            lastError = error
        }
    }

    /// Finish processing and get final diarization results.
    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized, let activeSession = session else { return nil }

        // Process remaining buffered audio
        if !audioBuffer.isEmpty {
            let minSamples = Int(sampleRate * 3.0)
            if audioBuffer.count >= minSamples {
                await processChunk(audioBuffer, at: streamPosition)
            }
            audioBuffer.removeAll()
        }

        // Finalize the session — processes any remaining internal buffer
        do {
            let finalResult = try activeSession.finalize()

            let bridgeSegments = finalResult.segments.map { seg -> TimedSpeakerSegment in
                let speakerId = mapAxiiSpeakerId(seg)
                let embedding = seg.speaker.embedding ?? []
                return TimedSpeakerSegment(
                    speakerId: speakerId,
                    embedding: embedding,
                    startTimeSeconds: Float(seg.start),
                    endTimeSeconds: Float(seg.end),
                    qualityScore: confidenceScore(for: seg.identification)
                )
            }

            var speakerEmbeddings: [String: [Float]] = [:]
            for seg in finalResult.segments {
                let spkId = mapAxiiSpeakerId(seg)
                if let emb = seg.speaker.embedding, !emb.isEmpty, speakerEmbeddings[spkId] == nil {
                    speakerEmbeddings[spkId] = emb
                }
            }

            let smoothed = postProcessSegments(bridgeSegments)
            let result = DiarizationResult(
                segments: smoothed,
                speakerEmbeddings: speakerEmbeddings.isEmpty ? nil : speakerEmbeddings
            )

            lastResult = result
            debugLog("✅ [DiarizationManager] Finalized: \(result.speakerCount) speakers, \(smoothed.count) segments")
            return result
        } catch {
            debugLog("❌ [DiarizationManager] Finalization failed: \(error)")
            return lastResult
        }
    }

    // MARK: - Speaker Management

    /// Match an embedding against the current session's known speakers.
    func matchAgainstCache(embedding: [Float]) -> String? {
        guard let activeSession = session else { return nil }
        // Use Axii's built-in speaker matching
        if let match = activeSession.matchSpeaker(embedding: embedding, threshold: 0.6) {
            return match.id
        }
        return nil
    }

    /// Merge two speakers using Axii's pin mechanism.
    /// Returns the embedding of the source speaker for voice learning.
    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]? {
        guard let activeSession = session else {
            debugLog("⚠️ [DiarizationManager] mergeCacheSpeakers: no active session")
            return nil
        }

        // Get the source speaker's embedding before merging
        let sourceEmbedding = lastResult?.speakerEmbeddings?[sourceId]

        // Pin all source segments to the destination speaker
        let sourceSegments = allSegments.filter { $0.speakerId == sourceId }
        let timeRanges = sourceSegments.map { seg in
            (start: Double(seg.startTimeSeconds), end: Double(seg.endTimeSeconds))
        }

        if let destProfile = knownSpeakerProfiles.first(where: { $0.id == destinationId }) {
            activeSession.pinSegments(timeRanges, toSpeaker: destProfile)
        }

        // Reprocess to apply the merge
        do {
            let _ = try activeSession.reprocess()
        } catch {
            debugLog("⚠️ [DiarizationManager] Reprocess after merge failed: \(error)")
        }

        // Update local state
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

        debugLog("🔗 [DiarizationManager] Merged speaker '\(sourceId)' → '\(destinationId)' (speakers remaining: \(totalSpeakerCount))")
        return sourceEmbedding
    }

    /// Compare two audio samples to determine if they're the same speaker.
    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        guard let pipe = pipeline else {
            throw DiarizationError.notInitialized
        }

        let minSamples = Int(sampleRate * 3.0)
        guard audio1.count >= minSamples, audio2.count >= minSamples else {
            throw DiarizationError.insufficientAudio
        }

        // Create temporary sessions for each audio sample
        let session1 = pipe.createSession()
        let session2 = pipe.createSession()

        session1.addAudio(audio1)
        session2.addAudio(audio2)

        let result1 = try session1.finalize()
        let result2 = try session2.finalize()

        guard let emb1 = result1.segments.first?.speaker.embedding,
              let emb2 = result2.segments.first?.speaker.embedding else {
            throw DiarizationError.processingFailed("Could not extract speaker embeddings")
        }

        return VectorMath.cosineSimilarity(emb1, emb2)
    }

    /// Export enriched embeddings for voice learning after a confirmed meeting.
    func enrichedEmbeddings(for speakerId: String) -> [[Float]]? {
        guard let activeSession = session else { return nil }
        guard let profile = knownSpeakerProfiles.first(where: { $0.id == speakerId }) else {
            return nil
        }
        return activeSession.enrichedEmbeddings(for: profile)
    }

    // MARK: - Audio File Processing

    /// Process an audio file for diarization (used for voice training).
    func processAudioFile(_ fileURL: URL) async throws -> DiarizationResult {
        guard isEnabled, isInitialized, let pipe = pipeline else {
            throw DiarizationError.notInitialized
        }

        debugLog("🎤 [DiarizationManager] Processing audio file: \(fileURL.lastPathComponent)")

        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            throw DiarizationError.processingFailed("Could not read audio file")
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.processingFailed("Could not create audio buffer")
        }
        try audioFile.read(into: buffer)

        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            throw DiarizationError.processingFailed("Could not convert audio format")
        }

        isProcessing = true

        do {
            // Create a dedicated session for file processing
            let fileSession = pipe.createSession()
            fileSession.addAudio(floatSamples)
            let axiiResult = try fileSession.finalize()

            let bridgeSegments = axiiResult.segments.map { seg -> TimedSpeakerSegment in
                let speakerId = mapAxiiSpeakerId(seg)
                let embedding = seg.speaker.embedding ?? []
                return TimedSpeakerSegment(
                    speakerId: speakerId,
                    embedding: embedding,
                    startTimeSeconds: Float(seg.start),
                    endTimeSeconds: Float(seg.end),
                    qualityScore: confidenceScore(for: seg.identification)
                )
            }

            var speakerEmbeddings: [String: [Float]] = [:]
            for seg in axiiResult.segments {
                let spkId = mapAxiiSpeakerId(seg)
                if let emb = seg.speaker.embedding, !emb.isEmpty, speakerEmbeddings[spkId] == nil {
                    speakerEmbeddings[spkId] = emb
                }
            }

            let result = DiarizationResult(
                segments: bridgeSegments,
                speakerEmbeddings: speakerEmbeddings.isEmpty ? nil : speakerEmbeddings
            )

            lastResult = result
            isProcessing = false

            debugLog("✅ [DiarizationManager] File processing complete. Found \(result.speakerCount) speaker(s)")
            return result
        } catch {
            isProcessing = false
            lastError = error
            throw DiarizationError.processingFailed(error.localizedDescription)
        }
    }

    // MARK: - Reset and Cleanup

    func reset() {
        audioBuffer.removeAll()
        allSegments.removeAll()
        lastResult = nil
        lastError = nil
        processingProgress = 0.0
        isProcessing = false
        streamPosition = 0.0
        currentSpeakers.removeAll()
        totalSpeakerCount = 0
        userSpeakerId = nil
        logCounter = 0
        resamplingConverter = nil
        resamplingSourceFormat = nil

        // Recreate session (preserves known speaker profiles)
        if let pipe = pipeline {
            if knownSpeakerProfiles.isEmpty {
                session = pipe.createSession()
            } else {
                session = pipe.createSession(knownSpeakers: knownSpeakerProfiles)
            }
        }

        debugLog("🔄 [DiarizationManager] Reset complete")
    }

    // MARK: - Private Helpers

    /// Map an Axii segment to a stable speaker ID string.
    private func mapAxiiSpeakerId(_ segment: DiarizationSegment) -> String {
        switch segment.identification {
        case .autoMatched(let speakerID, _):
            return speakerID
        case .pinned(let speakerID):
            return speakerID
        case .unknown:
            return segment.speaker.id
        }
    }

    /// Convert Axii identification confidence to a quality score.
    private func confidenceScore(for identification: SpeakerIdentification) -> Float {
        switch identification {
        case .autoMatched(_, let confidence):
            return confidence
        case .pinned:
            return 1.0
        case .unknown:
            return 0.5
        }
    }

    /// Identify if any detected speakers match the current user's voice profile.
    private func identifyUserSpeaker(in result: DiarizationResult) {
        guard UserProfile.shared.hasVoiceProfile,
              UserProfile.shared.voiceEmbedding != nil else {
            return
        }

        guard userSpeakerId == nil else { return }

        for segment in result.segments {
            let (matches, confidence) = UserProfile.shared.matchesUserVoice(segment.embedding)
            if matches {
                userSpeakerId = segment.speakerId
                debugLog("🎤 [DiarizationManager] ✅ IDENTIFIED USER as speaker \(segment.speakerId) (confidence: \(String(format: "%.1f%%", confidence * 100)))")
                break
            }
        }
    }

    /// Apply post-processing to smooth diarization results.
    private func postProcessSegments(_ segments: [TimedSpeakerSegment]) -> [TimedSpeakerSegment] {
        guard segments.count > 1 else { return segments }

        var smoothed: [TimedSpeakerSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            let currentDuration = current.endTimeSeconds - current.startTimeSeconds

            if currentDuration < minSegmentDuration {
                if smoothed.isEmpty {
                    current = TimedSpeakerSegment(
                        speakerId: next.speakerId,
                        embedding: next.embedding,
                        startTimeSeconds: current.startTimeSeconds,
                        endTimeSeconds: next.endTimeSeconds,
                        qualityScore: next.qualityScore
                    )
                    continue
                } else if let last = smoothed.last, last.speakerId == next.speakerId {
                    smoothed.removeLast()
                    current = TimedSpeakerSegment(
                        speakerId: last.speakerId,
                        embedding: last.embedding,
                        startTimeSeconds: last.startTimeSeconds,
                        endTimeSeconds: next.endTimeSeconds,
                        qualityScore: max(last.qualityScore, next.qualityScore)
                    )
                    continue
                }
            }

            if current.speakerId == next.speakerId {
                current = TimedSpeakerSegment(
                    speakerId: current.speakerId,
                    embedding: current.embedding,
                    startTimeSeconds: current.startTimeSeconds,
                    endTimeSeconds: next.endTimeSeconds,
                    qualityScore: max(current.qualityScore, next.qualityScore)
                )
            } else {
                smoothed.append(current)
                current = next
            }
        }

        smoothed.append(current)
        return smoothed
    }

    /// Convert AVAudioPCMBuffer to Float array at 16kHz mono.
    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate

        // Fast path: already at 16kHz
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

        // Slow path: resampling via AVAudioConverter
        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            return nil
        }

        guard let sourceMonoFormat = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1) else {
            return nil
        }
        guard let sourceMonoBuffer = AVAudioPCMBuffer(pcmFormat: sourceMonoFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
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
            debugLog("⚠️ [DiarizationManager] Resampling failed: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        let outputCount = Int(outputBuffer.frameLength)
        var samples = [Float](repeating: 0, count: outputCount)
        memcpy(&samples, outputData[0], outputCount * MemoryLayout<Float>.size)
        return samples
    }

    deinit {
        audioBuffer.removeAll()
        allSegments.removeAll()
        streamPosition = 0.0
        debugLog("🧹 [DiarizationManager] Cleaned up")
    }
}
#endif

// MARK: - Speaker Profile Bridge

/// Bridges WhoNext's voice profile storage with AxiiDiarization's SpeakerProfile protocol.
struct WhoNextSpeakerProfile: Sendable {
    let id: String
    let name: String
    let embeddings: [[Float]]
}

#if canImport(AxiiDiarization)
extension WhoNextSpeakerProfile: SpeakerProfile {}
#endif

// MARK: - Error Types

enum DiarizationError: LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case processingFailed(String)
    case invalidAudioFormat
    case insufficientAudio

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Diarization manager not initialized"
        case .initializationFailed(let message):
            return "Failed to initialize diarization: \(message)"
        case .processingFailed(let message):
            return "Diarization processing failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for diarization"
        case .insufficientAudio:
            return "Not enough audio for reliable diarization (minimum 3 seconds required)"
        }
    }
}
