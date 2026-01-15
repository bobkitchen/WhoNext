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

    // Speaker diarization state
    @Published var detectedSpeakerCount: Int = 0

    // MARK: - Components

    private let audioCapturer = AudioCapturer()
    private let chunkBuffer = AudioChunkBuffer()
    private let transcriber = TranscriptionEngine()

    // MARK: - Diarization Components

    #if canImport(FluidAudio)
    private let diarizationManager = DiarizationManager(enableRealTimeProcessing: true)
    private let diarizationBuffer = DiarizationBuffer()
    private let segmentAligner = SegmentAligner()
    #endif

    // MARK: - Private State

    private var recordingTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

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
    }

    // MARK: - Pre-warming

    /// Initialize transcription engine and diarization ahead of time
    func preWarm() async {
        do {
            // Load WhisperKit model
            let model = MeetingRecordingConfiguration.shared.transcriptionSettings.whisperModel
            try await transcriber.initialize(model: model)
            print("[SimpleRecordingEngine] Pre-warmed transcriber with model: \(model)")

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
            if !transcriber.isReady {
                let model = MeetingRecordingConfiguration.shared.transcriptionSettings.whisperModel
                try await transcriber.initialize(model: model)
            }

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

        // Update state
        isRecording = false
        recordingState = .processing

        // Finalize meeting
        if let meeting = currentMeeting {
            await finalizeMeeting(meeting)
        }

        recordingState = .idle
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
                        await MainActor.run {
                            Task {
                                await self.transcribeChunk(chunk)
                            }
                        }
                    }

                    #if canImport(FluidAudio)
                    // Also feed to diarization buffer (parallel pipeline)
                    let elapsed = await MainActor.run { self.recordingDuration }
                    if let (diarChunk, startTime) = await diarBuffer.addBuffer(audioBuffer, recordingElapsed: elapsed) {
                        await MainActor.run {
                            Task {
                                await self.processDiarizationChunk(diarChunk, startTime: startTime)
                            }
                        }
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
                        await MainActor.run {
                            Task {
                                await self.transcribeChunk(chunk)
                            }
                        }
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

    private func transcribeChunk(_ chunk: [Float]) async {
        do {
            // Log chunk stats
            let stats = await chunkBuffer.getStats()
            print("[SimpleRecordingEngine] Transcribing chunk: \(chunk.count) samples")
            print("[SimpleRecordingEngine] Buffer stats: \(stats.description)")

            // Transcribe
            if let result = try await transcriber.transcribe(audioChunk: chunk) {
                // Query speaker from diarization
                var speakerID: String? = nil
                var speakerName: String? = nil

                #if canImport(FluidAudio)
                // Query the segment aligner for the dominant speaker during this transcript window
                // Transcription chunks are ~15 seconds, query from the start of this segment
                let segmentStart = max(0, recordingDuration - 15.0)
                if let speaker = segmentAligner.dominantSpeaker(for: segmentStart, duration: 15.0) {
                    speakerID = speaker
                    speakerName = SegmentAligner.formatSpeakerName(speaker)
                    print("[SimpleRecordingEngine] Speaker identified: \(speakerName ?? "unknown")")
                }
                #endif

                // Convert to TranscriptSegment for LiveMeeting
                let segment = TranscriptSegment(
                    text: result.text,
                    timestamp: recordingDuration,  // Seconds from start
                    speakerID: speakerID,
                    speakerName: speakerName,
                    confidence: result.confidence,
                    isFinalized: true
                )

                // Add to meeting
                currentMeeting?.transcript.append(segment)
                currentMeeting?.wordCount += result.text.split(separator: " ").count

                let speakerInfo = speakerName ?? "unknown speaker"
                print("[SimpleRecordingEngine] Added segment (\(speakerInfo)): \"\(result.text.prefix(50))...\"")
            }
        } catch {
            print("[SimpleRecordingEngine] Transcription error: \(error)")
        }
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

        // Update segment aligner with latest results
        if let result = diarizationManager.lastResult {
            print("[SimpleRecordingEngine] Diarization result: \(result.segments.count) segments, \(result.speakerCount) speakers")
            segmentAligner.updateDiarizationResults(result)

            // Update detected speaker count
            let speakerCount = diarizationManager.totalSpeakerCount
            if speakerCount != detectedSpeakerCount {
                detectedSpeakerCount = speakerCount
                print("[SimpleRecordingEngine] Speaker count updated: \(speakerCount)")

                // Update meeting type
                updateMeetingType(speakerCount: speakerCount)

                // Update participants
                updateParticipants(from: result)
            }
        } else {
            print("[SimpleRecordingEngine] No diarization result yet (isEnabled: \(diarizationManager.isEnabled), isProcessing: \(diarizationManager.isProcessing))")
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

    /// Update participants from diarization results
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
                participant.name = nil  // Will show as "Speaker N" via displayName
                participant.confidence = 1.0
                participant.isCurrentUser = false  // TODO: Match against user voice profile
                participant.totalSpeakingTime = speakingTimes[speakerId] ?? 0

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

        // Show transcript import window
        DispatchQueue.main.async {
            TranscriptImportWindowManager.shared.presentWindow()
        }

        print("[SimpleRecordingEngine] Meeting finalized: \(meeting.transcript.count) segments, \(meeting.wordCount) words")
    }

    private func saveToUserDefaults(_ meeting: LiveMeeting) {
        // Save transcript
        if let transcriptData = try? JSONEncoder().encode(meeting.transcript) {
            UserDefaults.standard.set(transcriptData, forKey: "pendingTranscript")
        }

        // Save meeting title
        UserDefaults.standard.set(meeting.calendarTitle, forKey: "pendingMeetingTitle")

        // Save duration
        UserDefaults.standard.set(meeting.duration, forKey: "pendingRecordingDuration")

        // Get voice embeddings from diarization results
        #if canImport(FluidAudio)
        var speakerEmbeddings: [String: [Float]] = [:]
        if let result = diarizationManager.lastResult {
            // Extract average embedding per speaker from their segments
            for segment in result.segments {
                if speakerEmbeddings[segment.speakerId] == nil {
                    speakerEmbeddings[segment.speakerId] = segment.embedding
                }
            }
        }
        #endif

        // Save participant data with voice embeddings
        let serializableParticipants = meeting.identifiedParticipants.map { participant in
            #if canImport(FluidAudio)
            // Convert numeric speakerID back to string format for embedding lookup
            let speakerIdString = "speaker_\(participant.speakerID)"
            let embedding = speakerEmbeddings[speakerIdString]
            return SerializableParticipant(from: participant, voiceEmbedding: embedding)
            #else
            return SerializableParticipant(from: participant, voiceEmbedding: nil)
            #endif
        }

        if let participantData = try? JSONEncoder().encode(serializableParticipants) {
            UserDefaults.standard.set(participantData, forKey: "pendingParticipants")
        }

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
