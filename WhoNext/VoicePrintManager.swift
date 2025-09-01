import Foundation
import CoreData
import AVFoundation

/// Manages voice embeddings and speaker identification
/// Links DiarizationManager speaker embeddings to Person records
class VoicePrintManager: ObservableObject {
    
    // MARK: - Properties
    
    private let persistenceController: PersistenceController
    private let embeddingDimension = 256 // Standard dimension for speaker embeddings
    private let minimumConfidenceThreshold: Float = 0.7
    private let highConfidenceThreshold: Float = 0.9
    
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
        guard embedding.count == embeddingDimension else {
            print("[VoicePrintManager] Invalid embedding dimension: \(embedding.count), expected \(embeddingDimension)")
            return
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
    
    /// Find matching person for a given embedding
    func findMatchingPerson(for embedding: [Float]) -> (Person?, Float)? {
        guard embedding.count == embeddingDimension else {
            print("[VoicePrintManager] Invalid embedding dimension for matching")
            return nil
        }
        
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "voiceEmbeddings != nil")
        
        do {
            let people = try context.fetch(request)
            var bestMatch: (Person, Float)?
            
            for person in people {
                guard let storedData = person.voiceEmbeddings,
                      let storedEmbedding = deserializeEmbedding(from: storedData) else {
                    continue
                }
                
                // Calculate cosine similarity
                let similarity = cosineSimilarity(embedding, storedEmbedding)
                
                // Apply confidence weighting
                let weightedSimilarity = similarity * person.voiceConfidence
                
                if weightedSimilarity > minimumConfidenceThreshold {
                    if bestMatch == nil || weightedSimilarity > bestMatch!.1 {
                        bestMatch = (person, weightedSimilarity)
                    }
                }
            }
            
            if let match = bestMatch {
                lastMatchConfidence = match.1
                print("[VoicePrintManager] Found match: \(match.0.wrappedName) with confidence \(match.1)")
                return match
            }
            
        } catch {
            print("[VoicePrintManager] Error searching for matches: \(error)")
        }
        
        return nil
    }
    
    /// Match multiple embeddings to a list of expected attendees
    func matchToAttendees(_ embeddings: [Int: [Float]], attendeeNames: [String]) -> [Int: Person] {
        var matches: [Int: Person] = [:]
        
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
                    bestMatch = match
                }
            }
            
            if let match = bestMatch {
                matches[speakerId] = match.0
            }
        }
        
        return matches
    }
    
    // MARK: - Progressive Learning
    
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
    let speakerId: Int
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