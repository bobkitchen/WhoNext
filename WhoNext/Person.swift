import Foundation
import CoreData

@objc(Person)
public class Person: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Person> {
        return NSFetchRequest<Person>(entityName: "Person")
    }
    
    @NSManaged public var identifier: UUID?
    @NSManaged public var isDirectReport: Bool
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var photo: Data?
    @NSManaged public var role: String?
    @NSManaged public var scheduledConversationDate: Date?
    @NSManaged public var timezone: String?
    @NSManaged public var conversations: NSSet?  // Legacy single-person relationship
    @NSManaged public var conversationParticipations: NSSet?  // New: all conversation participations

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
    
    public var lastContactDate: Date? {
        conversationsArray.first?.date
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

// MARK: - Conversation Participations

extension Person {

    /// All conversation participations as an array (sorted by conversation date descending)
    public var conversationParticipationsArray: [ConversationParticipant] {
        let set = conversationParticipations as? Set<ConversationParticipant> ?? []
        return set.sorted { ($0.conversation?.date ?? .distantPast) > ($1.conversation?.date ?? .distantPast) }
    }

    /// Total speaking time across all conversations
    public var totalSpeakingTime: Double {
        conversationParticipationsArray.reduce(0) { $0 + $1.speakingTime }
    }
}

// MARK: - Voice Embedding Management

extension Person {

    /// Get the stored voice embeddings as an array of Float arrays
    public var storedVoiceEmbeddings: [[Float]]? {
        guard let data = voiceEmbeddings else { return nil }
        return try? JSONDecoder().decode([[Float]].self, from: data)
    }

    /// Add a new voice embedding sample to this person
    /// - Parameter embedding: The voice embedding array from diarization
    public func addVoiceEmbedding(_ embedding: [Float]) {
        var embeddings = storedVoiceEmbeddings ?? []
        embeddings.append(embedding)

        // Keep only the last 10 samples for efficiency
        if embeddings.count > 10 {
            embeddings = Array(embeddings.suffix(10))
        }

        // Encode and save
        if let data = try? JSONEncoder().encode(embeddings) {
            voiceEmbeddings = data
            voiceSampleCount = Int32(embeddings.count)
            lastVoiceUpdate = Date()

            // Increase confidence based on sample count
            voiceConfidence = min(Float(embeddings.count) * 0.1, 1.0)
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

    /// Calculate cosine similarity between this person's voice and a given embedding
    public func voiceSimilarity(to embedding: [Float]) -> Float {
        guard let averageEmbedding = averageVoiceEmbedding else { return 0 }
        return cosineSimilarity(averageEmbedding, embedding)
    }

    /// Cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
} 