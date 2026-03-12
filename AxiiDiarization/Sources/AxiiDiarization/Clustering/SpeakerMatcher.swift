import Accelerate
import Foundation

/// Matches cluster centroids against known speaker profiles and tracks discovered speakers.
final class SpeakerMatcher {

    struct MatchResult {
        let id: String
        let confidence: Float
    }

    private var knownSpeakers: [any SpeakerProfile]
    private let defaultThreshold: Float

    /// Speakers discovered during the session (not pre-loaded)
    private var discoveredSpeakers: [(id: String, embedding: [Float])] = []

    init(knownSpeakers: [any SpeakerProfile], threshold: Float) {
        self.knownSpeakers = knownSpeakers
        self.defaultThreshold = threshold
    }

    /// Match a cluster centroid against known speakers.
    func matchCluster(centroid: [Float], threshold: Float) -> MatchResult? {
        var bestMatch: MatchResult?

        for profile in knownSpeakers {
            // Best-of-N: compare against all stored embeddings for this profile
            var bestSim: Float = 0
            for storedEmb in profile.embeddings {
                let sim = cosineSimilarity(centroid, storedEmb)
                bestSim = max(bestSim, sim)
            }

            if bestSim >= threshold {
                if bestMatch == nil || bestSim > bestMatch!.confidence {
                    bestMatch = MatchResult(id: profile.id, confidence: bestSim)
                }
            }
        }

        return bestMatch
    }

    /// Match a single embedding against known + discovered speakers.
    func match(embedding: [Float], threshold: Float) -> (any SpeakerProfile)? {
        var bestProfile: (any SpeakerProfile)?
        var bestSim: Float = threshold

        for profile in knownSpeakers {
            for storedEmb in profile.embeddings {
                let sim = cosineSimilarity(embedding, storedEmb)
                if sim > bestSim {
                    bestSim = sim
                    bestProfile = profile
                }
            }
        }

        return bestProfile
    }

    /// Register a speaker discovered during clustering (for future matching).
    func registerDiscoveredSpeaker(id: String, embedding: [Float]) {
        // Don't duplicate
        if !discoveredSpeakers.contains(where: { $0.id == id }) {
            discoveredSpeakers.append((id: id, embedding: embedding))
        } else {
            // Update embedding
            if let idx = discoveredSpeakers.firstIndex(where: { $0.id == id }) {
                discoveredSpeakers[idx] = (id: id, embedding: embedding)
            }
        }
    }

    // MARK: - Helpers

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
