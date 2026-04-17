import Foundation
import Accelerate

/// Post-meeting refinement pass over the accumulated speaker database.
///
/// Streaming diarization has to make decisions with incomplete information: the first
/// 5-10 seconds of audio for a speaker produce weaker embeddings than the full 30
/// minutes of audio available by end-of-call. This class runs two refinement passes
/// once the meeting ends:
///
/// 1. **Re-identification**: query VoicePrintManager with the final (EMA-smoothed)
///    embedding for each unnamed speaker. Speakers that couldn't be matched at second
///    5 may match confidently at minute 30.
///
/// 2. **Cluster merging**: check every pair of current speakers and merge any whose
///    final embeddings exceed the merge threshold (indicating the streaming pass
///    accidentally split one person into two). This corrects the "phantom speaker"
///    problem that plagues streaming clusterers.
///
/// This is Option C of the roadmap. A full batch re-diarization from the raw WAV
/// (Option A) is more accurate but requires persisting full audio and a second
/// FluidAudio run, which is future work.
@MainActor
final class PostMeetingDiarizer {

    /// Cosine similarity threshold above which two speaker clusters are considered
    /// the same person. 0.80 is aggressive enough to merge split clusters but
    /// conservative enough to avoid collapsing genuinely different voices.
    private let clusterMergeThreshold: Float = 0.80

    /// Minimum confidence boost required to overwrite an existing name assignment.
    /// Prevents thrashing: if the streaming pass already made a decent voice match,
    /// we only upgrade it when the batch pass is clearly more confident.
    private let upgradeMinimumDelta: Float = 0.05

    /// Minimum voiceprint match confidence for the re-ID pass.
    private let voiceprintMinimumConfidence: Float = 0.40

    private let voicePrintManager: VoicePrintManager

    init(voicePrintManager: VoicePrintManager) {
        self.voicePrintManager = voicePrintManager
    }

    struct RefinementResult {
        let reidentifiedCount: Int
        let mergedClusterCount: Int
        let finalSpeakerCount: Int
    }

    /// Run both refinement passes and mutate the meeting in place.
    /// - Parameters:
    ///   - meeting: The meeting to refine.
    ///   - speakerEmbeddings: Final embeddings keyed by raw speaker ID (no `mic_`/`sys_` prefix).
    /// - Returns: Summary of changes applied.
    func refine(
        meeting: LiveMeeting,
        speakerEmbeddings: [String: [Float]]
    ) async -> RefinementResult {
        guard !speakerEmbeddings.isEmpty else {
            debugLog("[PostMeeting] No speaker embeddings to refine")
            return RefinementResult(reidentifiedCount: 0, mergedClusterCount: 0, finalSpeakerCount: meeting.identifiedParticipants.count)
        }

        debugLog("[PostMeeting] Starting refinement with \(speakerEmbeddings.count) speaker embeddings, \(meeting.identifiedParticipants.count) participants")

        let reidentified = await reidentifyUnnamedSpeakers(meeting: meeting, embeddings: speakerEmbeddings)
        let merged = mergeDuplicateClusters(meeting: meeting, embeddings: speakerEmbeddings)

        let result = RefinementResult(
            reidentifiedCount: reidentified,
            mergedClusterCount: merged,
            finalSpeakerCount: meeting.identifiedParticipants.count
        )

        debugLog("[PostMeeting] Refinement complete: \(reidentified) re-identified, \(merged) clusters merged, \(result.finalSpeakerCount) final speakers")
        return result
    }

    // MARK: - Pass 1: Voiceprint re-identification

    /// For each unnamed or weakly-named participant, query VoicePrintManager with the
    /// final embedding. If the match beats the streaming-pass confidence by at least
    /// `upgradeMinimumDelta`, upgrade the name and propagate via renameSpeaker.
    private func reidentifyUnnamedSpeakers(
        meeting: LiveMeeting,
        embeddings: [String: [Float]]
    ) async -> Int {
        var upgradedCount = 0

        for participant in meeting.identifiedParticipants {
            // Skip participants the user has explicitly confirmed or named.
            if participant.isCurrentUser { continue }
            if participant.namingMode == .linkedToPerson { continue }
            if participant.namingMode == .namedByUser { continue }

            let rawID = participant.speakerID
                .replacingOccurrences(of: "mic_", with: "")
                .replacingOccurrences(of: "sys_", with: "")
            guard let finalEmbedding = embeddings[rawID], !finalEmbedding.isEmpty else { continue }

            let existingConfidence = participant.namingMode == .suggestedByVoice ? participant.confidence : 0

            guard let match = await voicePrintManager.findMatchingPerson(for: finalEmbedding),
                  let person = match.0,
                  match.1 >= voiceprintMinimumConfidence,
                  match.1 >= existingConfidence + upgradeMinimumDelta else { continue }

            let previousName = participant.displayName
            meeting.renameSpeaker(
                speakerID: participant.speakerID,
                to: person.wrappedName,
                person: person
            )
            // renameSpeaker marks the participant linkedToPerson — but we want to keep this
            // as suggestedByVoice so the user can still correct it if wrong. Override:
            participant.namingMode = .suggestedByVoice
            participant.confidence = match.1

            debugLog("[PostMeeting] 🎤 Re-identified '\(previousName)' → '\(person.wrappedName)' (confidence \(String(format: "%.0f%%", match.1 * 100)), was \(String(format: "%.0f%%", existingConfidence * 100)))")
            upgradedCount += 1
        }

        return upgradedCount
    }

    // MARK: - Pass 2: Cluster merging

    /// Find pairs of speakers whose final embeddings are too similar to be different
    /// people and merge them. Prefers merging into the participant with more speaking
    /// time (presumed more reliable).
    private func mergeDuplicateClusters(
        meeting: LiveMeeting,
        embeddings: [String: [Float]]
    ) -> Int {
        // Collect (participant, rawID, embedding, speakingTime) tuples.
        struct ClusterInfo {
            let participant: IdentifiedParticipant
            let rawID: String
            let embedding: [Float]
            let speakingTime: TimeInterval
        }

        var clusters: [ClusterInfo] = []
        for participant in meeting.identifiedParticipants {
            let rawID = participant.speakerID
                .replacingOccurrences(of: "mic_", with: "")
                .replacingOccurrences(of: "sys_", with: "")
            if let emb = embeddings[rawID], !emb.isEmpty {
                clusters.append(ClusterInfo(
                    participant: participant,
                    rawID: rawID,
                    embedding: emb,
                    speakingTime: participant.totalSpeakingTime
                ))
            }
        }

        guard clusters.count >= 2 else { return 0 }

        var mergedCount = 0
        var speakerIDsToSkip: Set<String> = []

        // Greedy pairwise merge. O(N²) but N is tiny (≤ 10 speakers typically).
        for i in 0..<clusters.count {
            let a = clusters[i]
            if speakerIDsToSkip.contains(a.participant.speakerID) { continue }

            for j in (i + 1)..<clusters.count {
                let b = clusters[j]
                if speakerIDsToSkip.contains(b.participant.speakerID) { continue }

                // Never merge across streams — mic_X and sys_Y are different by design
                // (one local, one remote). Only merge within the same stream.
                let aIsMic = a.participant.speakerID.hasPrefix("mic_")
                let bIsMic = b.participant.speakerID.hasPrefix("mic_")
                if aIsMic != bIsMic { continue }

                let similarity = cosineSimilarity(a.embedding, b.embedding)
                guard similarity >= clusterMergeThreshold else { continue }

                // Merge the one with less speaking time into the one with more.
                let (dominant, subordinate) = a.speakingTime >= b.speakingTime ? (a, b) : (b, a)

                debugLog("[PostMeeting] 🔀 Merging '\(subordinate.participant.displayName)' → '\(dominant.participant.displayName)' (cosine \(String(format: "%.3f", similarity)), times \(String(format: "%.0fs", subordinate.speakingTime)) → \(String(format: "%.0fs", dominant.speakingTime)))")

                meeting.mergeSpeakers(
                    sourceID: subordinate.participant.speakerID,
                    into: dominant.participant.speakerID
                )
                speakerIDsToSkip.insert(subordinate.participant.speakerID)
                mergedCount += 1
            }
        }

        return mergedCount
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
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
