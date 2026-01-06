import Foundation
import CoreData

@objc(UserProfileEntity)
public class UserProfileEntity: NSManagedObject, @unchecked Sendable {

    // MARK: - Singleton Access

    /// Fetches or creates the single UserProfile entity
    static func getOrCreate(in context: NSManagedObjectContext) -> UserProfileEntity {
        let fetchRequest: NSFetchRequest<UserProfileEntity> = UserProfileEntity.fetchRequest()
        fetchRequest.fetchLimit = 1

        do {
            if let existing = try context.fetch(fetchRequest).first {
                return existing
            }
        } catch {
            print("Error fetching UserProfileEntity: \(error)")
        }

        // Create new if none exists
        let newProfile = UserProfileEntity(context: context)
        newProfile.identifier = UUID()
        newProfile.createdAt = Date()
        newProfile.modifiedAt = Date()
        return newProfile
    }

    // MARK: - Voice Embedding Helpers

    /// Get voice embedding as Float array
    var voiceEmbeddingArray: [Float]? {
        get {
            guard let data = voiceEmbedding else { return nil }
            return data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }
        set {
            guard let array = newValue else {
                voiceEmbedding = nil
                return
            }
            voiceEmbedding = array.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }
    }

    /// Add a voice sample and update the embedding
    func addVoiceSample(_ embedding: [Float]) {
        if let existing = voiceEmbeddingArray {
            // Weighted average: give more weight to existing profile
            let weight = min(0.2, 1.0 / Float(voiceSampleCount + 1))
            voiceEmbeddingArray = zip(existing, embedding).map { old, new in
                old * (1 - weight) + new * weight
            }
        } else {
            voiceEmbeddingArray = embedding
        }

        voiceSampleCount += 1
        lastVoiceUpdate = Date()
        modifiedAt = Date()

        // Update confidence based on sample count
        updateVoiceConfidence()
    }

    /// Clear voice profile
    func clearVoiceProfile() {
        voiceEmbedding = nil
        voiceConfidence = 0.0
        voiceSampleCount = 0
        lastVoiceUpdate = nil
        modifiedAt = Date()
    }

    /// Match a given embedding against the user's voice profile
    func matchesUserVoice(_ embedding: [Float], threshold: Float = 0.7) -> (matches: Bool, confidence: Float) {
        guard let userEmbedding = voiceEmbeddingArray else {
            return (false, 0.0)
        }

        let similarity = cosineSimilarity(userEmbedding, embedding)
        return (similarity >= threshold, similarity)
    }

    // MARK: - Private Methods

    private func updateVoiceConfidence() {
        // Confidence improves with more samples, plateaus around 10 samples
        let sampleFactor = min(Float(voiceSampleCount) / 10.0, 1.0)
        voiceConfidence = 0.5 + (sampleFactor * 0.5) // Range: 0.5 - 1.0
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Update Helper

    /// Mark as modified for sync
    func markModified() {
        modifiedAt = Date()
    }
}
