import Foundation
import CoreData

@objc(UserProfileEntity)
public class UserProfileEntity: NSManagedObject, @unchecked Sendable {

    // MARK: - Singleton Access

    /// Constant identifier for the singleton UserProfile
    /// Using a fixed UUID ensures all devices reference the same CloudKit record
    static let singletonIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Fetches or creates the single UserProfile entity
    /// Handles merging if multiple profiles exist (from before this fix)
    static func getOrCreate(in context: NSManagedObjectContext) -> UserProfileEntity {
        let fetchRequest: NSFetchRequest<UserProfileEntity> = UserProfileEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]

        do {
            let allProfiles = try context.fetch(fetchRequest)

            if allProfiles.isEmpty {
                // No profiles exist - create one with the singleton identifier
                print("👤 [UserProfile] Creating new singleton profile")
                return createSingletonProfile(in: context)
            }

            // Check if we have the canonical singleton
            if let singleton = allProfiles.first(where: { $0.identifier == singletonIdentifier }) {
                // Merge any other profiles into the singleton, then delete them
                let duplicates = allProfiles.filter { $0.identifier != singletonIdentifier }
                if !duplicates.isEmpty {
                    print("👤 [UserProfile] Found \(duplicates.count) duplicate profile(s) - merging...")
                    mergeDuplicates(duplicates, into: singleton, context: context)
                }
                return singleton
            }

            // No singleton exists yet - migrate the most recent profile to become the singleton
            let mostRecent = allProfiles[0] // Already sorted by modifiedAt descending
            print("👤 [UserProfile] Migrating existing profile to singleton identifier")
            mostRecent.identifier = singletonIdentifier

            // Merge any other profiles into this one, then delete them
            let duplicates = Array(allProfiles.dropFirst())
            if !duplicates.isEmpty {
                print("👤 [UserProfile] Merging \(duplicates.count) duplicate profile(s)")
                mergeDuplicates(duplicates, into: mostRecent, context: context)
            }

            try? context.save()
            return mostRecent

        } catch {
            print("👤 [UserProfile] Error fetching profiles: \(error)")
            return createSingletonProfile(in: context)
        }
    }

    /// Create a new singleton profile with the constant identifier
    private static func createSingletonProfile(in context: NSManagedObjectContext) -> UserProfileEntity {
        let newProfile = UserProfileEntity(context: context)
        newProfile.identifier = singletonIdentifier
        newProfile.createdAt = Date()
        newProfile.modifiedAt = Date()
        return newProfile
    }

    /// Merge duplicate profiles into the primary one, preferring non-nil/non-empty values
    /// Uses modifiedAt to prefer more recently updated data
    private static func mergeDuplicates(_ duplicates: [UserProfileEntity], into primary: UserProfileEntity, context: NSManagedObjectContext) {
        for duplicate in duplicates {
            // Merge text fields - prefer non-empty values, use modifiedAt as tiebreaker
            if let dupModified = duplicate.modifiedAt, let primaryModified = primary.modifiedAt {
                let dupIsNewer = dupModified > primaryModified

                // Name
                if (primary.name ?? "").isEmpty && !(duplicate.name ?? "").isEmpty {
                    primary.name = duplicate.name
                    print("👤 [UserProfile] Merged name from duplicate: \(duplicate.name ?? "")")
                } else if dupIsNewer && !(duplicate.name ?? "").isEmpty {
                    primary.name = duplicate.name
                    print("👤 [UserProfile] Using newer name: \(duplicate.name ?? "")")
                }

                // Email
                if (primary.email ?? "").isEmpty && !(duplicate.email ?? "").isEmpty {
                    primary.email = duplicate.email
                    print("👤 [UserProfile] Merged email from duplicate")
                } else if dupIsNewer && !(duplicate.email ?? "").isEmpty {
                    primary.email = duplicate.email
                }

                // Job Title
                if (primary.jobTitle ?? "").isEmpty && !(duplicate.jobTitle ?? "").isEmpty {
                    primary.jobTitle = duplicate.jobTitle
                } else if dupIsNewer && !(duplicate.jobTitle ?? "").isEmpty {
                    primary.jobTitle = duplicate.jobTitle
                }

                // Organization
                if (primary.organization ?? "").isEmpty && !(duplicate.organization ?? "").isEmpty {
                    primary.organization = duplicate.organization
                } else if dupIsNewer && !(duplicate.organization ?? "").isEmpty {
                    primary.organization = duplicate.organization
                }

                // Photo - prefer non-nil, then newer
                if primary.photo == nil && duplicate.photo != nil {
                    primary.photo = duplicate.photo
                } else if dupIsNewer && duplicate.photo != nil {
                    primary.photo = duplicate.photo
                }

                // Voice data - prefer profile with more samples, or newer if equal
                if duplicate.voiceSampleCount > primary.voiceSampleCount {
                    primary.voiceEmbedding = duplicate.voiceEmbedding
                    primary.voiceConfidence = duplicate.voiceConfidence
                    primary.voiceSampleCount = duplicate.voiceSampleCount
                    primary.lastVoiceUpdate = duplicate.lastVoiceUpdate
                    print("👤 [UserProfile] Using voice data with \(duplicate.voiceSampleCount) samples")
                } else if duplicate.voiceSampleCount == primary.voiceSampleCount && dupIsNewer && duplicate.voiceEmbedding != nil {
                    primary.voiceEmbedding = duplicate.voiceEmbedding
                    primary.voiceConfidence = duplicate.voiceConfidence
                    primary.voiceSampleCount = duplicate.voiceSampleCount
                    primary.lastVoiceUpdate = duplicate.lastVoiceUpdate
                }

                // Update modifiedAt to the newer of the two
                if dupIsNewer {
                    primary.modifiedAt = dupModified
                }
            }

            // Delete the duplicate
            context.delete(duplicate)
            print("👤 [UserProfile] Deleted duplicate profile")
        }

        // Save after merge
        do {
            if context.hasChanges {
                try context.save()
                print("👤 [UserProfile] Merge completed and saved")
            }
        } catch {
            print("👤 [UserProfile] Error saving after merge: \(error)")
        }
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
