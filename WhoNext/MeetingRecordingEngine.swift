import Foundation
import AVFoundation
import SwiftUI
import AppKit
import CoreData
import EventKit
import ScreenCaptureKit

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
    private let audioCapture = SystemAudioCapture()
    private let twoWayDetector = TwoWayAudioDetector()
    private let storageManager = AudioStorageManager()
    private var modernSpeechFramework: Any? // Will hold ModernSpeechFramework if available
    private var transcriptProcessor: TranscriptProcessor?
    private let calendarService = CalendarService.shared
    
    // MARK: - Diarization (Speaker Detection)
    #if canImport(FluidAudio)
    private var diarizationManager: DiarizationManager?
    #endif
    
    // MARK: - Recording Properties
    private var audioWriter: AVAudioFile?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let maxBufferCount = 100 // Keep last 100 buffers (~10 seconds at 100ms intervals)
    private var calendarMonitorTimer: Timer?
    private var currentCalendarEvent: UpcomingMeeting?
    private var lastTranscriptionText: String = "" // Track the last full transcript to detect new content
    
    // MARK: - User Preferences
    @AppStorage("autoRecordEnabled") private var autoRecordPref: Bool = true
    @AppStorage("recordingConfidenceThreshold") private var confidenceThreshold: Double = 0.7
    @AppStorage("minimumMeetingDuration") private var minimumDuration: TimeInterval = 30.0
    @AppStorage("screenRecordingPromptDismissed") private var screenRecordingPromptDismissed: Bool = false
    @AppStorage("lastScreenRecordingPromptDate") private var lastScreenRecordingPromptDate: Double = 0
    
    // MARK: - Initialization
    private init() {
        setupDetection()
        setupNotifications()
        loadPreferences()
        setupTranscription()
        setupDiarization()
    }
    
    private func setupTranscription() {
        // Initialize modern speech framework if available
        if #available(macOS 26.0, *) {
            // Only create a new framework if one doesn't exist
            if modernSpeechFramework == nil {
                Task { @MainActor in
                    // Create framework with current locale
                    modernSpeechFramework = ModernSpeechFramework(locale: .current)
                    do {
                        if let framework = modernSpeechFramework as? ModernSpeechFramework {
                            try await framework.initialize()
                            print("✅ Modern Speech Framework ready (SpeechAnalyzer + SpeechTranscriber)")
                            print("✅ Using AsyncStream<AnalyzerInput> pattern for streaming")
                        }
                    } catch {
                        print("⚠️ Failed to initialize Modern Speech Framework: \(error)")
                        print("⚠️ Error details: \(error.localizedDescription)")
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
            diarizationManager = DiarizationManager(isEnabled: true, enableRealTimeProcessing: true)
            do {
                try await diarizationManager?.initialize()
                print("✅ DiarizationManager initialized for speaker detection")
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
            
            do {
                // Start audio capture
                try await audioCapture.startCapture()
                
                // Set up audio buffer callback
                audioCapture.onAudioBuffersAvailable = { [weak self] micBuffer, systemBuffer in
                    self?.processAudioBuffers(mic: micBuffer, system: systemBuffer)
                }
                
                // Start two-way detection
                twoWayDetector.startMonitoring()
                
                await MainActor.run {
                    self.isMonitoring = true
                    self.recordingState = .monitoring
                }
                
                print("✅ Meeting recording engine started successfully")
                
            } catch {
                await MainActor.run {
                    self.recordingState = .error(error.localizedDescription)
                }
                print("❌ Failed to start monitoring: \(error)")
            }
        }
    }
    
    /// Stop monitoring and recording
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🛑 Stopping meeting recording engine")
        
        // Stop calendar monitoring
        stopCalendarMonitoring()
        
        // Stop recording if active
        if isRecording {
            stopRecording()
        }
        
        // Stop detection
        twoWayDetector.stopMonitoring()
        
        // Stop audio capture
        audioCapture.stopCapture()
        
        DispatchQueue.main.async {
            self.isMonitoring = false
            self.recordingState = .idle
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
            startRecording(isManual: true)
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
        // Pass to two-way detector for conversation analysis
        twoWayDetector.analyzeAudioStreams(micBuffer: mic, systemBuffer: system)
        
        // If recording, save the mixed audio
        if isRecording {
            // Mix the audio buffers for complete conversation
            if let mixedBuffer = audioCapture.mixAudioBuffers(mic: mic, system: system) {
                saveAudioBuffer(mixedBuffer)
                
                // Process for diarization (speaker detection)
                #if canImport(FluidAudio)
                if let diarizationManager = diarizationManager {
                    Task {
                        await diarizationManager.processAudioBuffer(mixedBuffer)
                        
                        // Update meeting type based on speaker count
                        await MainActor.run {
                            if let result = diarizationManager.lastResult {
                                let speakerCount = result.speakerCount
                                let progressValue = diarizationManager.processingProgress
                                
                                self.currentMeeting?.updateMeetingType(
                                    speakerCount: speakerCount,
                                    confidence: progressValue > 0 ? Float(progressValue) : 0.5
                                )
                                
                                // Log detection
                                if let meetingType = self.currentMeeting?.meetingType {
                                    print("🎙️ Detected \(speakerCount) speakers → Meeting Type: \(meetingType.displayName)")
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
                                let fullTranscript = try await framework.processAudioStream(mixedBuffer)
                                
                                // Check if we have new content (the transcript grows incrementally)
                                if fullTranscript.count > self.lastTranscriptionText.count {
                                    // Extract only the new portion
                                    let newContent = String(fullTranscript.dropFirst(self.lastTranscriptionText.count))
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    if !newContent.isEmpty {
                                        // Add only the new content as a segment
                                        let segment = TranscriptSegment(
                                            text: newContent,
                                            timestamp: Date().timeIntervalSince(self.recordingStartTime ?? Date()),
                                            speakerID: nil,
                                            speakerName: nil,
                                            confidence: 0.95,
                                            isFinalized: true
                                        )
                                        self.currentMeeting?.addTranscriptSegment(segment)
                                        
                                        print("📝 New segment #\(self.currentMeeting?.transcript.count ?? 0): \(newContent.split(separator: " ").count) words")
                                        print("📊 Total transcript: \(fullTranscript.split(separator: " ").count) words")
                                        
                                        // Update our tracking
                                        self.lastTranscriptionText = fullTranscript
                                        
                                        // Update meeting metrics
                                        self.updateMeetingMetrics()
                                    }
                                } else if !fullTranscript.isEmpty && self.lastTranscriptionText.isEmpty {
                                    // First transcription
                                    let segment = TranscriptSegment(
                                        text: fullTranscript,
                                        timestamp: Date().timeIntervalSince(self.recordingStartTime ?? Date()),
                                        speakerID: nil,
                                        speakerName: nil,
                                        confidence: 0.95,
                                        isFinalized: true
                                    )
                                    self.currentMeeting?.addTranscriptSegment(segment)
                                    self.lastTranscriptionText = fullTranscript
                                    
                                    print("📝 First segment: \(fullTranscript.split(separator: " ").count) words")
                                } else {
                                    // Still accumulating audio
                                    let elapsed = Date().timeIntervalSince(self.recordingStartTime ?? Date())
                                    if Int(elapsed) % 5 == 0 { // Log every 5 seconds
                                        print("🎤 Accumulating audio... (\(Int(elapsed))s recorded, waiting for transcription)")
                                    }
                                }
                            } catch {
                                print("❌ Transcription error: \(error.localizedDescription)")
                                print("❌ Full error: \(error)")
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
        DispatchQueue.main.async {
            self.recordingState = .conversationDetected
        }
        
        // Check if auto-record is enabled
        if autoRecordEnabled {
            print("🎙️ Auto-starting recording for detected conversation")
            startRecording(isManual: false)
        } else {
            // Show notification to user
            showRecordingPrompt()
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
        
        // For auto-recording, reset the transcription framework
        // (Manual recording already resets before calling this)
        if !isManual {
            if #available(macOS 26.0, *) {
                Task { @MainActor in
                    if let framework = modernSpeechFramework as? ModernSpeechFramework {
                        framework.reset()
                        print("✅ Reset transcription framework for auto-recording")
                    }
                }
            }
            lastTranscriptionText = "" // Reset transcript tracking
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
        
        // Try to get calendar context
        if let calendarEvent = getUpcomingCalendarEvent() {
            meeting.calendarTitle = calendarEvent.title
            meeting.scheduledDuration = calendarEvent.duration
            meeting.expectedParticipants = calendarEvent.attendees ?? []
        }
        
        // For manual recording, ensure audio capture is running
        if isManual && !audioCapture.isCapturing {
            // Set up audio buffer callbacks
            audioCapture.onAudioBuffersAvailable = { [weak self] micBuffer, systemBuffer in
                self?.processAudioBuffers(mic: micBuffer, system: systemBuffer)
            }
            
            // Also set up mixed audio callback for better transcription
            audioCapture.onMixedAudioAvailable = { [weak self] mixedBuffer in
                // Mixed audio is already handled in processAudioBuffers
                // This is here for future use if needed
            }
            
            Task {
                do {
                    try await audioCapture.startCapture()
                    print("🎤 Started audio capture for manual recording")
                } catch {
                    print("❌ Failed to start audio capture: \(error)")
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
        
        // Update state and show window
        DispatchQueue.main.async {
            self.isRecording = true
            self.currentMeeting = meeting
            self.recordingState = .recording
            
            // Show recording window after state is set
            print("🪟 Showing enhanced live meeting window")
            LiveMeetingWindowManager.shared.showWindow(for: meeting)
        }
        
        print("✅ Recording started: \(meeting.id)")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
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
                        print("🔄 Flushing remaining audio for transcription...")
                        let finalTranscription = await framework.flushAndTranscribe()
                        
                        // Finalize diarization results
                        #if canImport(FluidAudio)
                        var speakerSegments: [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] = []
                        if let diarizationManager = self.diarizationManager {
                            if let finalResult = await diarizationManager.finishProcessing() {
                                print("📊 Final diarization: \(finalResult.speakerCount) speakers detected")
                                
                                // Final update to meeting type
                                await MainActor.run {
                                    meeting.updateMeetingType(
                                        speakerCount: finalResult.speakerCount,
                                        confidence: 1.0 // High confidence after full processing
                                    )
                                    print("✅ Final Meeting Type: \(meeting.meetingType.displayName)")
                                }
                                
                                // Could also process speaker segments here if needed
                                // for segment in finalResult.segments { ... }
                            }
                            
                            // Reset diarization for next meeting
                            await MainActor.run {
                                diarizationManager.reset()
                            }
                        }
                        #else
                        // Get speaker segments if diarization is enabled
                        // Speaker segments not available in fallback implementation
                        let speakerSegments: [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] = []
                        #endif
                        
                        if !speakerSegments.isEmpty {
                            // Add speaker-attributed segments
                            await MainActor.run {
                                for (index, segment) in speakerSegments.enumerated() {
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
        }
        
        print("✅ Recording stopped after \(Int(duration))s")
        
        // Hide recording window
        hideLiveMeetingWindow()
    }
    
    // MARK: - Private Methods - Post-Processing
    
    private func processMeeting(_ meeting: LiveMeeting) async {
        await MainActor.run {
            self.recordingState = .processing
        }
        
        print("🔄 Processing meeting: \(meeting.id)")
        print("📊 Meeting has \(meeting.transcript.count) transcript segments")
        
        // Convert transcript to text for processing
        let transcriptText = meeting.transcript.map { segment in
            if let speaker = segment.speakerName {
                return "\(speaker): \(segment.text)"
            } else {
                return segment.text
            }
        }.joined(separator: "\n")
        
        print("📝 Combined transcript length: \(transcriptText.count) characters, \(transcriptText.split(separator: " ").count) words")
        
        // Check if we should open the transcript import UI for review
        if !transcriptText.isEmpty {
            // Open the transcript import window with the recorded content
            await MainActor.run {
                // Store the transcript temporarily for the import window
                UserDefaults.standard.set(transcriptText, forKey: "PendingRecordedTranscript")
                UserDefaults.standard.set(meeting.displayTitle, forKey: "PendingRecordedTitle")
                UserDefaults.standard.set(meeting.startTime, forKey: "PendingRecordedDate")
                UserDefaults.standard.set(meeting.duration, forKey: "PendingRecordedDuration")
                
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
            let alert = NSAlert()
            alert.messageText = "Meeting Detected"
            alert.informativeText = "Would you like to start recording?"
            alert.addButton(withTitle: "Record")
            alert.addButton(withTitle: "Dismiss")
            alert.alertStyle = .informational
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.manualStartRecording()
            }
        }
    }
    
    private func showLiveMeetingWindow() {
        guard let meeting = currentMeeting else { return }
        print("🪟 Showing live meeting window")
        
        DispatchQueue.main.async {
            LiveMeetingWindowManager.shared.showWindow(for: meeting)
        }
    }
    
    private func hideLiveMeetingWindow() {
        print("🪟 Hiding live meeting window")
        
        DispatchQueue.main.async {
            LiveMeetingWindowManager.shared.hideWindow()
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
    
    private func startRecordingTimer() {
        DispatchQueue.main.async {
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                
                self.recordingDuration = Date().timeIntervalSince(startTime)
                self.currentMeeting?.duration = self.recordingDuration
            }
        }
    }
    
    @objc private func handleAppTermination() {
        if isRecording {
            stopRecording()
        }
        stopMonitoring()
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
            
            // Update speaker turn count (simplified - counts speaker changes)
            var lastSpeaker: String? = nil
            var turnCount = 0
            for segment in meeting.transcript {
                if let speaker = segment.speakerName, speaker != lastSpeaker {
                    turnCount += 1
                    lastSpeaker = speaker
                }
            }
            meeting.speakerTurnCount = turnCount
            
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
        // Check calendar every 30 seconds
        calendarMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkForUpcomingMeetings()
        }
        
        // Check immediately
        checkForUpcomingMeetings()
    }
    
    private func checkForUpcomingMeetings() {
        // Fetch meetings for next 15 minutes
        calendarService.fetchUpcomingMeetings(daysAhead: 1)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            
            // Find meetings starting in the next 2-3 minutes
            for meeting in self.calendarService.upcomingMeetings {
                let timeUntilMeeting = meeting.startDate.timeIntervalSince(now)
                
                // Meeting starting in 2-3 minutes
                if timeUntilMeeting > 0 && timeUntilMeeting <= 180 {
                    print("🔔 Meeting '\(meeting.title)' starting in \(Int(timeUntilMeeting/60)) minutes")
                    
                    // Set as current event
                    self.currentCalendarEvent = meeting
                    
                    // Prepare for the meeting (Phase 3: Smart Calendar Integration)
                    Task {
                        // Convert UpcomingMeeting to CalendarEvent
                        let calendarEvent = CalendarEvent(
                            title: meeting.title,
                            startDate: meeting.startDate,
                            duration: 3600, // Default 1 hour duration
                            attendees: meeting.attendees
                        )
                        await self.prepareForUpcomingMeeting(calendarEvent)
                    }
                    
                    // If auto-record is enabled and not already recording
                    if self.autoRecordPref && !self.isRecording {
                        // Schedule recording start
                        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, timeUntilMeeting - 30)) {
                            // Check for audio activity or app detection
                            if self.shouldStartRecording(for: meeting) {
                                self.startRecording(isManual: false)
                            }
                        }
                    }
                }
                
                // Check if we should stop recording (meeting ended)
                if let current = self.currentCalendarEvent,
                   current.id == meeting.id {
                    let meetingEndTime = meeting.startDate.addingTimeInterval(3600) // Assume 1 hour
                    if now > meetingEndTime && self.isRecording {
                        print("🔚 Meeting ended, stopping recording")
                        self.stopRecording()
                        self.currentCalendarEvent = nil
                    }
                }
            }
        }
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
            "us.zoom.xos",           // Zoom
            "com.microsoft.teams",    // Microsoft Teams
            "com.google.Chrome",      // Chrome (for Google Meet)
            "com.tinyspeck.slackmacgap", // Slack
            "com.webex.meetingmanager" // Webex
        ]
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier,
               meetingAppBundleIds.contains(bundleId),
               app.isActive {
                print("🖥️ Meeting app detected: \(app.localizedName ?? bundleId)")
                return true
            }
        }
        
        return false
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
            
            // Update meeting with identified participants
            await MainActor.run {
                for (speakerId, person) in matches {
                    let participant = IdentifiedParticipant()
                    participant.name = person.name
                    participant.person = person
                    participant.speakerID = Int(speakerId) ?? 0
                    participant.confidence = person.voiceConfidence
                    
                    meeting.addIdentifiedParticipant(participant)
                    print("✅ Identified speaker \(speakerId) as \(person.name ?? "Unknown")")
                }
                
                // Flag unexpected participants
                for speakerId in detectedSpeakers {
                    if matches[speakerId] == nil {
                        print("⚠️ Unexpected participant detected: Speaker \(speakerId)")
                        meeting.hasUnexpectedParticipants = true
                    }
                }
            }
            }
        }
        #endif
    }
    
}

// MARK: - Supporting Types

struct CalendarEvent {
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendees: [String]?
}