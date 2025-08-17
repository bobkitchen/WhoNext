import Foundation
import AVFoundation
import SwiftUI
import AppKit
import CoreData
import EventKit

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
    private var transcriptProcessor: TranscriptProcessor?
    private let calendarService = CalendarService.shared
    
    // MARK: - Recording Properties
    private var audioWriter: AVAudioFile?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private let maxBufferCount = 100 // Keep last 100 buffers (~10 seconds at 100ms intervals)
    private var calendarMonitorTimer: Timer?
    private var currentCalendarEvent: UpcomingMeeting?
    
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
    
    // MARK: - Public Methods
    
    /// Start monitoring for conversations and auto-recording
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🎙️ Starting meeting recording engine monitoring")
        
        // Request microphone permission first
        Task {
            let authorized = await requestMicrophonePermission()
            guard authorized else {
                await MainActor.run {
                    self.recordingState = .error("Microphone permission denied. Please grant access in System Settings.")
                }
                return
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
        
        // Convert transcript to text for processing
        let transcriptText = meeting.transcript.map { segment in
            if let speaker = segment.speakerName {
                return "\(speaker): \(segment.text)"
            } else {
                return segment.text
            }
        }.joined(separator: "\n")
        
        // Process through existing TranscriptProcessor for AI analysis
        if !transcriptText.isEmpty {
            // Create processor on main thread if needed
            if transcriptProcessor == nil {
                await MainActor.run {
                    self.transcriptProcessor = TranscriptProcessor()
                }
            }
            if let processedTranscript = await transcriptProcessor?.processTranscript(transcriptText) {
                // Save with AI-generated summary and analysis
                await saveProcessedMeeting(meeting, processed: processedTranscript)
                return
            }
        }
        
        // Fallback to original logic if processing fails
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
    
}

// MARK: - Supporting Types

struct CalendarEvent {
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendees: [String]?
}