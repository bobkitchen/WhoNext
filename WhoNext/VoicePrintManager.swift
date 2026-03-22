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
    /// Cache stores value types (not managed objects) so it's safe across contexts
    /// Each person stores all individual embeddings for best-of-N matching
    private var cachedEmbeddingsData: [(personId: UUID, name: String, embeddings: [[Float]], confidence: Float)]?
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
                debugLog("[VoicePrintManager] 📐 Learned embedding dimension: \(embedding.count)")
            } else {
                debugLog("[VoicePrintManager] ⚠️ Embedding dimension changed: \(embedding.count) vs stored \(storedDim). Updating.")
                UserDefaults.standard.set(embedding.count, forKey: "VoicePrintEmbeddingDimension")
                invalidateCache()
            }
        }

        let context = persistenceController.container.viewContext
        
        // Use JSON serialization (matches Person.addVoiceEmbedding format)
        person.addVoiceEmbedding(embedding)
        
        // Save context
        do {
            try context.save()
            // Invalidate cache so next lookup picks up the new embedding
            invalidateCache()
            debugLog("[VoicePrintManager] Saved voice embedding for \(person.wrappedName)")
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
    
    /// Refresh the embeddings cache from Core Data on a background context
    /// Stores all individual embeddings per person for best-of-N matching
    private func refreshEmbeddingsCache() async {
        await withCheckedContinuation { continuation in
            persistenceController.container.performBackgroundTask { context in
                let request: NSFetchRequest<Person> = Person.fetchRequest()
                request.predicate = NSPredicate(format: "voiceEmbeddings != nil")

                do {
                    let people = try context.fetch(request)
                    var cached: [(personId: UUID, name: String, embeddings: [[Float]], confidence: Float)] = []

                    for person in people {
                        if let storedData = person.voiceEmbeddings,
                           let id = person.identifier {
                            // Try to get all individual embeddings first (best-of-N)
                            if let allEmbeddings = self.deserializeAllEmbeddings(from: storedData), !allEmbeddings.isEmpty {
                                cached.append((
                                    personId: id,
                                    name: person.wrappedName,
                                    embeddings: allEmbeddings,
                                    confidence: person.voiceConfidence
                                ))
                            } else if let singleEmbedding = self.deserializeEmbedding(from: storedData) {
                                // Fallback: wrap single averaged embedding
                                cached.append((
                                    personId: id,
                                    name: person.wrappedName,
                                    embeddings: [singleEmbedding],
                                    confidence: person.voiceConfidence
                                ))
                            }
                        }
                    }

                    self.cachedEmbeddingsData = cached
                    self.cacheTimestamp = Date()
                    debugLog("[VoicePrintManager] Refreshed cache with \(cached.count) people (background, best-of-N)")
                } catch {
                    print("[VoicePrintManager] Error refreshing cache: \(error)")
                    self.cachedEmbeddingsData = nil
                }
                continuation.resume()
            }
        }
    }

    /// Invalidate the cache (call after saving new embeddings)
    func invalidateCache() {
        cachedEmbeddingsData = nil
        cacheTimestamp = .distantPast
    }

    /// Pre-warm the cache so first diarization chunk doesn't block
    func warmCache() async {
        await refreshEmbeddingsCache()
    }

    /// Find matching person for a given embedding (uses caching to avoid repeated Core Data fetches)
    func findMatchingPerson(for embedding: [Float]) async -> (Person?, Float)? {
        guard !embedding.isEmpty else {
            print("[VoicePrintManager] ❌ Empty embedding")
            return nil
        }

        // Check if cache needs refresh
        let now = Date()
        if cachedEmbeddingsData == nil || now.timeIntervalSince(cacheTimestamp) > cacheValidityInterval {
            await refreshEmbeddingsCache()
        }

        guard let cached = cachedEmbeddingsData, !cached.isEmpty else {
            debugLog("[VoicePrintManager] ⚠️ No people with voice embeddings in database - voice learning not started yet")
            return nil
        }

        debugLog("[VoicePrintManager] Searching \(cached.count) cached voice embeddings (best-of-N)...")

        var bestMatch: (personId: UUID, name: String, similarity: Float)?
        var allMatches: [(String, Float)] = []  // For debug logging

        for entry in cached {
            // Best-of-N: find the maximum similarity across all stored embeddings
            let similarity = bestOfNSimilarity(embedding, stored: entry.embeddings)

            allMatches.append((entry.name, similarity))

            if similarity > minimumConfidenceThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (personId: entry.personId, name: entry.name, similarity: similarity)
                }
            }
        }

        // Log all comparisons for debugging
        let sortedMatches = allMatches.sorted { $0.1 > $1.1 }
        for (name, score) in sortedMatches.prefix(3) {
            let status = score >= minimumConfidenceThreshold ? "✓" : "✗"
            debugLog("[VoicePrintManager]   \(status) \(name): \(String(format: "%.1f%%", score * 100))")
        }

        if let match = bestMatch {
            lastMatchConfidence = match.similarity
            debugLog("[VoicePrintManager] ✅ Best match: \(match.name) with confidence \(String(format: "%.1f%%", match.similarity * 100))")
            let context = persistenceController.container.viewContext
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "identifier == %@", match.personId as CVarArg)
            let person = try? context.fetch(request).first
            return (person, match.similarity)
        } else {
            print("[VoicePrintManager] ❌ No match above \(String(format: "%.0f%%", minimumConfidenceThreshold * 100)) threshold")
        }

        return nil
    }
    
    /// Match multiple embeddings to a list of expected attendees
    func matchToAttendees(_ embeddings: [String: [Float]], attendeeNames: [String]) async -> [String: Person] {
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
                   let storedEmbeddings = deserializeAllEmbeddings(from: storedData) {
                    let weightedSimilarity = bestOfNSimilarity(embedding, stored: storedEmbeddings)
                    
                    if weightedSimilarity > minimumConfidenceThreshold {
                        if bestMatch == nil || weightedSimilarity > bestMatch!.1 {
                            bestMatch = (person, weightedSimilarity)
                        }
                    }
                }
            }
            
            // If no match among attendees, search all people
            if bestMatch == nil {
                if let match = await findMatchingPerson(for: embedding) {
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
            debugLog("[VoicePrintManager] Empty embedding in feedback save")
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
                debugLog("[VoicePrintManager] ✅ Boosted learning for \(person.wrappedName) (confirmed match)")
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
        debugLog("[VoicePrintManager] ⚠️ Incorrect match recorded for \(person.wrappedName)")

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
        
        debugLog("[VoicePrintManager] Updated confidence for \(person.wrappedName): \(person.voiceConfidence)")
    }
    
    /// Check if a person needs more voice samples
    func needsMoreSamples(_ person: Person) -> Bool {
        return person.voiceSampleCount < 3 || person.voiceConfidence < 0.8
    }
    
    // MARK: - Helper Methods

    /// Deserialize all individual embeddings from stored data (for best-of-N matching)
    /// Returns individual embeddings without averaging, unlike deserializeEmbedding()
    private func deserializeAllEmbeddings(from data: Data) -> [[Float]]? {
        // Try JSON array-of-arrays format (current standard)
        if let embeddings = try? JSONDecoder().decode([[Float]].self, from: data), !embeddings.isEmpty {
            return embeddings
        }
        // Try single-array JSON format (wrap in array)
        if let single = try? JSONDecoder().decode([Float].self, from: data) {
            return [single]
        }
        return nil
    }

    /// Best-of-N similarity: returns max cosine similarity across all stored embeddings
    /// If even one clean embedding is stored, this finds it (unlike averaging which dilutes)
    private func bestOfNSimilarity(_ query: [Float], stored: [[Float]]) -> Float {
        var maxSimilarity: Float = 0
        for storedEmbedding in stored {
            guard query.count == storedEmbedding.count else { continue }
            let similarity = cosineSimilarity(query, storedEmbedding)
            if similarity > maxSimilarity {
                maxSimilarity = similarity
            }
        }
        return maxSimilarity
    }

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        VectorMath.cosineSimilarity(a, b)
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
    
    /// Deserialize embedding from Data (JSON format, with raw binary fallback for migration)
    private func deserializeEmbedding(from data: Data) -> [Float]? {
        // Try JSON format first (current standard)
        if let embeddings = try? JSONDecoder().decode([[Float]].self, from: data) {
            // Return the average of all stored embeddings
            guard !embeddings.isEmpty else { return nil }
            let size = embeddings[0].count
            var average = [Float](repeating: 0, count: size)
            for embedding in embeddings {
                for i in 0..<min(embedding.count, size) {
                    average[i] += embedding[i]
                }
            }
            let count = Float(embeddings.count)
            return average.map { $0 / count }
        }

        // Try single-array JSON format
        if let single = try? JSONDecoder().decode([Float].self, from: data) {
            return single
        }

        // Fallback: raw binary format (legacy migration)
        guard data.count == embeddingDimension * MemoryLayout<Float>.size else {
            debugLog("[VoicePrintManager] Invalid data size for embedding: \(data.count) bytes")
            return nil
        }
        let rawEmbedding = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        debugLog("[VoicePrintManager] ⚠️ Migrated raw binary embedding to JSON format")
        return rawEmbedding
    }
    
    // MARK: - Batch Operations
    
    /// Pre-load embeddings for expected participants
    func preloadEmbeddings(for people: [Person]) -> [UUID: [Float]] {
        var embeddings: [UUID: [Float]] = [:]
        
        for person in people {
            if let data = person.voiceEmbeddings,
               let embedding = deserializeEmbedding(from: data) {
                embeddings[person.id] = embedding
                debugLog("[VoicePrintManager] Pre-loaded embedding for \(person.wrappedName)")
            }
        }
        
        return embeddings
    }
    
    /// Find a Person record by name (case-insensitive) that has stored voice embeddings.
    /// Used by guided diarization to match calendar attendee names to voice profiles.
    func findMatchingPersonByName(_ name: String) async -> Person? {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        // Case-insensitive name match with voice data
        request.predicate = NSPredicate(
            format: "name ==[cd] %@ AND voiceEmbeddings != nil",
            name
        )
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("[VoicePrintManager] Error finding person by name '\(name)': \(error)")
            return nil
        }
    }

    /// Get all stored voice embeddings as (id, name, embedding) tuples.
    /// Used as a fallback when no calendar-matched speakers are available for guided diarization.
    func getAllStoredEmbeddings() async -> [(id: String, name: String, embedding: [Float])] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "voiceEmbeddings != nil")

        do {
            let people = try context.fetch(request)
            return people.compactMap { person in
                guard let data = person.voiceEmbeddings,
                      let embedding = deserializeEmbedding(from: data) else { return nil }
                return (
                    id: person.identifier?.uuidString ?? UUID().uuidString,
                    name: person.wrappedName,
                    embedding: embedding
                )
            }
        } catch {
            print("[VoicePrintManager] Error fetching all embeddings: \(error)")
            return []
        }
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
            debugLog("[VoicePrintManager] Cleared all voice data")
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
                
                debugLog("[VoiceLearning] Improved model for \(person.wrappedName)")
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