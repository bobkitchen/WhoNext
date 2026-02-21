import Foundation
import AVFoundation
import Combine
import ScreenCaptureKit
#if canImport(FluidAudio)
import FluidAudio
#endif

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

    // MARK: - Components

    private let audioCapturer = AudioCapturer()
    private let chunkBuffer = AudioChunkBuffer()
    private var transcriber: (any TranscriptionEngineProtocol)?

    // MARK: - Diarization Components

    #if canImport(FluidAudio)
    private let diarizationManager = DiarizationManager(enableRealTimeProcessing: true)
    private let diarizationBuffer = DiarizationBuffer()
    private let segmentAligner = SegmentAligner()
    private let voicePrintManager = VoicePrintManager()
    #endif

    // MARK: - Private State

    private var recordingTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    /// Cursor tracking the first transcript segment that may still need speaker backfill.
    /// Avoids re-scanning already-attributed segments on every diarization update.
    private var backfillCursor: Int = 0

    // MARK: - Initialization

    private init() {
        setupObservers()
        print("[SimpleRecordingEngine] Initialized")
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
    }

    // MARK: - Pre-warming

    /// Initialize transcription engine and diarization ahead of time
    func preWarm() async {
        do {
            // Create transcription engine based on settings
            let settings = MeetingRecordingConfiguration.shared.transcriptionSettings
            transcriber = TranscriptionManagerFactory.createEngine(for: settings)
            try await transcriber?.initialize()

            let engineName = settings.transcriptionEngine.displayName
            print("[SimpleRecordingEngine] Pre-warmed transcriber with engine: \(engineName)")

            // Initialize diarization
            #if canImport(FluidAudio)
            try await diarizationManager.initialize()
            print("[SimpleRecordingEngine] Pre-warmed diarization manager")
            #endif
        } catch {
            print("[SimpleRecordingEngine] Pre-warm failed: \(error)")
        }
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
            print("[SimpleRecordingEngine] Already recording")
            return
        }

        print("[SimpleRecordingEngine] Starting recording...")

        do {
            // Ensure transcriber is ready
            if transcriber == nil || transcriber?.isReady != true {
                let settings = MeetingRecordingConfiguration.shared.transcriptionSettings
                transcriber = TranscriptionManagerFactory.createEngine(for: settings)
                try await transcriber?.initialize()
                print("[SimpleRecordingEngine] Transcriber initialized: \(settings.transcriptionEngine.displayName)")
            }

            // Reset transcription state for new recording (important for Parakeet decoder state)
            transcriber?.resetState()

            // Create new meeting
            let meeting = LiveMeeting()
            meeting.calendarTitle = "Recording"
            meeting.startTime = Date()
            currentMeeting = meeting

            // Reset chunk buffer
            await chunkBuffer.reset()

            // Initialize and reset diarization components
            #if canImport(FluidAudio)
            // Ensure diarization is initialized (may not have been pre-warmed)
            do {
                try await diarizationManager.initialize()
                print("[SimpleRecordingEngine] Diarization manager initialized")
            } catch {
                print("[SimpleRecordingEngine] Diarization initialization failed: \(error)")
            }
            await diarizationBuffer.reset()
            segmentAligner.reset()
            diarizationManager.reset()
            detectedSpeakerCount = 0
            backfillCursor = 0
            #endif

            // Start audio capture
            try await audioCapturer.startCapture()

            // Update state
            isRecording = true
            recordingState = .recording
            recordingDuration = 0
            recordingStartTime = Date()

            // Start duration timer
            startDurationTimer()

            // Show recording window
            RecordingWindowManager.shared.show()

            // Start processing loop
            recordingTask = Task {
                await processAudioStreams()
            }

            print("[SimpleRecordingEngine] Recording started")

        } catch {
            print("[SimpleRecordingEngine] Failed to start: \(error)")
            recordingState = .error(error.localizedDescription)
            currentMeeting = nil
        }
    }

    /// Stop recording
    func stopRecording() async {
        guard isRecording else {
            print("[SimpleRecordingEngine] Not recording")
            return
        }

        print("[SimpleRecordingEngine] Stopping recording...")

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

        // Flush remaining diarization audio
        #if canImport(FluidAudio)
        if let (finalDiarChunk, startTime) = await diarizationBuffer.flush() {
            await processDiarizationChunk(finalDiarChunk, startTime: startTime)
        }
        // Get final diarization results
        _ = await diarizationManager.finishProcessing()
        #endif

        // Update state for processing phase
        recordingState = .processing

        // Finalize meeting
        if let meeting = currentMeeting {
            await finalizeMeeting(meeting)
        }

        print("[SimpleRecordingEngine] Recording stopped")
    }

    // MARK: - Audio Processing

    private func processAudioStreams() async {
        print("[SimpleRecordingEngine] Starting audio stream processing")

        // Get streams on main actor before entering task group
        let micStream = audioCapturer.micStream!
        let systemStream = audioCapturer.systemStream!
        let buffer = chunkBuffer

        #if canImport(FluidAudio)
        let diarBuffer = diarizationBuffer
        #endif

        // Process mic and system audio concurrently
        await withTaskGroup(of: Void.self) { group in
            // Mic stream processor (for transcription and diarization)
            group.addTask {
                for await audioBuffer in micStream {
                    guard !Task.isCancelled else { break }

                    // Add to chunk buffer for transcription
                    if let chunk = await buffer.addBuffer(audioBuffer, isMic: true) {
                        await self.transcribeChunk(chunk)
                    }

                    #if canImport(FluidAudio)
                    // Also feed to diarization buffer (parallel pipeline)
                    let elapsed = await MainActor.run { self.recordingDuration }
                    if let (diarChunk, startTime) = await diarBuffer.addBuffer(audioBuffer, recordingElapsed: elapsed) {
                        await self.processDiarizationChunk(diarChunk, startTime: startTime)
                    }
                    #endif
                }
            }

            // System stream processor (for transcription)
            group.addTask {
                for await audioBuffer in systemStream {
                    guard !Task.isCancelled else { break }

                    // Add to chunk buffer for transcription
                    if let chunk = await buffer.addBuffer(audioBuffer, isMic: false) {
                        await self.transcribeChunk(chunk)
                    }
                }
            }

            #if canImport(FluidAudio)
            // Diarization stream processor (parallel pipeline, uses mic audio)
            // Note: We process the same micStream data for diarization
            // since multiple consumers of an AsyncStream isn't supported,
            // we'll process diarization from the mic processor task
            #endif
        }

        print("[SimpleRecordingEngine] Audio stream processing ended")
    }

    /// Perform transcription work off the main actor, then update UI on MainActor
    private nonisolated func transcribeChunkInBackground(_ chunk: [Float], transcriber: any TranscriptionEngineProtocol) async -> (text: String, confidence: Float)? {
        do {
            if let result = try await transcriber.transcribe(audioChunk: chunk) {
                return (text: result.text, confidence: result.confidence)
            }
        } catch {
            print("[SimpleRecordingEngine] Transcription error: \(error)")
        }
        return nil
    }

    private func transcribeChunk(_ chunk: [Float]) async {
        guard let transcriber else {
            print("[SimpleRecordingEngine] Transcriber not initialized")
            return
        }

        // Log chunk stats
        let stats = await chunkBuffer.getStats()
        print("[SimpleRecordingEngine] Transcribing chunk: \(chunk.count) samples")
        print("[SimpleRecordingEngine] Buffer stats: \(stats.description)")

        // Perform heavy transcription work off MainActor
        guard let result = await transcribeChunkInBackground(chunk, transcriber: transcriber) else {
            return
        }

        // Back on MainActor for UI updates
        // Query speaker from diarization
        var speakerID: String? = nil
        var speakerName: String? = nil

        #if canImport(FluidAudio)
        // Use the chunk's actual timestamp rather than global recordingDuration.
        // The transcription chunk corresponds to approximately the last chunkDuration
        // of audio. Query the dominant speaker for that time window.
        let chunkDuration: TimeInterval = 10.0
        let segmentStart = max(0, recordingDuration - chunkDuration)
        if let speaker = segmentAligner.dominantSpeaker(for: segmentStart, duration: chunkDuration) {
            speakerID = speaker
            // Use user-assigned name if available, otherwise format from speaker ID
            let numericId = SegmentAligner.parseNumericId(speaker)
            if let participant = currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == numericId }),
               let userName = participant.name, participant.namingMode == .namedByUser {
                speakerName = userName
            } else {
                speakerName = SegmentAligner.formatSpeakerName(speaker)
            }
            print("[SimpleRecordingEngine] Speaker identified: \(speakerName ?? "unknown")")
        }
        #endif

        // Create segment and update meeting on MainActor
        let segment = TranscriptSegment(
            text: result.text,
            timestamp: recordingDuration,
            speakerID: speakerID,
            speakerName: speakerName,
            confidence: result.confidence,
            isFinalized: true
        )

        currentMeeting?.transcript.append(segment)
        currentMeeting?.wordCount += result.text.split(separator: " ").count

        let speakerInfo = speakerName ?? "unknown speaker"
        print("[SimpleRecordingEngine] Added segment (\(speakerInfo)): \"\(result.text.prefix(50))...\"")
    }

    // MARK: - Diarization Processing

    #if canImport(FluidAudio)
    /// Process a diarization chunk through the FluidAudio pipeline
    private func processDiarizationChunk(_ chunk: [Float], startTime: TimeInterval) async {
        print("[SimpleRecordingEngine] Processing diarization chunk: \(chunk.count) samples at \(String(format: "%.1f", startTime))s")

        // Create AVAudioPCMBuffer from Float array for DiarizationManager
        // DiarizationManager expects 16kHz mono audio
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else {
            print("[SimpleRecordingEngine] Failed to create audio buffer for diarization")
            return
        }

        // Copy samples to buffer
        buffer.frameLength = AVAudioFrameCount(chunk.count)
        if let channelData = buffer.floatChannelData {
            for i in 0..<chunk.count {
                channelData[0][i] = chunk[i]
            }
        }

        // Process through DiarizationManager
        await diarizationManager.processAudioBuffer(buffer)

        // Check for diarization errors
        if let error = diarizationManager.lastError {
            print("[SimpleRecordingEngine] Diarization error: \(error.localizedDescription)")
            // Don't return - still try to use any partial results
        }

        // Update segment aligner with latest results
        if let result = diarizationManager.lastResult {
            print("[SimpleRecordingEngine] Diarization result: \(result.segments.count) segments, \(result.speakerCount) speakers")
            segmentAligner.updateDiarizationResults(result)

            // Always update participants and meeting type from latest results,
            // since speaker merging can reduce the count between chunks.
            let speakerCount = diarizationManager.totalSpeakerCount
            if speakerCount != detectedSpeakerCount {
                print("[SimpleRecordingEngine] Speaker count changed: \(detectedSpeakerCount) -> \(speakerCount)")
            }
            detectedSpeakerCount = speakerCount
            updateMeetingType(speakerCount: speakerCount)
            updateParticipants(from: result)

            // Sync participants: remove any whose speaker IDs were merged away
            let validSpeakerIDs = Set(result.segments.map { SegmentAligner.parseNumericId($0.speakerId) })
            currentMeeting?.syncParticipants(withSpeakerIDs: validSpeakerIDs)

            // Backfill speaker labels into transcript segments that arrived before diarization
            backfillSpeakerLabels()
        } else {
            print("[SimpleRecordingEngine] No diarization result yet (isEnabled: \(diarizationManager.isEnabled), isProcessing: \(diarizationManager.isProcessing))")
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
                // Use user-assigned name if available
                let numericId = SegmentAligner.parseNumericId(speaker)
                let speakerName: String
                if let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == numericId }),
                   let userName = participant.name, participant.namingMode == .namedByUser {
                    speakerName = userName
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
            } else {
                // First segment still nil — this is the new cursor position
                newCursor = min(newCursor, i)
            }
        }

        backfillCursor = newCursor

        if backfilledCount > 0 {
            print("[SimpleRecordingEngine] Backfilled speaker labels for \(backfilledCount) transcript segments (cursor at \(backfillCursor))")
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
    private func updateParticipants(from result: DiarizationResult) {
        guard let meeting = currentMeeting else { return }

        // Get speaking times per speaker
        let speakingTimes = segmentAligner.getSpeakingTimes()
        let uniqueSpeakers = segmentAligner.getUniqueSpeakers()

        for speakerId in uniqueSpeakers {
            // Convert string speakerId to numeric ID (e.g., "speaker_0" -> 0)
            let numericId = SegmentAligner.parseNumericId(speakerId)

            // Check if we already have this participant (by numeric speakerID)
            if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == numericId }) {
                // Update speaking time for existing participant
                existingParticipant.totalSpeakingTime = speakingTimes[speakerId] ?? 0
            } else {
                // Add new participant
                let participant = IdentifiedParticipant()
                participant.speakerID = numericId
                participant.confidence = 1.0
                participant.isCurrentUser = false
                participant.totalSpeakingTime = speakingTimes[speakerId] ?? 0

                // Attempt voice-based identification using VoicePrintManager
                if let embedding = result.speakerDatabase?[speakerId] {
                    if let match = voicePrintManager.findMatchingPerson(for: embedding),
                       let matchedPerson = match.0,
                       match.1 > 0.80 {
                        participant.name = matchedPerson.wrappedName
                        participant.namingMode = .suggestedByVoice
                        participant.personRecord = matchedPerson
                        participant.person = matchedPerson
                        participant.confidence = match.1
                        print("[SimpleRecordingEngine] 🎤 Voice match: \(matchedPerson.wrappedName) (confidence: \(String(format: "%.0f%%", match.1 * 100)))")
                    }
                }

                meeting.identifiedParticipants.append(participant)
                print("[SimpleRecordingEngine] Added participant: \(participant.displayName)")
            }
        }
    }
    #endif

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
        print("[SimpleRecordingEngine] Finalizing meeting...")

        // Update final duration
        meeting.duration = recordingDuration
        meeting.isRecording = false

        // Store meeting data for handoff to review UI
        saveToUserDefaults(meeting)
        meeting.cleanupFlushFile()

        // Show transcript import window
        DispatchQueue.main.async {
            TranscriptImportWindowManager.shared.presentWindow()
        }

        print("[SimpleRecordingEngine] Meeting finalized: \(meeting.transcript.count) segments, \(meeting.wordCount) words")
    }

    private func saveToUserDefaults(_ meeting: LiveMeeting) {
        // Build transcript as plain text (matching reader's expected format)
        let transcriptText = meeting.getFullTranscriptText()

        // Get voice embeddings from diarization results
        #if canImport(FluidAudio)
        var speakerEmbeddings: [String: [Float]] = [:]
        if let result = diarizationManager.lastResult {
            for segment in result.segments {
                if speakerEmbeddings[segment.speakerId] == nil {
                    speakerEmbeddings[segment.speakerId] = segment.embedding
                }
            }
        }
        #endif

        // Build participant data with voice embeddings
        let serializableParticipants = meeting.identifiedParticipants.map { participant in
            #if canImport(FluidAudio)
            let speakerIdString = "\(participant.speakerID)"
            let embedding = speakerEmbeddings[speakerIdString]
            return SerializableParticipant(from: participant, voiceEmbedding: embedding)
            #else
            return SerializableParticipant(from: participant, voiceEmbedding: nil)
            #endif
        }

        // Get user notes as plain text
        let userNotes = meeting.userNotesPlainText

        // Write all keys atomically using correct keys matching TranscriptImportWindowView reader
        let defaults = UserDefaults.standard
        defaults.set(transcriptText, forKey: "PendingRecordedTranscript")
        defaults.set(meeting.calendarTitle, forKey: "PendingRecordedTitle")
        defaults.set(meeting.startTime, forKey: "PendingRecordedDate")
        defaults.set(meeting.duration, forKey: "PendingRecordedDuration")
        if !userNotes.isEmpty {
            defaults.set(userNotes, forKey: "PendingRecordedUserNotes")
        }
        if let participantData = try? JSONEncoder().encode(serializableParticipants) {
            defaults.set(participantData, forKey: "PendingRecordedParticipants")
        }
        defaults.synchronize()

        print("[SimpleRecordingEngine] Saved meeting data to UserDefaults (\(meeting.identifiedParticipants.count) participants)")
    }

    // MARK: - Monitoring (Simplified)

    func startMonitoring() {
        // Simplified: just mark as monitoring
        // Auto-detection to be added in future phase
        isMonitoring = true
        print("[SimpleRecordingEngine] Monitoring started (passive)")
    }

    func stopMonitoring() {
        isMonitoring = false
        print("[SimpleRecordingEngine] Monitoring stopped")
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
        print("[SimpleRecordingEngine] Permission prompts reset")
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
