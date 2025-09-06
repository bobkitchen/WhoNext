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
        
        // 4. Meeting app bonus (10% weight)
        if isMeetingAppActive() {
            confidence += 0.1
            print("💻 Meeting app active (+0.1)")
        }
        
        return min(confidence, 1.0)
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
    
    private func isMeetingAppActive() -> Bool {
        // Check if common meeting apps are running
        let runningApps = NSWorkspace.shared.runningApplications
        let meetingApps = ["zoom.us", "Microsoft Teams", "Google Chrome", "Safari", "Slack"]
        
        return runningApps.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return meetingApps.contains { meetingApp in
                bundleID.lowercased().contains(meetingApp.lowercased())
            }
        }
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
            self.energyThreshold = 0.01 // More sensitive for microphone
        case .systemAudio:
            self.energyThreshold = 0.008 // Slightly less sensitive for system audio
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
        guard !recentEnergies.isEmpty else { return energyThreshold }
        
        // Use median of recent energies as baseline
        let sortedEnergies = recentEnergies.sorted()
        let median = sortedEnergies[sortedEnergies.count / 2]
        
        // Adaptive threshold is 2x median or minimum threshold, whichever is higher
        return max(median * 2, energyThreshold)
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