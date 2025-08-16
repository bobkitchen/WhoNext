import Foundation
import SwiftUI

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
    
    // MARK: - Meeting Metadata
    var startTime: Date = Date()
    var endTime: Date?
    var isManual: Bool = false // true if manually started, false if auto-detected
    
    // MARK: - Calendar Context (if available)
    var calendarTitle: String?
    var scheduledDuration: TimeInterval?
    var expectedParticipants: [String] = []
    
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
}

// MARK: - Transcript Segment

struct TranscriptSegment: Identifiable, Codable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval // Seconds from start of recording
    let speakerID: String?
    let speakerName: String?
    let confidence: Float
    let isFinalized: Bool // true if refined by Whisper, false if from Parakeet
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Identified Participant

class IdentifiedParticipant: ObservableObject, Identifiable {
    let id = UUID()
    
    @Published var name: String?
    @Published var confidence: Float = 0.0
    @Published var voicePrint: VoicePrint?
    @Published var personRecord: Person?
    @Published var isCurrentlySpeaking: Bool = false
    @Published var totalSpeakingTime: TimeInterval = 0
    @Published var lastSpokeAt: Date?
    
    var displayName: String {
        if let name = name {
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