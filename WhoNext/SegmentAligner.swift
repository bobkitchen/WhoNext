import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Aligns transcript segments with speaker diarization results
/// Uses time-based matching to determine which speaker was talking during each transcript segment
class SegmentAligner {

    // MARK: - Properties

    #if canImport(FluidAudio)
    /// Accumulated diarization segments for the session
    private var allSegments: [TimedSpeakerSegment] = []

    /// Speaker stabilizer to prevent rapid label switching
    private let stabilizer = SpeakerStabilizer()

    /// Track unique speakers seen
    private var knownSpeakers: Set<String> = []
    #endif

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        print("[SegmentAligner] Initialized")
    }

    // MARK: - Public Interface

    #if canImport(FluidAudio)
    /// Update with new diarization results
    /// - Parameter result: New DiarizationResult from FluidAudio
    func updateDiarizationResults(_ result: DiarizationResult) {
        lock.lock()
        defer { lock.unlock() }

        // Replace with latest segments (DiarizationManager maintains cumulative history)
        allSegments = result.segments

        // Track known speakers
        for segment in result.segments {
            knownSpeakers.insert(segment.speakerId)
        }

        print("[SegmentAligner] Updated with \(result.segments.count) segments, \(knownSpeakers.count) unique speakers")
    }

    /// Find the dominant speaker for a transcript time range
    /// - Parameters:
    ///   - transcriptStart: Start time of transcript segment (seconds from recording start)
    ///   - duration: Estimated duration of the text segment
    /// - Returns: Speaker ID or nil if no speaker found
    func dominantSpeaker(for transcriptStart: TimeInterval, duration: TimeInterval = 15.0) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !allSegments.isEmpty else {
            return nil
        }

        let endTime = transcriptStart + duration

        // Build a temporary DiarizationResult to use its helper method
        let result = DiarizationResult(segments: allSegments, speakerDatabase: nil, timings: nil)
        let speaker = result.dominantSpeaker(between: transcriptStart, and: endTime)

        // Run through stabilizer to prevent rapid switching
        if let speaker = speaker {
            let stabilized = stabilizer.stabilize(rawLabel: speaker, currentLabel: nil)
            return stabilized
        }

        return nil
    }

    /// Get segments for a specific time range
    func segments(between startTime: TimeInterval, and endTime: TimeInterval) -> [TimedSpeakerSegment] {
        lock.lock()
        defer { lock.unlock() }

        return allSegments.filter { segment in
            Double(segment.endTimeSeconds) >= startTime && Double(segment.startTimeSeconds) <= endTime
        }
    }

    /// Get all unique speaker IDs seen so far
    func getUniqueSpeakers() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        return Array(knownSpeakers).sorted()
    }

    /// Get total speaking time for each speaker
    func getSpeakingTimes() -> [String: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }

        var times: [String: TimeInterval] = [:]

        for segment in allSegments {
            let duration = Double(segment.endTimeSeconds - segment.startTimeSeconds)
            times[segment.speakerId, default: 0] += duration
        }

        return times
    }

    /// Get segment count
    func getSegmentCount() -> Int {
        lock.lock()
        defer { lock.unlock() }

        return allSegments.count
    }
    #endif

    /// Reset all accumulated data
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        #if canImport(FluidAudio)
        allSegments.removeAll()
        knownSpeakers.removeAll()
        stabilizer.reset()
        #endif

        print("[SegmentAligner] Reset")
    }
}

// MARK: - Speaker ID Utilities

extension SegmentAligner {

    /// Parse numeric speaker ID from FluidAudio format (e.g., "speaker_0" -> 0)
    static func parseNumericId(_ speakerId: String) -> Int {
        // FluidAudio typically uses "speaker_0", "speaker_1", etc.
        if let match = speakerId.range(of: #"\d+$"#, options: .regularExpression),
           let num = Int(speakerId[match]) {
            return num
        }

        // Fallback: hash the string to get a consistent ID
        return abs(speakerId.hashValue % 100)
    }

    /// Format speaker ID for display (e.g., "speaker_0" -> "Speaker 1", "2" -> "Speaker 2")
    static func formatSpeakerName(_ speakerId: String) -> String {
        // FluidAudio uses 1-based IDs like "1", "2" directly
        // Legacy format uses "speaker_0", "speaker_1" (0-based)
        if let num = Int(speakerId) {
            // Already a 1-based number, use directly
            return "Speaker \(num)"
        }
        // Legacy format: extract number and add 1
        let numericId = parseNumericId(speakerId)
        return "Speaker \(numericId + 1)"
    }
}

// MARK: - Diagnostics

extension SegmentAligner {

    /// Get diagnostic statistics
    func getStats() -> SegmentAlignerStats {
        lock.lock()
        defer { lock.unlock() }

        #if canImport(FluidAudio)
        let speakerCount = knownSpeakers.count
        let segmentCount = allSegments.count

        var totalDuration: TimeInterval = 0
        var earliestTime: TimeInterval = .greatestFiniteMagnitude
        var latestTime: TimeInterval = 0

        for segment in allSegments {
            let start = Double(segment.startTimeSeconds)
            let end = Double(segment.endTimeSeconds)
            totalDuration += (end - start)
            earliestTime = min(earliestTime, start)
            latestTime = max(latestTime, end)
        }

        if earliestTime == .greatestFiniteMagnitude {
            earliestTime = 0
        }

        return SegmentAlignerStats(
            speakerCount: speakerCount,
            segmentCount: segmentCount,
            totalSpeakingDuration: totalDuration,
            timeRange: (earliestTime, latestTime)
        )
        #else
        return SegmentAlignerStats(
            speakerCount: 0,
            segmentCount: 0,
            totalSpeakingDuration: 0,
            timeRange: (0, 0)
        )
        #endif
    }
}

struct SegmentAlignerStats {
    let speakerCount: Int
    let segmentCount: Int
    let totalSpeakingDuration: TimeInterval
    let timeRange: (start: TimeInterval, end: TimeInterval)

    var description: String {
        """
        Speakers: \(speakerCount)
        Segments: \(segmentCount)
        Total speaking: \(String(format: "%.1f", totalSpeakingDuration))s
        Time range: \(String(format: "%.1f", timeRange.start))s - \(String(format: "%.1f", timeRange.end))s
        """
    }
}
