import Foundation
import CoreData

@objc(Conversation)
public class Conversation: NSManagedObject {
    @NSManaged public var date: Date?
    @NSManaged public var duration: Int32
    @NSManaged public var engagementLevel: String?
    @NSManaged public var legacyId: Date?
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var lastSentimentAnalysis: Date?
    @NSManaged public var notes: String?
    @NSManaged public var summary: String?
    @NSManaged public var uuid: UUID?
    @NSManaged public var analysisVersion: String?
    @NSManaged public var keyTopics: [String]?
    @NSManaged public var qualityScore: Double
    @NSManaged public var sentimentLabel: String?
    @NSManaged public var sentimentScore: Double
    @NSManaged public var person: Person?  // Legacy single-person relationship (backward compatibility)
    @NSManaged public var participants: NSSet?  // New: all participants with full attribution data
    @NSManaged public var notesRTF: Data?

    // Sync-related timestamp fields
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var deletedAt: Date?

    public var notesAttributedString: NSAttributedString? {
        get {
            guard let data = notesRTF else { return nil }
            return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        set {
            notesRTF = newValue.flatMap { try? $0.data(from: NSRange(location: 0, length: $0.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) }
        }
    }
}

extension Conversation: Identifiable {
    public var id: UUID {
        get {
            return uuid ?? UUID()
        }
        set {
            uuid = newValue
        }
    }
}

// MARK: - Participants Accessors

extension Conversation {

    /// All participants as a sorted array (by speaking time descending)
    public var participantsArray: [ConversationParticipant] {
        let set = participants as? Set<ConversationParticipant> ?? []
        return set.sorted { $0.speakingTime > $1.speakingTime }
    }

    /// Add a participant to this conversation
    @objc(addParticipantsObject:)
    public func addToParticipants(_ value: ConversationParticipant) {
        let items = mutableSetValue(forKey: "participants")
        items.add(value)
    }

    /// Remove a participant from this conversation
    @objc(removeParticipantsObject:)
    public func removeFromParticipants(_ value: ConversationParticipant) {
        let items = mutableSetValue(forKey: "participants")
        items.remove(value)
    }

    /// Add multiple participants to this conversation
    @objc(addParticipants:)
    public func addToParticipants(_ values: NSSet) {
        let items = mutableSetValue(forKey: "participants")
        items.union(values as Set<NSObject>)
    }

    /// Remove multiple participants from this conversation
    @objc(removeParticipants:)
    public func removeFromParticipants(_ values: NSSet) {
        let items = mutableSetValue(forKey: "participants")
        items.minus(values as Set<NSObject>)
    }

    /// The participant identified as the current user (if any)
    public var currentUserParticipant: ConversationParticipant? {
        participantsArray.first { $0.isCurrentUser }
    }

    /// External participants (excluding current user)
    public var externalParticipants: [ConversationParticipant] {
        participantsArray.filter { !$0.isCurrentUser }
    }
}