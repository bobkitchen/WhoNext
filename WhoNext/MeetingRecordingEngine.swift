import Foundation
import AVFoundation
import SwiftUI
import AppKit
import CoreData
import EventKit
import ScreenCaptureKit
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Main orchestrator for automatic meeting recording based on two-way audio detection
/// Coordinates audio capture, conversation detection, recording, and transcription
class MeetingRecordingEngine: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MeetingRecordingEngine()
    
    // MARK: - Published Properties
    @Published var isMonitoring: Bool = false
    @Published var isRecording: Bool = false
    @Published var currentMeeting: LiveMeeting?
    @Published var recordingState: RecordingState = .idle
    @Published var autoRecordEnabled: Bool = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var isBufferingTranscript: Bool = false  // True when accumulating words for a sentence

    // MARK: - Overlapping Meeting Detection
    @Published var overlappingMeetings: [UpcomingMeeting] = []  // Calendar events during recording window
    @Published var selectedMeetingID: String? = nil  // User's selected meeting (nil = generic title)
    
    // MARK: - Recording State
    enum RecordingState {
        case idle
        case monitoring
        case conversationDetected
        case recording
        case processing
        case error(String)
    }
    
    // MARK: - Core Components
    let audioCapture = SystemAudioCapture() // Made public for UI access
    private let twoWayDetector = TwoWayAudioDetector()
    private let storageManager = AudioStorageManager()
    private var modernSpeechFramework: Any? // Will hold ModernSpeechFramework if available
    private var transcriptProcessor: TranscriptProcessor?
    private let calendarService = CalendarService.shared
    private let microphoneMonitor = MicrophoneActivityMonitor()
    let qualityMonitor = RecordingQualityMonitor() // Made public for UI access
    private let voicePrintManager = VoicePrintManager() // Voice recognition
    private let voiceLearningSystem: VoiceLearningSystem
    
    // MARK: - Properties
    
    // Recording State
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var lastCorrelationTime: Date?  // Track when we last correlated speakers
    private var totalFramesProcessed: AVAudioFramePosition = 0  // Frame-accurate tracking

    // AsyncStream Tasks (modern structured concurrency)
    private var audioStreamTask: Task<Void, Never>?

    // Pre-warming State
    private var isPrewarming = false

    // Pre-meeting preparation (smart calendar integration)
    private var preloadedVoiceEmbeddings: [UUID: [Float]] = [:]  // Person ID -> voice embedding
    private var expectedParticipants: [String] = []  // Names from calendar
    private var preparationTimer: Timer?
    
    // Audio Capture

    private var audioWriter: AVAudioFile?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let maxBufferCount = 500 // Keep ~5-10 seconds of audioffers (~10 seconds at 100ms intervals)
    private var calendarMonitorTimer: Timer?
    private var currentCalendarEvent: UpcomingMeeting?
    private var lastTranscriptionText: String = "" // Track the last full transcript to detect new content

    // MARK: - Sentence Buffering (for cleaner transcript display)
    private var sentenceBuffer: String = ""  // Accumulates words until sentence complete
    private var sentenceBufferSpeakerID: String = "speaker_1"  // Track speaker for buffered content
    private var lastBufferUpdateTime: Date = Date()  // For pause detection
    private let sentencePauseThreshold: TimeInterval = 2.0  // Seconds of silence = sentence end
    
    // MARK: - Diarization (Speaker Detection)
    #if canImport(FluidAudio)
    internal var diarizationManager: DiarizationManager?  // Made internal for voice embedding access
    #endif

    // MARK: - Two-Stream Diarization (Architecture A+)
    // System audio goes to diarization for remote speakers
    // Mic audio goes to leakage detector for ME detection
    private var leakageDetector: LeakageDetector?  // Initialized on MainActor in setupLeakageDetection()
    private var meSegments: [MESegment] = []  // Detected ME speaking segments
    private var currentMESegmentStart: TimeInterval?  // Start of current ME segment (nil if not speaking)
    private let meSegmentMinDuration: TimeInterval = 0.3  // Minimum duration to count as ME speech

    // MARK: - User Preferences
    @AppStorage("autoRecordEnabled") private var autoRecordPref: Bool = true
    @AppStorage("recordingConfidenceThreshold") private var confidenceThreshold: Double = 0.7
    @AppStorage("minimumMeetingDuration") private var minimumDuration: TimeInterval = 30.0
    @AppStorage("screenRecordingPromptDismissed") private var screenRecordingPromptDismissed: Bool = false
    @AppStorage("lastScreenRecordingPromptDate") private var lastScreenRecordingPromptDate: Double = 0
    
    // MARK: - Initialization
    private init() {
        // Initialize voice learning system
        voiceLearningSystem = VoiceLearningSystem(voicePrintManager: voicePrintManager)

        setupDetection()
        setupNotifications()
        loadPreferences()
        setupTranscription()
        setupDiarization()
        setupLeakageDetection()
    }

    private func setupLeakageDetection() {
        // Initialize leakage detector on MainActor for @Published properties
        Task { @MainActor in
            self.leakageDetector = LeakageDetector()
            print("🔊 Leakage detector initialized for two-stream diarization")
        }
    }
    
    private func setupTranscription() {
        // Initialize modern speech framework if available
        if #available(macOS 26.0, *) {
            // Only create a new framework if one doesn't exist
            if modernSpeechFramework == nil {
                // Pre-initialize asynchronously to warm up the engine
                Task { @MainActor in
                    // Create framework on main actor
                    modernSpeechFramework = ModernSpeechFramework(locale: .current)

                    do {
                        if let framework = modernSpeechFramework as? ModernSpeechFramework {
                            print("🔥 Pre-initializing Modern Speech Framework...")
                            try await framework.initialize()
                            print("✅ Modern Speech Framework pre-warmed and ready")
                            print("✅ Using AsyncStream<AnalyzerInput> pattern for streaming")
                        }
                    } catch {
                        print("⚠️ Failed to pre-initialize Modern Speech Framework: \(error)")
                        print("⚠️ Error details: \(error.localizedDescription)")
                        print("ℹ️ Will retry initialization when recording starts")
                    }
                }
            } else {
                print("ℹ️ Modern Speech Framework already initialized")
            }
        }
    }
    
    private func setupDiarization() {
        #if canImport(FluidAudio)
        Task { @MainActor in
            // Get user-configured sensitivity, but enforce a higher minimum to prevent over-segmentation
            let config = MeetingRecordingConfiguration.shared
            let configSensitivity = Float(config.transcriptionSettings.speakerSensitivity)
            let sensitivity = configSensitivity
            
            // Create diarization manager with custom threshold
            diarizationManager = DiarizationManager(
                isEnabled: true, 
                enableRealTimeProcessing: true,
                clusteringThreshold: sensitivity
            )
            
            do {
                try await diarizationManager?.initialize()
                print("✅ DiarizationManager initialized with sensitivity: \(sensitivity)")
            } catch {
                print("⚠️ Failed to initialize DiarizationManager: \(error)")
            }
        }
        #endif
    }
    
    // MARK: - Permission Handling
    
    /// Request microphone permission
    @MainActor
    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            // Show alert to guide user to settings
            showPermissionDeniedAlert()
            return false
        @unknown default:
            return false
        }
    }
    
    /// Show alert when permission is denied
    private func showPermissionDeniedAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText = "To record meetings, WhoNext needs access to your microphone. Please grant permission in System Settings > Privacy & Security > Microphone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    /// Request screen recording permission
    @MainActor
    private func requestScreenRecordingPermission() async -> Bool {
        if #available(macOS 13.0, *) {
            // Check if we have screen recording permission by attempting to get content
            do {
                let _ = try await SCShareableContent.current
                return true // Permission granted
            } catch {
                // Permission denied or not determined
                // Check if we should show the alert
                let shouldShowAlert = shouldPromptForScreenRecording()
                
                if shouldShowAlert {
                    showScreenRecordingPermissionAlert()
                }
                return false
            }
        }
        return true // Not needed for older macOS versions
    }
    
    /// Determine if we should show the screen recording prompt
    private func shouldPromptForScreenRecording() -> Bool {
        // Don't show if user previously dismissed
        if screenRecordingPromptDismissed {
            // Check if it's been more than 7 days since last prompt
            let daysSinceLastPrompt = (Date().timeIntervalSince1970 - lastScreenRecordingPromptDate) / 86400
            if daysSinceLastPrompt < 7 {
                return false
            }
        }
        return true
    }
    
    /// Show alert for screen recording permission
    private func showScreenRecordingPermissionAlert() {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Recommended"
            alert.informativeText = "To capture system audio from meeting apps (Zoom, Teams, etc.), WhoNext needs screen recording permission. Without it, only microphone audio will be recorded.\n\nYou can grant permission in System Settings > Privacy & Security > Screen Recording."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Continue with Microphone Only")
            alert.addButton(withTitle: "Ask Me Later")
            
            let response = alert.runModal()
            
            // Track the user's choice
            self?.lastScreenRecordingPromptDate = Date().timeIntervalSince1970
            
            switch response {
            case .alertFirstButtonReturn:
                // Open System Settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
                self?.screenRecordingPromptDismissed = false
                
            case .alertSecondButtonReturn:
                // Continue with microphone only
                self?.screenRecordingPromptDismissed = true
                print("ℹ️ User chose to continue with microphone only")
                
            case .alertThirdButtonReturn:
                // Ask me later
                self?.screenRecordingPromptDismissed = true
                print("ℹ️ User chose to be asked later about screen recording")
                
            default:
                break
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Reset permission prompts
    func resetPermissionPrompts() {
        screenRecordingPromptDismissed = false
        lastScreenRecordingPromptDate = 0
        print("♻️ Permission prompts have been reset")
    }
    
    /// Check current permission status
    func checkPermissionStatus() async -> (microphone: Bool, screenRecording: Bool) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        var screenStatus = false
        if #available(macOS 13.0, *) {
            do {
                let _ = try await SCShareableContent.current
                screenStatus = true
            } catch {
                screenStatus = false
            }
        }
        
        return (microphone: micStatus, screenRecording: screenStatus)
    }
    
    /// Start manual recording
    func startManualRecording() {
        print("👤 Starting manual recording")
        
        // Request permissions
        Task {
            // First check microphone permission (required)
            let micAuthorized = await requestMicrophonePermission()
            guard micAuthorized else {
                await MainActor.run {
                    self.recordingState = .error("Microphone permission denied. Please grant access in System Settings.")
                }
                return
            }
            
            // Then check screen recording permission (optional but recommended)
            let screenRecordingAuthorized = await requestScreenRecordingPermission()
            if !screenRecordingAuthorized {
                print("⚠️ Screen recording permission not granted - recording with microphone only")
            }
            
            // Reset the transcription framework BEFORE starting
            if #available(macOS 26.0, *) {
                await MainActor.run {
                    if let framework = self.modernSpeechFramework as? ModernSpeechFramework {
                        let currentTranscript = framework.getCurrentTranscript()
                        if !currentTranscript.isEmpty {
                            print("⚠️ Found existing transcript (\(currentTranscript.count) chars), resetting...")
                        }
                        framework.reset()
                        print("✅ Reset transcription framework before recording")
                        
                        // Verify reset worked
                        let afterReset = framework.getCurrentTranscript()
                        if !afterReset.isEmpty {
                            print("❌ WARNING: Transcript not cleared after reset!")
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.lastTranscriptionText = "" // Reset transcript tracking
                
                // Start manual recording
                self.startRecording(isManual: true)
            }
        }
    }
    
    /// Start monitoring for conversations and auto-recording
    func startMonitoring() {
        guard !isMonitoring else { return }

        print("🎙️ Starting meeting recording engine monitoring")

        // Request permissions
        Task {
            // First check microphone permission (required)
            let micAuthorized = await requestMicrophonePermission()
            guard micAuthorized else {
                await MainActor.run {
                    self.recordingState = .error("Microphone permission denied. Please grant access in System Settings.")
                }
                return
            }

            // Then check screen recording permission (optional but recommended)
            let screenRecordingAuthorized = await requestScreenRecordingPermission()
            if !screenRecordingAuthorized {
                print("⚠️ Screen recording permission not granted - using microphone-only mode")
            }

            // Try to start audio capture (but don't fail if it doesn't work)
            var audioCaptureWorking = false
            do {
                try await audioCapture.startCapture()

                // CRITICAL FIX: Wait for first audio buffer before starting detection
                // This prevents race condition where detection starts before audio is flowing
                await audioCapture.waitForFirstBuffer()
                print("✅ Audio sync complete - detection can now start")

                // Start AsyncStream consumer task (modern structured concurrency)
                startAudioStreamProcessing()

                // Also maintain callback for backward compatibility
                audioCapture.onAudioBuffersAvailable = { [weak self] micBuffer, systemBuffer in
                    self?.processAudioBuffers(mic: micBuffer, system: systemBuffer)
                }

                // Start two-way detection (now safe - audio is confirmed flowing)
                twoWayDetector.startMonitoring()

                audioCaptureWorking = true
                print("✅ Audio capture started successfully")
            } catch {
                print("⚠️ Audio capture failed: \(error.localizedDescription)")
                print("ℹ️  Monitoring will continue with calendar and app detection only")
            }

            // Always start microphone activity monitoring for ad-hoc calls
            await MainActor.run {
                self.microphoneMonitor.startMonitoring()
                self.microphoneMonitor.onPotentialMeetingDetected = { [weak self] appName in
                    self?.handleAdHocMeetingDetected(appName)
                }
            }

            // Always enable monitoring (even if audio capture failed)
            await MainActor.run {
                self.isMonitoring = true
                if audioCaptureWorking {
                    self.recordingState = .monitoring
                } else {
                    self.recordingState = .monitoring // Still monitoring, just without audio
                }

                // Monitoring indicator now shown inline in toolbar (MonitoringIndicator)
                // No floating window needed for monitoring state

                // Start smart calendar preparation timer
                self.startPreparationTimer()
            }

            print("✅ Meeting recording engine started successfully")
            if !audioCaptureWorking {
                print("⚠️  Note: Running in limited mode (calendar + app detection only)")
            }
        }
    }
    
    /// Stop monitoring and recording
    func stopMonitoring() {
        guard isMonitoring else { return }

        print("🛑 Stopping meeting recording engine")

        // Stop calendar monitoring
        stopCalendarMonitoring()

        // Stop preparation timer
        preparationTimer?.invalidate()
        preparationTimer = nil
        preloadedVoiceEmbeddings.removeAll()
        expectedParticipants.removeAll()

        // Stop microphone monitoring
        microphoneMonitor.stopMonitoring()

        // Stop recording if active
        if isRecording {
            stopRecording()
        }

        // Stop detection
        twoWayDetector.stopMonitoring()

        // Cancel AsyncStream processing task
        audioStreamTask?.cancel()
        audioStreamTask = nil

        // Stop audio capture
        audioCapture.stopCapture()

        DispatchQueue.main.async {
            self.isMonitoring = false
            self.recordingState = .idle
            // Monitoring indicator updates automatically via @Published properties
        }
    }

    // MARK: - AsyncStream Audio Processing

    /// Start consuming audio from AsyncStream (modern structured concurrency)
    private func startAudioStreamProcessing() {
        // Cancel any existing task
        audioStreamTask?.cancel()

        // Create new task to consume mixed audio stream
        audioStreamTask = Task { [weak self] in
            guard let self = self else { return }

            print("🎵 AsyncStream: Started audio processing pipeline")

            for await mixedBuffer in audioCapture.mixedAudioStream {
                // Check for cancellation
                guard !Task.isCancelled else {
                    print("🎵 AsyncStream: Processing cancelled")
                    break
                }

                // Process buffer (this replaces the callback approach)
                await self.processAudioBuffers(mic: nil, system: nil)

                // Note: mixedBuffer is the combined audio ready for transcription
                // The actual processing happens in processAudioBuffers which is
                // still called via callback for compatibility
            }

            print("🎵 AsyncStream: Audio processing completed")
        }
    }

    /// Manually start recording
    func manualStartRecording() {
        guard !isRecording else { return }

        Task {
            let authorized = await requestMicrophonePermission()
            guard authorized else {
                await MainActor.run {
                    self.recordingState = .error("Microphone permission denied. Please grant access in System Settings.")
                }
                return
            }

            print("👤 Manual recording started")
            // Must run on main thread since startRecording updates @Published properties
            await MainActor.run {
                self.startRecording(isManual: true)
            }
        }
    }
    
    /// Manually stop recording
    func manualStopRecording() {
        guard isRecording else { return }
        
        print("👤 Manual recording stopped")
        stopRecording()
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupDetection() {
        // Set up two-way audio detection callbacks
        twoWayDetector.onConversationStart = { [weak self] in
            self?.handleConversationStart()
        }
        
        twoWayDetector.onConversationEnd = { [weak self] in
            self?.handleConversationEnd()
        }
    }
    
    private func setupNotifications() {
        // Listen for app termination to clean up
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    private func loadPreferences() {
        autoRecordEnabled = autoRecordPref
    }
    
    // MARK: - Private Methods - Audio Processing
    
    private func processAudioBuffers(mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?) {
        // Update calendar status in detector
        twoWayDetector.isMeetingScheduled = (currentCalendarEvent != nil)

        // Pass to two-way detector for conversation analysis
        twoWayDetector.analyzeAudioStreams(micBuffer: mic, systemBuffer: system)

        // If recording or pre-warming, process audio streams
        if isRecording || isPrewarming {

            // MARK: Two-Stream Diarization (Architecture A+)
            // - System audio ONLY goes to diarization (for remote speakers)
            // - Mic audio goes to leakage detector (for ME detection)
            // - Mixed audio still saved for recording and transcription

            // Step 1: Feed system audio to leakage detector's reference buffer
            if let systemBuffer = system, let leakageDetector = self.leakageDetector {
                Task { @MainActor in
                    leakageDetector.processSystemAudio(systemBuffer)
                }
            }

            // Step 2: Process mic for leakage-aware ME detection
            if let micBuffer = mic, isRecording, let leakageDetector = self.leakageDetector {
                Task { @MainActor in
                    let systemLevel = self.calculateRMSLevel(system)
                    let result = leakageDetector.detectGenuineSpeech(micBuffer, systemLevel: systemLevel)

                    // Calculate current time relative to recording start
                    let currentTime: TimeInterval
                    if let startTime = self.recordingStartTime {
                        currentTime = Date().timeIntervalSince(startTime)
                    } else {
                        currentTime = 0
                    }
                    let bufferDuration = Double(micBuffer.frameLength) / micBuffer.format.sampleRate

                    if result.isGenuineME {
                        // Genuine ME speech detected
                        if self.currentMESegmentStart == nil {
                            // Start new ME segment
                            self.currentMESegmentStart = currentTime
                            print("🎙️ ME speech started at \(String(format: "%.2f", currentTime))s (confidence: \(String(format: "%.2f", result.confidence)))")
                        }
                    } else {
                        // Not ME speech (silence, leakage, or no speech)
                        if let segmentStart = self.currentMESegmentStart {
                            let segmentDuration = currentTime - segmentStart
                            if segmentDuration >= self.meSegmentMinDuration {
                                // End ME segment and record it
                                let segment = MESegment(
                                    startTime: segmentStart,
                                    endTime: currentTime,
                                    confidence: result.confidence
                                )
                                self.meSegments.append(segment)
                                print("🎙️ ME segment ended: \(String(format: "%.2f", segmentStart))s - \(String(format: "%.2f", currentTime))s (\(String(format: "%.1f", segmentDuration))s)")
                            }
                            self.currentMESegmentStart = nil
                        }
                    }
                }
            }

            // Mix the audio buffers for complete conversation (for recording + transcription)
            if let mixedBuffer = audioCapture.mixAudioBuffers(mic: mic, system: system) {
                // Track frame position for accurate timing
                totalFramesProcessed += AVAudioFramePosition(mixedBuffer.frameLength)
                // Only save to disk if actually recording
                if isRecording {
                    saveAudioBuffer(mixedBuffer)
                }

                // Step 3: Process SYSTEM-ONLY for diarization (remote speakers)
                // This is the key change: diarization only sees system audio,
                // which prevents user's voice from contaminating speaker clusters
                #if canImport(FluidAudio)
                if isRecording, let diarizationManager = diarizationManager, let systemBuffer = system {
                    Task {
                        // Phase 2: Update overlap state for centroid protection
                        // This lets diarization manager know when both mic and system are active
                        await diarizationManager.updateOverlapState(micBuffer: mic, systemBuffer: system)

                        // Route system-only audio to diarization
                        await diarizationManager.processAudioBuffer(systemBuffer)
                        
                        // Update meeting type and identify speakers
                        await MainActor.run {
                            if let result = diarizationManager.lastResult {
                                // Use the historical speaker count, not just current buffer
                                let speakerCount = diarizationManager.totalSpeakerCount > 0 ? 
                                    diarizationManager.totalSpeakerCount : result.speakerCount
                                let progressValue = diarizationManager.processingProgress
                                
                                self.currentMeeting?.updateMeetingType(
                                    speakerCount: speakerCount,
                                    confidence: progressValue > 0 ? Float(progressValue) : 0.5
                                )
                                
                                // Update or create participants for each detected speaker
                                // Use speakerDatabase keys (post-merge) as the authoritative list
                                let validSpeakerIDs: Set<String>
                                if let speakerDB = result.speakerDatabase, !speakerDB.isEmpty {
                                    validSpeakerIDs = Set(speakerDB.keys)
                                } else {
                                    validSpeakerIDs = Set(result.segments.map { $0.speakerId })
                                }

                                // Convert speaker IDs to integers for participant tracking
                                var validSpeakerNumbers: Set<Int> = []
                                for speakerId in validSpeakerIDs {
                                    let speakerNumber: Int
                                    if let directNumber = Int(speakerId) {
                                        speakerNumber = directNumber
                                    } else if speakerId.hasPrefix("speaker_") {
                                        speakerNumber = Int(speakerId.replacingOccurrences(of: "speaker_", with: "")) ?? 1
                                    } else {
                                        speakerNumber = 1
                                    }
                                    validSpeakerNumbers.insert(speakerNumber)
                                }

                                // Sync participants - remove any that were merged away
                                self.currentMeeting?.syncParticipants(withSpeakerIDs: validSpeakerNumbers)

                                // Add any new speakers
                                for speakerNumber in validSpeakerNumbers {
                                    if !self.currentMeeting!.identifiedParticipants.contains(where: { $0.speakerID == speakerNumber }) {
                                        let participant = IdentifiedParticipant()
                                        participant.speakerID = speakerNumber

                                        // Check if this speaker matches the current user's voice
                                        let speakerId = "speaker_\(speakerNumber)"
                                        if diarizationManager.isUserSpeaker(speakerId) {
                                            participant.isCurrentUser = true
                                            participant.name = UserProfile.shared.name ?? "You"
                                            participant.namingMode = .linkedToPerson
                                            participant.confidence = diarizationManager.userSpeakerConfidence
                                            print("🎤 Added current user as Speaker \(speakerNumber) (confidence: \(String(format: "%.0f%%", diarizationManager.userSpeakerConfidence * 100)))")
                                        } else {
                                            participant.name = nil // Will be named later by user or voice matching
                                            print("🎤 Added new participant: Speaker \(speakerNumber)")
                                        }

                                        self.currentMeeting?.addIdentifiedParticipant(participant)
                                    } else {
                                        // Update existing participant if they're now identified as current user
                                        let speakerId = "speaker_\(speakerNumber)"
                                        if diarizationManager.isUserSpeaker(speakerId),
                                           let participant = self.currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == speakerNumber }),
                                           !participant.isCurrentUser {
                                            participant.isCurrentUser = true
                                            participant.name = UserProfile.shared.name ?? "You"
                                            participant.namingMode = .linkedToPerson
                                            participant.confidence = diarizationManager.userSpeakerConfidence
                                            print("🎤 Updated Speaker \(speakerNumber) as current user (confidence: \(String(format: "%.0f%%", diarizationManager.userSpeakerConfidence * 100)))")
                                        }
                                    }
                                }

                                // Try to identify speakers from embeddings in real-time
                                if let speakerDatabase = result.speakerDatabase, !speakerDatabase.isEmpty {
                                    Task {
                                        await self.identifySpeakersInRealTime(speakerDatabase)
                                    }
                                }
                            }
                        }
                    }
                }
                #endif
                
                // Process for real-time transcription using modern Speech framework
                if #available(macOS 26.0, *) {
                    if let framework = modernSpeechFramework as? ModernSpeechFramework {
                        Task { @MainActor in
                            do {
                                // CRITICAL FIX: Use processAudioStreamWithTimestamp to get accurate buffer timing
                                // This fixes speaker attribution by using the AUDIO's timestamp, not ARRIVAL time
                                let result = try await framework.processAudioStreamWithTimestamp(mixedBuffer)
                                let fullTranscript = result.transcript
                                let bufferStartTime = result.bufferStartTime
                                let bufferEndTime = result.bufferEndTime

                                // Sentence-buffered transcription for cleaner display
                                // Accumulates words until sentence is complete (punctuation or pause)

                                // Check if we have new content (the transcript grows incrementally)
                                if fullTranscript.count > self.lastTranscriptionText.count {
                                    // Extract only the new portion
                                    let newContent = String(fullTranscript.dropFirst(self.lastTranscriptionText.count))

                                    if !newContent.isEmpty {
                                        // Get the current speaker from diarization if available
                                        var currentSpeakerID = "speaker_1" // Default speaker

                                        #if canImport(FluidAudio)
                                        if let diarizationManager = self.diarizationManager,
                                           let lastResult = diarizationManager.lastResult,
                                           !lastResult.segments.isEmpty {
                                            // CRITICAL FIX: Use the BUFFER's timestamp for speaker lookup
                                            // NOT the current frame count (which has moved ahead due to transcription latency)
                                            // Use dominantSpeaker for the time range this audio was actually recorded
                                            // Note: dominantSpeaker is an extension on DiarizationResult, not DiarizationManager
                                            if let speaker = lastResult.dominantSpeaker(between: bufferStartTime, and: bufferEndTime) {
                                                currentSpeakerID = speaker.hasPrefix("speaker_") ? speaker : "speaker_\(speaker)"
                                            } else {
                                                // Fallback: Find the segment that contains the buffer's midpoint
                                                let bufferMidpoint = (bufferStartTime + bufferEndTime) / 2.0

                                                let activeSegment = lastResult.segments.first { segment in
                                                    let segmentStart = Double(segment.startTimeSeconds)
                                                    let segmentEnd = Double(segment.endTimeSeconds)
                                                    return bufferMidpoint >= segmentStart && bufferMidpoint <= segmentEnd
                                                }

                                                if let speakerId = activeSegment?.speakerId {
                                                    currentSpeakerID = speakerId.hasPrefix("speaker_") ? speakerId : "speaker_\(speakerId)"
                                                } else {
                                                    // Last fallback: most recent segment before this buffer
                                                    let recentSegments = lastResult.segments.filter {
                                                        Double($0.endTimeSeconds) <= bufferEndTime
                                                    }
                                                    if let mostRecent = recentSegments.max(by: { $0.endTimeSeconds < $1.endTimeSeconds }) {
                                                        let speakerId = mostRecent.speakerId
                                                        currentSpeakerID = speakerId.hasPrefix("speaker_") ? speakerId : "speaker_\(speakerId)"
                                                    }
                                                }
                                            }
                                        }
                                        #endif

                                        // If speaker changed, flush current buffer first
                                        if currentSpeakerID != self.sentenceBufferSpeakerID && !self.sentenceBuffer.isEmpty {
                                            self.flushSentenceBuffer()
                                        }

                                        // Append new content to sentence buffer
                                        self.sentenceBuffer += newContent
                                        self.sentenceBufferSpeakerID = currentSpeakerID
                                        self.lastBufferUpdateTime = Date()
                                        self.isBufferingTranscript = true

                                        // Check if sentence is complete (ends with punctuation)
                                        let trimmedBuffer = self.sentenceBuffer.trimmingCharacters(in: .whitespaces)
                                        let sentenceEnders: Set<Character> = [".", "?", "!"]
                                        let isSentenceComplete = trimmedBuffer.last.map { sentenceEnders.contains($0) } ?? false

                                        if isSentenceComplete {
                                            self.flushSentenceBuffer()
                                        }

                                        // Update tracking
                                        if self.currentMeeting != nil {
                                            self.lastTranscriptionText = fullTranscript
                                        }

                                        // Update meeting metrics
                                        self.updateMeetingMetrics()
                                    }
                                } else {
                                    // No new content - check for pause-based sentence completion
                                    let timeSinceLastUpdate = Date().timeIntervalSince(self.lastBufferUpdateTime)
                                    if !self.sentenceBuffer.isEmpty && timeSinceLastUpdate >= self.sentencePauseThreshold {
                                        self.flushSentenceBuffer()
                                    }
                                }
                            } catch {
                                print("❌ Transcription error: \(error.localizedDescription)")
                                // Continue recording even if transcription fails
                                print("⚠️ Transcription failed but recording continues")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func saveAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Add to buffer queue
        audioBuffers.append(buffer)
        
        // Keep only recent buffers to avoid memory issues
        if audioBuffers.count > maxBufferCount {
            audioBuffers.removeFirst()
        }
        
        // Write to file if we have an audio writer
        if let audioWriter = audioWriter {
            do {
                try audioWriter.write(from: buffer)
            } catch {
                print("❌ Error writing audio buffer: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods - Recording Control
    
    private func handleConversationStart() {
        // Check if auto-recording is enabled
        guard autoRecordEnabled else {
            print("🔇 Conversation detected but auto-record is disabled - skipping")
            return
        }

        let appName = twoWayDetector.detectedApp ?? "Unknown App"
        print("🎙️ Auto-starting recording for detected conversation (Source: \(appName))")

        // Must run on main thread since startRecording updates @Published properties
        DispatchQueue.main.async {
            self.recordingState = .conversationDetected
            // If we were pre-warming, this will seamlessly transition
            self.startRecording(isManual: false)
        }
    }
    
    private func handleConversationEnd() {
        // Only stop if this was an auto-started recording
        if isRecording && !(currentMeeting?.isManual ?? true) {
            print("🛑 Auto-stopping recording - conversation ended")
            stopRecording()
        }
    }
    
    private func startRecording(isManual: Bool) {
        guard !isRecording else { return }

        recordingStartTime = Date()
        totalFramesProcessed = 0  // Reset frame counter for accurate timing
        resetSentenceBuffer()  // Clear any leftover buffer from previous recording

        // For auto-recording, reset the transcription framework
        // (Manual recording already resets before calling this)
        if !isManual {
            if #available(macOS 26.0, *) {
                Task { @MainActor in
                    if let framework = modernSpeechFramework as? ModernSpeechFramework {
                        // If we were pre-warming, we don't need to reset/start again
                        if self.isPrewarming {
                            print("🔥 Using pre-warmed speech engine - skipping initialization")
                            self.isPrewarming = false
                        } else {
                            framework.reset()
                            print("✅ Reset transcription framework for auto-recording")
                            
                            // Start transcription
                            do {
                                try await framework.startTranscription()
                                print("✅ Started transcription for auto-recording")
                            } catch {
                                print("❌ Failed to start transcription: \(error)")
                            }
                        }
                    }
                }
            }
            // Don't reset lastTranscriptionText if we were pre-warming (it should be empty anyway, 
            // but we want to capture what was buffered)
            if !isPrewarming {
                lastTranscriptionText = "" 
            }
        } else {
            // Reset tracking if not pre-warming
            if !isPrewarming {
                lastTranscriptionText = ""
            }
        }

        // Create live meeting object
        let meeting = LiveMeeting()
        meeting.isManual = isManual
        meeting.startTime = recordingStartTime!

        // Initialize metrics
        meeting.wordCount = 0
        meeting.currentFileSize = 0
        meeting.averageConfidence = 0.0
        meeting.bufferHealth = .good
        meeting.detectedLanguage = "English" // Will be updated by transcription

        // Detect overlapping calendar events
        detectOverlappingMeetings()

        // Apply calendar context based on detected meetings
        if overlappingMeetings.count == 1 {
            // Only one meeting - auto-select it
            let calendarMeeting = overlappingMeetings[0]
            selectedMeetingID = calendarMeeting.id
            applyCalendarContext(from: calendarMeeting, to: meeting)  // Apply to the LiveMeeting we just created
        } else if overlappingMeetings.count > 1 {
            // Multiple meetings - use generic title until user selects
            selectedMeetingID = nil
            // meeting.calendarTitle stays nil, so displayTitle will show "Meeting HH:MM"
        }
        // If no meetings found, calendarTitle stays nil (generic title)

        // For manual recording, ensure audio capture is running
        if isManual && !audioCapture.isCapturing {
            // Set up audio buffer callbacks
            audioCapture.onAudioBuffersAvailable = { [weak self] micBuffer, systemBuffer in
                self?.processAudioBuffers(mic: micBuffer, system: systemBuffer)
            }

            audioCapture.onMixedAudioAvailable = { [weak self] mixedBuffer in
                // Mixed audio is already handled in processAudioBuffers
                // This is here for future use if needed
            }

            // Start tasks in parallel for better performance
            Task {
                do {
                    try await audioCapture.startCapture()
                    print("🎤 Started audio capture for manual recording")
                } catch {
                    print("❌ Failed to start audio capture: \(error)")
                }
            }

            // Also start transcription if manual
            if #available(macOS 26.0, *) {
                Task { @MainActor in
                    if let framework = modernSpeechFramework as? ModernSpeechFramework {
                        // Check pre-warming
                        if self.isPrewarming {
                            print("🔥 Using pre-warmed speech engine for manual start")
                            self.isPrewarming = false
                        } else {
                            do {
                                try await framework.startTranscription()
                                print("✅ Started transcription for manual recording")
                            } catch {
                                print("❌ Failed to start transcription: \(error)")
                            }
                        }
                    }
                }
            }
        }
        
        // Set up audio file for recording
        do {
            let audioURL = try storageManager.createAudioFile(for: meeting.id)
            
            // Create audio settings from format
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: audioCapture.audioFormat.sampleRate,
                AVNumberOfChannelsKey: audioCapture.audioFormat.channelCount,
                AVEncoderBitRateKey: 32000
            ]
            
            audioWriter = try AVAudioFile(
                forWriting: audioURL,
                settings: settings
            )
            meeting.audioFilePath = audioURL.path
        } catch {
            print("❌ Failed to create audio file: \(error)")
            return
        }
        
        // Transcription is now handled directly via NativeSpeechFramework in processAudioBuffers
        
        // Start recording timer
        startRecordingTimer()
        
        // Update state and transition window to recording
        DispatchQueue.main.async {
            self.isRecording = true
            self.currentMeeting = meeting
            self.recordingState = .recording

            // Open the new recording window with note-taking
            print("🪟 Opening recording window")
            RecordingWindowManager.shared.show()
        }
        
        print("✅ Recording started: \(meeting.id)")
        
        // Attempt to identify speakers from voice prints after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds for initial audio
            await identifySpeakersFromVoicePrints()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }

        // Flush any remaining buffered text before stopping
        Task { @MainActor in
            self.flushSentenceBuffer()
        }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

        // Stop recording timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Close audio file
        audioWriter = nil
        
        // Process the recorded meeting
        if let meeting = currentMeeting {
            DispatchQueue.main.async {
                meeting.duration = duration
                meeting.endTime = Date()
            }
            
            Task {
                // Force transcription of any remaining audio before processing meeting
                if #available(macOS 26.0, *) {
                    if let framework = modernSpeechFramework as? ModernSpeechFramework {
                        print("🔄 Stopping transcription and flushing remaining audio...")
                        
                        // Stop transcription properly
                        do {
                            try await framework.stopTranscription()
                            print("✅ Transcription stopped successfully")
                        } catch {
                            print("⚠️ Error stopping transcription: \(error)")
                        }
                        
                        // Get final transcript
                        let finalTranscription = await framework.getFinalizedTranscript()
                        
                        // Finalize diarization results
                        #if canImport(FluidAudio)
                        var speakerSegments: [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] = []
                        if let diarizationManager = self.diarizationManager {
                            if let finalResult = await diarizationManager.finishProcessing() {
                                print("📊 Final diarization: \(finalResult.speakerCount) speakers detected")

                                // MARK: Two-Stream Timeline Merge
                                // Merge ME segments (from leakage detection) with diarization segments
                                let mergedSegments = await MainActor.run {
                                    self.mergeTimelinesWithME(finalResult.segments)
                                }

                                // Count unique speakers including ME
                                let uniqueSpeakers = Set(mergedSegments.map { $0.speakerId })
                                let finalSpeakerCount = uniqueSpeakers.count
                                print("📊 After ME merge: \(finalSpeakerCount) unique speakers (\(uniqueSpeakers.joined(separator: ", ")))")

                                // Final update to meeting type
                                await MainActor.run {
                                    meeting.updateMeetingType(
                                        speakerCount: finalSpeakerCount,
                                        confidence: 1.0 // High confidence after full processing
                                    )
                                    print("✅ Final Meeting Type: \(meeting.meetingType.displayName)")

                                    // Ensure ME participant exists
                                    if uniqueSpeakers.contains("ME") {
                                        if !meeting.identifiedParticipants.contains(where: { $0.speakerID == 0 }) {
                                            let meParticipant = IdentifiedParticipant()
                                            meParticipant.speakerID = 0  // Special ID for ME
                                            meParticipant.name = "ME"
                                            meParticipant.isCurrentUser = true
                                            meeting.addIdentifiedParticipant(meParticipant)
                                            print("🎙️ Added ME as participant")
                                        }
                                    }
                                }

                                // Extract and save speaker embeddings if available
                                if let speakerDatabase = finalResult.speakerDatabase {
                                    await MainActor.run {
                                        self.saveSpeakerEmbeddings(speakerDatabase, for: meeting)
                                    }
                                }
                            }

                            // Reset diarization and ME detection for next meeting
                            await MainActor.run {
                                diarizationManager.reset()
                                self.resetMEDetection()
                            }
                        }
                        #else
                        // Get speaker segments if diarization is enabled
                        // Speaker segments not available in fallback implementation
                        let speakerSegments: [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] = []
                        #endif
                        
                        if !speakerSegments.isEmpty {
                            // Add speaker-attributed segments
                            let segments = speakerSegments // Shadow for Swift 6 concurrency safety
                            await MainActor.run {
                                for (index, segment) in segments.enumerated() {
                                    let transcriptSegment = TranscriptSegment(
                                        text: segment.text,
                                        timestamp: segment.startTime,
                                        speakerID: segment.speaker,
                                        speakerName: segment.speaker,
                                        confidence: 0.95,
                                        isFinalized: true
                                    )
                                    self.currentMeeting?.addTranscriptSegment(transcriptSegment)
                                }
                                print("👥 Added \(speakerSegments.count) speaker-attributed segments")
                            }
                        } else if !finalTranscription.isEmpty {
                            // Fallback to non-attributed transcript
                            await MainActor.run {
                                let segment = TranscriptSegment(
                                    text: finalTranscription,
                                    timestamp: Date().timeIntervalSince(self.recordingStartTime ?? Date()),
                                    speakerID: nil,
                                    speakerName: nil,
                                    confidence: 0.95,
                                    isFinalized: true
                                )
                                self.currentMeeting?.addTranscriptSegment(segment)
                                print("📝 Final transcription added: \(finalTranscription.prefix(100))...")
                            }
                        } else {
                            print("⚠️ No transcription available from flush")
                        }
                    }
                }
                
                // Now process the meeting with all transcriptions
                await processMeeting(meeting)
                
                // CRITICAL: Reset the transcription framework after processing
                // This prevents transcript from persisting to next recording
                if #available(macOS 26.0, *) {
                    await MainActor.run {
                        if let framework = self.modernSpeechFramework as? ModernSpeechFramework {
                            framework.reset()
                            print("✅ Reset transcription framework after recording")
                        }
                    }
                }
            }
        }
        
        // For manual recording, stop audio capture if not monitoring
        let wasManual = currentMeeting?.isManual ?? false
        if wasManual && !isMonitoring {
            audioCapture.stopCapture()
            print("🎤 Stopped audio capture after manual recording")
        }
        
        // Reset state
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingDuration = 0
            self.recordingState = self.isMonitoring ? .monitoring : .idle

            // Hide the recording window when recording stops
            RecordingWindowManager.shared.hide()
            // Monitoring indicator in toolbar updates automatically
        }

        print("✅ Recording stopped after \(Int(duration))s")
    }
    
    // MARK: - Private Methods - Post-Processing
    
    private func processMeeting(_ meeting: LiveMeeting) async {
        await MainActor.run {
            self.recordingState = .processing
        }
        
        // print("🔄 Processing meeting: \(meeting.id)")
        // print("📊 Meeting has \(meeting.transcript.count) transcript segments")
        
        // Get voice analysis data (diarization speaker count)
        let voiceDetectedSpeakerCount = meeting.detectedSpeakerCount
        print("🎤 Voice analysis detected \(voiceDetectedSpeakerCount) speaker(s)")
        
        // Keep segments in chronological order, but format them clearly
        var formattedTranscript = ""
        var lastSpeaker: String? = nil
        
        for segment in meeting.transcript {
            let speakerName = segment.speakerName ?? "Speaker"
            
            // Only add speaker label if it changed from last segment
            if speakerName != lastSpeaker {
                formattedTranscript += "\n\(speakerName):\n"
                lastSpeaker = speakerName
            }
            
            // Add the segment text
            formattedTranscript += "\(segment.text) "
        }
        
        // Add metadata about voice analysis at the beginning
        let transcriptWithMetadata: String
        if voiceDetectedSpeakerCount > 0 {
            transcriptWithMetadata = """
            [Voice Analysis: \(voiceDetectedSpeakerCount) speaker(s) detected]
            \(formattedTranscript)
            """
        } else {
            transcriptWithMetadata = formattedTranscript
        }
        
        // print("📝 Combined transcript length: \(transcriptWithMetadata.count) characters, \(transcriptWithMetadata.split(separator: " ").count) words")
        
        // Check if we should open the transcript import UI for review
        if !transcriptWithMetadata.isEmpty {
            // Open the transcript import window with the recorded content
            await MainActor.run {
                // Store the transcript temporarily for the import window
                UserDefaults.standard.set(transcriptWithMetadata, forKey: "PendingRecordedTranscript")
                UserDefaults.standard.set(meeting.displayTitle, forKey: "PendingRecordedTitle")
                UserDefaults.standard.set(meeting.startTime, forKey: "PendingRecordedDate")
                UserDefaults.standard.set(meeting.duration, forKey: "PendingRecordedDuration")
                UserDefaults.standard.set(voiceDetectedSpeakerCount, forKey: "PendingRecordedSpeakerCount")

                // Store user notes taken during recording (Granola-style notes)
                let userNotesText = meeting.userNotesPlainText
                if !userNotesText.isEmpty {
                    UserDefaults.standard.set(userNotesText, forKey: "PendingRecordedUserNotes")
                    print("📝 Saving user notes: \(userNotesText.prefix(100))...")
                }

                // Store full identified participant data from the recording window
                // This preserves isCurrentUser, confidence, speakingTime, Person links, and voice embeddings
                if !meeting.identifiedParticipants.isEmpty {
                    // Get speaker embeddings from diarization manager for voice learning
                    var speakerEmbeddings: [Int: [Float]] = [:]
                    if let speakerDB = self.diarizationManager?.lastResult?.speakerDatabase {
                        for (stringKey, embedding) in speakerDB {
                            // Handle both "SPEAKER_1" and "1" formats
                            let cleanKey = stringKey.replacingOccurrences(of: "SPEAKER_", with: "")
                            if let intKey = Int(cleanKey) {
                                speakerEmbeddings[intKey] = embedding
                            }
                        }
                        print("📝 Including \(speakerEmbeddings.count) voice embeddings for voice learning")
                    }

                    // Serialize with embeddings
                    if let participantData = SerializableParticipant.serialize(meeting.identifiedParticipants, withEmbeddingsFrom: speakerEmbeddings) {
                        UserDefaults.standard.set(participantData, forKey: "PendingRecordedParticipants")
                        let participantSummary = meeting.identifiedParticipants.map { p in
                            let marker = p.isCurrentUser ? " (You)" : ""
                            let hasEmbedding = speakerEmbeddings[p.speakerID] != nil ? " 🎤" : ""
                            return "\(p.displayName)\(marker)\(hasEmbedding)"
                        }.joined(separator: ", ")
                        print("📝 Saving participant data: \(participantSummary)")
                    }

                    // Also keep names for backward compatibility
                    let participantNames = meeting.identifiedParticipants.compactMap { $0.name }
                    if !participantNames.isEmpty {
                        UserDefaults.standard.set(participantNames, forKey: "PendingRecordedParticipantNames")
                    }
                }

                // If we have multiple speakers detected, prompt for voice confirmation
                // This improves voice recognition for future meetings
                if voiceDetectedSpeakerCount >= 2 {
                    #if canImport(FluidAudio)
                    // Post notification to show participant confirmation UI
                    NotificationCenter.default.post(
                        name: .showParticipantConfirmation,
                        object: nil,
                        userInfo: [
                            "meeting": meeting,
                            "audioPath": meeting.audioFilePath as Any
                        ]
                    )
                    print("🎯 Posted notification to show participant confirmation for \(voiceDetectedSpeakerCount) speakers")
                    #endif
                }

                // Open the transcript import window
                TranscriptImportWindowManager.shared.presentWindow()
                
                // Reset recording state
                self.currentMeeting = nil
                self.recordingState = self.isMonitoring ? .monitoring : .idle
                self.lastTranscriptionText = "" // Reset transcript tracking
                
                print("📝 Opening transcript import window for review")
            }
            
            // Store audio file path for potential future use
            if let audioPath = meeting.audioFilePath {
                storageManager.scheduleAutoDelete(for: meeting.id, afterDays: 30)
            }
        } else {
            // No transcript available, just reset
            await MainActor.run {
                self.currentMeeting = nil
                self.recordingState = self.isMonitoring ? .monitoring : .idle
            }
            print("⚠️ No transcript available to process")
        }
        
        print("✅ Meeting redirected to transcript import for review")
    }
    
    private func saveAsIndividualConversations(_ meeting: LiveMeeting) async {
        print("💾 Saving as individual conversations for \(meeting.identifiedParticipants.count) participants")
        
        // Get Core Data context
        let context = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Try to match participants with existing Person entities
            for participant in meeting.identifiedParticipants {
                // Try to find existing person by name
                guard let name = participant.name else {
                    continue
                }
                
                let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
                fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
                
                do {
                    let matches = try context.fetch(fetchRequest)
                    let person = matches.first ?? createNewPerson(name: name, context: context)
                    
                    // Create conversation for this person
                    let conversation = Conversation(context: context)
                    conversation.uuid = UUID()
                    conversation.date = meeting.startTime
                    conversation.duration = Int32(meeting.duration)
                    conversation.person = person
                    
                    // Set title and notes
                    conversation.summary = meeting.displayTitle
                    conversation.notes = meeting.transcript.map { segment in
                        if let speaker = segment.speakerName {
                            return "\(speaker): \(segment.text)"
                        } else {
                            return segment.text
                        }
                    }.joined(separator: "\n")
                    
                    // Store audio file path in notes if available
                    if let audioPath = meeting.audioFilePath {
                        conversation.notes = (conversation.notes ?? "") + "\n\n[Audio Recording: \(audioPath)]"
                    }
                    
                    print("✅ Created conversation for \(person.name ?? "Unknown")")
                } catch {
                    print("❌ Failed to fetch/create person: \(error)")
                }
            }
            
            // Save all changes
            do {
                try context.save()
                print("✅ Individual conversations saved to Core Data")
            } catch {
                print("❌ Failed to save conversations: \(error)")
            }
        }
    }
    
    private func createNewPerson(name: String, context: NSManagedObjectContext) -> Person {
        let person = Person(context: context)
        person.identifier = UUID()
        person.name = name
        person.createdAt = Date()
        return person
    }
    
    private func saveProcessedMeeting(_ meeting: LiveMeeting, processed: ProcessedTranscript) async {
        print("🤖 Saving AI-processed meeting with summary")
        
        let context = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Match participants from AI analysis with Person entities
            for participantInfo in processed.participants {
                let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
                fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", participantInfo.name)
                
                do {
                    let matches = try context.fetch(fetchRequest)
                    let person = matches.first ?? createNewPerson(name: participantInfo.name, context: context)
                    
                    // Create conversation with AI-generated content
                    let conversation = Conversation(context: context)
                    conversation.uuid = UUID()
                    conversation.date = meeting.startTime
                    conversation.duration = Int32(meeting.duration)
                    conversation.person = person
                    
                    // Use AI-generated title and summary
                    conversation.summary = processed.suggestedTitle
                    conversation.notes = processed.summary
                    
                    // Store action items in notes
                    if !processed.actionItems.isEmpty {
                        let actionItemsText = "\n\n**Action Items:**\n" + processed.actionItems.map { "• \($0)" }.joined(separator: "\n")
                        conversation.notes = (conversation.notes ?? "") + actionItemsText
                    }
                    
                    // Store sentiment data (if these properties exist)
                    // conversation.sentimentScore = processed.sentimentAnalysis.sentimentScore
                    // conversation.engagementLevel = processed.sentimentAnalysis.engagementLevel
                    
                    // Store audio file path in notes
                    if let audioPath = meeting.audioFilePath {
                        conversation.notes = (conversation.notes ?? "") + "\n\n[Audio Recording: \(audioPath)]"
                    }
                    
                    print("✅ Created AI-processed conversation for \(person.name ?? "Unknown")")
                } catch {
                    print("❌ Failed to process participant \(participantInfo.name): \(error)")
                }
            }
            
            // Save all changes
            do {
                try context.save()
                print("✅ AI-processed meeting saved successfully")
            } catch {
                print("❌ Failed to save processed meeting: \(error)")
            }
        }
    }
    
    private func saveAsGroupMeeting(_ meeting: LiveMeeting) async {
        print("💾 Saving as group meeting with \(meeting.identifiedParticipants.count) participants")
        
        // Get Core Data context
        let context = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Create or find Group
            let group = Group(context: context)
            group.identifier = UUID()
            group.name = meeting.calendarTitle ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
            group.createdAt = Date()
            
            // Create GroupMeeting
            let groupMeeting = GroupMeeting(context: context)
            groupMeeting.identifier = meeting.id
            groupMeeting.date = meeting.startTime
            groupMeeting.duration = Int32(meeting.duration)
            groupMeeting.title = meeting.displayTitle
            groupMeeting.audioFilePath = meeting.audioFilePath
            
            // Set transcript
            if !meeting.transcript.isEmpty {
                let transcriptText = meeting.transcript.map { segment in
                    if let speaker = segment.speakerName {
                        return "\(speaker): \(segment.text)"
                    } else {
                        return segment.text
                    }
                }.joined(separator: "\n")
                groupMeeting.transcript = transcriptText
                groupMeeting.setTranscriptSegments(meeting.transcript)
            }
            
            // Associate with group
            groupMeeting.group = group
            
            // Save
            do {
                try context.save()
                print("✅ Group meeting saved to Core Data")
            } catch {
                print("❌ Failed to save group meeting: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods - UI
    
    private func showRecordingPrompt() {
        // Show user notification about detected conversation
        DispatchQueue.main.async {
            // Start pre-warming the engine while user decides
            self.prewarmRecording()
            
            let alert = NSAlert()
            alert.messageText = "Meeting Detected"
            alert.informativeText = "Would you like to start recording?"
            alert.addButton(withTitle: "Record")
            alert.addButton(withTitle: "Dismiss")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                self.manualStartRecording()
            } else {
                // User dismissed - cancel pre-warming
                self.cancelPrewarming()
            }
        }
    }
    
    private func prewarmRecording() {
        guard !isRecording && !isPrewarming else { return }
        
        print("🔥 Pre-warming speech engine...")
        isPrewarming = true
        lastTranscriptionText = ""
        
        if #available(macOS 26.0, *) {
            Task { @MainActor in
                if let framework = modernSpeechFramework as? ModernSpeechFramework {
                    framework.reset()
                    do {
                        try await framework.startTranscription()
                        print("🔥 Pre-warming started successfully")
                    } catch {
                        print("❌ Pre-warming failed: \(error)")
                        self.isPrewarming = false
                    }
                }
            }
        }
    }
    
    private func cancelPrewarming() {
        guard isPrewarming else { return }
        
        print("❄️ Canceling pre-warming...")
        isPrewarming = false
        
        if #available(macOS 26.0, *) {
            Task { @MainActor in
                if let framework = modernSpeechFramework as? ModernSpeechFramework {
                    try? await framework.stopTranscription()
                    framework.reset()
                }
            }
        }
    }
    
    // MARK: - Private Methods - Voice Print Management
    
    /// Save speaker embeddings from diarization to Person records
    private func saveSpeakerEmbeddings(_ speakerDatabase: [String: [Float]], for meeting: LiveMeeting) {
        print("🎤 Processing \(speakerDatabase.count) speaker embeddings")
        
        let voicePrintManager = VoicePrintManager()
        
        // Process each speaker's embedding
        for (speakerId, embedding) in speakerDatabase {
            print("🔊 Processing embedding for speaker: \(speakerId)")
            
            // Try to match with identified participants
            if let participant = meeting.identifiedParticipants.first(where: { 
                "\($0.speakerID)" == speakerId || $0.name == speakerId 
            }) {
                // We have a name for this speaker
                if let name = participant.name, !name.isEmpty {
                    print("✅ Found identified participant: \(name)")
                    
                    // Find or create Person record
                    let context = PersistenceController.shared.container.viewContext
                    let request: NSFetchRequest<Person> = Person.fetchRequest()
                    request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
                    
                    if let people = try? context.fetch(request), let person = people.first {
                        // Save embedding to existing person
                        voicePrintManager.saveEmbedding(embedding, for: person)
                        print("💾 Saved voice print for existing person: \(person.wrappedName)")
                    } else {
                        // Create new person and save embedding
                        let newPerson = Person(context: context)
                        newPerson.name = name
                        // Person entity doesn't have uuid, it has identifier
                        voicePrintManager.saveEmbedding(embedding, for: newPerson)
                        
                        do {
                            try context.save()
                            print("💾 Created new person and saved voice print: \(name)")
                        } catch {
                            print("❌ Error creating person: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    /// Identify speakers in real-time during recording using voice imprints
    /// Uses progressive confidence thresholds:
    /// - 70%+ → Tentative match (shown to user but not auto-assigned)
    /// - 80%+ → Auto-assign with good confidence
    /// Prioritizes pre-loaded embeddings from calendar attendees for faster matching
    private func identifySpeakersInRealTime(_ speakerDatabase: [String: [Float]]) async {
        // Confidence thresholds for progressive matching
        let autoAssignThreshold: Float = 0.80  // Auto-assign at 80%+
        let tentativeThreshold: Float = 0.70   // Show as suggestion at 70%+

        // Log preloaded embeddings status
        if !preloadedVoiceEmbeddings.isEmpty {
            print("🎯 [VoiceMatch] Using \(preloadedVoiceEmbeddings.count) pre-loaded embeddings from calendar")
        }

        for (speakerId, embedding) in speakerDatabase {
            // Check if we already identified this speaker with high confidence
            if let existingParticipant = await MainActor.run(body: {
                currentMeeting?.identifiedParticipants.first(where: {
                    "\($0.speakerID)" == speakerId && $0.confidence >= autoAssignThreshold && $0.namingMode == .linkedToPerson
                })
            }), existingParticipant != nil {
                continue // Already confidently identified via voice imprint
            }

            // Log embedding info for debugging
            print("🔍 [VoiceMatch] Checking speaker \(speakerId) with \(embedding.count)-dim embedding")

            // PRIORITY 1: Check against pre-loaded embeddings from calendar attendees (faster)
            var matchedFromPreload = false
            if !preloadedVoiceEmbeddings.isEmpty {
                var bestPreloadMatch: (personId: UUID, confidence: Float)? = nil

                for (personId, preloadedEmbedding) in preloadedVoiceEmbeddings {
                    let similarity = cosineSimilarity(embedding, preloadedEmbedding)
                    if similarity >= tentativeThreshold {
                        if bestPreloadMatch == nil || similarity > bestPreloadMatch!.confidence {
                            bestPreloadMatch = (personId, similarity)
                        }
                    }
                }

                if let match = bestPreloadMatch {
                    // Found a match in preloaded embeddings - fetch the person
                    let context = PersistenceController.shared.container.viewContext
                    let request: NSFetchRequest<Person> = Person.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", match.personId as CVarArg)
                    request.fetchLimit = 1

                    if let person = try? context.fetch(request).first {
                        matchedFromPreload = true
                        let confidence = match.confidence
                        let personName = person.name
                        let personSampleCount = person.voiceSampleCount

                        if confidence >= autoAssignThreshold {
                            await MainActor.run {
                                if let participant = currentMeeting?.identifiedParticipants.first(where: { "\($0.speakerID)" == speakerId }) {
                                    participant.name = personName
                                    participant.confidence = confidence
                                    participant.personRecord = person
                                    participant.person = person
                                    participant.namingMode = .linkedToPerson
                                }
                                if let name = personName, let meeting = currentMeeting {
                                    updateTranscriptSpeakerNames(meeting: meeting, speakerId: speakerId, name: name)
                                }
                                print("🎯 CALENDAR MATCH: Speaker \(speakerId) → \(personName ?? "Unknown") (confidence: \(String(format: "%.0f%%", confidence * 100)), pre-loaded)")
                            }
                        } else if confidence >= tentativeThreshold {
                            await MainActor.run {
                                if let participant = currentMeeting?.identifiedParticipants.first(where: { "\($0.speakerID)" == speakerId }) {
                                    if participant.namingMode != .namedByUser && participant.namingMode != .linkedToPerson {
                                        participant.name = personName
                                        participant.confidence = confidence
                                        participant.namingMode = .suggestedByVoice
                                    }
                                }
                                print("🤔 CALENDAR SUGGESTION: Speaker \(speakerId) might be \(personName ?? "Unknown") (confidence: \(String(format: "%.0f%%", confidence * 100)))")
                            }
                        }
                    }
                }
            }

            // PRIORITY 2: Fall back to full database search if not matched from preload
            if !matchedFromPreload, let (person, confidence) = voicePrintManager.findMatchingPerson(for: embedding) {
                // Extract Sendable data to pass to MainActor
                let personID = person?.objectID
                let personName = person?.name
                let personSampleCount = person?.voiceSampleCount ?? 0

                if confidence >= autoAssignThreshold {
                    // High confidence - auto-assign
                    await MainActor.run {
                        // Re-fetch person on main context if we have an ID
                        var mainPerson: Person? = nil
                        if let objectID = personID {
                            let context = PersistenceController.shared.container.viewContext
                            mainPerson = try? context.existingObject(with: objectID) as? Person
                        }

                        // Update or create participant
                        if let participant = currentMeeting?.identifiedParticipants.first(where: { "\($0.speakerID)" == speakerId }) {
                            participant.name = personName
                            participant.confidence = confidence
                            participant.personRecord = mainPerson
                            participant.person = mainPerson
                            participant.namingMode = .linkedToPerson  // Mark as auto-identified via voice
                        } else {
                            let participant = IdentifiedParticipant()
                            participant.speakerID = Int(speakerId) ?? 0
                            participant.name = personName
                            participant.confidence = confidence
                            participant.personRecord = mainPerson
                            participant.person = mainPerson
                            participant.namingMode = .linkedToPerson  // Mark as auto-identified via voice
                            currentMeeting?.identifyParticipant(participant)
                        }

                        // Update transcript segment speaker names for this speaker
                        if let name = personName, let meeting = currentMeeting {
                            updateTranscriptSpeakerNames(meeting: meeting, speakerId: speakerId, name: name)
                        }

                        print("🎯 AUTO-IDENTIFIED: Speaker \(speakerId) → \(personName ?? "Unknown") (confidence: \(String(format: "%.0f%%", confidence * 100)), samples: \(personSampleCount))")
                    }
                } else if confidence >= tentativeThreshold {
                    // Tentative match - set as suggestion but don't fully commit
                    await MainActor.run {
                        if let participant = currentMeeting?.identifiedParticipants.first(where: { "\($0.speakerID)" == speakerId }) {
                            // Only update if not already named by user
                            if participant.namingMode != .namedByUser && participant.namingMode != .linkedToPerson {
                                participant.name = personName
                                participant.confidence = confidence
                                participant.namingMode = .suggestedByVoice  // New mode for tentative matches
                            }
                        }
                        print("🤔 TENTATIVE MATCH: Speaker \(speakerId) might be \(personName ?? "Unknown") (confidence: \(String(format: "%.0f%%", confidence * 100)))")
                    }
                } else {
                    print("❌ LOW CONFIDENCE: Speaker \(speakerId) closest match \(personName ?? "Unknown") at \(String(format: "%.0f%%", confidence * 100))")
                }
            } else {
                print("❓ NO MATCH: Speaker \(speakerId) - no known voices in database or embedding dimension mismatch")
            }
        }
    }

    /// Update speaker names in transcript segments when a speaker is identified
    private func updateTranscriptSpeakerNames(meeting: LiveMeeting, speakerId: String, name: String) {
        // TranscriptSegment.speakerName is mutable, so we can update it
        for i in 0..<meeting.transcript.count {
            if meeting.transcript[i].speakerID == speakerId ||
               meeting.transcript[i].speakerID == "speaker_\(speakerId)" {
                meeting.transcript[i].speakerName = name
            }
        }
    }
    
    /// Identify speakers using voice prints at recording start
    private func identifySpeakersFromVoicePrints() async {
        guard let diarizationManager = diarizationManager else { return }
        
        let lastResult = await MainActor.run { diarizationManager.lastResult }
        guard let lastResult = lastResult,
              let speakerDatabase = lastResult.speakerDatabase else {
            return
        }
        
        print("🔍 Attempting to identify \(speakerDatabase.count) speakers from voice prints")
        
        let voicePrintManager = VoicePrintManager()
        
        for (speakerId, embedding) in speakerDatabase {
            if let (person, confidence) = voicePrintManager.findMatchingPerson(for: embedding) {
                // Extract Sendable data
                let personID = person?.objectID
                let personName = person?.name
                
                print("🎯 Identified speaker \(speakerId) as \(personName ?? "Unknown") with confidence \(confidence)")
                
                // Update current meeting with identified participant
                await MainActor.run {
                    // Re-fetch person on main context
                    var mainPerson: Person? = nil
                    if let objectID = personID {
                        let context = PersistenceController.shared.container.viewContext
                        mainPerson = try? context.existingObject(with: objectID) as? Person
                    }
                    
                    let participant = IdentifiedParticipant()
                    participant.speakerID = Int(speakerId) ?? 0
                    participant.name = personName
                    participant.confidence = confidence
                    participant.personRecord = mainPerson
                    participant.person = mainPerson  // Also set the alias
                    currentMeeting?.identifyParticipant(participant)
                }
            }
        }
    }
    
    // MARK: - Private Methods - Helpers
    
    private func getUpcomingCalendarEvent() -> CalendarEvent? {
        // Check CalendarService for upcoming meeting
        let upcomingMeetings = CalendarService.shared.upcomingMeetings

        // Find meeting starting within 5 minutes
        let now = Date()
        return upcomingMeetings.first { meeting in
            let timeDiff = meeting.startDate.timeIntervalSince(now)
            return timeDiff >= -300 && timeDiff <= 300 // Within 5 minutes
        }.map { meeting in
            CalendarEvent(
                title: meeting.title,
                startDate: meeting.startDate,
                duration: 3600, // Default 1 hour
                attendees: meeting.attendees
            )
        }
    }

    /// Calculate RMS level of audio buffer for leakage detection
    private func calculateRMSLevel(_ buffer: AVAudioPCMBuffer?) -> Float {
        guard let buffer = buffer,
              let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        let samples = channelData[0]

        for i in 0..<frameLength {
            let sample = samples[i]
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameLength))
    }

    // MARK: - Timeline Merge (Two-Stream Diarization)

    #if canImport(FluidAudio)
    /// Merge ME segments (from leakage detection) with diarization segments (from system audio)
    /// ME segments take priority - if mic was active and not leakage, that's the user speaking
    /// - Parameters:
    ///   - diarizationSegments: Segments from system-only diarization
    /// - Returns: Merged segments with ME properly attributed
    private func mergeTimelinesWithME(_ diarizationSegments: [TimedSpeakerSegment]) -> [TimedSpeakerSegment] {
        var mergedSegments: [TimedSpeakerSegment] = []
        let sortedMESegments = meSegments.sorted { $0.startTime < $1.startTime }

        print("🔀 Merging \(diarizationSegments.count) diarization segments with \(sortedMESegments.count) ME segments")

        for segment in diarizationSegments {
            let segmentStart = segment.startTimeSeconds
            let segmentEnd = segment.endTimeSeconds

            // Check if this segment overlaps with any ME segment
            let overlappingME = sortedMESegments.first { meSegment in
                meSegment.overlaps(with: segmentStart, end: segmentEnd)
            }

            if let meOverlap = overlappingME {
                // Calculate overlap ratio
                let overlapStart = max(Float(meOverlap.startTime), segmentStart)
                let overlapEnd = min(Float(meOverlap.endTime), segmentEnd)
                let overlapDuration = overlapEnd - overlapStart
                let segmentDuration = segmentEnd - segmentStart

                let overlapRatio = segmentDuration > 0 ? overlapDuration / segmentDuration : Float(0)

                if overlapRatio > 0.5 {
                    // More than 50% overlap with ME - create new segment assigned to ME
                    let meAssignedSegment = TimedSpeakerSegment(
                        speakerId: "ME",
                        embedding: segment.embedding,
                        startTimeSeconds: segmentStart,
                        endTimeSeconds: segmentEnd,
                        qualityScore: segment.qualityScore
                    )
                    mergedSegments.append(meAssignedSegment)
                    print("🎙️ Segment \(String(format: "%.2f", segmentStart))-\(String(format: "%.2f", segmentEnd))s: ME (\(Int(overlapRatio * 100))% overlap)")
                } else {
                    // Less than 50% overlap - keep original speaker but note the partial overlap
                    mergedSegments.append(segment)
                    print("👤 Segment \(String(format: "%.2f", segmentStart))-\(String(format: "%.2f", segmentEnd))s: \(segment.speakerId) (partial ME overlap: \(Int(overlapRatio * 100))%)")
                }
            } else {
                // No ME overlap - this is a remote speaker
                mergedSegments.append(segment)
            }
        }

        // Add any ME segments that don't overlap with diarization (mic-only speech)
        for meSegment in sortedMESegments {
            let hasOverlap = diarizationSegments.contains { segment in
                meSegment.overlaps(with: segment.startTimeSeconds, end: segment.endTimeSeconds)
            }

            if !hasOverlap && meSegment.duration >= meSegmentMinDuration {
                // ME was speaking but diarization didn't detect anything (no system audio)
                // This is pure local speech
                let meSpeakerSegment = TimedSpeakerSegment(
                    speakerId: "ME",
                    embedding: [],
                    startTimeSeconds: Float(meSegment.startTime),
                    endTimeSeconds: Float(meSegment.endTime),
                    qualityScore: meSegment.confidence
                )
                mergedSegments.append(meSpeakerSegment)
                print("🎙️ Added pure ME segment: \(String(format: "%.2f", meSegment.startTime))-\(String(format: "%.2f", meSegment.endTime))s")
            }
        }

        // Sort by start time
        mergedSegments.sort { $0.startTimeSeconds < $1.startTimeSeconds }

        let meCount = mergedSegments.filter { $0.speakerId == "ME" }.count
        let remoteCount = mergedSegments.count - meCount
        print("📊 Timeline merge complete: \(meCount) ME segments, \(remoteCount) remote speaker segments")

        return mergedSegments
    }
    #endif

    /// Clear ME segments for next recording
    @MainActor
    private func resetMEDetection() {
        meSegments.removeAll()
        currentMESegmentStart = nil
        leakageDetector?.reset()
        print("🔄 ME detection reset for next recording")
    }

    // MARK: - Overlapping Meeting Detection

    /// Detects all calendar events that overlap with the current time window
    /// Populates overlappingMeetings array for user selection
    private func detectOverlappingMeetings() {
        let upcomingMeetings = CalendarService.shared.upcomingMeetings
        let now = Date()

        // Find all meetings that are currently active or starting within 5 minutes
        // A meeting is "active" if: now is between start and end (start + duration)
        overlappingMeetings = upcomingMeetings.filter { meeting in
            let startDiff = meeting.startDate.timeIntervalSince(now)
            let duration = meeting.duration ?? 3600  // Default 1 hour if not specified
            let endTime = meeting.startDate.addingTimeInterval(duration)
            let endDiff = endTime.timeIntervalSince(now)

            // Meeting is relevant if:
            // 1. Starting within next 5 minutes (startDiff <= 300 && startDiff >= -60)
            // 2. Currently in progress (startDiff < 0 && endDiff > 0)
            let isStartingSoon = startDiff >= -60 && startDiff <= 300
            let isInProgress = startDiff < 0 && endDiff > 0

            return isStartingSoon || isInProgress
        }

        print("📅 Detected \(overlappingMeetings.count) overlapping meeting(s)")
        for meeting in overlappingMeetings {
            print("   - \(meeting.title) at \(meeting.startDate)")
        }
    }

    /// Apply calendar context from an UpcomingMeeting to a LiveMeeting
    private func applyCalendarContext(from calendarMeeting: UpcomingMeeting, to liveMeeting: LiveMeeting?) {
        guard let liveMeeting = liveMeeting else { return }

        liveMeeting.calendarTitle = calendarMeeting.title
        liveMeeting.calendarEventTitle = calendarMeeting.title
        liveMeeting.scheduledDuration = calendarMeeting.duration ?? 3600
        liveMeeting.expectedParticipants = calendarMeeting.attendees ?? []

        print("✅ Applied calendar context: '\(calendarMeeting.title)' with \(liveMeeting.expectedParticipants.count) expected participants")
    }

    /// User selects which meeting they're attending (for overlapping meetings)
    func selectMeeting(id: String) {
        guard let meeting = overlappingMeetings.first(where: { $0.id == id }) else {
            print("⚠️ Meeting with ID \(id) not found in overlapping meetings")
            return
        }

        selectedMeetingID = id
        applyCalendarContext(from: meeting, to: currentMeeting)

        // Trigger speaker correlation with new expected participants
        Task { @MainActor in
            await self.correlateDetectedSpeakers()
        }
    }

    /// Clear meeting selection (reverts to generic title)
    func clearMeetingSelection() {
        selectedMeetingID = nil
        if let meeting = currentMeeting {
            meeting.calendarTitle = nil
            meeting.calendarEventTitle = nil
            meeting.expectedParticipants = []
        }
    }
    
    private func startRecordingTimer() {
        DispatchQueue.main.async {
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }

                self.recordingDuration = Date().timeIntervalSince(startTime)
                self.currentMeeting?.duration = self.recordingDuration

                // Auto-correlate speakers every 30 seconds to identify participants in real-time
                let now = Date()
                let shouldCorrelate = self.lastCorrelationTime == nil ||
                    now.timeIntervalSince(self.lastCorrelationTime!) >= 30.0

                if shouldCorrelate {
                    self.lastCorrelationTime = now
                    Task { @MainActor in
                        await self.correlateDetectedSpeakers()

                        // Update meeting type based on speaker count
                        #if canImport(FluidAudio)
                        if let manager = self.diarizationManager,
                           let result = await manager.lastResult {
                            let speakerCount = result.speakerCount
                            self.currentMeeting?.updateMeetingType(speakerCount: speakerCount, confidence: 0.9)
                            print("🎯 Auto-correlated speakers: \(speakerCount) detected, type: \(self.currentMeeting?.meetingType.rawValue ?? "unknown")")
                        }
                        #endif
                    }
                }

                // Flush old transcript segments every 5 minutes to manage memory
                let duration = Int(self.recordingDuration)
                if duration > 0 && duration % 300 == 0 { // Every 5 minutes
                    self.currentMeeting?.flushOldSegments()
                }
            }
        }
    }
    
    @objc private func handleAppTermination() {
        if isRecording {
            stopRecording()
        }
        stopMonitoring()
    }

    // MARK: - Sentence Buffer Management

    /// Flush the sentence buffer and create a transcript segment
    /// Called when sentence is complete (punctuation) or after pause threshold
    @MainActor
    private func flushSentenceBuffer() {
        guard !sentenceBuffer.isEmpty else { return }

        // Clean up the buffer - ensure complete words only
        let cleanedText = sentenceBuffer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")  // Remove double spaces

        guard !cleanedText.isEmpty else {
            sentenceBuffer = ""
            isBufferingTranscript = false
            return
        }

        // Create the transcript segment
        let segment = TranscriptSegment(
            text: cleanedText,
            timestamp: Date().timeIntervalSince(self.recordingStartTime ?? Date()),
            speakerID: sentenceBufferSpeakerID,
            speakerName: nil,
            confidence: 0.95,
            isFinalized: true
        )

        currentMeeting?.addTranscriptSegment(segment)

        // Clear the buffer
        sentenceBuffer = ""
        isBufferingTranscript = false
    }

    /// Reset sentence buffer state (called when recording starts/stops)
    private func resetSentenceBuffer() {
        sentenceBuffer = ""
        sentenceBufferSpeakerID = "speaker_1"
        lastBufferUpdateTime = Date()
        isBufferingTranscript = false
    }

    // MARK: - Meeting Metrics Updates
    
    /// Update all meeting metrics
    private func updateMeetingMetrics() {
        guard let meeting = currentMeeting else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update word count
            let wordCount = meeting.transcript.reduce(0) { count, segment in
                count + segment.text.split(separator: " ").count
            }
            meeting.wordCount = wordCount
            
            // Update file size
            if let path = meeting.audioFilePath {
                let url = URL(fileURLWithPath: path)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64 {
                    meeting.currentFileSize = fileSize
                }
            }
            
            // Update average confidence
            if !meeting.transcript.isEmpty {
                let totalConfidence = meeting.transcript.reduce(Float(0)) { $0 + $1.confidence }
                meeting.averageConfidence = totalConfidence / Float(meeting.transcript.count)
            }
            
            // Update speaker turn count and calculate durations
            var lastSpeaker: String? = nil
            var turnCount = 0
            var speakerDurations: [Int: TimeInterval] = [:]
            var lastSpeakerID: Int? = nil
            
            for segment in meeting.transcript {
                if let speaker = segment.speakerName, speaker != lastSpeaker {
                    turnCount += 1
                    lastSpeaker = speaker
                }
                
                // Calculate duration for this segment (estimate: 0.4s per word)
                let words = segment.text.split(separator: " ").count
                let estimatedDuration = Double(words) * 0.4
                
                if let speakerIDString = segment.speakerID {
                    // Parse speaker ID to Int for matching with IdentifiedParticipant
                    let speakerID: Int
                    if let id = Int(speakerIDString) {
                        speakerID = id
                    } else if speakerIDString.hasPrefix("speaker_") {
                        speakerID = Int(speakerIDString.replacingOccurrences(of: "speaker_", with: "")) ?? 0
                    } else {
                        speakerID = 0
                    }
                    
                    speakerDurations[speakerID, default: 0] += estimatedDuration
                    lastSpeakerID = speakerID
                }
            }
            meeting.speakerTurnCount = turnCount
            
            // Update participants with calculated stats
            let currentMeetingDuration = Date().timeIntervalSince(meeting.startTime)
            
            for participant in meeting.identifiedParticipants {
                // Update total speaking time
                if let duration = speakerDurations[participant.speakerID] {
                    participant.totalSpeakingTime = duration
                }
                
                // Update currently speaking status
                // They are speaking if they were the speaker of the last segment
                // AND that segment happened recently (within last 5 seconds)
                var isSpeaking = false
                if let lastID = lastSpeakerID, lastID == participant.speakerID {
                    if let lastSegment = meeting.transcript.last {
                        // Check if segment is recent
                        // segment.timestamp is offset from start
                        let timeSinceSegment = currentMeetingDuration - lastSegment.timestamp
                        if timeSinceSegment < 5.0 {
                            isSpeaking = true
                            participant.lastSpokeAt = Date()
                        }
                    }
                }
                participant.isCurrentlySpeaking = isSpeaking
            }
            
            // Update system metrics
            self.updateSystemMetrics()
        }
    }
    
    /// Update system performance metrics
    private func updateSystemMetrics() {
        guard let meeting = currentMeeting else { return }

        // Get CPU usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         intPtr,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            // Calculate CPU usage percentage (simplified)
            let userTime = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
            let systemTime = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
            let totalTime = userTime + systemTime
            let uptime = ProcessInfo.processInfo.systemUptime
            meeting.cpuUsage = uptime > 0 ? min((totalTime / uptime) * 100, 100) : 0

            // Update memory usage
            meeting.memoryUsage = Int64(info.resident_size)
        }

        // Update buffer health based on dropped frames or processing delays
        if meeting.droppedFrames > 10 {
            meeting.bufferHealth = .critical
        } else if meeting.droppedFrames > 5 {
            meeting.bufferHealth = .warning
        } else {
            meeting.bufferHealth = .good
        }

        // Update quality monitor
        Task { @MainActor in
            let hasSystemAudio = self.audioCapture.captureMode == .full || self.audioCapture.captureMode == .systemAudioOnly
            let hasDiarization = self.diarizationManager != nil
            let audioLevel = (self.audioCapture.microphoneLevel + self.audioCapture.systemAudioLevel) / 2.0
            let cpuUsage = Float(meeting.cpuUsage / 100.0)

            self.qualityMonitor.updateQualityStatus(
                hasSystemAudio: hasSystemAudio,
                transcriptionLatency: 0.0, // Will be calculated based on buffer timing
                audioLevel: audioLevel,
                hasDiarization: hasDiarization,
                droppedFrames: meeting.droppedFrames,
                cpuUsage: cpuUsage,
                memoryUsage: meeting.memoryUsage
            )
        }
    }
}

// TranscriptionPipelineDelegate removed - transcription now handled directly in processAudioBuffers

// MARK: - Calendar Monitoring

extension MeetingRecordingEngine {
    private func startCalendarMonitoring() {
        print("📅 Starting calendar monitoring")
        
        // Request calendar access
        calendarService.requestAccess { [weak self] granted, error in
            if granted {
                self?.setupCalendarTimer()
            } else {
                print("⚠️ Calendar access not granted")
            }
        }
    }
    
    private func stopCalendarMonitoring() {
        calendarMonitorTimer?.invalidate()
        calendarMonitorTimer = nil
        print("📅 Stopped calendar monitoring")
    }
    
    private func setupCalendarTimer() {
        // Check calendar every 30 seconds as backup (primary detection via EventKit notifications)
        // Polling reduced from 5s to 30s since EventKit notifications provide instant updates
        calendarMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkForUpcomingMeetings(source: "polling")
        }
        
        // Check immediately
        checkForUpcomingMeetings(source: "initial")

        // Set up EventKit notifications for instant updates (primary detection method)
        setupCalendarNotifications()
    }
    
    /// Set up EventKit notifications for instant calendar updates
    private func setupCalendarNotifications() {
        // Subscribe to calendar change notifications for instant updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: nil
        )
        
        print("📅 Calendar notifications: Subscribed to instant updates")
    }
    
    @objc private func calendarChanged() {
        print("📅 Calendar changed - checking for meetings immediately (EventKit notification)")
        checkForUpcomingMeetings(source: "notification")
    }

    // MARK: - Smart Calendar Preparation

    /// Start timer for pre-meeting preparation
    private func startPreparationTimer() {
        // Check every 60 seconds for upcoming meetings (5 min window)
        preparationTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.prepareForUpcomingMeeting()
        }

        // Check immediately
        prepareForUpcomingMeeting()
        print("📅 Smart calendar preparation: Started")
    }

    /// Pre-load voice embeddings for expected participants
    private func prepareForUpcomingMeeting() {
        guard let nextMeeting = calendarService.upcomingMeetings.first else { return }

        let now = Date()
        let timeUntilMeeting = nextMeeting.startDate.timeIntervalSince(now)

        // Pre-load 5 minutes before meeting
        guard timeUntilMeeting > 0 && timeUntilMeeting <= 300 else { return }

        // Only prepare once per meeting
        let meetingID = nextMeeting.title + nextMeeting.startDate.description
        guard !expectedParticipants.contains(meetingID) else { return }
        expectedParticipants.append(meetingID)

        print("📅 Preparing for meeting: \(nextMeeting.title) in \(Int(timeUntilMeeting/60)) minutes")

        // Pre-load voice embeddings for attendees
        guard let attendees = nextMeeting.attendees, !attendees.isEmpty else {
            print("  ℹ️  No attendees listed for this meeting")
            return
        }

        Task {
            for attendee in attendees {
                await preloadVoiceEmbedding(for: attendee)
            }

            print("✅ Pre-loaded voice embeddings for \(attendees.count) attendees")
        }
    }

    /// Pre-load voice embedding for a participant
    private func preloadVoiceEmbedding(for name: String) async {
        // Try to find person in database
        guard let person = findPerson(byName: name) else {
            print("  ⚠️ No person record found for: \(name)")
            return
        }

        // Get their voice embedding if available
        if let embedding = voicePrintManager.getStoredEmbedding(for: person) {
            preloadedVoiceEmbeddings[person.id] = embedding
            print("  ✅ Pre-loaded voice for: \(name)")
        } else {
            print("  ℹ️  No voice data yet for: \(name)")
        }
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Find person by name in Core Data
    private func findPerson(byName name: String) -> Person? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()

        // Search by name (case-insensitive, partial match)
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("⚠️ Error fetching person by name '\(name)': \(error)")
            return nil
        }
    }

    private func checkForUpcomingMeetings(source: String = "unknown") {
        print("📅 Checking meetings (source: \(source))")
        // Fetch meetings for next 24 hours
        calendarService.fetchUpcomingMeetings(daysAhead: 1)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            
            // Check all upcoming meetings
            for meeting in self.calendarService.upcomingMeetings {
                let timeUntilMeeting = meeting.startDate.timeIntervalSince(now)
                let timeSinceMeetingStart = now.timeIntervalSince(meeting.startDate)
                
                // Meeting window: 5 minutes before to 15 minutes after start time
                let isInMeetingWindow = timeUntilMeeting <= 300 && timeSinceMeetingStart <= 900
                
                if isInMeetingWindow {
                    // Set as current event if not already set
                    if self.currentCalendarEvent?.id != meeting.id {
                        print("🔔 Meeting '\(meeting.title)' detected in active window")
                        self.currentCalendarEvent = meeting
                        
                        // Prepare for the meeting
                        Task {
                            let calendarEvent = CalendarEvent(
                                title: meeting.title,
                                startDate: meeting.startDate,
                                duration: meeting.duration ?? 3600, // Use actual duration or default 1 hour
                                attendees: meeting.attendees
                            )
                            await self.prepareForUpcomingMeeting(calendarEvent)
                        }
                    }
                    
                    // Start recording if conditions are met
                    if self.autoRecordPref && !self.isRecording {
                        // Use multi-signal detection
                        let shouldStart = self.shouldStartSmartRecording(for: meeting)
                        if shouldStart {
                            print("🎬 Auto-starting recording for: \(meeting.title)")
                            // Must run on main thread since startRecording updates @Published properties
                            DispatchQueue.main.async {
                                self.startRecording(isManual: false)
                            }
                        }
                    }
                } else if timeUntilMeeting > 300 && timeUntilMeeting <= 600 {
                    // Meeting coming up in 5-10 minutes - prepare but don't start yet
                    print("⏰ Meeting '\(meeting.title)' starting in \(Int(timeUntilMeeting/60)) minutes")
                    
                    // Pre-load participant data
                    Task {
                        let calendarEvent = CalendarEvent(
                            title: meeting.title,
                            startDate: meeting.startDate,
                            duration: meeting.duration ?? 3600,
                            attendees: meeting.attendees
                        )
                        await self.prepareForUpcomingMeeting(calendarEvent)
                    }
                }
                
                // Smart stop detection
                if let current = self.currentCalendarEvent,
                   current.id == meeting.id && self.isRecording {
                    
                    // Check multiple stop conditions
                    if self.shouldStopRecording(for: meeting) {
                        print("🔚 Meeting appears to have ended, stopping recording")
                        self.stopRecording()
                        self.currentCalendarEvent = nil
                    }
                }
            }
        }
    }
    
    /// Smart recording start detection using multiple signals
    /// MVP: When calendar event is active, ANY speech = immediate start
    private func shouldStartSmartRecording(for meeting: UpcomingMeeting) -> Bool {
        let now = Date()
        let timeSinceMeetingStart = now.timeIntervalSince(meeting.startDate)
        let isInMeetingWindow = timeSinceMeetingStart >= -300 && timeSinceMeetingStart <= 900  // 5 min before to 15 min after

        // SIMPLIFIED PATH: Calendar event active + any audio = GO
        // This is the MVP detection that should work reliably
        if isInMeetingWindow {
            let hasAnyAudio = twoWayDetector.hasRecentAudioActivity()
            if hasAnyAudio {
                print("🎬 CALENDAR MVP: Meeting '\(meeting.title)' in window + audio detected → AUTO-START")
                return true
            }
        }

        // FALLBACK: Complex multi-signal detection for non-calendar scenarios
        var confidence: Float = 0.0
        var breakdown: [String: Float] = [:]

        // Calendar signal (30% weight) - meeting is in active window
        if isInMeetingWindow && timeSinceMeetingStart >= 0 {
            confidence += 0.3
            breakdown["calendar"] = 0.3
            print("📅 Calendar signal: Meeting in progress (+30%)")
        } else {
            breakdown["calendar"] = 0.0
        }

        // Audio signal (40% weight) - two-way conversation detected
        if twoWayDetector.conversationDetected {
            confidence += 0.4
            breakdown["conversation"] = 0.4
            print("🎙️ Audio signal: Conversation detected (+40%)")
        } else if twoWayDetector.microphoneActivity || twoWayDetector.systemAudioActivity {
            confidence += 0.2  // Partial credit for single-sided audio
            breakdown["partial_audio"] = 0.2
            print("🔊 Audio signal: Partial activity detected (+20%)")
        } else {
            breakdown["audio"] = 0.0
        }

        // App signal (30% weight) - meeting app is active
        if isMeetingAppActive() {
            confidence += 0.3
            breakdown["app_active"] = 0.3
            print("💻 App signal: Meeting app active (+30%)")
        } else {
            breakdown["app_active"] = 0.0
        }

        // Diagnostic breakdown
        print("🎯 Recording Confidence Breakdown:")
        for (factor, value) in breakdown.sorted(by: { $0.key < $1.key }) {
            print("  - \(factor): \(Int(value * 100))%")
        }
        print("  → Total: \(Int(confidence * 100))% (threshold: 60%)")

        // Start recording if confidence is above 60%
        return confidence >= 0.6
    }
    
    /// Smart stop detection using multiple signals
    private func shouldStopRecording(for meeting: UpcomingMeeting) -> Bool {
        let now = Date()
        
        // Check if meeting scheduled time has ended (with 10 minute buffer)
        let meetingDuration = meeting.duration ?? 3600 // Default 1 hour
        let meetingEndTime = meeting.startDate.addingTimeInterval(meetingDuration + 600) // +10 min buffer
        let isPastEndTime = now > meetingEndTime
        
        // Check for extended silence (2 minutes)
        let silenceDuration = now.timeIntervalSince(twoWayDetector.lastActivityTime)
        let hasExtendedSilence = silenceDuration > 120
        
        // Check if meeting app is still active
        let meetingAppActive = isMeetingAppActive()
        
        // Stop if: past end time AND (silence OR no app)
        if isPastEndTime && (hasExtendedSilence || !meetingAppActive) {
            return true
        }
        
        // Also stop if extreme silence (5 minutes) regardless of schedule
        if silenceDuration > 300 {
            print("⚠️ No activity for 5 minutes - assuming meeting ended")
            return true
        }
        
        return false
    }
    
    private func shouldStartRecording(for meeting: UpcomingMeeting) -> Bool {
        // Check if conversation is detected
        if twoWayDetector.conversationDetected {
            return true
        }
        
        // Check if meeting app is active
        if isMeetingAppActive() {
            return true
        }
        
        // Check if it's time for the meeting
        let timeUntilMeeting = meeting.startDate.timeIntervalSince(Date())
        return timeUntilMeeting <= 30 && timeUntilMeeting >= -60 // Within 30 seconds before or 60 seconds after
    }
    
    private func isMeetingAppActive() -> Bool {
        // Check for common meeting apps
        let runningApps = NSWorkspace.shared.runningApplications
        let meetingAppBundleIds = [
            // Primary video conferencing apps
            "us.zoom.xos",                // Zoom
            "com.microsoft.teams",         // Microsoft Teams  
            "com.microsoft.teams2",        // New Teams
            "com.cisco.webex",            // Webex
            "com.webex.meetingmanager",   // Webex Meetings
            "com.gotomeeting.gotomeeting", // GoToMeeting
            "com.logmein.gotomeeting",    // GoToMeeting alternate
            "com.bluejeans.BlueJeans",    // BlueJeans
            "com.8x8.vipmeetings",        // 8x8 Meet
            "com.amazon.Amazon-Chime",    // Amazon Chime
            
            // Communication apps with meeting features
            "com.tinyspeck.slackmacgap",  // Slack
            "com.discord.Discord",         // Discord
            "com.microsoft.skype",         // Skype
            "com.skype.skype",            // Skype alternate
            
            // Apple apps
            "com.apple.FaceTime",         // FaceTime
            "com.apple.iWork.Keynote",    // Keynote (for presentations)
            
            // Messaging apps with calling
            "WhatsApp",                   // WhatsApp Desktop
            "com.facebook.archon",        // Messenger
            "ru.keepcoder.Telegram",     // Telegram
            "org.whispersystems.signal-desktop", // Signal
            
            // Browsers (for web-based meetings)
            "com.google.Chrome",          // Chrome
            "com.google.Chrome.canary",   // Chrome Canary
            "com.apple.Safari",           // Safari
            "org.mozilla.firefox",        // Firefox
            "com.microsoft.edgemac",      // Edge
            "com.brave.Browser",          // Brave
            "com.operasoftware.Opera",    // Opera
            "com.vivaldi.Vivaldi",        // Vivaldi
            
            // Business communication
            "com.ringcentral.glip",       // RingCentral
            "com.citrix.workspace.DesktopApp", // Citrix Workspace
            "com.vmware.horizon",          // VMware Horizon
            
            // Other collaboration tools
            "com.figma.Desktop",          // Figma (design reviews)
            "com.miro.desktop",           // Miro (whiteboarding)
            "com.notion.app",             // Notion (collaborative docs)
        ]
        
        // Check active apps
        for app in runningApps {
            if let bundleId = app.bundleIdentifier {
                // Check if it's a known meeting app
                if meetingAppBundleIds.contains(bundleId) && app.isActive {
                    print("🖥️ Meeting app detected: \(app.localizedName ?? bundleId)")
                    return true
                }
                
                // Special check for browsers - look for meeting-related window titles
                if isBrowserInMeeting(app: app, bundleId: bundleId) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Check if a browser is showing a meeting page
    private func isBrowserInMeeting(app: NSRunningApplication, bundleId: String) -> Bool {
        let browserBundleIds = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi"
        ]
        
        guard browserBundleIds.contains(bundleId) && app.isActive else {
            return false
        }
        
        // Check if the browser has a window with meeting-related URL patterns
        // This would need accessibility permissions to read window titles
        // For now, just detecting an active browser is a signal
        
        // Common meeting URL patterns to check for (would need window title access):
        // - meet.google.com
        // - zoom.us/j/
        // - teams.microsoft.com
        // - whereby.com
        // - around.co
        
        print("🌐 Active browser detected: \(app.localizedName ?? bundleId) - possible web meeting")
        
        // Return true if browser is active and we're in monitoring mode
        // This combined with audio detection will trigger recording
        return true
    }
    
    // MARK: - Smart Calendar Integration (Phase 3) - Helper Methods
    
    /// Prepare for an upcoming calendar meeting
    @MainActor
    func prepareForUpcomingMeeting(_ event: CalendarEvent) async {
        print("🎯 Preparing for upcoming meeting: \(event.title)")
        
        // Extract participant names from attendees
        let participants = event.attendees ?? []
        
        // Pre-load voice embeddings for expected participants
        if !participants.isEmpty {
            print("👥 Pre-loading voice embeddings for \(participants.count) expected participants")
            
            // Get VoicePrintManager instance
            let voicePrintManager = VoicePrintManager()
            
            // Pre-load embeddings for each participant
            for participantName in participants {
                if let person = findPerson(named: participantName) {
                    // This loads the embedding into memory for faster matching
                    if let _ = voicePrintManager.getStoredEmbedding(for: person) {
                        print("✅ Pre-loaded voice embedding for \(participantName)")
                    }
                }
            }
        }
        
        // Update current meeting with expected participants if recording
        if let meeting = currentMeeting {
            meeting.expectedParticipants = participants
            meeting.calendarEventTitle = event.title
        }
        
        // Show notification to user
        showMeetingReadyNotification(event)
    }
    
    /// Find a Person entity by name
    func findPerson(named name: String) -> Person? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        request.fetchLimit = 1
        
        do {
            let people = try context.fetch(request)
            return people.first
        } catch {
            print("❌ Failed to find person \(name): \(error)")
            return nil
        }
    }
    
    /// Show notification that meeting is ready to record
    private func showMeetingReadyNotification(_ event: CalendarEvent) {
        #if os(macOS)
        let notification = NSUserNotification()
        notification.title = "Meeting Ready to Record"
        notification.informativeText = "Ready to record: \(event.title)"
        notification.soundName = nil // Deprecated API
        notification.deliveryDate = Date()
        
        NSUserNotificationCenter.default.deliver(notification)
        #endif
    }
    
    /// Correlate detected speakers with expected attendees during recording
    func correlateDetectedSpeakers() async {
        guard let meeting = currentMeeting else { return }

        let expectedAttendees = meeting.expectedParticipants

        #if canImport(FluidAudio)
        // Get current diarization results
        if let manager = diarizationManager {
            let diarizationResults = await manager.lastResult
            if let diarizationResults = diarizationResults {
            let detectedSpeakers = Set(diarizationResults.segments.map { $0.speakerId })

            print("📊 Correlating \(detectedSpeakers.count) detected speakers with \(expectedAttendees.count) expected attendees")

            // Use VoicePrintManager to match speakers
            let voicePrintManager = VoicePrintManager()

            // Build embeddings dictionary from diarization results
            var embeddings: [String: [Float]] = [:]
            for segment in diarizationResults.segments {
                if embeddings[segment.speakerId] == nil {
                    embeddings[segment.speakerId] = segment.embedding
                }
            }

            // Match to expected attendees
            let matches = voicePrintManager.matchToAttendees(embeddings, attendeeNames: expectedAttendees)

            // Map to Sendable structure for concurrency safety
            let sendableMatches = matches.mapValues { person in
                (objectID: person.objectID, name: person.name, confidence: person.voiceConfidence)
            }

            // Update meeting with identified participants
            await MainActor.run {
                for (speakerId, matchData) in sendableMatches {
                    // Re-fetch person on main context
                    let context = PersistenceController.shared.container.viewContext
                    let person = try? context.existingObject(with: matchData.objectID) as? Person

                    let participant = IdentifiedParticipant()
                    participant.name = matchData.name
                    participant.person = person
                    participant.speakerID = Int(speakerId) ?? 0
                    participant.confidence = matchData.confidence

                    meeting.addIdentifiedParticipant(participant)
                    print("✅ Identified speaker \(speakerId) as \(matchData.name ?? "Unknown")")
                }

                // Flag unexpected participants
                for speakerId in detectedSpeakers {
                    if sendableMatches[speakerId] == nil {
                        print("⚠️ Unexpected participant detected: Speaker \(speakerId)")
                        meeting.hasUnexpectedParticipants = true
                    }
                }
            }
            }
        }
        #endif
    }

    /// Handle ad-hoc meeting detected by microphone monitor
    private func handleAdHocMeetingDetected(_ appName: String) {
        print("📞 Ad-hoc meeting detected via microphone: \(appName)")
        // Unified recording status window automatically shows meeting status
    }

}

// MARK: - Supporting Types

struct CalendarEvent {
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendees: [String]?
}

/// Represents a detected ME (user) speaking segment
struct MESegment {
    let startTime: TimeInterval  // Relative to recording start
    let endTime: TimeInterval
    let confidence: Float

    var duration: TimeInterval { endTime - startTime }

    /// Check if this ME segment overlaps with a given time range
    func overlaps(with start: Float, end: Float) -> Bool {
        Float(startTime) < end && Float(endTime) > start
    }
}