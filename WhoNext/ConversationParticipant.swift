import Foundation
import CoreData

/// Represents a participant in a conversation with full speaker attribution data.
/// This entity stores the identified speaker information from diarization and voice matching.
@objc(ConversationParticipant)
public class ConversationParticipant: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ConversationParticipant> {
        return NSFetchRequest<ConversationParticipant>(entityName: "ConversationParticipant")
    }

    // MARK: - Attributes

    /// Unique identifier for this participant record
    @NSManaged public var identifier: UUID?

    /// Display name of the participant
    @NSManaged public var name: String?

    /// Speaker ID from diarization (e.g., 1, 2, 3...)
    @NSManaged public var speakerID: Int32

    /// Total speaking time in seconds
    @NSManaged public var speakingTime: Double

    /// Whether this participant was identified as the current user
    @NSManaged public var isCurrentUser: Bool

    /// Confidence score of voice identification (0.0 - 1.0)
    @NSManaged public var confidence: Float

    /// How the participant was named: "linked", "transcript", or "unnamed"
    @NSManaged public var namingMode: String?

    // MARK: - Relationships

    /// The conversation this participant belongs to
    @NSManaged public var conversation: Conversation?

    /// The Person record if linked (optional - may be nil for transcript-only naming)
    @NSManaged public var person: Person?

    // MARK: - Lifecycle

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        if identifier == nil {
            identifier = UUID()
        }
    }
}

// MARK: - Computed Properties

extension ConversationParticipant {

    /// Display name with fallback to speaker ID
    public var displayName: String {
        if isCurrentUser {
            return name ?? "Me"
        }
        return name ?? "Speaker \(speakerID)"
    }

    /// Formatted speaking time as MM:SS
    public var formattedSpeakingTime: String {
        let minutes = Int(speakingTime) / 60
        let seconds = Int(speakingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// The NamingMode enum value
    var namingModeValue: NamingMode {
        get {
            guard let mode = namingMode else { return .unnamed }
            return NamingMode(rawValue: mode) ?? .unnamed
        }
        set {
            namingMode = newValue.rawValue
        }
    }
}

// MARK: - Identifiable

extension ConversationParticipant: Identifiable {
    public var id: UUID {
        get {
            if let existing = identifier {
                return existing
            }
            let newId = UUID()
            identifier = newId
            return newId
        }
        set {
            identifier = newValue
        }
    }
}

// MARK: - Factory Methods

extension ConversationParticipant {

    /// Create a ConversationParticipant from a ParticipantInfo
    static func create(
        from participantInfo: ParticipantInfo,
        in context: NSManagedObjectContext,
        linkedPerson: Person? = nil
    ) -> ConversationParticipant {
        let participant = ConversationParticipant(context: context)
        participant.identifier = participantInfo.id
        participant.name = participantInfo.name
        participant.speakerID = Int32(participantInfo.speakerID)
        participant.speakingTime = participantInfo.speakingTime
        participant.isCurrentUser = participantInfo.isCurrentUser
        participant.confidence = participantInfo.confidence
        participant.namingMode = participantInfo.isCurrentUser ? NamingMode.linkedToPerson.rawValue :
                                 (linkedPerson != nil ? NamingMode.linkedToPerson.rawValue : NamingMode.transcriptOnly.rawValue)
        participant.person = linkedPerson
        return participant
    }

    /// Create a ConversationParticipant from a SerializableParticipant
    static func create(
        from serializable: SerializableParticipant,
        in context: NSManagedObjectContext,
        linkedPerson: Person? = nil
    ) -> ConversationParticipant {
        let participant = ConversationParticipant(context: context)
        participant.identifier = serializable.id
        participant.name = serializable.name ?? serializable.displayName
        participant.speakerID = Int32(serializable.speakerID)
        participant.speakingTime = serializable.totalSpeakingTime
        participant.isCurrentUser = serializable.isCurrentUser
        participant.confidence = serializable.confidence
        participant.namingMode = serializable.namingMode.rawValue
        participant.person = linkedPerson
        return participant
    }
}
