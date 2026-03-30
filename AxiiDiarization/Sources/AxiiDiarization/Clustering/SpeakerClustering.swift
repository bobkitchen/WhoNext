import Accelerate
import Foundation
import os

private let clusterLog = Logger(subsystem: "com.axii.diarization", category: "clustering")

/// Agglomerative hierarchical clustering using cosine similarity.
/// Maintains stable cluster IDs across incremental calls.
final class SpeakerClustering {

    /// Cluster centroids from previous run, keyed by cluster label
    private var previousCentroids: [Int: [Float]] = [:]
    private var nextClusterLabel: Int = 0

    /// Cluster a set of embeddings.
    /// - Parameters:
    ///   - embeddings: Array of speaker embedding vectors
    ///   - threshold: Cosine similarity threshold for merging clusters
    /// - Returns: Array of cluster labels (one per embedding), stable across calls
    func cluster(embeddings: [[Float]], threshold: Float) -> [Int] {
        let n = embeddings.count
        guard n > 0 else { return [] }
        guard n > 1 else {
            let label = assignLabel(for: embeddings[0])
            return [label]
        }

        // Initial assignment: each embedding in its own cluster
        var labels = Array(0..<n)
        var centroids: [Int: [Float]] = [:]
        for i in 0..<n {
            centroids[i] = embeddings[i]
        }

        // Compute pairwise cosine similarity
        var similarities = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let sim = cosineSimilarity(embeddings[i], embeddings[j])
                similarities[i][j] = sim
                similarities[j][i] = sim
            }
        }

        // Agglomerative clustering: merge most similar pair until below threshold
        var activeClusters = Set(0..<n)
        var mergeCount = 0

        while activeClusters.count > 1 {
            // Find most similar pair
            var bestSim: Float = -1
            var bestI = -1
            var bestJ = -1

            let active = Array(activeClusters).sorted()
            for idx in 0..<active.count {
                for jdx in (idx + 1)..<active.count {
                    let i = active[idx]
                    let j = active[jdx]
                    if let ci = centroids[i], let cj = centroids[j] {
                        let sim = cosineSimilarity(ci, cj)
                        if sim > bestSim {
                            bestSim = sim
                            bestI = i
                            bestJ = j
                        }
                    }
                }
            }

            guard bestSim >= threshold else { break }

            // Merge bestJ into bestI
            let membersI = labels.enumerated().filter { $0.element == bestI }.map { $0.offset }
            let membersJ = labels.enumerated().filter { $0.element == bestJ }.map { $0.offset }

            clusterLog.debug("[Merge] clusters \(bestI)(\(membersI.count) members) + \(bestJ)(\(membersJ.count) members) at similarity \(String(format: "%.3f", bestSim))")

            // Update labels
            for idx in membersJ {
                labels[idx] = bestI
            }

            // Update centroid (average of all members)
            let allMembers = membersI + membersJ
            let memberEmbs = allMembers.map { embeddings[$0] }
            centroids[bestI] = averageCentroid(memberEmbs)
            centroids.removeValue(forKey: bestJ)
            activeClusters.remove(bestJ)
            mergeCount += 1
        }

        clusterLog.info("[Cluster] \(n) embeddings → \(activeClusters.count) clusters after \(mergeCount) merges (threshold=\(String(format: "%.2f", threshold)))")

        // Map local cluster labels to stable global labels
        var localToGlobal: [Int: Int] = [:]
        let uniqueLabels = Set(labels)

        for localLabel in uniqueLabels {
            if let centroid = centroids[localLabel] {
                localToGlobal[localLabel] = assignLabel(for: centroid)
            }
        }

        // Update stored centroids incrementally — do NOT clear all previous centroids.
        // Only update entries that were matched or add new ones.
        for (localLabel, globalLabel) in localToGlobal {
            if let c = centroids[localLabel] {
                previousCentroids[globalLabel] = c
            }
        }

        return labels.map { localToGlobal[$0] ?? assignLabel(for: embeddings[0]) }
    }

    // MARK: - Stable Label Assignment

    /// Assign a global label for a centroid, matching to previous centroids if similar.
    private func assignLabel(for embedding: [Float]) -> Int {
        var bestLabel: Int?
        var bestSim: Float = 0.25  // WeSpeaker on mixed mono audio peaks at ~0.35-0.50 for same-speaker; 0.25 catches label drift

        for (label, centroid) in previousCentroids {
            let sim = cosineSimilarity(embedding, centroid)
            if sim > bestSim {
                bestSim = sim
                bestLabel = label
            }
        }

        if let label = bestLabel {
            clusterLog.debug("[Label] Reusing label \(label) (similarity \(String(format: "%.3f", bestSim)))")
            previousCentroids[label] = embedding
            return label
        }

        let label = nextClusterLabel
        nextClusterLabel += 1
        clusterLog.debug("[Label] New label \(label) (best previous similarity was \(String(format: "%.3f", bestSim)))")
        previousCentroids[label] = embedding
        return label
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

    private func averageCentroid(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        let dim = first.count
        var sum = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            for i in 0..<min(dim, emb.count) {
                sum[i] += emb[i]
            }
        }
        let n = Float(embeddings.count)
        var result = sum.map { $0 / n }
        // L2 normalize
        var norm: Float = 0
        vDSP_dotpr(result, 1, result, 1, &norm, vDSP_Length(dim))
        norm = sqrt(norm)
        if norm > 0 {
            vDSP_vsdiv(result, 1, &norm, &result, 1, vDSP_Length(dim))
        }
        return result
    }
}
