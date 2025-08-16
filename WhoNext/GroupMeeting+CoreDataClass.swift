import Foundation
import CoreData

@objc(GroupMeeting)
public class GroupMeeting: NSManagedObject, @unchecked Sendable {
    
    // MARK: - Computed Properties
    
    /// Returns the number of attendees
    var attendeeCount: Int {
        attendees?.count ?? 0
    }
    
    /// Returns all attendees sorted by name
    var sortedAttendees: [Person] {
        let attendeesSet = attendees as? Set<Person> ?? []
        return attendeesSet.sorted { person1, person2 in
            (person1.name ?? "") < (person2.name ?? "")
        }
    }
    
    /// Returns the display title for the meeting
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        } else if let groupName = group?.name {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateString = date.map { dateFormatter.string(from: $0) } ?? "Unknown date"
            return "\(groupName) - \(dateString)"
        } else {
            return "Meeting \(identifier?.uuidString.prefix(8) ?? "Unknown")"
        }
    }
    
    /// Returns the formatted duration string
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Checks if the meeting is scheduled for deletion
    var isScheduledForDeletion: Bool {
        guard let scheduledDeletion = scheduledDeletion else { return false }
        return scheduledDeletion <= Date()
    }
    
    /// Returns the sentiment label based on score
    var sentimentLabel: String {
        switch sentimentScore {
        case 0.7...1.0:
            return "Positive"
        case 0.3..<0.7:
            return "Neutral"
        case 0..<0.3:
            return "Negative"
        default:
            return "Unknown"
        }
    }
    
    // MARK: - Transcript Management
    
    /// Parses transcript data from binary format
    var parsedTranscript: [TranscriptSegment]? {
        guard let transcriptData = transcriptData else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([TranscriptSegment].self, from: transcriptData)
        } catch {
            print("Failed to parse transcript data: \(error)")
            return nil
        }
    }
    
    /// Sets the transcript segments
    func setTranscriptSegments(_ segments: [TranscriptSegment]) {
        do {
            let encoder = JSONEncoder()
            transcriptData = try encoder.encode(segments)
            
            // Also update the plain text transcript
            transcript = segments.map { segment in
                if let speaker = segment.speakerName {
                    return "\(speaker): \(segment.text)"
                } else {
                    return segment.text
                }
            }.joined(separator: "\n")
        } catch {
            print("Failed to encode transcript segments: \(error)")
        }
    }
    
    // MARK: - Attendee Management
    
    /// Adds an attendee to the meeting
    func addAttendee(_ person: Person) {
        let currentAttendees = mutableSetValue(forKey: "attendees")
        currentAttendees.add(person)
    }
    
    /// Removes an attendee from the meeting
    func removeAttendee(_ person: Person) {
        let currentAttendees = mutableSetValue(forKey: "attendees")
        currentAttendees.remove(person)
    }
    
    /// Checks if a person attended the meeting
    func hasAttendee(_ person: Person) -> Bool {
        guard let attendees = attendees as? Set<Person> else { return false }
        return attendees.contains(person)
    }
    
    // MARK: - Audio Management
    
    /// Returns the URL for the audio file if it exists
    var audioFileURL: URL? {
        guard let audioFilePath = audioFilePath else { return nil }
        return URL(fileURLWithPath: audioFilePath)
    }
    
    /// Checks if the audio file exists
    var hasAudioFile: Bool {
        guard let url = audioFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Deletes the associated audio file
    func deleteAudioFile() {
        guard let url = audioFileURL, hasAudioFile else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
            audioFilePath = nil
            print("Deleted audio file for meeting \(identifier?.uuidString ?? "unknown")")
        } catch {
            print("Failed to delete audio file: \(error)")
        }
    }
    
    // MARK: - Soft Delete
    
    /// Marks the meeting as soft deleted
    func softDelete() {
        isSoftDeleted = true
        deletedAt = Date()
    }
    
    /// Restores a soft deleted meeting
    func restore() {
        isSoftDeleted = false
        deletedAt = nil
    }
    
    // MARK: - Quality Assessment
    
    /// Updates the quality score based on various factors
    func updateQualityScore() {
        var score: Double = 0.0
        var factors = 0
        
        // Factor 1: Duration (longer meetings get higher scores up to 2 hours)
        if duration > 0 {
            let durationScore = min(Double(duration) / 7200.0, 1.0) // Max at 2 hours
            score += durationScore
            factors += 1
        }
        
        // Factor 2: Attendee count (more attendees = higher engagement)
        if attendeeCount > 0 {
            let attendeeScore = min(Double(attendeeCount) / 10.0, 1.0) // Max at 10 attendees
            score += attendeeScore
            factors += 1
        }
        
        // Factor 3: Has transcript
        if transcript != nil && !transcript!.isEmpty {
            score += 1.0
            factors += 1
        }
        
        // Factor 4: Has summary
        if summary != nil && !summary!.isEmpty {
            score += 1.0
            factors += 1
        }
        
        // Factor 5: Has key topics
        if keyTopics != nil && !(keyTopics as? [String] ?? []).isEmpty {
            score += 1.0
            factors += 1
        }
        
        // Calculate average
        if factors > 0 {
            qualityScore = score / Double(factors)
        } else {
            qualityScore = 0.0
        }
    }
}