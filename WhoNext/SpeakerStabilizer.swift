import Foundation

/// Stabilizes speaker labels using hysteresis to prevent rapid label switching
/// Requires consecutive evidence before committing to a speaker change
/// This prevents noise-induced flip-flopping like A→B→A within short time windows
class SpeakerStabilizer {

    // MARK: - Configuration

    /// Number of consecutive segments required before committing to a label change
    private let requiredConsecutive: Int

    /// Maximum time window (seconds) to consider for hysteresis
    private let hysteresisWindowSeconds: Float

    // MARK: - State

    /// Current stable label for each segment position
    private var stableLabels: [String] = []

    /// Pending label change (if any)
    private var pendingLabel: String?

    /// Count of consecutive segments with the pending label
    private var pendingCount: Int = 0

    /// Last stable speaker (for continuity)
    private var lastStableSpeaker: String?

    /// Statistics for debugging
    private(set) var stabilizationStats = StabilizationStats()

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameters:
    ///   - requiredConsecutive: Number of consecutive matches required for label change (default: 2)
    ///   - hysteresisWindowSeconds: Time window for hysteresis (default: 1.5s)
    init(requiredConsecutive: Int = 2, hysteresisWindowSeconds: Float = 1.5) {
        self.requiredConsecutive = requiredConsecutive
        self.hysteresisWindowSeconds = hysteresisWindowSeconds
    }

    // MARK: - Public Methods

    /// Stabilize a raw speaker label based on previous context
    /// - Parameters:
    ///   - rawLabel: The label from the diarization model
    ///   - currentLabel: The currently assigned stable label (or nil if first segment)
    /// - Returns: The stabilized label (may be same as current if change not confirmed)
    func stabilize(rawLabel: String, currentLabel: String?) -> String {
        let current = currentLabel ?? rawLabel

        // If raw matches current, reset pending state
        if rawLabel == current {
            pendingLabel = nil
            pendingCount = 0
            lastStableSpeaker = current
            stabilizationStats.stableSegments += 1
            return current
        }

        // Raw differs from current - check if this confirms a pending change
        if rawLabel == pendingLabel {
            pendingCount += 1
            stabilizationStats.pendingChanges += 1

            if pendingCount >= requiredConsecutive {
                // Enough consecutive evidence - commit the change
                let newLabel = rawLabel
                pendingLabel = nil
                pendingCount = 0
                lastStableSpeaker = newLabel
                stabilizationStats.committedChanges += 1
                return newLabel
            }
        } else {
            // Different pending label - start new pending
            pendingLabel = rawLabel
            pendingCount = 1
            stabilizationStats.pendingChanges += 1
        }

        // Not enough evidence yet - keep current label
        stabilizationStats.suppressedChanges += 1
        return current
    }

    /// Stabilize an entire sequence of segments
    /// - Parameter segments: Array of (speakerId, startTime, endTime) tuples
    /// - Returns: Stabilized speaker IDs in same order
    func stabilizeSequence(_ segments: [(speakerId: String, startTime: Float, endTime: Float)]) -> [String] {
        guard !segments.isEmpty else { return [] }

        var result: [String] = []
        var currentStable: String? = nil

        for (index, segment) in segments.enumerated() {
            let duration = segment.endTime - segment.startTime

            // For very short segments, inherit from previous
            if duration < 0.3 && currentStable != nil {
                result.append(currentStable!)
                stabilizationStats.shortSegmentsInherited += 1
                continue
            }

            // Apply hysteresis
            let stabilized = stabilize(rawLabel: segment.speakerId, currentLabel: currentStable)
            result.append(stabilized)
            currentStable = stabilized
        }

        return result
    }

    /// Apply temporal smoothing to remove isolated label changes
    /// Removes A-B-A patterns where B is very short
    /// - Parameters:
    ///   - segments: Segments to smooth
    ///   - minDurationForChange: Minimum duration (seconds) for a speaker change to be valid
    /// - Returns: Smoothed segments with speaker IDs updated
    func temporalSmooth(
        segments: [(speakerId: String, startTime: Float, endTime: Float)],
        minDurationForChange: Float = 0.5
    ) -> [(speakerId: String, startTime: Float, endTime: Float)] {
        guard segments.count >= 3 else { return segments }

        var result = segments

        // Look for A-B-A patterns where B is short
        var i = 1
        while i < result.count - 1 {
            let prev = result[i - 1]
            let curr = result[i]
            let next = result[i + 1]

            let currDuration = curr.endTime - curr.startTime

            // If previous and next have same speaker, and current is short
            if prev.speakerId == next.speakerId &&
               prev.speakerId != curr.speakerId &&
               currDuration < minDurationForChange {
                // Merge current into the surrounding speaker
                result[i] = (speakerId: prev.speakerId, startTime: curr.startTime, endTime: curr.endTime)
                stabilizationStats.temporalSmooths += 1
            }

            i += 1
        }

        return result
    }

    /// Reset all state
    func reset() {
        stableLabels.removeAll()
        pendingLabel = nil
        pendingCount = 0
        lastStableSpeaker = nil
        stabilizationStats = StabilizationStats()
    }
}

// MARK: - Statistics

struct StabilizationStats {
    var stableSegments: Int = 0          // Segments that matched current label
    var pendingChanges: Int = 0          // Times a change was pending
    var committedChanges: Int = 0        // Times a change was committed
    var suppressedChanges: Int = 0       // Times a change was suppressed (not enough evidence)
    var shortSegmentsInherited: Int = 0  // Very short segments that inherited from previous
    var temporalSmooths: Int = 0         // A-B-A patterns smoothed

    var suppressionRate: Float {
        let total = Float(committedChanges + suppressedChanges)
        return total > 0 ? Float(suppressedChanges) / total : 0
    }

    var description: String {
        """
        Stabilization Stats:
        - Stable segments: \(stableSegments)
        - Committed changes: \(committedChanges)
        - Suppressed changes: \(suppressedChanges) (\(Int(suppressionRate * 100))%)
        - Short segments inherited: \(shortSegmentsInherited)
        - Temporal smooths: \(temporalSmooths)
        """
    }
}
