import Foundation
import CoreData
import AVFoundation

/// Manages voice embeddings and speaker identification
/// Links DiarizationManager speaker embeddings to Person records
class VoicePrintManager: ObservableObject {

    // MARK: - Properties

    private let persistenceController: PersistenceController
    /// Embedding dimension — learned from the first embedding saved, defaults to 256
    private var embeddingDimension: Int {
        let stored = UserDefaults.standard.integer(forKey: "VoicePrintEmbeddingDimension")
        return stored != 0 ? stored : 256
    }
    private let minimumConfidenceThreshold: Float = 0.7
    private let highConfidenceThreshold: Float = 0.9

    // MARK: - Embedding Cache (avoids repeated Core Data fetches)
    private var cachedPeopleEmbeddings: [(person: Person, embedding: [Float])]?
    private var cacheTimestamp: Date = .distantPast
    private let cacheValidityInterval: TimeInterval = 30.0  // Cache valid for 30 seconds

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var lastMatchConfidence: Float = 0.0
    
    // MARK: - Initialization
    
    init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.persistenceController = persistenceController
    }
    
    // MARK: - Voice Embedding Management
    
    /// Save or update voice embedding for a person
    func saveEmbedding(_ embedding: [Float], for person: Person) {
        // Record actual dimension on first save; warn on mismatch
        let storedDim = embeddingDimension
        if embedding.count != storedDim {
            if UserDefaults.standard.integer(forKey: "VoicePrintEmbeddingDimension") == 0 {
                // First embedding ever — record the dimension
                UserDefaults.standard.set(embedding.count, forKey: "VoicePrintEmbeddingDimension")
                print("[VoicePrintManager] 📐 Learned embedding dimension: \(embedding.count)")
            } else {
                print("[VoicePrintManager] ⚠️ Embedding dimension changed: \(embedding.count) vs stored \(storedDim). Updating.")
                UserDefaults.standard.set(embedding.count, forKey: "VoicePrintEmbeddingDimension")
                invalidateCache()
            }
        }

        let context = persistenceController.container.viewContext
        
        // Serialize embedding to Data
        let embeddingData = embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        // Update person's voice data
        person.voiceEmbeddings = embeddingData
        person.lastVoiceUpdate = Date()
        
        // Increment sample count
        person.voiceSampleCount += 1
        
        // Update confidence based on sample count
        updateConfidence(for: person)
        
        // Save context
        do {
            try context.save()
            // Invalidate cache so next lookup picks up the new embedding
            invalidateCache()
            print("[VoicePrintManager] Saved voice embedding for \(person.wrappedName)")
        } catch {
            print("[VoicePrintManager] Error saving embedding: \(error)")
        }
    }
    
    /// Add multiple embeddings and average them for better accuracy
    func addEmbeddings(_ embeddings: [[Float]], for person: Person) {
        guard !embeddings.isEmpty else { return }
        
        // Average multiple embeddings for better representation
        let averagedEmbedding = averageEmbeddings(embeddings)
        
        // If person already has embeddings, merge with existing
        if let existingData = person.voiceEmbeddings,
           let existingEmbedding = deserializeEmbedding(from: existingData) {
            // Weighted average: give more weight to new samples
            let weight = min(0.3, 1.0 / Float(person.voiceSampleCount + 1))
            let mergedEmbedding = zip(existingEmbedding, averagedEmbedding).map { existing, new in
                existing * (1 - weight) + new * weight
            }
            saveEmbedding(mergedEmbedding, for: person)
        } else {
            saveEmbedding(averagedEmbedding, for: person)
        }
    }
    
    /// Refresh the embeddings cache from Core Data
    private func refreshEmbeddingsCache() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "voiceEmbeddings != nil")

        do {
            let people = try context.fetch(request)
            var cached: [(person: Person, embedding: [Float])] = []

            for person in people {
                if let storedData = person.voiceEmbeddings,
                   let embedding = deserializeEmbedding(from: storedData) {
                    cached.append((person: person, embedding: embedding))
                }
            }

            cachedPeopleEmbeddings = cached
            cacheTimestamp = Date()
            print("[VoicePrintManager] 📦 Refreshed cache with \(cached.count) people")
        } catch {
            print("[VoicePrintManager] ❌ Error refreshing cache: \(error)")
            cachedPeopleEmbeddings = nil
        }
    }

    /// Invalidate the cache (call after saving new embeddings)
    func invalidateCache() {
        cachedPeopleEmbeddings = nil
        cacheTimestamp = .distantPast
    }

    /// Find matching person for a given embedding (uses caching to avoid repeated Core Data fetches)
    func findMatchingPerson(for embedding: [Float]) -> (Person?, Float)? {
        guard !embedding.isEmpty else {
            print("[VoicePrintManager] ❌ Empty embedding")
            return nil
        }

        // Check if cache needs refresh
        let now = Date()
        if cachedPeopleEmbeddings == nil || now.timeIntervalSince(cacheTimestamp) > cacheValidityInterval {
            refreshEmbeddingsCache()
        }

        guard let cached = cachedPeopleEmbeddings, !cached.isEmpty else {
            print("[VoicePrintManager] ⚠️ No people with voice embeddings in database - voice learning not started yet")
            return nil
        }

        print("[VoicePrintManager] 🔍 Searching \(cached.count) cached voice embeddings...")

        var bestMatch: (Person, Float)?
        var allMatches: [(String, Float)] = []  // For debug logging

        for (person, storedEmbedding) in cached {
            // Skip mismatched dimensions instead of silently failing
            guard embedding.count == storedEmbedding.count else {
                print("[VoicePrintManager] ⚠️ Dimension mismatch for \(person.wrappedName): \(embedding.count) vs \(storedEmbedding.count), skipping")
                continue
            }

            // Calculate cosine similarity
            let similarity = cosineSimilarity(embedding, storedEmbedding)

            // Apply confidence weighting based on voice sample count
            let weightedSimilarity = similarity * person.voiceConfidence

            allMatches.append((person.wrappedName, weightedSimilarity))

            if weightedSimilarity > minimumConfidenceThreshold {
                if bestMatch == nil || weightedSimilarity > bestMatch!.1 {
                    bestMatch = (person, weightedSimilarity)
                }
            }
        }

        // Log all comparisons for debugging
        let sortedMatches = allMatches.sorted { $0.1 > $1.1 }
        for (name, score) in sortedMatches.prefix(3) {
            let status = score >= minimumConfidenceThreshold ? "✓" : "✗"
            print("[VoicePrintManager]   \(status) \(name): \(String(format: "%.1f%%", score * 100))")
        }

        if let match = bestMatch {
            lastMatchConfidence = match.1
            print("[VoicePrintManager] ✅ Best match: \(match.0.wrappedName) with confidence \(String(format: "%.1f%%", match.1 * 100))")
            return match
        } else {
            print("[VoicePrintManager] ❌ No match above \(String(format: "%.0f%%", minimumConfidenceThreshold * 100)) threshold")
        }

        return nil
    }
    
    /// Match multiple embeddings to a list of expected attendees
    func matchToAttendees(_ embeddings: [String: [Float]], attendeeNames: [String]) -> [String: Person] {
        var matches: [String: Person] = [:]
        
        // First, try to find existing people by name
        let context = persistenceController.container.viewContext
        var attendeePeople: [Person] = []
        
        for name in attendeeNames {
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
            
            if let people = try? context.fetch(request), let person = people.first {
                attendeePeople.append(person)
            }
        }
        
        // Now match embeddings to people
        for (speakerId, embedding) in embeddings {
            // First try matching against expected attendees with voice data
            var bestMatch: (Person, Float)?
            
            for person in attendeePeople where person.voiceEmbeddings != nil {
                if let storedData = person.voiceEmbeddings,
                   let storedEmbedding = deserializeEmbedding(from: storedData) {
                    let similarity = cosineSimilarity(embedding, storedEmbedding)
                    let weightedSimilarity = similarity * person.voiceConfidence
                    
                    if weightedSimilarity > minimumConfidenceThreshold {
                        if bestMatch == nil || weightedSimilarity > bestMatch!.1 {
                            bestMatch = (person, weightedSimilarity)
                        }
                    }
                }
            }
            
            // If no match among attendees, search all people
            if bestMatch == nil {
                if let match = findMatchingPerson(for: embedding) {
                    // match is (Person?, Float) but bestMatch needs (Person, Float)
                    // Only assign if we have a valid Person
                    if let person = match.0 {
                        bestMatch = (person, match.1)
                    }
                }
            }
            
            if let match = bestMatch {
                matches[speakerId] = match.0
            }
        }
        
        return matches
    }
    
    // MARK: - Progressive Learning with Feedback Loop

    /// Save embedding with boosted weight when user confirms a voice match
    /// This improves learning speed when users validate auto-identifications
    func saveEmbeddingWithFeedback(_ embedding: [Float], for person: Person, wasConfirmed: Bool) {
        guard !embedding.isEmpty else {
            print("[VoicePrintManager] Empty embedding in feedback save")
            return
        }

        // Determine learning weight based on feedback
        let feedbackBoost: Float = wasConfirmed ? 1.5 : 1.0  // 50% boost for confirmed matches

        if let existingData = person.voiceEmbeddings,
           let existingEmbedding = deserializeEmbedding(from: existingData) {
            // Weighted average with feedback boost
            let baseWeight = min(0.3, 1.0 / Float(person.voiceSampleCount + 1))
            let effectiveWeight = min(baseWeight * feedbackBoost, 0.5)  // Cap at 50%

            let mergedEmbedding = zip(existingEmbedding, embedding).map { existing, new in
                existing * (1 - effectiveWeight) + new * effectiveWeight
            }
            saveEmbedding(mergedEmbedding, for: person)

            if wasConfirmed {
                // Boost confidence for confirmed matches
                person.voiceConfidence = min(person.voiceConfidence + 0.1, 1.0)
                print("[VoicePrintManager] ✅ Boosted learning for \(person.wrappedName) (confirmed match)")
            }
        } else {
            saveEmbedding(embedding, for: person)
        }
    }

    /// Record negative feedback when a voice match was incorrect
    /// This doesn't change the embedding but logs for potential future use
    func recordIncorrectMatch(for person: Person, incorrectEmbedding: [Float]) {
        // For now, just log the incorrect match
        // Future: could track embeddings that should NOT match this person
        print("[VoicePrintManager] ⚠️ Incorrect match recorded for \(person.wrappedName)")

        // Slightly reduce confidence when mistakes happen (cap at minimum 0.3)
        person.voiceConfidence = max(person.voiceConfidence - 0.05, 0.3)
    }

    /// Update confidence for a person based on sample count and quality
    func updateConfidence(for person: Person, with newEmbedding: [Float]? = nil) {
        // Base confidence on number of samples
        let sampleConfidence = min(Float(person.voiceSampleCount) / 10.0, 1.0)
        
        // If we have a new embedding, check consistency with existing
        var consistencyScore: Float = 1.0
        if let newEmbedding = newEmbedding,
           let existingData = person.voiceEmbeddings,
           let existingEmbedding = deserializeEmbedding(from: existingData) {
            consistencyScore = cosineSimilarity(newEmbedding, existingEmbedding)
        }
        
        // Combined confidence
        person.voiceConfidence = sampleConfidence * 0.7 + consistencyScore * 0.3
        
        print("[VoicePrintManager] Updated confidence for \(person.wrappedName): \(person.voiceConfidence)")
    }
    
    /// Check if a person needs more voice samples
    func needsMoreSamples(_ person: Person) -> Bool {
        return person.voiceSampleCount < 3 || person.voiceConfidence < 0.8
    }
    
    // MARK: - Helper Methods
    
    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
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
    
    /// Average multiple embeddings
    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        
        let dimension = embeddings[0].count
        var averaged = [Float](repeating: 0, count: dimension)
        
        for embedding in embeddings {
            for i in 0..<dimension {
                averaged[i] += embedding[i]
            }
        }
        
        let count = Float(embeddings.count)
        return averaged.map { $0 / count }
    }
    
    /// Deserialize embedding from Data
    private func deserializeEmbedding(from data: Data) -> [Float]? {
        guard data.count == embeddingDimension * MemoryLayout<Float>.size else {
            print("[VoicePrintManager] Invalid data size for embedding")
            return nil
        }
        
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
    
    // MARK: - Batch Operations
    
    /// Pre-load embeddings for expected participants
    func preloadEmbeddings(for people: [Person]) -> [UUID: [Float]] {
        var embeddings: [UUID: [Float]] = [:]
        
        for person in people {
            if let data = person.voiceEmbeddings,
               let embedding = deserializeEmbedding(from: data) {
                embeddings[person.id] = embedding
                print("[VoicePrintManager] Pre-loaded embedding for \(person.wrappedName)")
            }
        }
        
        return embeddings
    }
    
    /// Clear all voice data (for privacy/reset)
    func clearAllVoiceData() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "voiceEmbeddings != nil")
        
        do {
            let people = try context.fetch(request)
            for person in people {
                person.voiceEmbeddings = nil
                person.voiceConfidence = 0
                person.voiceSampleCount = 0
                person.lastVoiceUpdate = nil
            }
            try context.save()
            print("[VoicePrintManager] Cleared all voice data")
        } catch {
            print("[VoicePrintManager] Error clearing voice data: \(error)")
        }
    }
}

// MARK: - Voice Learning System

/// Manages progressive improvement of voice models
class VoiceLearningSystem {
    private let voicePrintManager: VoicePrintManager
    private let persistenceController: PersistenceController
    
    init(voicePrintManager: VoicePrintManager = VoicePrintManager(),
         persistenceController: PersistenceController = PersistenceController.shared) {
        self.voicePrintManager = voicePrintManager
        self.persistenceController = persistenceController
    }
    
    /// Process completed meeting to improve voice models
    func improveModels(from meeting: CompletedMeeting) {
        guard let confirmedParticipants = meeting.confirmedParticipants else { return }
        
        for participant in confirmedParticipants {
            if let person = participant.person,
               let embeddings = participant.voiceEmbeddings {
                // Add new embeddings to person's model
                voicePrintManager.addEmbeddings(embeddings, for: person)
                
                print("[VoiceLearning] Improved model for \(person.wrappedName)")
            }
        }
    }
    
    /// Generate learning recommendations
    func getLearningRecommendations() -> [VoiceLearningRecommendation] {
        var recommendations: [VoiceLearningRecommendation] = []
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        
        if let people = try? context.fetch(request) {
            for person in people {
                if person.voiceSampleCount == 0 {
                    recommendations.append(VoiceLearningRecommendation(
                        person: person,
                        type: .noSamples,
                        priority: .high,
                        message: "No voice samples yet. Record a meeting with \(person.wrappedName) to enable voice recognition."
                    ))
                } else if voicePrintManager.needsMoreSamples(person) {
                    recommendations.append(VoiceLearningRecommendation(
                        person: person,
                        type: .needsMoreSamples,
                        priority: .medium,
                        message: "\(person.wrappedName) needs \(3 - person.voiceSampleCount) more voice samples for reliable recognition."
                    ))
                }
            }
        }
        
        return recommendations.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }
}

// MARK: - Supporting Types

/// Represents a completed meeting with confirmed participants
struct CompletedMeeting {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let confirmedParticipants: [ConfirmedParticipant]?
}

/// Represents a confirmed participant with voice data
struct ConfirmedParticipant {
    let person: Person?
    let speakerId: String
    let voiceEmbeddings: [[Float]]?
    let speakingDuration: TimeInterval
}

/// Voice learning recommendation
struct VoiceLearningRecommendation {
    let person: Person
    let type: RecommendationType
    let priority: Priority
    let message: String
    
    enum RecommendationType {
        case noSamples
        case needsMoreSamples
        case lowConfidence
        case inconsistentSamples
    }
    
    enum Priority: Int {
        case high = 0
        case medium = 1
        case low = 2
    }
}

// MARK: - VoicePrintManager Extensions for Learning

extension VoicePrintManager {
    
    /// Deserialize embeddings from Core Data binary data
    func deserializeEmbeddings(from data: Data) -> [[Float]]? {
        do {
            let embeddings = try JSONDecoder().decode([[Float]].self, from: data)
            return embeddings
        } catch {
            print("❌ Failed to deserialize embeddings: \(error)")
            return nil
        }
    }
    
    /// Serialize embeddings for Core Data storage
    func serializeEmbeddings(_ embeddings: [[Float]]) -> Data? {
        do {
            let data = try JSONEncoder().encode(embeddings)
            return data
        } catch {
            print("❌ Failed to serialize embeddings: \(error)")
            return nil
        }
    }
    
    /// Get stored embedding for a person (for pre-loading)
    func getStoredEmbedding(for person: Person) -> [Float]? {
        guard let data = person.voiceEmbeddings else { return nil }
        return deserializeEmbedding(from: data)
    }
}