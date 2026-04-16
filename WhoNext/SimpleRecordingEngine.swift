import Foundation
import AVFoundation
import Accelerate
import Combine
import ScreenCaptureKit
import os
import AxiiDiarization

// MARK: - Diarization Backend Factory

/// Creates the appropriate diarization engine based on user's config selection.
@MainActor
func createDiarizationEngine(enableRealTimeProcessing: Bool = true, maxSpeakers: Int? = nil) -> any DiarizationEngine {
    let backend = MeetingRecordingConfiguration.shared.transcriptionSettings.diarizationBackend
    switch backend {
    case .fluidAudio:
        debugLog("[DiarizationFactory] Creating FluidAudio backend")
        return FluidAudioDiarizationBackend(
            clusteringThreshold: 0.7,
            maxSpeakers: maxSpeakers
        )
    case .axiiDiarization:
        debugLog("[DiarizationFactory] Creating AxiiDiarization backend")
        return DiarizationManager(
            enableRealTimeProcessing: enableRealTimeProcessing,
            maxSpeakers: maxSpeakers
        )
    case .centroidClustering:
        debugLog("[DiarizationFactory] Creating CentroidClusterer backend")
        return CentroidClusterer(
            maxSpeakers: maxSpeakers ?? 6
        )
    case .speechSwift:
        debugLog("[DiarizationFactory] Creating speech-swift backend (Pyannote v4 + WeSpeaker)")
        return SpeechSwiftDiarizationBackend(
            clusteringThreshold: 0.715,
            maxSpeakers: maxSpeakers
        )
    }
}

/// Simplified recording engine - replaces the complex MeetingRecordingEngine
/// Uses clean, linear pipeline: AudioCapturer -> AudioChunkBuffer -> TranscriptionEngine
/// Parallel diarization pipeline: AudioCapturer -> DiarizationBuffer -> DiarizationManager -> SegmentAligner
@MainActor
class SimpleRecordingEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = SimpleRecordingEngine()

    // MARK: - Published State (UI-Compatible Interface)

    @Published var isRecording = false
    @Published var isMonitoring = false
    @Published var currentMeeting: LiveMeeting?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingState: RecordingState = .idle
    @Published var autoRecordEnabled = false

    // Audio levels for UI
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0

    // Audio capture mode (mic-only if screen recording permission denied)
    @Published var isMicOnlyMode: Bool = false

    // Speaker diarization state
    @Published var detectedSpeakerCount: Int = 0
    @Published var hasRemoteAudio: Bool = false

    /// Expected number of attendees from calendar data (used to constrain diarization)
    var expectedAttendeeCount: Int?

    // MARK: - Diarization Strategy

    /// Determines how speaker identification is performed based on AEC availability and meeting size.
    /// - streamLabeling: 1:1 with AEC — mic=local, system=remote. Zero diarization.
    /// - streamLabelingNoAEC: 1:1 without AEC — energy gate on mic, Axii on system (1 remote speaker).
    /// - groupStreaming: Group — energy gate on mic, Axii on system (N remote speakers).
    enum DiarizationStrategy: String {
        case streamLabeling       // 1:1 with AEC: mic=local, system=remote. Zero diarization.
        case streamLabelingNoAEC  // 1:1 without AEC: energy gate on mic, Axii on system (1 speaker).
        case groupStreaming       // Group: energy gate on mic, Axii on system (N speakers).
    }

    @Published private(set) var diarizationStrategy: DiarizationStrategy = .streamLabelingNoAEC

    /// RMS threshold for VAD (Voice Activity Detection) in stream labeling / hybrid modes
    private let vadRMSThreshold: Float = 0.003

    // MARK: - Multi-Speaker Detection (Dynamic Upgrade)

    /// Rolling window of system audio speech energy values for multi-speaker detection.
    /// When energy variance is high relative to mean, it suggests multiple speakers.
    private var systemSpeechEnergies: [Float] = []
    /// Maximum number of energy samples to retain in the rolling window
    private let energyWindowSize = 50
    /// Number of consecutive windows where multi-speaker evidence was detected
    private var multiSpeakerEvidenceCount = 0
    /// Threshold: trigger upgrade after this many consecutive evidence windows.
    /// Raised from 3 to 10 to prevent false positives from single-source audio
    /// (e.g., YouTube video with natural energy variation).
    private let multiSpeakerEvidenceThreshold = 10
    /// Coefficient of variation threshold — above this suggests multiple speakers.
    /// Raised from 0.6 to 0.8 because single-speaker audio (YouTube, podcasts)
    /// regularly produces CV of 0.6-0.7 due to natural speech dynamics.
    private let energyCVThreshold: Float = 0.8

    // MARK: - System Audio Buffer (Strategy Upgrade Catch-Up)

    /// Buffers recent system audio during streamLabeling mode so the diarizer
    /// can catch up when upgrading to hybridGroup mid-recording.
    private var systemAudioCatchUpBuffer: [AVAudioPCMBuffer] = []
    /// Maximum catch-up buffer duration in seconds (at 16kHz)
    private let maxCatchUpBufferSeconds: Double = 60.0
    /// Running count of buffered frames for size management
    private var catchUpBufferFrameCount: Int = 0

    // MARK: - Components

    private let audioCapturer = AudioCapturer()
    private let chunkBuffer = AudioChunkBuffer()
    private var transcriber: (any TranscriptionEngineProtocol)?

    // MARK: - Diarization Components

    /// System stream diarizer — backend selected at recording start based on config.
    /// No mic diarizer needed: energy gate handles local speaker detection.
    private var systemDiarizationManager: any DiarizationEngine = DiarizationManager(enableRealTimeProcessing: true)
    private let systemDiarizationBuffer = DiarizationBuffer()
    private let segmentAligner = SegmentAligner()
    private let voicePrintManager = VoicePrintManager()

    // MARK: - Auto-Enrollment (Voice Profile)

    /// Accumulates clean mic audio for extracting the local user's voice embedding.
    /// Used during the first ~15 seconds of a recording to auto-enroll the speaker.
    private var enrollmentSamples: [Float] = []
    /// Target sample count for enrollment (15 seconds at 16kHz)
    private let enrollmentTargetSamples = 15 * 16000
    /// Whether enrollment has been completed for this session
    private var enrollmentComplete = false

    // MARK: - Asymmetric Dual-Stream Components

    private var energyGateDetector: EnergyGateDetector?
    /// Current system audio RMS, updated by system stream for energy gate cross-reference.
    /// Thread-safe: written by system audio task, read by mic audio task inside withTaskGroup.
    private let systemRMSLock = OSAllocatedUnfairLock(initialState: Float(0))

    private var currentSystemRMS: Float {
        get { systemRMSLock.withLock { $0 } }
        set { systemRMSLock.withLock { $0 = newValue } }
    }

    // MARK: - Offline Re-Diarization Components

    /// Audio file writer for saving system audio to disk during recording
    private var systemAudioWriter: AVAudioFile?
    /// URL of the system audio file being recorded
    private var systemAudioFileURL: URL?
    /// Audio file writer for saving mic audio to disk during recording
    private var micAudioWriter: AVAudioFile?
    /// URL of the mic audio file being recorded
    private var micAudioFileURL: URL?
    /// Cached converter for WAV writing (avoids creating a new AVAudioConverter per buffer)
    private var wavWriterConverter: AVAudioConverter?
    private var wavWriterSourceFormat: AVAudioFormat?
    /// Audio storage manager for file creation, compression, and lifecycle
    private let audioStorageManager = AudioStorageManager()

    // MARK: - Private State

    private var recordingTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    /// Precise elapsed recording time using wall clock (sub-ms accuracy).
    /// Unlike `recordingDuration` (updated by 1-second Timer on MainActor),
    /// this can be called from any thread at any time.
    private var preciseElapsed: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    private var cancellables = Set<AnyCancellable>()

    /// Cursor tracking the first transcript segment that may still need speaker backfill.
    /// Avoids re-scanning already-attributed segments on every diarization update.
    private var backfillCursor: Int = 0

    // MARK: - Initialization

    private init() {
        setupObservers()
        debugLog("[SimpleRecordingEngine] Initialized")
    }

    private func setupObservers() {
        // Forward audio levels from capturer
        audioCapturer.$micLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.micLevel = level
            }
            .store(in: &cancellables)

        audioCapturer.$systemLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.systemLevel = level
            }
            .store(in: &cancellables)

        // Forward capture mode changes
        audioCapturer.$captureMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.isMicOnlyMode = (mode == .microphoneOnly)
            }
            .store(in: &cancellables)

        // Log AEC status changes
        audioCapturer.$isEchoCancellationActive
            .receive(on: RunLoop.main)
            .sink { active in
                debugLog("[SimpleRecordingEngine] AEC status: \(active ? "active" : "inactive")")
            }
            .store(in: &cancellables)
    }

    // MARK: - Pre-warming

    /// Initialize transcription engine and diarization ahead of time
    func preWarm() async {
        // Create transcription engine based on settings
        let settings = MeetingRecordingConfiguration.shared.transcriptionSettings
        transcriber = TranscriptionManagerFactory.createEngine(for: settings)
        do {
            try await transcriber?.initialize()
            let engineName = settings.transcriptionEngine.displayName
            debugLog("[SimpleRecordingEngine] Pre-warmed transcriber with engine: \(engineName)")
        } catch {
            debugLog("[SimpleRecordingEngine] Transcriber pre-warm failed: \(error) — will record without transcription")
        }

        // Initialize diarization (independent of transcriber)
        systemDiarizationManager = createDiarizationEngine()
        do {
            try await systemDiarizationManager.initialize()
            let backendName = MeetingRecordingConfiguration.shared.transcriptionSettings.diarizationBackend.displayName
            debugLog("[SimpleRecordingEngine] Pre-warmed system diarization manager (\(backendName))")
        } catch {
            debugLog("[SimpleRecordingEngine] Diarization pre-warm failed: \(error)")
        }

        await voicePrintManager.warmCache()
        debugLog("[SimpleRecordingEngine] Pre-warmed voice print cache")
    }

    // MARK: - Recording Control

    func manualStartRecording() {
        Task {
            await startRecording()
        }
    }

    func manualStopRecording() {
        Task {
            await stopRecording()
        }
    }

    /// Start recording
    func startRecording() async {
        guard !isRecording else {
            debugLog("[SimpleRecordingEngine] Already recording")
            return
        }

        debugLog("[SimpleRecordingEngine] Starting recording...")

        do {
            // --- Phase 1: Start audio capture first ---
            // Audio capture must complete before strategy selection so
            // isEchoCancellationActive is set before ensureDiarizationReady() reads it.
            let meeting = LiveMeeting()
            meeting.calendarTitle = "Recording"
            meeting.startTime = Date()
            currentMeeting = meeting
            await chunkBuffer.reset()

            // Derive expected attendee count from calendar data if available
            if !meeting.expectedParticipants.isEmpty {
                expectedAttendeeCount = meeting.expectedParticipants.count
            }

            // Start audio capture first (sets AEC status)
            try await audioCapturer.startCapture()

            // Now run transcriber init + diarization ready in parallel
            // (both depend on AEC status being set, but are independent of each other)
            async let transcriberReady: Void = ensureTranscriberReady()
            async let diarizationReady: Void = ensureDiarizationReady()

            do {
                try await transcriberReady
            } catch {
                debugLog("[SimpleRecordingEngine] Transcriber unavailable (\(error.localizedDescription)) — recording without transcription")
            }
            _ = await diarizationReady  // non-throwing wrapper

            // Start diagnostic collection for this session
            DiarizationDiagnostics.shared.startSession()

            // --- Phase 2: Start (all sequential deps satisfied) ---
            isRecording = true
            recordingState = .recording
            recordingDuration = 0
            recordingStartTime = Date()
            startDurationTimer()
            RecordingWindowManager.shared.show()

            recordingTask = Task {
                await processAudioStreams()
            }

            debugLog("[SimpleRecordingEngine] Recording started")
            SessionLog.shared.flush()

        } catch {
            debugLog("[SimpleRecordingEngine] Failed to start: \(error)")
            recordingState = .error(error.localizedDescription)
            currentMeeting = nil
        }
    }

    /// Ensure the transcription engine is initialized and ready
    private func ensureTranscriberReady() async throws {
        if transcriber == nil || transcriber?.isReady != true {
            let settings = MeetingRecordingConfiguration.shared.transcriptionSettings
            transcriber = TranscriptionManagerFactory.createEngine(for: settings)
            try await transcriber?.initialize()
            debugLog("[SimpleRecordingEngine] Transcriber initialized: \(settings.transcriptionEngine.displayName)")
        }
        transcriber?.resetState()
    }

    /// Ensure diarization is initialized and reset for a new recording.
    /// Selects strategy based on AEC availability and expected attendee count.
    private func ensureDiarizationReady() async {
        // --- Strategy Selection ---
        let attendeeCount = expectedAttendeeCount ?? 2
        let aecAvailable = audioCapturer.isEchoCancellationActive

        if aecAvailable && attendeeCount <= 2 {
            diarizationStrategy = .streamLabeling
        } else if aecAvailable && attendeeCount > 2 {
            diarizationStrategy = .groupStreaming  // Group with AEC — clean system audio for diarization
        } else if attendeeCount <= 2 {
            diarizationStrategy = .streamLabelingNoAEC
        } else {
            diarizationStrategy = .groupStreaming  // Group without AEC — fallback
        }
        debugLog("[SimpleRecordingEngine] 🎯 Strategy: \(diarizationStrategy.rawValue) (AEC: \(aecAvailable), attendees: \(attendeeCount))")

        // --- Initialize Based on Strategy ---
        switch diarizationStrategy {
        case .streamLabeling:
            // AEC 1:1: mic=local, system=remote. No diarization needed.
            detectedSpeakerCount = 2
            hasRemoteAudio = true
            debugLog("[SimpleRecordingEngine] Stream labeling mode: no diarizers created")

        case .streamLabelingNoAEC:
            // 1:1 without AEC: energy gate on mic, simple VAD on system.
            // NO diarizer — a diarizer on mixed mono system audio creates phantom speakers
            // because voice variation over 30+ minutes causes embedding drift.
            // Instead, use binary classification: energy gate = You, system VAD = Remote Speaker.
            energyGateDetector = EnergyGateDetector()
            currentSystemRMS = 0

            hasRemoteAudio = true
            detectedSpeakerCount = 2
            debugLog("[SimpleRecordingEngine] 1:1 no-AEC mode: energy gate on mic, VAD-only on system (no diarizer)")

        case .groupStreaming:
            // Group: energy gate on mic, diarizer on system (auto-detect N remote speakers)
            energyGateDetector = EnergyGateDetector()
            currentSystemRMS = 0

            let remoteSpeakers = max(attendeeCount - 1, 2)
            systemDiarizationManager = createDiarizationEngine(maxSpeakers: remoteSpeakers + 1)
            do {
                try await systemDiarizationManager.initialize()
                debugLog("[SimpleRecordingEngine] System diarization initialized (groupStreaming, maxSpeakers: \(remoteSpeakers + 1))")
            } catch {
                debugLog("[SimpleRecordingEngine] System diarization init failed: \(error)")
            }

            await preloadKnownSpeakersForMeeting()

            hasRemoteAudio = true
            detectedSpeakerCount = attendeeCount
            debugLog("[SimpleRecordingEngine] Group streaming mode: energy gate on mic, Axii on system")
        }

        await systemDiarizationBuffer.reset()
        segmentAligner.reset()
        backfillCursor = 0

        // Reset dynamic upgrade detection state
        systemSpeechEnergies.removeAll()
        multiSpeakerEvidenceCount = 0
        systemAudioCatchUpBuffer.removeAll()
        catchUpBufferFrameCount = 0

        // Reset auto-enrollment
        enrollmentSamples.removeAll()
        enrollmentComplete = false
    }

    // MARK: - Guided Diarization Helpers

    /// Pre-load known voice profiles into the system diarizer from VoicePrintManager.
    /// Uses calendar expectedParticipants to narrow scope, falls back to all known voices.
    private func preloadKnownSpeakersForMeeting() async {
        guard let meeting = currentMeeting else { return }

        // Gather expected people from calendar attendees
        let expectedNames = meeting.expectedParticipants
        var knownSpeakers: [(id: String, name: String, embedding: [Float])] = []

        if !expectedNames.isEmpty {
            // Try to match calendar names to Person records with voice embeddings
            for name in expectedNames {
                // Search for Person by name in VoicePrintManager cache
                if let match = await voicePrintManager.findMatchingPersonByName(name),
                   let embedding = voicePrintManager.getStoredEmbedding(for: match) {
                    knownSpeakers.append((
                        id: match.identifier?.uuidString ?? UUID().uuidString,
                        name: match.wrappedName,
                        embedding: embedding
                    ))
                }
            }
        }

        // If no calendar matches, load all known voice profiles as candidates
        if knownSpeakers.isEmpty {
            let allEmbeddings = await voicePrintManager.getAllStoredEmbeddings()
            knownSpeakers = allEmbeddings
        }

        if !knownSpeakers.isEmpty {
            systemDiarizationManager.preloadKnownSpeakers(knownSpeakers)
            debugLog("[SimpleRecordingEngine] 🎯 Pre-loaded \(knownSpeakers.count) known speakers for guided diarization")
        } else {
            debugLog("[SimpleRecordingEngine] ⚠️ No known voice profiles available for guided diarization")
        }
    }
    /// Merge two speakers and feed the correction back to VoicePrintManager.
    /// Called from the UI when the user confirms a drag-and-drop speaker merge.
    func handleSpeakerMerge(sourceID: String, destinationID: String, destinationPerson: Person?) -> [Float]? {
        let sourceCentroid = systemDiarizationManager.mergeCacheSpeakers(
            sourceId: sourceID,
            destinationId: destinationID
        )

        // Feed the merged embedding to VoicePrintManager for cross-session voice learning
        if let centroid = sourceCentroid, let person = destinationPerson {
            voicePrintManager.saveEmbeddingWithFeedback(centroid, for: person, wasConfirmed: true)
            debugLog("[SimpleRecordingEngine] Voice learning: saved merged embedding to \(person.wrappedName)")
        }

        return sourceCentroid
    }

    /// Stop recording
    func stopRecording() async {
        guard isRecording else {
            debugLog("[SimpleRecordingEngine] Not recording")
            return
        }

        debugLog("[SimpleRecordingEngine] Stopping recording...")

        // Ensure state is always cleaned up, even if finalization throws
        defer {
            isRecording = false
            recordingState = .idle
        }

        // Cancel processing task
        recordingTask?.cancel()
        recordingTask = nil

        // Stop timer
        stopDurationTimer()

        // Stop audio capture
        audioCapturer.stopCapture()

        // Flush remaining transcription audio
        if let finalChunk = await chunkBuffer.flush() {
            await transcribeChunk(finalChunk)
        }

        // Flush remaining diarization audio (strategy-aware)
        switch diarizationStrategy {
        case .streamLabeling:
            // No diarization to flush — VAD-only mode
            break

        case .streamLabelingNoAEC:
            // No diarizer to flush — just flush energy gate
            if let finalSegment = energyGateDetector?.flush(at: recordingDuration) {
                let result = DiarizationResult(
                    segments: [finalSegment],
                    speakerEmbeddings: nil
                )
                segmentAligner.updateDiarizationResults(result)
            }
            energyGateDetector?.reset()

        case .groupStreaming:
            // Flush system diarization
            if let (finalSysDiarChunk, sysStartTime) = await systemDiarizationBuffer.flush() {
                await processSystemDiarizationChunk(finalSysDiarChunk, startTime: sysStartTime)
            }
            _ = await systemDiarizationManager.finishProcessing()

            // Flush any in-progress energy gate segment
            if let finalSegment = energyGateDetector?.flush(at: recordingDuration) {
                let result = DiarizationResult(
                    segments: [finalSegment],
                    speakerEmbeddings: nil
                )
                segmentAligner.updateDiarizationResults(result)
            }
            energyGateDetector?.reset()
        }

        // Close audio file writers and reset cached converter
        systemAudioWriter = nil
        micAudioWriter = nil
        wavWriterConverter = nil
        wavWriterSourceFormat = nil

        // Stop diagnostic collection and log pipeline summary
        DiarizationDiagnostics.shared.logPipelineSnapshot()
        DiarizationDiagnostics.shared.stopSession()

        // Post-meeting voice learning (save embeddings before finalization)
        await saveVoiceEmbeddingsPostMeeting()

        // Clean up catch-up buffer memory
        systemAudioCatchUpBuffer.removeAll()
        catchUpBufferFrameCount = 0

        // Update state for processing phase
        recordingState = .processing

        // Finalize meeting
        if let meeting = currentMeeting {
            await finalizeMeeting(meeting)
        }

        // Meeting summary — always logged (visible without Xcode via session log export)
        logMeetingSummary()
        SessionLog.shared.flush()
        debugLog("[SimpleRecordingEngine] Recording stopped")
    }

    /// Thread-safe accessor for the current diarization strategy.
    /// Used from task group closures that can't directly access @Published properties.
    @MainActor
    private func currentStrategy() -> DiarizationStrategy {
        diarizationStrategy
    }

    // MARK: - Audio Processing

    private func processAudioStreams() async {
        debugLog("[SimpleRecordingEngine] Starting audio stream processing (strategy: \(diarizationStrategy.rawValue))")

        // Get streams on main actor before entering task group
        let micStream = audioCapturer.micStream!
        let systemStream = audioCapturer.systemStream!
        let buffer = chunkBuffer
        // NOTE: Read diarizationStrategy LIVE in each iteration (via self.diarizationStrategy),
        // not captured once here. The strategy can upgrade mid-recording (e.g., streamLabeling
        // → groupStreaming) and the running loop must pick up the change.

        let systemDiarBuffer = systemDiarizationBuffer

        // Process mic and system audio concurrently
        await withTaskGroup(of: Void.self) { group in
            // Mic stream processor
            group.addTask {
                for await audioBuffer in micStream {
                    guard !Task.isCancelled else { break }

                    // Always add to chunk buffer for transcription
                    if let chunk = await buffer.addBuffer(audioBuffer, isMic: true) {
                        await self.transcribeChunk(chunk)
                    }

                    // Read strategy live each iteration so mid-recording upgrades take effect
                    let currentStrategy = await self.currentStrategy()
                    switch currentStrategy {
                    case .streamLabeling:
                        // AEC 1:1: mic = local speaker. VAD only.
                        await self.processMicVAD(audioBuffer)

                    case .streamLabelingNoAEC:
                        // 1:1 no-AEC: energy gate detects local speech
                        await self.processEnergyGateMic(audioBuffer)

                    case .groupStreaming:
                        // Group: energy gate detects local speech vs system bleed
                        await self.processEnergyGateMic(audioBuffer)
                    }
                }
            }

            // System stream processor
            group.addTask {
                for await audioBuffer in systemStream {
                    guard !Task.isCancelled else { break }

                    // Always add to chunk buffer for transcription
                    if let chunk = await buffer.addBuffer(audioBuffer, isMic: false) {
                        await self.transcribeChunk(chunk)
                    }

                    // Read strategy live each iteration so mid-recording upgrades take effect
                    let currentStrategy = await self.currentStrategy()
                    switch currentStrategy {
                    case .streamLabeling:
                        // AEC 1:1: system = remote speaker. VAD only.
                        await self.processSystemVAD(audioBuffer)

                    case .streamLabelingNoAEC:
                        // 1:1 no-AEC: simple VAD on system, suppressed when energy gate says local speaker is talking.
                        // No diarizer — binary classification avoids phantom speaker creation.
                        await self.processSystemVADNoAEC(audioBuffer)

                    case .groupStreaming:
                        // Group: feed system audio to diarizer for remote speaker(s)
                        await self.processSystemDiarization(audioBuffer, systemDiarBuffer: systemDiarBuffer)
                    }
                }
            }

        }

        debugLog("[SimpleRecordingEngine] Audio stream processing ended")
    }

    /// Perform transcription work off the main actor, then update UI on MainActor
    private nonisolated func transcribeChunkInBackground(_ chunk: [Float], transcriber: any TranscriptionEngineProtocol) async -> (text: String, confidence: Float, tokenTimings: [UnifiedTranscriptionResult.UnifiedTokenTiming]?)? {
        do {
            if let result = try await transcriber.transcribe(audioChunk: chunk) {
                return (text: result.text, confidence: result.confidence, tokenTimings: result.tokenTimings)
            }
        } catch {
            debugLog("[SimpleRecordingEngine] Transcription error: \(error)")
        }
        return nil
    }

    private func transcribeChunk(_ chunk: [Float]) async {
        guard let transcriber else {
            debugLog("[SimpleRecordingEngine] Transcriber not initialized")
            return
        }

        // Capture chunk start time BEFORE async transcription — using precise wall clock.
        // If captured after the await, recordingDuration will have advanced by the
        // transcription latency (2-4s), causing word absolute times to misalign with
        // segment timestamps and breaking speaker attribution.
        let chunkDuration = Double(chunk.count) / 16000.0
        let chunkStartTime = max(0, preciseElapsed - chunkDuration)

        // Log chunk stats
        let stats = await chunkBuffer.getStats()
        debugLog("[SimpleRecordingEngine] Transcribing chunk: \(chunk.count) samples, chunkStart=\(String(format: "%.2f", chunkStartTime))s")
        debugLog("[SimpleRecordingEngine] Buffer stats: \(stats.description)")

        // Perform heavy transcription work off MainActor
        guard let result = await transcribeChunkInBackground(chunk, transcriber: transcriber) else {
            return
        }

        // Word-level speaker attribution path: when token timings are available,
        // align individual words to diarization segments and create one TranscriptSegment
        // per speaker change (instead of one per entire chunk).

        if let timings = result.tokenTimings, !timings.isEmpty {
            let groups = segmentAligner.alignWords(wordTimings: timings, chunkStartTime: chunkStartTime)

            if !groups.isEmpty {
                for group in groups {
                    let speakerName = resolveSpeakerName(for: group.speakerId)

                    // Merge with previous segment if same speaker — builds a
                    // continuous, readable transcript instead of choppy per-chunk lines.
                    if let meeting = currentMeeting,
                       let lastIdx = meeting.transcript.indices.last,
                       meeting.transcript[lastIdx].speakerID == group.speakerId {
                        // Same speaker continues — append text to existing segment
                        let existing = meeting.transcript[lastIdx]
                        meeting.transcript[lastIdx] = TranscriptSegment(
                            id: existing.id,
                            text: existing.text + group.text,
                            timestamp: existing.timestamp,
                            speakerID: existing.speakerID,
                            speakerName: existing.speakerName,
                            confidence: (existing.confidence + result.confidence) / 2,
                            isFinalized: true,
                            diarizationSource: existing.diarizationSource
                        )
                        meeting.wordCount += group.words.count
                        debugLog("[SimpleRecordingEngine] Appended to segment (\(speakerName)): \"\(group.text.prefix(50))\"")
                    } else {
                        // New speaker — create a new segment
                        let segment = TranscriptSegment(
                            text: group.text,
                            timestamp: group.startTime,
                            speakerID: group.speakerId,
                            speakerName: speakerName,
                            confidence: result.confidence,
                            isFinalized: true
                        )
                        currentMeeting?.transcript.append(segment)
                        currentMeeting?.wordCount += group.words.count
                        debugLog("[SimpleRecordingEngine] New segment (\(speakerName)): \"\(group.text.prefix(50))\"")
                    }
                }
                return
            }
            // Fall through to single-segment path if alignWords returned empty
        }

        // Single-segment fallback: one speaker per chunk (original behavior)
        addSingleSegment(text: result.text, confidence: result.confidence)
    }

    /// Resolve a speaker ID to a display name using identified participants or formatting.
    private func resolveSpeakerName(for speakerId: String) -> String {
        if let participant = currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == speakerId }),
           participant.namingMode != .unnamed {
            return participant.displayName
        }
        return SegmentAligner.formatSpeakerName(speakerId)
    }

    /// Create a single TranscriptSegment for the entire chunk (original behavior / fallback).
    private func addSingleSegment(text: String, confidence: Float) {
        var speakerID: String? = nil
        var speakerName: String? = nil

        let chunkDuration: TimeInterval = 10.0
        let segmentStart = max(0, recordingDuration - chunkDuration)
        if let speaker = segmentAligner.dominantSpeaker(for: segmentStart, duration: chunkDuration) {
            speakerID = speaker
            if let participant = currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == speaker }),
               participant.namingMode != .unnamed {
                speakerName = participant.displayName
            } else {
                speakerName = SegmentAligner.formatSpeakerName(speaker)
            }
            debugLog("[SimpleRecordingEngine] Speaker identified: \(speakerName ?? "unknown")")
        } else if let meeting = currentMeeting, let lastSpeaker = meeting.transcript.last?.speakerID {
            speakerID = lastSpeaker
            speakerName = meeting.transcript.last?.speakerName
            debugLog("[SimpleRecordingEngine] Speaker fallback (temporal continuity): \(speakerName ?? lastSpeaker)")
        }

        let segment = TranscriptSegment(
            text: text,
            timestamp: recordingDuration,
            speakerID: speakerID,
            speakerName: speakerName,
            confidence: confidence,
            isFinalized: true
        )

        currentMeeting?.transcript.append(segment)
        currentMeeting?.wordCount += text.split(separator: " ").count

        let speakerInfo = speakerName ?? "unknown speaker"
        debugLog("[SimpleRecordingEngine] Added segment (\(speakerInfo)): \"\(text.prefix(50))...\"")
    }

    // MARK: - Diarization Processing

    /// Process a system audio diarization chunk through the Axii pipeline
    private func processSystemDiarizationChunk(_ chunk: [Float], startTime: TimeInterval) async {
        debugLog("[SimpleRecordingEngine] Processing system diarization chunk: \(chunk.count) samples at \(String(format: "%.1f", startTime))s")

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else {
            debugLog("[SimpleRecordingEngine] Failed to create audio buffer for system diarization")
            return
        }

        buffer.frameLength = AVAudioFrameCount(chunk.count)
        if let channelData = buffer.floatChannelData {
            for i in 0..<chunk.count {
                channelData[0][i] = chunk[i]
            }
        }

        await systemDiarizationManager.processAudioBuffer(buffer)

        if let error = systemDiarizationManager.lastError {
            debugLog("[SimpleRecordingEngine] System diarization error: \(error.localizedDescription)")
        }

        if let result = systemDiarizationManager.lastResult {
            debugLog("[SimpleRecordingEngine] System diarization result: \(result.segments.count) segments, \(result.speakerCount) speakers")
            segmentAligner.updateSystemDiarizationResults(result)

            // Speaker count = 1 (local via energy gate) + system diarizer remote speakers
            let systemSpeakers = systemDiarizationManager.totalSpeakerCount
            let effectiveCount = 1 + systemSpeakers
            if effectiveCount != detectedSpeakerCount {
                debugLog("[SimpleRecordingEngine] Speaker count updated (\(diarizationStrategy.rawValue)): \(detectedSpeakerCount) -> \(effectiveCount) (1 local + \(systemSpeakers) remote)")
            }
            detectedSpeakerCount = effectiveCount
            updateMeetingType(speakerCount: effectiveCount)

            // Cross-stream deduplication: suppress system clusters matching local user voice
            deduplicateLocalFromSystemClusters()

            // Note: auto-upgrade from streamLabelingNoAEC is no longer triggered here.
            // streamLabelingNoAEC now uses VAD-only (no diarizer), so this method
            // is only called in groupStreaming mode.

            await updateParticipants(from: result)

            // Sync with all valid speaker IDs: local + system speakers
            var allValidIDs = Set(result.segments.map { "sys_\($0.speakerId)" })
            allValidIDs.insert("mic_local_1")
            currentMeeting?.syncParticipants(withSpeakerIDs: allValidIDs)

            backfillSpeakerLabels()
        }
    }

    // MARK: - Stream Labeling Mode (VAD-Only)

    /// Process mic audio in stream labeling or hybrid mode: VAD only, label as local speaker.
    /// No diarization — AEC ensures mic contains only the local speaker's voice.
    private func processMicVAD(_ buffer: AVAudioPCMBuffer) async {
        let rms = calculateRMS(buffer)

        // Adaptive threshold: when system audio is active, AEC leaves residual
        // echo in the mic (~0.005-0.01 RMS). Raise the mic threshold to avoid
        // creating false mic segments for echo residual. Actual local speech is
        // much louder (~0.02-0.10 RMS) and still passes the higher threshold.
        let sysRMS = currentSystemRMS
        let effectiveThreshold: Float
        if sysRMS > vadRMSThreshold {
            // System active — require mic to be clearly above residual echo level
            effectiveThreshold = max(vadRMSThreshold * 5, 0.015)
        } else {
            effectiveThreshold = vadRMSThreshold
        }
        guard rms > effectiveThreshold else { return }  // Silence or echo residual — skip

        let elapsed = preciseElapsed  // Wall-clock precision (not 1s Timer)
        let duration = Double(buffer.frameLength) / 16000.0

        // Auto-enrollment: accumulate clean mic audio for voice profile extraction
        if !enrollmentComplete, let channelData = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            enrollmentSamples.append(contentsOf: samples)

            if enrollmentSamples.count >= enrollmentTargetSamples {
                await performAutoEnrollment()
            }
        }

        // Append a synthetic diarization segment for the local speaker.
        // Uses appendMicSegment (not updateDiarizationResults) so segments
        // accumulate over the recording rather than being replaced each call.
        let segment = TimedSpeakerSegment(
            speakerId: "local_1",
            embedding: [],
            startTimeSeconds: Float(elapsed - duration),
            endTimeSeconds: Float(elapsed),
            qualityScore: min(rms * 10, 1.0)  // Normalize RMS to quality estimate
        )
        segmentAligner.appendMicSegment(segment)

        // Ensure local participant exists
        if let meeting = currentMeeting,
           !meeting.identifiedParticipants.contains(where: { $0.speakerID == "mic_local_1" }) {
            let participant = IdentifiedParticipant()
            participant.speakerID = "mic_local_1"
            participant.isCurrentUser = true
            let userName = UserProfile.shared.displayName
            if !userName.isEmpty {
                participant.name = userName
                participant.namingMode = .linkedToPerson
            }
            meeting.identifiedParticipants.append(participant)
            debugLog("[SimpleRecordingEngine] 👤 Stream labeling: added local speaker participant")
        }

        // Update speaking time from accumulated segments
        if let meeting = currentMeeting,
           let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == "mic_local_1" }) {
            let speakingTimes = segmentAligner.getSpeakingTimes()
            participant.totalSpeakingTime = speakingTimes["mic_local_1"] ?? 0
        }
    }

    /// Extract a voice embedding from accumulated clean mic audio and save as the user's profile.
    /// Called once during the first ~15 seconds of recording when enough speech is captured.
    private func performAutoEnrollment() async {
        guard !enrollmentComplete else { return }
        enrollmentComplete = true

        debugLog("[SimpleRecordingEngine] 🎤 Auto-enrollment: extracting voice embedding from \(enrollmentSamples.count) samples")

        // Use FluidAudio's embedding extractor if available via the diarization backend
        // For now, feed the enrollment audio through the diarization engine to get an embedding
        do {
            // Create a temporary diarizer just for embedding extraction
            let tempDiarizer = createDiarizationEngine(maxSpeakers: 1)
            try await tempDiarizer.initialize()

            // Convert samples to AVAudioPCMBuffer
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(enrollmentSamples.count)) else {
                debugLog("[SimpleRecordingEngine] ⚠️ Auto-enrollment: failed to create buffer")
                return
            }
            buffer.frameLength = AVAudioFrameCount(enrollmentSamples.count)
            if let channelData = buffer.floatChannelData {
                enrollmentSamples.withUnsafeBufferPointer { srcPtr in
                    memcpy(channelData[0], srcPtr.baseAddress!, enrollmentSamples.count * MemoryLayout<Float>.size)
                }
            }

            await tempDiarizer.processAudioBuffer(buffer)
            let result = await tempDiarizer.finishProcessing()

            // Extract the dominant speaker's embedding
            if let embeddings = result?.speakerEmbeddings,
               let (speakerId, embedding) = embeddings.first,
               !embedding.isEmpty {

                // Save to UserProfile for cross-session persistence
                UserProfile.shared.voiceEmbedding = embedding
                debugLog("[SimpleRecordingEngine] ✅ Auto-enrollment: saved voice embedding (\(embedding.count)-dim) from speaker \(speakerId)")

                // Also feed to the active diarizer as a known speaker anchor
                let userName = UserProfile.shared.displayName
                systemDiarizationManager.preloadKnownSpeakers([
                    (id: "local_user", name: userName.isEmpty ? "You" : userName, embedding: embedding)
                ])
                debugLog("[SimpleRecordingEngine] 🎯 Auto-enrollment: anchored local user in diarizer")
            } else {
                debugLog("[SimpleRecordingEngine] ⚠️ Auto-enrollment: no embedding extracted from \(enrollmentSamples.count) samples")
            }
        } catch {
            debugLog("[SimpleRecordingEngine] ⚠️ Auto-enrollment failed: \(error)")
        }

        // Free memory regardless
        enrollmentSamples.removeAll()
    }

    /// Process system audio in stream labeling mode: VAD only, label as remote speaker.
    /// No diarization — in a 1:1 with AEC, system = single remote speaker.
    /// Also buffers audio and runs multi-speaker detection for dynamic upgrade.
    private func processSystemVAD(_ buffer: AVAudioPCMBuffer) async {
        let rms = calculateRMS(buffer)

        // Buffer system audio for potential catch-up (even silence, for timing continuity)
        bufferSystemAudioForCatchUp(buffer)

        guard rms > vadRMSThreshold else { return }  // Silence — skip

        let elapsed = preciseElapsed  // Wall-clock precision (not 1s Timer)
        let duration = Double(buffer.frameLength) / 16000.0

        // Append a synthetic segment for the remote speaker.
        // Uses appendSystemSegment so segments accumulate over the recording.
        let segment = TimedSpeakerSegment(
            speakerId: "remote_1",
            embedding: [],
            startTimeSeconds: Float(elapsed - duration),
            endTimeSeconds: Float(elapsed),
            qualityScore: min(rms * 10, 1.0)
        )
        segmentAligner.appendSystemSegment(segment)

        // Ensure remote participant exists
        if let meeting = currentMeeting,
           !meeting.identifiedParticipants.contains(where: { $0.speakerID == "sys_remote_1" }) {
            let participant = IdentifiedParticipant()
            participant.speakerID = "sys_remote_1"
            participant.isCurrentUser = false
            meeting.identifiedParticipants.append(participant)
            debugLog("[SimpleRecordingEngine] 👤 Stream labeling: added remote speaker participant")
        }

        // Update speaking time from accumulated segments
        if let meeting = currentMeeting,
           let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == "sys_remote_1" }) {
            let speakingTimes = segmentAligner.getSpeakingTimes()
            participant.totalSpeakingTime = speakingTimes["sys_remote_1"] ?? 0
        }

        // Feed energy to multi-speaker detector
        trackSystemSpeechEnergy(rms)
    }

    /// Process system audio in 1:1 no-AEC mode: VAD-only, no diarizer.
    /// Labels all system audio as "remote_1" UNLESS the energy gate says the local speaker
    /// is currently talking — in that case, suppress attribution because the system audio
    /// is likely voice bleed from the local speaker, not the remote participant.
    private func processSystemVADNoAEC(_ buffer: AVAudioPCMBuffer) async {
        let rms = calculateRMS(buffer)

        // Always update system RMS for energy gate cross-reference
        currentSystemRMS = rms

        // Track system buffers for diagnostics
        let frameCount = Int(buffer.frameLength)
        await MainActor.run {
            DiarizationDiagnostics.shared.counters.systemBuffersReceived += 1
            DiarizationDiagnostics.shared.counters.systemTotalFrames += frameCount
        }

        // Write to disk for offline re-diarization
        if let writer = systemAudioWriter {
            do {
                try writeBufferToWAV(buffer, writer: writer)
                await MainActor.run { DiarizationDiagnostics.shared.counters.wavFramesWritten += frameCount }
            } catch {
                debugLog("[SimpleRecordingEngine] Failed to write system audio to file: \(error)")
            }
        }

        // Buffer system audio for potential group-mode catch-up
        bufferSystemAudioForCatchUp(buffer)

        guard rms > vadRMSThreshold else { return }  // Silence — skip

        // KEY FIX: If energy gate says local speaker is talking, this system audio
        // is likely voice bleed — suppress remote speaker attribution.
        if energyGateDetector?.isSpeaking == true {
            return
        }

        let elapsed = preciseElapsed  // Wall-clock precision (not 1s Timer)
        let duration = Double(buffer.frameLength) / 16000.0

        let segment = TimedSpeakerSegment(
            speakerId: "remote_1",
            embedding: [],
            startTimeSeconds: Float(elapsed - duration),
            endTimeSeconds: Float(elapsed),
            qualityScore: min(rms * 10, 1.0)
        )
        segmentAligner.appendSystemSegment(segment)

        // Ensure remote participant exists
        if let meeting = currentMeeting,
           !meeting.identifiedParticipants.contains(where: { $0.speakerID == "sys_remote_1" }) {
            let participant = IdentifiedParticipant()
            participant.speakerID = "sys_remote_1"
            participant.isCurrentUser = false
            meeting.identifiedParticipants.append(participant)
            debugLog("[SimpleRecordingEngine] 👤 No-AEC VAD: added remote speaker participant")
        }

        // Update speaking time from accumulated segments
        if let meeting = currentMeeting,
           let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == "sys_remote_1" }) {
            let speakingTimes = segmentAligner.getSpeakingTimes()
            participant.totalSpeakingTime = speakingTimes["sys_remote_1"] ?? 0
        }

        // Feed energy to multi-speaker detector (for potential group upgrade)
        trackSystemSpeechEnergy(rms)
    }

    // MARK: - Energy Gate + Diarizer Processing

    /// Process mic audio via energy gate: detects local speech without diarization.
    private func processEnergyGateMic(_ buffer: AVAudioPCMBuffer) async {
        await MainActor.run { DiarizationDiagnostics.shared.counters.micBuffersReceived += 1 }

        // Write mic audio to disk for offline re-diarization
        if let writer = micAudioWriter {
            do {
                try writeBufferToWAV(buffer, writer: writer)
            } catch {
                debugLog("[SimpleRecordingEngine] Failed to write mic audio to file: \(error)")
            }
        }

        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        let elapsed = preciseElapsed  // Wall-clock precision (not 1s Timer)
        let chunkDuration = Double(count) / 16000.0
        let chunkStartTime = max(0, elapsed - chunkDuration)

        let sysRMS = currentSystemRMS
        guard let detector = energyGateDetector else { return }
        let segments = detector.processChunk(micSamples: samples, systemRMS: sysRMS, chunkStartTime: chunkStartTime)

        if !segments.isEmpty {
            await MainActor.run { DiarizationDiagnostics.shared.counters.micEnergyGateSegments += segments.count }
            // Append each segment individually so they accumulate
            for segment in segments {
                segmentAligner.appendMicSegment(segment)
            }
        }

        // Ensure local participant exists (same pattern as processMicVAD)
        if let meeting = currentMeeting,
           !meeting.identifiedParticipants.contains(where: { $0.speakerID == "mic_local_1" }) {
            let participant = IdentifiedParticipant()
            participant.speakerID = "mic_local_1"
            participant.isCurrentUser = true
            let userName = UserProfile.shared.displayName
            if !userName.isEmpty {
                participant.name = userName
                participant.namingMode = .linkedToPerson
            }
            meeting.identifiedParticipants.append(participant)
            debugLog("[SimpleRecordingEngine] 👤 Energy gate: added local speaker participant")
        }

        // Update speaking time from accumulated segments
        if !segments.isEmpty, let meeting = currentMeeting,
           let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == "mic_local_1" }) {
            let speakingTimes = segmentAligner.getSpeakingTimes()
            participant.totalSpeakingTime = speakingTimes["mic_local_1"] ?? 0
        }
    }

    /// Process system audio: update system RMS and feed to Axii diarizer.
    private func processSystemDiarization(_ buffer: AVAudioPCMBuffer, systemDiarBuffer: DiarizationBuffer) async {
        // Pipeline counter: track system buffers received
        let frameCount = Int(buffer.frameLength)
        await MainActor.run {
            DiarizationDiagnostics.shared.counters.systemBuffersReceived += 1
            DiarizationDiagnostics.shared.counters.systemTotalFrames += frameCount
        }

        // Update currentSystemRMS for energy gate cross-reference
        let rms = calculateRMS(buffer)
        currentSystemRMS = rms

        // Write to disk for offline re-diarization
        if let writer = systemAudioWriter {
            do {
                try writeBufferToWAV(buffer, writer: writer)
                await MainActor.run { DiarizationDiagnostics.shared.counters.wavFramesWritten += Int(buffer.frameLength) }
            } catch {
                debugLog("[SimpleRecordingEngine] Failed to write system audio to file: \(error)")
            }
        }

        // Feed to system diarization buffer -> AxiiDiarization
        let elapsed = preciseElapsed  // Wall-clock precision (not 1s Timer)
        if let (diarChunk, startTime) = await systemDiarBuffer.addBuffer(buffer, recordingElapsed: elapsed) {
            await MainActor.run { DiarizationDiagnostics.shared.counters.systemChunksEmitted += 1 }
            await processSystemDiarizationChunk(diarChunk, startTime: startTime)
        }
    }

    // MARK: - Cross-Stream Deduplication

    /// When system diarizer produces a speaker database, check each cluster embedding
    /// against the user's voice profile. Suppress any system cluster that matches the
    /// local user (voice bleed through system audio).
    private func deduplicateLocalFromSystemClusters() {
        guard diarizationStrategy == .streamLabelingNoAEC || diarizationStrategy == .groupStreaming else { return }
        guard let userEmbedding = UserProfile.shared.voiceEmbedding else { return }
        guard let db = systemDiarizationManager.lastResult?.speakerDatabase else { return }

        for (speakerId, clusterEmbedding) in db {
            let similarity = cosineSimilarity(userEmbedding, clusterEmbedding)
            if similarity > 0.45 {
                debugLog("[SimpleRecordingEngine] 🔇 Suppressing system cluster '\(speakerId)' — cosine similarity \(String(format: "%.3f", similarity)) to local user voice")
                // Remove this cluster's segments from the aligner
                segmentAligner.removeSystemSpeaker("sys_\(speakerId)")
                // Remove from identified participants
                currentMeeting?.identifiedParticipants.removeAll { $0.speakerID == "sys_\(speakerId)" }
            }
        }
    }

    /// Cosine similarity between two float vectors using vDSP.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }

    // MARK: - System Audio Catch-Up Buffer

    /// Buffer system audio during streamLabeling for potential catch-up on upgrade.
    /// Keeps a rolling window of the most recent audio up to maxCatchUpBufferSeconds.
    private func bufferSystemAudioForCatchUp(_ buffer: AVAudioPCMBuffer) {
        guard diarizationStrategy == .streamLabeling else { return }

        let newFrames = Int(buffer.frameLength)
        let maxFrames = Int(maxCatchUpBufferSeconds * 16000.0)

        // Deep copy the buffer before storing
        guard let copy = deepCopyBuffer(buffer) else { return }
        systemAudioCatchUpBuffer.append(copy)
        catchUpBufferFrameCount += newFrames

        // Trim oldest buffers if over capacity
        while catchUpBufferFrameCount > maxFrames, !systemAudioCatchUpBuffer.isEmpty {
            let removed = systemAudioCatchUpBuffer.removeFirst()
            catchUpBufferFrameCount -= Int(removed.frameLength)
        }
    }

    /// Write a buffer to a WAV file, converting to 16kHz mono if needed.
    /// Reuses a cached AVAudioConverter to avoid per-buffer allocation overhead.
    private func writeBufferToWAV(_ buffer: AVAudioPCMBuffer, writer: AVAudioFile) throws {
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        if buffer.format.sampleRate != 16000 || buffer.format.channelCount != 1 {
            // Lazily create or reuse converter for this source format
            if wavWriterConverter == nil || wavWriterSourceFormat?.sampleRate != buffer.format.sampleRate {
                wavWriterConverter = AVAudioConverter(from: buffer.format, to: targetFormat)
                wavWriterSourceFormat = buffer.format
            }
            guard let converter = wavWriterConverter else { return }

            let ratio = 16000.0 / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                try writer.write(from: outputBuffer)
            }
        } else {
            try writer.write(from: buffer)
        }
    }

    /// Deep copy an AVAudioPCMBuffer (mirrors AudioCapturer.deepCopy)
    private func deepCopyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        if let srcData = buffer.floatChannelData, let dstData = copy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dstData[channel], srcData[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    // MARK: - Multi-Speaker Energy Detection

    /// Track speech energy from the system stream to detect multiple speakers.
    /// Uses coefficient of variation (CV) of speech energy levels — a single speaker
    /// has relatively consistent energy, while multiple speakers create higher variance.
    private func trackSystemSpeechEnergy(_ rms: Float) {
        systemSpeechEnergies.append(rms)
        if systemSpeechEnergies.count > energyWindowSize {
            systemSpeechEnergies.removeFirst(systemSpeechEnergies.count - energyWindowSize)
        }

        // Need enough samples before evaluating
        guard systemSpeechEnergies.count >= energyWindowSize / 2 else { return }

        let mean = systemSpeechEnergies.reduce(0, +) / Float(systemSpeechEnergies.count)
        guard mean > 0 else { return }

        let variance = systemSpeechEnergies.reduce(Float(0)) { acc, val in
            let diff = val - mean
            return acc + diff * diff
        } / Float(systemSpeechEnergies.count)
        let stddev = sqrt(variance)
        let cv = stddev / mean  // Coefficient of variation

        if cv > energyCVThreshold {
            multiSpeakerEvidenceCount += 1
            if multiSpeakerEvidenceCount == multiSpeakerEvidenceThreshold {
                debugLog("[SimpleRecordingEngine] 🔍 Multi-speaker detected on system stream (CV: \(String(format: "%.2f", cv)) > \(energyCVThreshold), evidence: \(multiSpeakerEvidenceCount))")
                // Only auto-upgrade from streamLabelingNoAEC — energy CV is unreliable
                // for streamLabeling (AEC active) because varied mono audio (YouTube,
                // podcasts) produces high CV without actually having multiple speakers.
                // Explicit upgrades via updateExpectedAttendeeCount() still work for both.
                if diarizationStrategy == .streamLabelingNoAEC {
                    Task {
                        await upgradeToGroupStreaming()
                    }
                }
            }
        } else {
            // Reset evidence counter on low-variance window (single speaker)
            multiSpeakerEvidenceCount = max(0, multiSpeakerEvidenceCount - 1)
        }
    }

    /// Calculate RMS of an audio buffer for VAD
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let samples = channelData[0]
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        return sqrt(sum / Float(count))
    }

    // MARK: - Dynamic Strategy Upgrade

    /// Upgrade from streamLabeling/streamLabelingNoAEC to groupStreaming
    /// when multiple remote speakers are confirmed.
    ///
    /// Called from two paths:
    /// 1. **Explicit**: `updateExpectedAttendeeCount()` — calendar says 3+ attendees (reliable)
    /// 2. **Auto-detected**: energy CV analysis — only from streamLabelingNoAEC to avoid
    ///    false triggers on varied mono audio (YouTube, podcasts etc.)
    func upgradeToGroupStreaming() async {
        guard diarizationStrategy == .streamLabeling || diarizationStrategy == .streamLabelingNoAEC else { return }

        debugLog("[SimpleRecordingEngine] 🔄 Upgrading strategy: \(diarizationStrategy.rawValue) → groupStreaming")
        diarizationStrategy = .groupStreaming

        // Initialize system diarizer and energy gate on-the-fly
        energyGateDetector = EnergyGateDetector()
        currentSystemRMS = 0

        let attendeeCount = expectedAttendeeCount ?? 3
        let remoteSpeakers = max(attendeeCount - 1, 2)
        systemDiarizationManager = createDiarizationEngine(maxSpeakers: remoteSpeakers + 1)
        do {
            try await systemDiarizationManager.initialize()
            await preloadKnownSpeakersForMeeting()
            debugLog("[SimpleRecordingEngine] ✅ Group streaming diarizer initialized mid-recording")

            // Feed buffered system audio for catch-up
            await feedCatchUpBufferToDiarizer()
        } catch {
            debugLog("[SimpleRecordingEngine] ❌ Failed to initialize group streaming diarizer: \(error)")
        }

        // Clean up detection state — no longer needed
        systemSpeechEnergies.removeAll()
        multiSpeakerEvidenceCount = 0
        systemAudioCatchUpBuffer.removeAll()
        catchUpBufferFrameCount = 0
    }

    /// Feed accumulated system audio buffer to the newly initialized diarizer for catch-up.
    private func feedCatchUpBufferToDiarizer() async {
        guard !systemAudioCatchUpBuffer.isEmpty else {
            debugLog("[SimpleRecordingEngine] No catch-up audio to feed")
            return
        }

        let bufferCount = systemAudioCatchUpBuffer.count
        let totalSeconds = Double(catchUpBufferFrameCount) / 16000.0
        debugLog("[SimpleRecordingEngine] 🔄 Feeding \(bufferCount) catch-up buffers (\(String(format: "%.1f", totalSeconds))s) to system diarizer")

        for buffer in systemAudioCatchUpBuffer {
            await systemDiarizationManager.processAudioBuffer(buffer)
        }

        debugLog("[SimpleRecordingEngine] ✅ Catch-up buffer fed to diarizer")
    }

    /// Update expected attendee count mid-recording. Triggers strategy upgrade if needed.
    func updateExpectedAttendeeCount(_ count: Int) async {
        let oldCount = expectedAttendeeCount
        expectedAttendeeCount = count
        debugLog("[SimpleRecordingEngine] Expected attendee count updated: \(oldCount.map(String.init) ?? "nil") → \(count)")

        if count > 2 && diarizationStrategy == .streamLabeling {
            await upgradeToGroupStreaming()
        }
    }

    // MARK: - Post-Meeting Voice Learning

    /// Save voice embeddings from the completed recording back to VoicePrintManager.
    /// Implements Quill-style progressive voice learning — each meeting improves recognition.
    private func saveVoiceEmbeddingsPostMeeting() async {
        guard let meeting = currentMeeting else { return }

        var savedCount = 0

        for participant in meeting.identifiedParticipants {
            // Only save for participants linked to a Person record
            guard let person = participant.personRecord else { continue }

            // Get the best embedding from diarization results
            let rawId = participant.speakerID
                .replacingOccurrences(of: "mic_", with: "")
                .replacingOccurrences(of: "sys_", with: "")

            var embedding: [Float]?

            // Get embedding from system diarizer (Axii)
            if let sysDb = systemDiarizationManager.lastResult?.speakerDatabase {
                embedding = sysDb[rawId]
            }

            guard let validEmbedding = embedding, !validEmbedding.isEmpty else { continue }

            // Higher confidence weight for guided diarization matches
            let wasConfirmed = participant.namingMode == .linkedToPerson ||
                               participant.namingMode == .suggestedByVoice
            voicePrintManager.saveEmbeddingWithFeedback(
                validEmbedding,
                for: person,
                wasConfirmed: wasConfirmed
            )
            savedCount += 1
        }

        if savedCount > 0 {
            debugLog("[SimpleRecordingEngine] 🧠 Post-meeting voice learning: saved \(savedCount) embeddings")
        }
    }

    /// Backfill speaker labels into transcript segments that arrived before diarization caught up.
    /// Uses backfillCursor to skip already-attributed segments (O(new) instead of O(all)).
    private func backfillSpeakerLabels() {
        guard let meeting = currentMeeting else { return }

        var backfilledCount = 0
        var newCursor = meeting.transcript.count // Assume all done unless we find a nil

        for i in backfillCursor..<meeting.transcript.count {
            let segment = meeting.transcript[i]
            guard segment.speakerID == nil else { continue }

            // Query the aligner for who was speaking at this segment's time
            if let speaker = segmentAligner.dominantSpeaker(for: segment.timestamp, duration: 5.0) {
                // Use participant name if identified (by user, voice match, or auto-detection)
                let speakerName: String
                if let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == speaker }),
                   participant.namingMode != .unnamed {
                    speakerName = participant.displayName
                } else {
                    speakerName = SegmentAligner.formatSpeakerName(speaker)
                }
                meeting.transcript[i] = TranscriptSegment(
                    id: segment.id,
                    text: segment.text,
                    timestamp: segment.timestamp,
                    speakerID: speaker,
                    speakerName: speakerName,
                    confidence: segment.confidence,
                    isFinalized: segment.isFinalized
                )
                backfilledCount += 1
            } else if i > 0, let prevSpeaker = meeting.transcript[i - 1].speakerID {
                // Temporal continuity fallback: if diarization can't determine the speaker,
                // inherit from the previous segment (same person likely still talking)
                let prevName = meeting.transcript[i - 1].speakerName ?? SegmentAligner.formatSpeakerName(prevSpeaker)
                meeting.transcript[i] = TranscriptSegment(
                    id: segment.id,
                    text: segment.text,
                    timestamp: segment.timestamp,
                    speakerID: prevSpeaker,
                    speakerName: prevName,
                    confidence: segment.confidence,
                    isFinalized: segment.isFinalized
                )
                backfilledCount += 1
            } else {
                // First segment still nil — this is the new cursor position
                newCursor = min(newCursor, i)
            }
        }

        backfillCursor = newCursor

        if backfilledCount > 0 {
            debugLog("[SimpleRecordingEngine] Backfilled speaker labels for \(backfilledCount) transcript segments (cursor at \(backfillCursor))")
        }
    }

    /// Update meeting type based on speaker count
    private func updateMeetingType(speakerCount: Int) {
        guard let meeting = currentMeeting else { return }

        if speakerCount == 2 {
            meeting.meetingType = .oneOnOne
        } else if speakerCount > 2 {
            meeting.meetingType = .group
        }
        // Don't set type for 0 or 1 speakers (could be solo or not yet determined)
    }

    /// Update participants from diarization results, attempting voice-based identification
    private func updateParticipants(from result: DiarizationResult) async {
        guard let meeting = currentMeeting else { return }

        // Get speaking times per speaker
        let speakingTimes = segmentAligner.getSpeakingTimes()
        let uniqueSpeakers = segmentAligner.getUniqueSpeakers()

        for speakerId in uniqueSpeakers {
            // Check if we already have this participant (by string speakerID)
            if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == speakerId }) {
                // Update speaking time for existing participant
                existingParticipant.totalSpeakingTime = speakingTimes[speakerId] ?? 0
            } else {
                // Add new participant
                let participant = IdentifiedParticipant()
                participant.speakerID = speakerId
                participant.confidence = 1.0
                participant.isCurrentUser = false
                participant.totalSpeakingTime = speakingTimes[speakerId] ?? 0

                // Attempt voice-based identification using VoicePrintManager
                // speakerDatabase uses raw IDs ("1", "2") but speakerId is prefixed ("mic_1", "sys_2")
                let rawId = speakerId.replacingOccurrences(of: "mic_", with: "")
                                     .replacingOccurrences(of: "sys_", with: "")
                if let embedding = result.speakerDatabase?[rawId] {
                    if let match = await voicePrintManager.findMatchingPerson(for: embedding),
                       let matchedPerson = match.0,
                       match.1 > 0.35 {
                        participant.name = matchedPerson.wrappedName
                        participant.namingMode = .suggestedByVoice
                        participant.personRecord = matchedPerson
                        participant.person = matchedPerson
                        participant.confidence = match.1
                        debugLog("[SimpleRecordingEngine] 🎤 Voice match: \(matchedPerson.wrappedName) (confidence: \(String(format: "%.0f%%", match.1 * 100)))")
                    }
                }

                // Check if this speaker is the current user (identified by voice profile)
                if let userSpkId = systemDiarizationManager.userSpeakerId {
                    // SegmentAligner prefixes mic speakers with "mic_", so compare with prefix
                    if speakerId == "mic_\(userSpkId)" {
                        participant.isCurrentUser = true
                        participant.name = UserProfile.shared.displayName
                        participant.namingMode = .linkedToPerson

                        // If another participant was previously marked as "me" (e.g., user clicked
                        // "This is me" on the wrong speaker), unmark them — voice-based ID is more reliable
                        for other in meeting.identifiedParticipants where other.isCurrentUser && other.speakerID != speakerId {
                            other.isCurrentUser = false
                            // Revert their transcript labels back to generic speaker name
                            let revertName = SegmentAligner.formatSpeakerName(other.speakerID)
                            other.name = nil
                            other.namingMode = .unnamed
                            for i in meeting.transcript.indices where meeting.transcript[i].speakerID == other.speakerID {
                                meeting.transcript[i].speakerName = revertName
                            }
                            debugLog("[SimpleRecordingEngine] ⚠️ Reverted \(other.speakerID) — voice ID says \(speakerId) is the real user")
                        }

                        // Save this speaker's embedding for future voice recognition improvement
                        if let embedding = result.speakerDatabase?[rawId], !embedding.isEmpty {
                            UserProfile.shared.addVoiceSample(embedding)
                            debugLog("[SimpleRecordingEngine] 🎤 Saved voice embedding to UserProfile from \(speakerId)")
                        }

                        debugLog("[SimpleRecordingEngine] 👤 Auto-identified current user as speaker \(speakerId)")
                    }
                }

                meeting.identifiedParticipants.append(participant)
                debugLog("[SimpleRecordingEngine] Added participant: \(participant.displayName)")

                // Backfill existing transcript segments with the participant's display name
                if participant.namingMode != .unnamed {
                    let displayName = participant.displayName
                    for i in meeting.transcript.indices where meeting.transcript[i].speakerID == speakerId {
                        meeting.transcript[i].speakerName = displayName
                    }
                    debugLog("[SimpleRecordingEngine] Backfilled transcript with name '\(displayName)' for speaker \(speakerId)")
                }
            }
        }
    }

    /// Expose latest diarization result for voice embedding access (e.g., "This is me" feature)
    var diarizationManagerResult: DiarizationResult? {
        systemDiarizationManager.lastResult
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
                self.currentMeeting?.duration = self.recordingDuration
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Meeting Finalization

    private func finalizeMeeting(_ meeting: LiveMeeting) async {
        debugLog("[SimpleRecordingEngine] Finalizing meeting...")

        // Update final duration
        meeting.duration = recordingDuration
        meeting.isRecording = false

        // Store meeting data for in-memory handoff to review UI
        storeMeetingHandoff(meeting)
        meeting.cleanupFlushFile()

        // Window transition: show review window BEFORE hiding recording window (no gap/flash)
        await MainActor.run {
            TranscriptImportWindowManager.shared.presentWindow(isFromRecording: true)
            RecordingWindowManager.shared.hide()
        }

        debugLog("[SimpleRecordingEngine] Meeting finalized: \(meeting.transcript.count) segments, \(meeting.wordCount) words")
    }

    private func logMeetingSummary() {
        let duration = recordingDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        let diarResult = systemDiarizationManager.lastResult
        let speakerCount = diarResult?.speakerEmbeddings?.count ?? 0
        let segmentCount = diarResult?.segments.count ?? 0

        let participants = currentMeeting?.identifiedParticipants ?? []
        let identified = participants.filter { $0.namingMode == .linkedToPerson || $0.isCurrentUser }
        let wordCount = currentMeeting?.wordCount ?? 0
        let strategy = diarizationStrategy.rawValue

        var summary = """
        📊 [Meeting Summary] \(minutes)m \(seconds)s recorded
           Strategy: \(strategy)
           Speakers: \(speakerCount) detected, \(identified.count) identified
        """

        for p in identified {
            let conf = String(format: "%.0f%%", p.confidence * 100)
            let label = p.isCurrentUser ? "\(p.name) (you)" : p.name
            summary += "\n      - \(label) \(conf)"
        }

        summary += """

           Segments: \(segmentCount) diarization, \(currentMeeting?.transcript.count ?? 0) transcript
           Words: \(wordCount)
        """

        debugLog(summary)
    }

    private func storeMeetingHandoff(_ meeting: LiveMeeting) {
        // Build transcript as plain text
        let transcriptText = meeting.getFullTranscriptText()

        // Get voice embeddings from diarization results (keyed by prefixed speaker ID)
        var speakerEmbeddings: [String: [Float]] = [:]
        if let result = systemDiarizationManager.lastResult {
            for segment in result.segments {
                let prefixedId = "sys_\(segment.speakerId)"
                if speakerEmbeddings[prefixedId] == nil {
                    speakerEmbeddings[prefixedId] = segment.embedding
                }
            }
        }

        // Auto-identify: if exactly one mic speaker, that's the current user
        let micParticipants = meeting.identifiedParticipants.filter { $0.speakerID.hasPrefix("mic_") }
        let hasCurrentUser = meeting.identifiedParticipants.contains { $0.isCurrentUser }
        if micParticipants.count == 1, !hasCurrentUser {
            let localSpeaker = micParticipants[0]
            localSpeaker.isCurrentUser = true
            let userName = UserProfile.shared.displayName
            if !userName.isEmpty {
                localSpeaker.name = userName
                localSpeaker.namingMode = .linkedToPerson
            }
            debugLog("[SimpleRecordingEngine] 👤 Auto-identified sole mic speaker as current user: \(localSpeaker.speakerID)")
        }

        // Build participant data with voice embeddings
        let serializableParticipants = meeting.identifiedParticipants.map { participant in
            let embedding = speakerEmbeddings[participant.speakerID]
            return SerializableParticipant(from: participant, voiceEmbedding: embedding)
        }

        // Get user notes as plain text
        let userNotes = meeting.userNotesPlainText

        // Store in-memory via MeetingHandoff singleton (replaces UserDefaults IPC)
        let pending = MeetingHandoff.PendingMeeting(
            transcript: transcriptText,
            title: meeting.calendarTitle ?? "",
            date: meeting.startTime,
            duration: meeting.duration,
            participants: serializableParticipants,
            userNotes: userNotes.isEmpty ? nil : userNotes
        )
        MeetingHandoff.shared.store(pending)

        debugLog("[SimpleRecordingEngine] Stored meeting handoff (\(meeting.identifiedParticipants.count) participants)")
    }

    // MARK: - Monitoring (Simplified)

    func startMonitoring() {
        // Simplified: just mark as monitoring
        // Auto-detection to be added in future phase
        isMonitoring = true
        debugLog("[SimpleRecordingEngine] Monitoring started (passive)")
    }

    func stopMonitoring() {
        isMonitoring = false
        debugLog("[SimpleRecordingEngine] Monitoring stopped")
    }

    // MARK: - Permission Management

    /// Check current permission status
    func checkPermissionStatus() async -> PermissionStatus {
        // Check microphone permission
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        // Check screen recording permission
        // Try to get shareable content - if it succeeds, we have permission
        var screenGranted = false
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            screenGranted = true
        } catch {
            screenGranted = false
        }

        return PermissionStatus(microphone: micGranted, screenRecording: screenGranted)
    }

    /// Reset permission prompt flags
    func resetPermissionPrompts() {
        // Clear any saved permission dismissal flags
        UserDefaults.standard.removeObject(forKey: "permissionPromptsDismissed")
        debugLog("[SimpleRecordingEngine] Permission prompts reset")
    }
}

// MARK: - Permission Status

struct PermissionStatus {
    /// True if microphone permission is granted
    let microphone: Bool
    /// True if screen recording permission is granted
    let screenRecording: Bool
}

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case monitoring
    case conversationDetected
    case recording
    case processing
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Ready"
        case .monitoring: return "Monitoring"
        case .conversationDetected: return "Conversation Detected"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - MeetingRecordingEngine Compatibility Alias

/// Alias for backward compatibility with existing UI code
typealias MeetingRecordingEngine = SimpleRecordingEngine
