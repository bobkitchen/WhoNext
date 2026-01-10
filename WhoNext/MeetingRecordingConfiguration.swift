import Foundation
import SwiftUI
import Combine
import AppKit

/// Configuration manager for meeting recording settings and automatic triggers
class MeetingRecordingConfiguration: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MeetingRecordingConfiguration()
    
    // MARK: - Published Settings
    @Published var isEnabled: Bool = true
    @Published var autoRecordingEnabled: Bool = true
    @Published var confidenceThreshold: Double = 0.7
    @Published var minimumConversationDuration: TimeInterval = 30.0
    @Published var maxSilenceDuration: TimeInterval = 120.0
    @Published var storageRetentionDays: Int = 30
    
    // MARK: - Recording Triggers
    @Published var triggers: RecordingTriggers = RecordingTriggers()
    
    // MARK: - Audio Quality Settings
    @Published var audioQuality: AudioQualitySettings = AudioQualitySettings()
    
    // MARK: - Transcription Settings
    @Published var transcriptionSettings: TranscriptionSettings = TranscriptionSettings()
    
    // MARK: - Privacy Settings
    @Published var privacySettings: PrivacySettings = PrivacySettings()
    
    // MARK: - User Defaults Keys
    private let userDefaultsKeys = UserDefaultsKeys()
    
    // MARK: - Initialization
    private init() {
        loadSettings()
        observeSettingsChanges()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        // Load main settings
        isEnabled = UserDefaults.standard.bool(forKey: userDefaultsKeys.isEnabled)
        autoRecordingEnabled = UserDefaults.standard.bool(forKey: userDefaultsKeys.autoRecordingEnabled)
        confidenceThreshold = UserDefaults.standard.double(forKey: userDefaultsKeys.confidenceThreshold)
        
        // Set defaults if not previously set
        if confidenceThreshold == 0 {
            confidenceThreshold = 0.7
            saveSettings()
        }
        
        // Load triggers
        triggers.loadFromUserDefaults()
        
        // Load audio quality settings
        audioQuality.loadFromUserDefaults()
        
        // Load transcription settings
        transcriptionSettings.loadFromUserDefaults()
        
        // Load privacy settings
        privacySettings.loadFromUserDefaults()
    }
    
    func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: userDefaultsKeys.isEnabled)
        UserDefaults.standard.set(autoRecordingEnabled, forKey: userDefaultsKeys.autoRecordingEnabled)
        UserDefaults.standard.set(confidenceThreshold, forKey: userDefaultsKeys.confidenceThreshold)
        UserDefaults.standard.set(minimumConversationDuration, forKey: userDefaultsKeys.minimumDuration)
        UserDefaults.standard.set(maxSilenceDuration, forKey: userDefaultsKeys.maxSilence)
        UserDefaults.standard.set(storageRetentionDays, forKey: userDefaultsKeys.retentionDays)
        
        triggers.saveToUserDefaults()
        audioQuality.saveToUserDefaults()
        transcriptionSettings.saveToUserDefaults()
        privacySettings.saveToUserDefaults()
    }
    
    private func observeSettingsChanges() {
        // Auto-save when settings change
        $isEnabled.sink { [weak self] _ in
            self?.saveSettings()
            self?.applySettings()
        }.store(in: &cancellables)
        
        $autoRecordingEnabled.sink { [weak self] _ in
            self?.saveSettings()
            self?.applySettings()
        }.store(in: &cancellables)
        
        $confidenceThreshold.sink { [weak self] _ in
            self?.saveSettings()
            self?.applySettings()
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Apply Settings
    
    private func applySettings() {
        // Apply settings to the recording engine
        let engine = MeetingRecordingEngine.shared
        
        if isEnabled && autoRecordingEnabled {
            engine.autoRecordEnabled = true
            
            // Start monitoring if not already
            if !engine.isMonitoring {
                engine.startMonitoring()
            }
        } else {
            engine.autoRecordEnabled = false
            
            // Stop monitoring if no manual recording is active
            if !engine.isRecording {
                engine.stopMonitoring()
            }
        }
    }
    
    // MARK: - Trigger Evaluation
    
    /// Evaluates whether recording should start based on current triggers
    func shouldStartRecording(confidence: Double, hasCalendarEvent: Bool, appContext: AppContext) -> Bool {
        // Check if recording is enabled
        guard isEnabled else { return false }
        
        // Check confidence threshold
        if confidence < confidenceThreshold { return false }
        
        // Evaluate triggers
        return triggers.evaluate(
            confidence: confidence,
            hasCalendarEvent: hasCalendarEvent,
            appContext: appContext
        )
    }
}

// MARK: - Recording Triggers

struct RecordingTriggers: Codable {
    var twoWayAudioEnabled: Bool = true
    var calendarIntegrationEnabled: Bool = true
    var meetingAppDetectionEnabled: Bool = true
    var keywordDetectionEnabled: Bool = false
    var keywords: [String] = ["meeting", "call", "discussion", "standup", "sync"]
    var timeBasedRules: [TimeBasedRule] = []
    
    func evaluate(confidence: Double, hasCalendarEvent: Bool, appContext: AppContext) -> Bool {
        // Two-way audio is the primary trigger
        if twoWayAudioEnabled && confidence >= 0.7 {
            return true
        }
        
        // Calendar event boost
        if calendarIntegrationEnabled && hasCalendarEvent && confidence >= 0.5 {
            return true
        }
        
        // Meeting app detection boost
        if meetingAppDetectionEnabled && appContext.hasMeetingApp && confidence >= 0.5 {
            return true
        }
        
        // Time-based rules
        if evaluateTimeBasedRules() && confidence >= 0.6 {
            return true
        }
        
        return false
    }
    
    private func evaluateTimeBasedRules() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        
        return timeBasedRules.contains { rule in
            rule.matches(weekday: weekday, hour: hour)
        }
    }
    
    mutating func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "recordingTriggers"),
           let decoded = try? JSONDecoder().decode(RecordingTriggers.self, from: data) {
            self = decoded
        }
    }
    
    func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "recordingTriggers")
        }
    }
}

// MARK: - Time-Based Rule

struct TimeBasedRule: Codable {
    var name: String
    var weekdays: Set<Int> // 1 = Sunday, 7 = Saturday
    var startHour: Int
    var endHour: Int
    var enabled: Bool
    
    func matches(weekday: Int, hour: Int) -> Bool {
        guard enabled else { return false }
        guard weekdays.contains(weekday) else { return false }
        return hour >= startHour && hour < endHour
    }
}

// MARK: - Audio Quality Settings

struct AudioQualitySettings: Codable {
    var sampleRate: Double = 16000 // 16kHz for speech
    var bitRate: Int = 64000 // 64kbps - minimum for reliable diarization
    var channels: Int = 1 // Mono
    var compressionEnabled: Bool = true
    
    mutating func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "audioQualitySettings"),
           let decoded = try? JSONDecoder().decode(AudioQualitySettings.self, from: data) {
            self = decoded
        }
    }
    
    func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "audioQualitySettings")
        }
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettings: Codable {
    var useLocalTranscription: Bool = true
    var whisperRefinementEnabled: Bool = true
    var speakerDiarizationEnabled: Bool = true
    var speakerSensitivity: Double = 0.70  // FluidAudio optimal: 0.7 achieves 17.7% DER. Range: 0.6-0.8 safe.
    var languageCode: String = "en-US"
    var punctuationEnabled: Bool = true
    var profanityFilterEnabled: Bool = false
    
    mutating func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "transcriptionSettings"),
           let decoded = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) {
            self = decoded

            // Migration: Reset speaker sensitivity if it's at the old problematic default (0.85)
            // or outside the new safe range (0.60-0.80)
            let migrationKey = "speakerSensitivityMigrated_v2"
            if !UserDefaults.standard.bool(forKey: migrationKey) {
                if self.speakerSensitivity >= 0.84 || self.speakerSensitivity < 0.60 {
                    print("[TranscriptionSettings] Migrating speaker sensitivity from \(self.speakerSensitivity) to optimal 0.70")
                    self.speakerSensitivity = 0.70
                    self.saveToUserDefaults()
                }
                UserDefaults.standard.set(true, forKey: migrationKey)
            }
        }
    }

    func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "transcriptionSettings")
        }
    }
}

// MARK: - Privacy Settings

struct PrivacySettings: Codable {
    var requireExplicitConsent: Bool = false
    var blurVideoInRecordings: Bool = true
    var excludedApps: [String] = []
    var excludedWebsites: [String] = []
    var pauseInPrivateBrowsing: Bool = true
    var notifyOnRecordingStart: Bool = true
    var showRecordingIndicator: Bool = true
    
    mutating func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: "privacySettings"),
           let decoded = try? JSONDecoder().decode(PrivacySettings.self, from: data) {
            self = decoded
        }
    }
    
    func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "privacySettings")
        }
    }
}

// MARK: - App Context

struct AppContext {
    var hasMeetingApp: Bool
    var activeAppName: String?
    var isInPrivateBrowsing: Bool
    var hasCalendarEventNow: Bool
    
    static func current() -> AppContext {
        // Check for meeting apps
        let runningApps = NSWorkspace.shared.runningApplications
        let meetingApps = ["zoom.us", "Microsoft Teams", "Slack", "Google Chrome", "Safari"]
        
        let hasMeetingApp = runningApps.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return meetingApps.contains { meetingApp in
                bundleID.lowercased().contains(meetingApp.lowercased())
            }
        }
        
        // Get active app
        let activeApp = NSWorkspace.shared.frontmostApplication
        
        // Check calendar
        let hasCalendarEvent = CalendarService.shared.hasCurrentMeeting()
        
        return AppContext(
            hasMeetingApp: hasMeetingApp,
            activeAppName: activeApp?.localizedName,
            isInPrivateBrowsing: false, // Would need to implement browser detection
            hasCalendarEventNow: hasCalendarEvent
        )
    }
}

// MARK: - User Defaults Keys

private struct UserDefaultsKeys {
    let isEnabled = "meetingRecording.isEnabled"
    let autoRecordingEnabled = "meetingRecording.autoEnabled"
    let confidenceThreshold = "meetingRecording.confidenceThreshold"
    let minimumDuration = "meetingRecording.minimumDuration"
    let maxSilence = "meetingRecording.maxSilence"
    let retentionDays = "meetingRecording.retentionDays"
}

// MARK: - Calendar Service Extension

extension CalendarService {
    func hasCurrentMeeting() -> Bool {
        let now = Date()
        return upcomingMeetings.contains { meeting in
            let endDate = meeting.startDate.addingTimeInterval(3600) // Assume 1 hour meetings
            return meeting.startDate <= now && endDate >= now
        }
    }
}