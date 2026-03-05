import Foundation
import CoreData
import SwiftUI

// MARK: - Person Category

enum PersonCategory: String, CaseIterable, Identifiable {
    case directReport = "directReport"
    case teammate = "teammate"
    case colleague = "colleague"
    case external = "external"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .directReport: return "Direct Report"
        case .teammate: return "Teammate"
        case .colleague: return "Colleague"
        case .external: return "External"
        }
    }

    var shortLabel: String {
        switch self {
        case .directReport: return "DR"
        case .teammate: return "Team"
        case .colleague: return "Org"
        case .external: return "Ext"
        }
    }

    var icon: String {
        switch self {
        case .directReport: return "arrow.down.right.circle.fill"
        case .teammate: return "person.2.fill"
        case .colleague: return "building.2.fill"
        case .external: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .directReport: return .blue
        case .teammate: return .green
        case .colleague: return .orange
        case .external: return .purple
        }
    }

    var expectedMeetingFrequencyDays: Int {
        switch self {
        case .directReport: return 10
        case .teammate: return 14
        case .colleague: return 30
        case .external: return 90
        }
    }
}

// MARK: - Person Entity

@objc(Person)
public class Person: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Person> {
        return NSFetchRequest<Person>(entityName: "Person")
    }

    @NSManaged public var identifier: UUID?
    @NSManaged public var isDirectReport: Bool
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var personCategory: String?
    @NSManaged public var photo: Data?
    @NSManaged public var role: String?
    @NSManaged public var scheduledConversationDate: Date?
    @NSManaged public var timezone: String?
    @NSManaged public var actionItems: NSSet?
    @NSManaged public var conversations: NSSet?  // Legacy single-person relationship
    @NSManaged public var groupMeetings: NSSet?  // Inverse of GroupMeeting.attendees
    @NSManaged public var groups: NSSet?
    // conversationParticipations removed - ConversationParticipant entity disabled

    // Sync-related timestamp fields
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var deletedAt: Date?

    // Voice recognition properties
    @NSManaged public var voiceEmbeddings: Data?
    @NSManaged public var lastVoiceUpdate: Date?
    @NSManaged public var voiceConfidence: Float
    @NSManaged public var voiceSampleCount: Int32

    // MARK: - Category Access

    var category: PersonCategory {
        get { PersonCategory(rawValue: personCategory ?? "") ?? .colleague }
        set {
            personCategory = newValue.rawValue
            // Keep isDirectReport in sync for CloudKit backward compatibility
            isDirectReport = (newValue == .directReport)
        }
    }

    // Guarantee that every newly-inserted Person gets a unique identifier
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        if identifier == nil {
            identifier = UUID()
        }
    }
}

// MARK: - Computed Properties
extension Person {
    public var wrappedName: String {
        name ?? "Unknown"
    }
    
    public var wrappedRole: String {
        role ?? "Unknown"
    }
    
    public var wrappedTimezone: String {
        timezone ?? "Unknown"
    }
    
    public var conversationsArray: [Conversation] {
        let set = conversations as? Set<Conversation> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public var groupMeetingsArray: [GroupMeeting] {
        let set = groupMeetings as? Set<GroupMeeting> ?? []
        return set
            .filter { !$0.isSoftDeleted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Computed from conversations + group meetings. The xcdatamodel also has a stored
    /// `lastContactDate` attribute — use this computed version for accurate data.
    public var mostRecentContactDate: Date? {
        let lastConversation = conversationsArray.first?.date
        let lastGroupMeeting = groupMeetingsArray.first?.date
        switch (lastConversation, lastGroupMeeting) {
        case let (c?, g?): return max(c, g)
        case let (c?, nil): return c
        case let (nil, g?): return g
        case (nil, nil): return nil
        }
    }
    
    public var initials: String {
        let components = (name ?? "").split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined()
    }

    /// Check if this person is the current user
    public var isCurrentUser: Bool {
        guard let name = name else { return false }
        return UserProfile.shared.isCurrentUser(name)
    }
}

extension Person: Identifiable {
    public var id: UUID {
        get {
            if let existing = identifier {
                return existing
            }
            // If the identifier was somehow nil (e.g. pre-migration objects), generate and persist one now
            let newId = UUID()
            identifier = newId
            return newId
        }
        set {
            identifier = newValue
        }
    }
}

// MARK: - Conversation Participations (Disabled - ConversationParticipant entity removed)
// TODO: Re-enable when ConversationParticipant is deployed to CloudKit Production

// MARK: - Voice Embedding Management

extension Person {

    /// Get the stored voice embeddings as an array of Float arrays
    public var storedVoiceEmbeddings: [[Float]]? {
        guard let data = voiceEmbeddings else { return nil }
        return try? JSONDecoder().decode([[Float]].self, from: data)
    }

    /// Add a new voice embedding sample to this person
    /// - Parameter embedding: The voice embedding array from diarization
    /// Thread-safe: performs work on the managed object context's queue
    public func addVoiceEmbedding(_ embedding: [Float]) {
        guard let context = managedObjectContext else { return }

        context.performAndWait {
            var embeddings = self.storedVoiceEmbeddings ?? []
            embeddings.append(embedding)

            // Keep only the last 10 samples for efficiency
            if embeddings.count > 10 {
                embeddings = Array(embeddings.suffix(10))
            }

            // Encode and save
            if let data = try? JSONEncoder().encode(embeddings) {
                self.voiceEmbeddings = data
                self.voiceSampleCount = Int32(embeddings.count)
                self.lastVoiceUpdate = Date()

                // Increase confidence based on sample count
                self.voiceConfidence = min(Float(embeddings.count) * 0.1, 1.0)
            }
        }
    }

    /// Calculate the average voice embedding for this person
    public var averageVoiceEmbedding: [Float]? {
        guard let embeddings = storedVoiceEmbeddings, !embeddings.isEmpty else { return nil }

        let embeddingSize = embeddings[0].count
        var average = [Float](repeating: 0, count: embeddingSize)

        for embedding in embeddings {
            for i in 0..<min(embedding.count, embeddingSize) {
                average[i] += embedding[i]
            }
        }

        let count = Float(embeddings.count)
        for i in 0..<embeddingSize {
            average[i] /= count
        }

        return average
    }

    /// Calculate cosine similarity between this person's voice and a given embedding (average-based)
    public func voiceSimilarity(to embedding: [Float]) -> Float {
        guard let averageEmbedding = averageVoiceEmbedding else { return 0 }
        return cosineSimilarity(averageEmbedding, embedding)
    }

    /// Best-of-N voice similarity: returns max cosine similarity across all stored embeddings
    /// More robust than average-based matching when some samples are noisy
    public func bestVoiceSimilarity(to embedding: [Float]) -> Float {
        guard let embeddings = storedVoiceEmbeddings, !embeddings.isEmpty else { return 0 }
        var maxSimilarity: Float = 0
        for stored in embeddings {
            guard stored.count == embedding.count else { continue }
            let sim = cosineSimilarity(stored, embedding)
            if sim > maxSimilarity { maxSimilarity = sim }
        }
        return maxSimilarity
    }

    /// Cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        VectorMath.cosineSimilarity(a, b)
    }
} 