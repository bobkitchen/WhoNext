import Foundation
import AVFoundation
import Accelerate
import SwiftUI
import AppKit

/// Detects two-way audio conversations by analyzing both microphone and system audio streams
/// This is the core engine for automatic meeting detection, similar to how Quill works
class TwoWayAudioDetector: ObservableObject {
    
    // MARK: - Published Properties
    @Published var conversationDetected: Bool = false
    @Published var conversationConfidence: Double = 0.0
    @Published var isMonitoring: Bool = false
    @Published var microphoneActivity: Bool = false
    @Published var systemAudioActivity: Bool = false
    
    // MARK: - Audio Detection Components
    private let microphoneVAD: VoiceActivityDetector
    private let systemAudioVAD: VoiceActivityDetector
    private let conversationAnalyzer: ConversationPatternAnalyzer
    
    // MARK: - Configuration
    private let confidenceThreshold: Double = 0.7
    private let minimumConversationDuration: TimeInterval = 5.0
    private let silenceThreshold: TimeInterval = 120.0 // 2 minutes of silence ends recording
    
    // MARK: - State Tracking
    private var conversationStartTime: Date?
    var lastActivityTime: Date = Date()  // Made public for smart stop detection
    private var recentMicActivity: [Bool] = []
    private var recentSystemActivity: [Bool] = []
    private let activityWindowSize = 10 // Track last 10 samples
    
    // MARK: - Callbacks
    var onConversationStart: (() -> Void)?
    var onConversationEnd: (() -> Void)?
    
    // MARK: - Initialization
    init() {
        self.microphoneVAD = VoiceActivityDetector(channel: .microphone)
        self.systemAudioVAD = VoiceActivityDetector(channel: .systemAudio)
        self.conversationAnalyzer = ConversationPatternAnalyzer()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring audio streams for conversation patterns
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🎙️ Starting two-way audio detection monitoring")
        isMonitoring = true
        
        microphoneVAD.startDetection()
        systemAudioVAD.startDetection()
    }
    
    /// Stop monitoring audio streams
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🛑 Stopping two-way audio detection monitoring")
        isMonitoring = false
        
        microphoneVAD.stopDetection()
        systemAudioVAD.stopDetection()
        
        if conversationDetected {
            endConversation()
        }
    }
    
    /// Analyze audio buffers from both channels for conversation patterns
    func analyzeAudioStreams(micBuffer: AVAudioPCMBuffer?, systemBuffer: AVAudioPCMBuffer?) {
        guard isMonitoring else { return }
        
        // 1. Detect voice activity on both channels
        let micHasSpeech = micBuffer != nil ? microphoneVAD.detectSpeech(in: micBuffer!) : false
        let systemHasSpeech = systemBuffer != nil ? systemAudioVAD.detectSpeech(in: systemBuffer!) : false
        
        // Update activity indicators
        DispatchQueue.main.async {
            self.microphoneActivity = micHasSpeech
            self.systemAudioActivity = systemHasSpeech
        }
        
        // 2. Track activity patterns
        updateActivityHistory(mic: micHasSpeech, system: systemHasSpeech)
        
        // 3. Analyze conversation patterns
        if micHasSpeech || systemHasSpeech {
            lastActivityTime = Date()
            
            // Add event to pattern analyzer
            conversationAnalyzer.addEvent(
                micActive: micHasSpeech,
                systemActive: systemHasSpeech,
                timestamp: Date()
            )
            
            // 4. Calculate conversation confidence
            let newConfidence = calculateConversationConfidence()
            
            DispatchQueue.main.async {
                self.conversationConfidence = newConfidence
            }
            
            // 5. Handle conversation state changes
            if newConfidence >= confidenceThreshold && !conversationDetected {
                startConversation()
            }
        }
        
        // 6. Check for conversation end (sustained silence)
        if conversationDetected {
            let silenceDuration = Date().timeIntervalSince(lastActivityTime)
            if silenceDuration > silenceThreshold {
                endConversation()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateActivityHistory(mic: Bool, system: Bool) {
        recentMicActivity.append(mic)
        recentSystemActivity.append(system)
        
        // Keep only recent samples
        if recentMicActivity.count > activityWindowSize {
            recentMicActivity.removeFirst()
        }
        if recentSystemActivity.count > activityWindowSize {
            recentSystemActivity.removeFirst()
        }
    }
    
    private func calculateConversationConfidence() -> Double {
        var confidence: Double = 0.0
        
        // 1. Turn-taking pattern (40% weight)
        if conversationAnalyzer.hasAlternatingPattern() {
            confidence += 0.4
            print("🔄 Turn-taking pattern detected (+0.4)")
        }
        
        // 2. Both channels active recently (30% weight)
        let micActivityRate = Double(recentMicActivity.filter { $0 }.count) / Double(activityWindowSize)
        let systemActivityRate = Double(recentSystemActivity.filter { $0 }.count) / Double(activityWindowSize)
        
        if micActivityRate > 0.2 && systemActivityRate > 0.2 {
            confidence += 0.3 * min(micActivityRate, systemActivityRate) * 2
            print("📊 Both channels active: mic=\(micActivityRate), system=\(systemActivityRate)")
        }
        
        // 3. Speech characteristics (20% weight)
        if conversationAnalyzer.hasSpeechCharacteristics() {
            confidence += 0.2
            print("🗣️ Speech characteristics detected (+0.2)")
        }
        
        // 4. Meeting app bonus (50% weight - Increased from 30%)
        // 4. Meeting app bonus (50% weight - Increased from 30%)
        // Check if we have a specific detected app OR just know a meeting app is running
        let appDetected = detectedApp != nil || isMeetingAppActive()
        
        if appDetected {
            confidence += 0.5
            let appName = detectedApp ?? "Generic Meeting App"
            print("💻 Meeting app detected: \(appName) (+0.5)")
            
            // If a meeting app is open, ANY speech should trigger recording immediately
            // This fixes the issue where we waited for "sustained" activity
            if micActivityRate > 0.0 || systemActivityRate > 0.0 {
                confidence += 0.2
                print("🗣️ Speech detected while meeting app active (+0.2)")
            }
        }
        
        // 5. Sustained Microphone Activity (Fallback for in-person/no-system-audio)
        // If we have significant speech but no system audio, we should still record
        // Relaxed thresholds: >30% mic activity, allow some system noise (<20%)
        if micActivityRate > 0.3 && systemActivityRate < 0.2 {
            // If we have speech characteristics OR just high sustained activity
            if conversationAnalyzer.hasSpeechCharacteristics() || micActivityRate > 0.5 {
                confidence += 0.4
                print("🎤 Sustained microphone speech detected (+0.4)")
            }
        }
        
        // 6. Calendar Context (The "Radiant" feature)
        // If a meeting is scheduled NOW, we are much more aggressive
        if isMeetingScheduled {
            if micActivityRate > 0.1 || systemActivityRate > 0.1 {
                confidence += 0.5 // Massive boost if audio is present during a scheduled meeting
                print("dV Calendar event active + audio detected (+0.5)")
            }
        }
        
        let finalConfidence = min(confidence, 1.0)
        if finalConfidence > 0.3 {
            print("📊 Total Confidence: \(String(format: "%.2f", finalConfidence)) (Threshold: \(confidenceThreshold))")
        }
        return finalConfidence
    }
    
    private func startConversation() {
        guard !conversationDetected else { return }
        
        conversationStartTime = Date()
        
        DispatchQueue.main.async {
            self.conversationDetected = true
            print("🎙️✅ Conversation detected! Starting recording...")
            self.onConversationStart?()
        }
    }
    
    private func endConversation() {
        guard conversationDetected else { return }
        
        let duration = conversationStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        DispatchQueue.main.async {
            self.conversationDetected = false
            self.conversationConfidence = 0.0
            print("🛑 Conversation ended after \(Int(duration))s")
            self.onConversationEnd?()
        }
        
        // Reset state
        conversationStartTime = nil
        conversationAnalyzer.reset()
        recentMicActivity.removeAll()
        recentSystemActivity.removeAll()
    }
    
    // MARK: - Simple Activity Queries (for calendar-based auto-start)

    /// Returns true if ANY microphone speech was detected in the recent activity window
    /// Used for simplified calendar-based detection: calendar event + any speech = go
    func hasRecentMicrophoneActivity() -> Bool {
        return recentMicActivity.contains(true)
    }

    /// Returns true if ANY system audio activity was detected in the recent activity window
    func hasRecentSystemAudioActivity() -> Bool {
        return recentSystemActivity.contains(true)
    }

    /// Returns true if ANY audio activity (mic or system) was detected recently
    func hasRecentAudioActivity() -> Bool {
        return hasRecentMicrophoneActivity() || hasRecentSystemAudioActivity()
    }

    // MARK: - Context Awareness
    var isMeetingScheduled: Bool = false
    @Published var detectedApp: String?
    
    private func isMeetingAppActive() -> Bool {
        // 1. Check running apps first
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Native apps - we trust these are for meetings if they are running (fallback)
        let nativeMeetingApps = [
            "zoom.us": "Zoom",
            "Microsoft Teams": "Teams",
            "Slack": "Slack",
            "Webex": "Webex"
        ]
        
        // Browser apps - we ONLY trust these if we see a specific window title
        let browserApps = [
            "Google Chrome": "Google Meet",
            "Safari": "Google Meet"
        ]
        
        var potentialNativeApp: String?
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Check native apps
            for (key, name) in nativeMeetingApps {
                if bundleID.lowercased().contains(key.lowercased()) {
                    potentialNativeApp = name
                    break
                }
            }
            if potentialNativeApp != nil { break }
        }
        
        // 2. Check window titles for "active meeting" indicators (requires Screen Recording permission)
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                      let title = window[kCGWindowName as String] as? String else { continue }
                
                // Check for specific active meeting indicators
                if ownerName.contains("Zoom") && (title.contains("Meeting") || title.contains("Webinar")) {
                    DispatchQueue.main.async { self.detectedApp = "Zoom Meeting" }
                    return true
                }
                
                if ownerName.contains("Teams") && (title.contains("Call") || title.contains("Meeting") || title.contains("|")) {
                    DispatchQueue.main.async { self.detectedApp = "Microsoft Teams" }
                    return true
                }
                
                // For browsers, we strictly require the title to match
                if (ownerName.contains("Google Chrome") || ownerName.contains("Safari")) && 
                   (title.contains("Meet") || title.contains("Meeting")) {
                    DispatchQueue.main.async { self.detectedApp = "Google Meet" }
                    return true
                }
                
                if ownerName.contains("Slack") && title.contains("Huddle") {
                    DispatchQueue.main.async { self.detectedApp = "Slack Huddle" }
                    return true
                }
            }
        }
        
        // 3. Fallback: If we didn't find a specific window title...
        // If a NATIVE app is running, we assume it might be a meeting (fallback behavior)
        if let appName = potentialNativeApp {
            DispatchQueue.main.async { self.detectedApp = appName }
            return true
        }
        
        // If only a browser was running (or nothing), and we didn't see a window title,
        // we do NOT consider it a meeting.
        DispatchQueue.main.async { self.detectedApp = nil }
        return false
    }
}

// MARK: - Voice Activity Detector

/// Detects speech activity in audio buffers using energy-based detection
class VoiceActivityDetector {
    enum Channel {
        case microphone
        case systemAudio
    }
    
    private let channel: Channel
    private var energyThreshold: Float = 0.01
    private var recentEnergies: [Float] = []
    private let energyWindowSize = 20
    
    init(channel: Channel) {
        self.channel = channel
        
        // Different thresholds for different channels
        switch channel {
        case .microphone:
            self.energyThreshold = 0.001 // Extremely sensitive (was 0.002)
        case .systemAudio:
            self.energyThreshold = 0.002 // Much more sensitive (was 0.008)
        }
    }
    
    func startDetection() {
        recentEnergies.removeAll()
    }
    
    func stopDetection() {
        recentEnergies.removeAll()
    }
    
    func detectSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        // Calculate RMS energy
        var energy: Float = 0.0
        for channel in 0..<channelCount {
            var channelEnergy: Float = 0.0
            vDSP_measqv(channelData[channel], 1, &channelEnergy, vDSP_Length(frameLength))
            energy += channelEnergy
        }
        energy = sqrt(energy / Float(channelCount * frameLength))
        
        // Track recent energies for adaptive threshold
        recentEnergies.append(energy)
        if recentEnergies.count > energyWindowSize {
            recentEnergies.removeFirst()
        }
        
        // Adaptive threshold based on recent activity
        let adaptiveThreshold = calculateAdaptiveThreshold()
        
        // Detect speech if energy exceeds threshold
        let hasSpeech = energy > adaptiveThreshold
        
        if hasSpeech {
            print("🎤 \(channel) speech detected: energy=\(energy), threshold=\(adaptiveThreshold)")
        }
        
        return hasSpeech
    }
    
    private func calculateAdaptiveThreshold() -> Float {
        // FIXED: Adaptive threshold was using median (including speech), causing self-silencing.
        // Now using a fixed sensitive threshold to ensure we catch all speech.
        return energyThreshold
    }
}

// MARK: - Conversation Pattern Analyzer

/// Analyzes audio events to identify conversation patterns (turn-taking, pauses, etc.)
class ConversationPatternAnalyzer {
    
    struct AudioEvent {
        let micActive: Bool
        let systemActive: Bool
        let timestamp: Date
    }
    
    private var events: [AudioEvent] = []
    private let maxEventCount = 100
    private let turnTakingWindow: TimeInterval = 10.0 // Analyze last 10 seconds
    
    func addEvent(micActive: Bool, systemActive: Bool, timestamp: Date) {
        events.append(AudioEvent(
            micActive: micActive,
            systemActive: systemActive,
            timestamp: timestamp
        ))
        
        // Keep only recent events
        if events.count > maxEventCount {
            events.removeFirst()
        }
    }
    
    func hasAlternatingPattern() -> Bool {
        guard events.count >= 10 else { return false }
        
        // Look for turn-taking in recent events
        let recentEvents = events.suffix(20)
        var alternations = 0
        var lastSpeaker: String?
        
        for event in recentEvents {
            let currentSpeaker: String?
            if event.micActive && !event.systemActive {
                currentSpeaker = "mic"
            } else if !event.micActive && event.systemActive {
                currentSpeaker = "system"
            } else {
                currentSpeaker = nil
            }
            
            if let current = currentSpeaker, current != lastSpeaker {
                alternations += 1
                lastSpeaker = current
            }
        }
        
        // At least 3 alternations indicates conversation
        return alternations >= 3
    }
    
    func hasSpeechCharacteristics() -> Bool {
        guard events.count >= 10 else { return false }
        
        // Check for typical speech patterns:
        // - Pauses between utterances (0.5-2 seconds)
        // - Not continuous (unlike music/video)
        // - Intermittent activity on both channels
        
        let recentEvents = events.suffix(30)
        var activeCount = 0
        var silenceCount = 0
        
        for event in recentEvents {
            if event.micActive || event.systemActive {
                activeCount += 1
            } else {
                silenceCount += 1
            }
        }
        
        // Speech typically has 40-70% activity with pauses
        let activityRatio = Double(activeCount) / Double(recentEvents.count)
        return activityRatio > 0.3 && activityRatio < 0.8
    }
    
    func reset() {
        events.removeAll()
    }
}