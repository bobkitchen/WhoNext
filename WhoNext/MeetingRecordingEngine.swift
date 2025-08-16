import Foundation
import AVFoundation
import SwiftUI
import AppKit

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
    private var transcriptionPipeline: HybridTranscriptionPipeline?
    
    // MARK: - Recording Properties
    private var audioWriter: AVAudioFile?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let maxBufferCount = 100 // Keep last 100 buffers (~10 seconds at 100ms intervals)
    
    // MARK: - User Preferences
    @AppStorage("autoRecordEnabled") private var autoRecordPref: Bool = true
    @AppStorage("recordingConfidenceThreshold") private var confidenceThreshold: Double = 0.7
    @AppStorage("minimumMeetingDuration") private var minimumDuration: TimeInterval = 30.0
    
    // MARK: - Initialization
    private init() {
        setupDetection()
        setupNotifications()
        loadPreferences()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for conversations and auto-recording
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🎙️ Starting meeting recording engine monitoring")
        
        Task {
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
        
        print("👤 Manual recording started")
        startRecording(isManual: true)
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
        
        // If recording, save buffers
        if isRecording {
            if let micBuffer = mic {
                saveAudioBuffer(micBuffer)
            }
            
            // Also process for real-time transcription
            if let pipeline = transcriptionPipeline {
                Task {
                    if let micBuffer = mic {
                        await pipeline.processAudioChunk(micBuffer)
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
        
        // Create live meeting object
        let meeting = LiveMeeting()
        meeting.isManual = isManual
        meeting.startTime = recordingStartTime!
        
        // Try to get calendar context
        if let calendarEvent = getUpcomingCalendarEvent() {
            meeting.calendarTitle = calendarEvent.title
            meeting.scheduledDuration = calendarEvent.duration
            meeting.expectedParticipants = calendarEvent.attendees ?? []
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
        
        // Initialize transcription pipeline
        transcriptionPipeline = HybridTranscriptionPipeline()
        transcriptionPipeline?.delegate = self
        
        // Start recording timer
        startRecordingTimer()
        
        // Update state
        DispatchQueue.main.async {
            self.isRecording = true
            self.currentMeeting = meeting
            self.recordingState = .recording
        }
        
        print("✅ Recording started: \(meeting.id)")
        
        // Show recording window
        showLiveMeetingWindow()
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        // Stop recording timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Close audio file
        audioWriter = nil
        
        // Process the recorded meeting
        if let meeting = currentMeeting {
            meeting.duration = duration
            meeting.endTime = Date()
            
            Task {
                await processMeeting(meeting)
            }
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
        
        // Get final transcription
        if let pipeline = transcriptionPipeline {
            let finalTranscript = await pipeline.finalizeTranscript()
            meeting.transcript = finalTranscript
        }
        
        // Determine if this should be a group or individual meeting
        let participantCount = meeting.identifiedParticipants.count
        
        if participantCount <= 3 {
            // Save as individual conversations
            await saveAsIndividualConversations(meeting)
        } else {
            // Save as group meeting
            await saveAsGroupMeeting(meeting)
        }
        
        // Schedule auto-deletion
        storageManager.scheduleAutoDelete(for: meeting.id, afterDays: 30)
        
        await MainActor.run {
            self.currentMeeting = nil
            self.recordingState = self.isMonitoring ? .monitoring : .idle
        }
        
        print("✅ Meeting processing complete")
    }
    
    private func saveAsIndividualConversations(_ meeting: LiveMeeting) async {
        // Implementation will save to individual Person conversation records
        print("💾 Saving as individual conversations for \(meeting.identifiedParticipants.count) participants")
    }
    
    private func saveAsGroupMeeting(_ meeting: LiveMeeting) async {
        // Implementation will save as GroupMeeting entity
        print("💾 Saving as group meeting with \(meeting.identifiedParticipants.count) participants")
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
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            
            DispatchQueue.main.async {
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
}

// MARK: - TranscriptionPipelineDelegate

extension MeetingRecordingEngine: TranscriptionPipelineDelegate {
    func transcriptionPipeline(_ pipeline: HybridTranscriptionPipeline, didTranscribe segment: TranscriptSegment) {
        // Add segment to current meeting
        DispatchQueue.main.async {
            self.currentMeeting?.transcript.append(segment)
        }
    }
    
    func transcriptionPipeline(_ pipeline: HybridTranscriptionPipeline, didIdentifySpeaker speaker: IdentifiedParticipant) {
        // Add or update speaker in current meeting
        DispatchQueue.main.async {
            if let existing = self.currentMeeting?.identifiedParticipants.first(where: { $0.id == speaker.id }) {
                // Update existing speaker
                existing.confidence = speaker.confidence
            } else {
                // Add new speaker
                self.currentMeeting?.identifiedParticipants.append(speaker)
            }
        }
    }
}

// MARK: - Supporting Types

struct CalendarEvent {
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendees: [String]?
}