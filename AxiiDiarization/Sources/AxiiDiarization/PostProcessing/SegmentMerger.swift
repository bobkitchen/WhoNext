import Foundation

/// Post-processes raw segments: padding, minimum duration filtering, gap merging.
enum SegmentMerger {

    struct MergedSegment {
        let speakerChannel: Int
        let start: Double
        let end: Double
    }

    /// Merge raw segments with padding, minimum duration, and gap merge.
    /// - Parameters:
    ///   - segments: Raw detected segments
    ///   - padding: Seconds to add before/after each segment
    ///   - minDuration: Minimum segment duration in seconds (shorter segments are dropped)
    ///   - maxGap: Maximum gap in seconds between same-speaker segments to merge
    static func merge(
        _ segments: [SegmentDetector.RawSegment],
        padding: Double = 0.2,
        minDuration: Double = 0.25,
        maxGap: Double = 0.5
    ) -> [MergedSegment] {
        guard !segments.isEmpty else { return [] }

        // Group by speaker channel
        var bySpeaker: [Int: [SegmentDetector.RawSegment]] = [:]
        for seg in segments {
            bySpeaker[seg.speakerChannel, default: []].append(seg)
        }

        var result: [MergedSegment] = []

        for (channel, channelSegments) in bySpeaker {
            // Sort by start time
            let sorted = channelSegments.sorted { $0.startTime < $1.startTime }

            // Apply padding and filter by min duration
            var padded: [(start: Double, end: Double)] = []
            for seg in sorted {
                let start = max(0, seg.startTime - padding)
                let end = seg.endTime + padding
                let duration = end - start
                if duration >= minDuration {
                    padded.append((start: start, end: end))
                }
            }

            guard !padded.isEmpty else { continue }

            // Merge segments with small gaps
            var merged: [(start: Double, end: Double)] = [padded[0]]
            for i in 1..<padded.count {
                let current = padded[i]
                let lastIdx = merged.count - 1
                let gap = current.start - merged[lastIdx].end

                if gap <= maxGap {
                    // Merge: extend the end of the last segment
                    merged[lastIdx].end = max(merged[lastIdx].end, current.end)
                } else {
                    merged.append(current)
                }
            }

            for seg in merged {
                result.append(MergedSegment(
                    speakerChannel: channel,
                    start: seg.start,
                    end: seg.end
                ))
            }
        }

        // Sort all segments by start time
        return result.sorted { $0.start < $1.start }
    }
}
