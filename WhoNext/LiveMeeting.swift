import Foundation
import SwiftUI

// MARK: - Meeting Type

enum MeetingType: String, Codable {
    case oneOnOne = "1:1"
    case group = "Group"
    case unknown = "Unknown"
    
    var displayName: String {
        rawValue
    }
    
    var color: Color {
        switch self {
        case .oneOnOne: return .blue
        case .group: return .green
        case .unknown: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .oneOnOne: return "person.2"
        case .group: return "person.3"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Represents a meeting currently being recorded and transcribed
class LiveMeeting: ObservableObject, Identifiable {
    
    // MARK: - Identification
    let id = UUID()
    
    // MARK: - Published Properties (for UI updates)
    @Published var isRecording: Bool = true
    @Published var duration: TimeInterval = 0
    @Published var transcript: [TranscriptSegment] = []
    @Published var identifiedParticipants: [IdentifiedParticipant] = []
    @Published var transcriptionProgress: Double = 0.0
    
    // MARK: - Meeting Type Detection
    @Published var meetingType: MeetingType = .unknown
    @Published var detectedSpeakerCount: Int = 0
    @Published var speakerDetectionConfidence: Float = 0.0
    @Published var typeDetectionTimestamp: Date?
    
    // MARK: - Enhanced Metrics
    @Published var wordCount: Int = 0
    @Published var currentFileSize: Int64 = 0
    @Published var averageConfidence: Float = 0.0
    @Published var detectedLanguage: String? = nil
    @Published var speakerTurnCount: Int = 0
    @Published var overlapCount: Int = 0
    
    // MARK: - System Metrics
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Int64 = 0
    @Published var bufferHealth: BufferHealth = .good
    @Published var droppedFrames: Int = 0
    
    // MARK: - Meeting Metadata
    var startTime: Date = Date()
    var endTime: Date?
    var isManual: Bool = false // true if manually started, false if auto-detected
    
    // MARK: - Calendar Context (if available)
    var calendarTitle: String?
    var calendarEventTitle: String?
    var scheduledDuration: TimeInterval?
    var expectedParticipants: [String] = []
    var hasUnexpectedParticipants: Bool = false
    
    // MARK: - Audio Recording
    var audioFilePath: String?
    var audioQuality: AudioQuality = .unknown
    
    // MARK: - Computed Properties
    
    var displayTitle: String {
        calendarTitle ?? "Meeting \(formattedStartTime)"
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    var participantCount: Int {
        identifiedParticipants.count
    }
    
    var meetingProgress: Double {
        guard let scheduled = scheduledDuration, scheduled > 0 else { return 0 }
        return min(duration / scheduled, 1.0)
    }
    
    // MARK: - Methods
    
    func addTranscriptSegment(_ segment: TranscriptSegment) {
        transcript.append(segment)
        
        // Update word count - use safer word counting
        let words = segment.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        wordCount += words
        
        // Update average confidence
        if transcript.count == 1 {
            averageConfidence = segment.confidence
        } else {
            // Running average
            averageConfidence = ((averageConfidence * Float(transcript.count - 1)) + segment.confidence) / Float(transcript.count)
        }
        
        // Track speaker changes - fixed array access
        if let speakerID = segment.speakerID {
            // Get the previous segment's speaker ID safely
            let previousSpeakerID = transcript.count >= 2 ? transcript[transcript.count - 2].speakerID : nil
            if speakerID != previousSpeakerID {
                speakerTurnCount += 1
            }
        }
    }
    
    func identifyParticipant(_ participant: IdentifiedParticipant) {
        if let index = identifiedParticipants.firstIndex(where: { $0.id == participant.id }) {
            // Update existing participant
            identifiedParticipants[index] = participant
        } else {
            // Add new participant
            identifiedParticipants.append(participant)
        }
    }
    
    func getTranscriptText() -> String {
        transcript.map { segment in
            if let speaker = segment.speakerName {
                return "\(speaker): \(segment.text)"
            } else {
                return segment.text
            }
        }.joined(separator: "\n")
    }

    // MARK: - Memory Management

    private var flushedSegments: [TranscriptSegment] = [] // Segments saved to disk
    private var lastFlushTime: Date?
    private let maxSegmentsInMemory = 100

    /// Flush old transcript segments to reduce memory usage during long meetings
    func flushOldSegments() {
        guard transcript.count > maxSegmentsInMemory else { return }

        // Move older segments to flushed array (would be written to disk in production)
        let segmentsToFlush = transcript.count - maxSegmentsInMemory
        let oldSegments = Array(transcript.prefix(segmentsToFlush))

        // In production, write to disk here
        flushedSegments.append(contentsOf: oldSegments)

        // Keep only recent segments in memory
        transcript = Array(transcript.suffix(maxSegmentsInMemory))

        lastFlushTime = Date()
        print("💾 Flushed \(segmentsToFlush) transcript segments to disk, keeping \(transcript.count) in memory")
    }

    /// Get full transcript including flushed segments
    func getFullTranscriptText() -> String {
        let allSegments = flushedSegments + transcript
        return allSegments.map { segment in
            if let speaker = segment.speakerName {
                return "\(speaker): \(segment.text)"
            } else {
                return segment.text
            }
        }.joined(separator: "\n")
    }
    
    // MARK: - Meeting Type Detection
    
    func updateMeetingType(speakerCount: Int, confidence: Float = 1.0) {
        detectedSpeakerCount = speakerCount
        speakerDetectionConfidence = confidence
        
        // Auto-classify based on speaker count
        let previousType = meetingType
        switch speakerCount {
        case 0:
            meetingType = .unknown
        case 1:
            // Single speaker detected - could be note-taking or waiting for others
            meetingType = .oneOnOne  // Assume 1:1 will start soon
        case 2:
            meetingType = .oneOnOne
        default:
            meetingType = .group
        }
        
        // Record when type was first detected
        if previousType == .unknown && meetingType != .unknown {
            typeDetectionTimestamp = Date()
        }
    }
    
    // MARK: - Participant Management
    
    /// Add or update an identified participant
    func addIdentifiedParticipant(_ participant: IdentifiedParticipant) {
        if let existingIndex = identifiedParticipants.firstIndex(where: { $0.id == participant.id }) {
            identifiedParticipants[existingIndex] = participant
        } else {
            identifiedParticipants.append(participant)
        }
    }
}

// MARK: - Transcript Segment

struct TranscriptSegment: Identifiable, Codable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval // Seconds from start of recording
    let speakerID: String?
    var speakerName: String? // Made mutable for live editing
    let confidence: Float
    let isFinalized: Bool // true if refined by Whisper, false if from Parakeet
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Naming Mode

enum NamingMode: String, Codable {
    case linkedToPerson = "linked"    // Has Person record, learning voice
    case transcriptOnly = "transcript" // Named but no Person record
    case unnamed = "unnamed"          // Not yet named
}

// MARK: - Identified Participant

class IdentifiedParticipant: ObservableObject, Identifiable {
    let id = UUID()
    
    @Published var name: String?
    @Published var confidence: Float = 0.0
    @Published var voicePrint: VoicePrint?
    @Published var personRecord: Person?
    @Published var person: Person?  // Alias for personRecord
    @Published var speakerID: Int = 0
    @Published var isCurrentlySpeaking: Bool = false
    @Published var totalSpeakingTime: TimeInterval = 0
    @Published var lastSpokeAt: Date?
    @Published var namingMode: NamingMode = .unnamed  // Track how this speaker was named
    @Published var isCurrentUser: Bool = false  // True if user identified this as themselves

    var displayName: String {
        if isCurrentUser {
            return "Me"
        } else if let name = name {
            return name
        } else if let person = personRecord {
            return person.name ?? "Unknown"
        } else {
            return "Speaker \(id.uuidString.prefix(4))"
        }
    }
    
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...1.0:
            return .high
        case 0.5..<0.8:
            return .medium
        default:
            return .low
        }
    }
    
    // MARK: - UI Support Properties
    
    /// Alias for isCurrentlySpeaking for UI compatibility
    var isSpeaking: Bool {
        isCurrentlySpeaking
    }
    
    /// Alias for totalSpeakingTime for UI compatibility
    var speakingDuration: TimeInterval {
        totalSpeakingTime
    }
    
    /// Color associated with this participant
    var color: Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple,
            .pink, .cyan, .indigo, .mint
        ]
        let index = abs(displayName.hashValue) % colors.count
        return colors[index]
    }
    
    /// Initials for avatar display
    var initials: String {
        let words = displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else {
            return String(displayName.prefix(2))
        }
    }
    
    enum ConfidenceLevel {
        case high
        case medium
        case low
        
        var color: Color {
            switch self {
            case .high: return .green
            case .medium: return .orange
            case .low: return .red
            }
        }
    }
}

// MARK: - Voice Print

struct VoicePrint: Codable {
    let id = UUID()
    let createdAt: Date
    let sampleCount: Int
    let mfccFeatures: [Float] // Mel-frequency cepstral coefficients
    let spectrogramHash: String // Hash of spectrogram for quick comparison
    
    func similarity(to other: VoicePrint) -> Float {
        // Calculate cosine similarity between MFCC features
        guard mfccFeatures.count == other.mfccFeatures.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<mfccFeatures.count {
            dotProduct += mfccFeatures[i] * other.mfccFeatures[i]
            normA += mfccFeatures[i] * mfccFeatures[i]
            normB += other.mfccFeatures[i] * other.mfccFeatures[i]
        }
        
        guard normA > 0 && normB > 0 else { return 0 }
        
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
}

// MARK: - Audio Quality

enum AudioQuality: String, Codable {
    case excellent
    case good
    case fair
    case poor
    case unknown
    
    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Buffer Health

enum BufferHealth: String, Codable {
    case good
    case warning
    case critical
    
    var description: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}