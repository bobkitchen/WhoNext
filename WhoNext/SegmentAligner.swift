import Foundation
import AxiiDiarization

// MARK: - Word-Level Speaker Attribution Types

/// A single word with absolute timing (recording-relative)
struct WordWithTiming {
    let word: String
    let startTime: TimeInterval  // Absolute (recording-relative)
    let endTime: TimeInterval
}

/// A group of consecutive words spoken by the same speaker
struct SpeakerWordGroup {
    let speakerId: String
    let words: [WordWithTiming]
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String { words.map { $0.word }.joined(separator: " ") }
}

/// Aligns transcript segments with speaker diarization results
/// Uses time-based matching to determine which speaker was talking during each transcript segment
class SegmentAligner {

    // MARK: - Properties

    /// Accumulated diarization segments from microphone audio
    private var micSegments: [TimedSpeakerSegment] = []

    /// Accumulated diarization segments from system audio
    private var systemSegments: [TimedSpeakerSegment] = []

    /// Speaker stabilizer for word-level path (alignWords) — prevents rapid label
    /// switching within a chunk's word stream.
    private let wordStabilizer = SpeakerStabilizer()

    /// Speaker stabilizer for segment-level path (dominantSpeaker / addSingleSegment) —
    /// kept separate from wordStabilizer so hysteresis state in one path cannot
    /// prematurely commit or reset a pending change in the other.
    private let segmentStabilizer = SpeakerStabilizer()

    /// Track unique speakers seen
    private var knownSpeakers: Set<String> = []

    /// Track last returned speaker for the word-level path
    private var lastReturnedWordSpeaker: String?

    /// Track last returned speaker for the segment-level path
    private var lastReturnedSegmentSpeaker: String?

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        debugLog("[SegmentAligner] Initialized")
    }

    // MARK: - Public Interface

    /// Prefix speaker IDs to distinguish mic vs system audio sources
    private static func prefixSegments(_ segments: [TimedSpeakerSegment], prefix: String) -> [TimedSpeakerSegment] {
        segments.map { segment in
            TimedSpeakerSegment(
                speakerId: "\(prefix)_\(segment.speakerId)",
                embedding: segment.embedding,
                startTimeSeconds: segment.startTimeSeconds,
                endTimeSeconds: segment.endTimeSeconds,
                qualityScore: segment.qualityScore
            )
        }
    }

    /// Replace mic segments with new diarization results (for diarizer engines that
    /// return cumulative results covering the full analyzed window).
    /// - Parameter result: New DiarizationResult from diarization engine
    func updateDiarizationResults(_ result: DiarizationResult) {
        lock.lock()
        defer { lock.unlock() }

        micSegments = Self.prefixSegments(result.segments, prefix: "mic")
        capAndTrack(source: "mic")
    }

    /// Replace system segments with new diarization results (for diarizer engines that
    /// return cumulative results covering the full analyzed window).
    /// - Parameter result: New DiarizationResult from diarization engine
    func updateSystemDiarizationResults(_ result: DiarizationResult) {
        lock.lock()
        defer { lock.unlock() }

        systemSegments = Self.prefixSegments(result.segments, prefix: "sys")
        capAndTrack(source: "system")
    }

    /// Append a mic segment (for VAD/stream labeling mode where each call
    /// produces a single short segment that must accumulate over time).
    func appendMicSegment(_ segment: TimedSpeakerSegment) {
        lock.lock()
        defer { lock.unlock() }

        let prefixed = Self.prefixSegments([segment], prefix: "mic")
        micSegments.append(contentsOf: prefixed)
        capAndTrack(source: "mic")
    }

    /// Append a system segment (for VAD/stream labeling mode where each call
    /// produces a single short segment that must accumulate over time).
    func appendSystemSegment(_ segment: TimedSpeakerSegment) {
        lock.lock()
        defer { lock.unlock() }

        let prefixed = Self.prefixSegments([segment], prefix: "sys")
        systemSegments.append(contentsOf: prefixed)
        capAndTrack(source: "system")
    }

    /// Common cap-and-track logic for both update and append paths
    private func capAndTrack(source: String) {
        // Defensive cap
        if source == "mic" && micSegments.count > 5000 {
            micSegments = Array(micSegments.suffix(5000))
            debugLog("[SegmentAligner] ⚠️ Mic segment cap hit: trimmed to 5000")
        }
        if source == "system" && systemSegments.count > 5000 {
            systemSegments = Array(systemSegments.suffix(5000))
            debugLog("[SegmentAligner] ⚠️ System segment cap hit: trimmed to 5000")
        }

        // Track known speakers
        let segments = source == "mic" ? micSegments : systemSegments
        for segment in segments {
            knownSpeakers.insert(segment.speakerId)
        }

        // Cap known speakers
        if knownSpeakers.count > 100 {
            let allSegments = micSegments + systemSegments
            let activeIds = Set(allSegments.map { $0.speakerId })
            knownSpeakers = knownSpeakers.intersection(activeIds)
            debugLog("[SegmentAligner] ⚠️ Speaker cap hit: pruned to \(knownSpeakers.count) active speakers")
        }

        let count = source == "mic" ? micSegments.count : systemSegments.count
        debugLog("[SegmentAligner] Updated \(source) with \(count) segments, \(knownSpeakers.count) unique speakers total")
    }

    /// Find the dominant speaker for a transcript time range.
    ///
    /// System-first priority (matches `alignWords`): in stream labeling mode, mic
    /// captures both local speech AND acoustic bleed from system audio (AEC residual
    /// ~0.015-0.020 RMS). System audio is a clean digital feed containing only the
    /// remote speaker. When both streams have overlap in the window, system wins
    /// unless mic overlap is strictly greater — this prevents mic-side bleed segments
    /// from claiming remote speech.
    /// - Parameters:
    ///   - transcriptStart: Start time of transcript segment (seconds from recording start)
    ///   - duration: Estimated duration of the text segment
    /// - Returns: Speaker ID or nil if no speaker found
    func dominantSpeaker(for transcriptStart: TimeInterval, duration: TimeInterval = 15.0) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !micSegments.isEmpty || !systemSegments.isEmpty else { return nil }

        let endTime = transcriptStart + duration

        // Pass 1: system segments only.
        var systemTimes: [String: Double] = [:]
        for seg in systemSegments {
            let segStart = Double(seg.startTimeSeconds)
            let segEnd = Double(seg.endTimeSeconds)
            let overlap = max(0, min(endTime, segEnd) - max(transcriptStart, segStart))
            if overlap > 0 {
                systemTimes[seg.speakerId, default: 0] += overlap
            }
        }
        let systemBest: (speaker: String, overlap: Double)? = systemTimes
            .max(by: { $0.value < $1.value })
            .map { ($0.key, $0.value) }

        // Pass 2: mic segments. Mic only beats system with strictly greater overlap.
        var micTimes: [String: Double] = [:]
        for seg in micSegments {
            let segStart = Double(seg.startTimeSeconds)
            let segEnd = Double(seg.endTimeSeconds)
            let overlap = max(0, min(endTime, segEnd) - max(transcriptStart, segStart))
            if overlap > 0 {
                micTimes[seg.speakerId, default: 0] += overlap
            }
        }
        let micBest: (speaker: String, overlap: Double)? = micTimes
            .max(by: { $0.value < $1.value })
            .map { ($0.key, $0.value) }

        let speaker: String?
        switch (systemBest, micBest) {
        case (nil, nil):
            speaker = nil
        case (.some(let s), nil):
            speaker = s.speaker
        case (nil, .some(let m)):
            speaker = m.speaker
        case (.some(let s), .some(let m)):
            speaker = m.overlap > s.overlap ? m.speaker : s.speaker
        }

        if let speaker = speaker {
            let stabilized = segmentStabilizer.stabilize(rawLabel: speaker, currentLabel: lastReturnedSegmentSpeaker)
            lastReturnedSegmentSpeaker = stabilized
            return stabilized
        }
        return nil
    }

    /// Get segments for a specific time range
    func segments(between startTime: TimeInterval, and endTime: TimeInterval) -> [TimedSpeakerSegment] {
        lock.lock()
        defer { lock.unlock() }

        let allSegments = micSegments + systemSegments
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
        let allSegments = micSegments + systemSegments
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
        return micSegments.count + systemSegments.count
    }

    /// Remove all system segments for a given speaker ID (used for cross-stream deduplication).
    /// - Parameter speakerId: Full prefixed speaker ID (e.g., "sys_1")
    func removeSystemSpeaker(_ speakerId: String) {
        lock.lock()
        defer { lock.unlock() }
        let before = systemSegments.count
        systemSegments.removeAll { $0.speakerId == speakerId }
        knownSpeakers.remove(speakerId)
        let removed = before - systemSegments.count
        if removed > 0 {
            debugLog("[SegmentAligner] Removed \(removed) segments for suppressed speaker '\(speakerId)'")
        }
    }

    // MARK: - Word-Level Speaker Attribution

    /// Align individual words to diarization segments, producing speaker-grouped word runs.
    /// - Parameters:
    ///   - wordTimings: Per-word timings from the transcription engine (chunk-relative)
    ///   - chunkStartTime: Absolute recording time when this chunk started
    /// - Returns: Array of SpeakerWordGroups with consecutive same-speaker words grouped together
    func alignWords(wordTimings: [UnifiedTranscriptionResult.UnifiedTokenTiming], chunkStartTime: TimeInterval) -> [SpeakerWordGroup] {
        lock.lock()
        defer { lock.unlock() }

        // System segments first: in stream labeling mode, mic captures both local
        // speaker + acoustic bleed from system audio. System audio only contains the
        // remote speaker's digital signal, so it's a higher-confidence source.
        // Checking system segments first ensures remote speech is attributed correctly
        // rather than being claimed by mic bleed segments.
        let allSegments = systemSegments + micSegments
        guard !allSegments.isEmpty, !wordTimings.isEmpty else { return [] }

        // Convert chunk-relative word times to absolute and assign speakers
        var attributedWords: [(word: WordWithTiming, speakerId: String)] = []

        for timing in wordTimings {
            let absStart = chunkStartTime + timing.startTime
            let absEnd = chunkStartTime + timing.endTime
            let midpoint = (absStart + absEnd) / 2.0

            let wordTiming = WordWithTiming(word: timing.word, startTime: absStart, endTime: absEnd)

            // Strategy 1: Find segment containing the word's midpoint.
            // System segments are checked first (higher confidence for remote speech).
            var assignedSpeaker: String? = nil
            for seg in allSegments {
                if Double(seg.startTimeSeconds) <= midpoint && midpoint <= Double(seg.endTimeSeconds) {
                    assignedSpeaker = seg.speakerId
                    break
                }
            }

            // Strategy 2: Overlap-weighted selection. System segments are checked FIRST
            // and win ties (>=); mic segments only override with strictly greater overlap.
            // This preserves the system-first priority invariant when overlaps tie.
            if assignedSpeaker == nil {
                var bestOverlap: Double = 0
                // First pass: system segments only (ties go to system).
                for seg in systemSegments {
                    let segStart = Double(seg.startTimeSeconds)
                    let segEnd = Double(seg.endTimeSeconds)
                    let overlap = max(0, min(absEnd, segEnd) - max(absStart, segStart))
                    if overlap > bestOverlap {
                        bestOverlap = overlap
                        assignedSpeaker = seg.speakerId
                    }
                }
                // Second pass: mic segments only beat system with strictly greater overlap.
                for seg in micSegments {
                    let segStart = Double(seg.startTimeSeconds)
                    let segEnd = Double(seg.endTimeSeconds)
                    let overlap = max(0, min(absEnd, segEnd) - max(absStart, segStart))
                    if overlap > bestOverlap {
                        bestOverlap = overlap
                        assignedSpeaker = seg.speakerId
                    }
                }
            }

            // Strategy 3: Nearest-neighbor within 0.5s
            if assignedSpeaker == nil {
                var bestDistance: Double = 0.5
                for seg in allSegments {
                    let segMid = Double(seg.startTimeSeconds + seg.endTimeSeconds) / 2.0
                    let distance = abs(midpoint - segMid)
                    if distance < bestDistance {
                        bestDistance = distance
                        assignedSpeaker = seg.speakerId
                    }
                }
            }

            // Strategy 4: Last returned speaker fallback
            let speaker = assignedSpeaker ?? lastReturnedWordSpeaker ?? "unknown"

            // Apply speaker stabilizer (word-path — separate from segment-path stabilizer)
            let stabilized = wordStabilizer.stabilize(rawLabel: speaker, currentLabel: lastReturnedWordSpeaker)
            lastReturnedWordSpeaker = stabilized

            attributedWords.append((word: wordTiming, speakerId: stabilized))
        }

        // Group consecutive same-speaker words into SpeakerWordGroups
        var groups: [SpeakerWordGroup] = []
        var currentGroupWords: [WordWithTiming] = []
        var currentSpeaker: String = ""

        for (word, speaker) in attributedWords {
            if speaker != currentSpeaker && !currentGroupWords.isEmpty {
                // Flush current group
                groups.append(SpeakerWordGroup(
                    speakerId: currentSpeaker,
                    words: currentGroupWords,
                    startTime: currentGroupWords.first!.startTime,
                    endTime: currentGroupWords.last!.endTime
                ))
                currentGroupWords = []
            }
            currentSpeaker = speaker
            currentGroupWords.append(word)
        }

        // Flush final group
        if !currentGroupWords.isEmpty {
            groups.append(SpeakerWordGroup(
                speakerId: currentSpeaker,
                words: currentGroupWords,
                startTime: currentGroupWords.first!.startTime,
                endTime: currentGroupWords.last!.endTime
            ))
        }

        return groups
    }

    /// Reset all accumulated data
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        micSegments.removeAll()
        systemSegments.removeAll()
        knownSpeakers.removeAll()
        wordStabilizer.reset()
        segmentStabilizer.reset()
        lastReturnedWordSpeaker = nil
        lastReturnedSegmentSpeaker = nil

        debugLog("[SegmentAligner] Reset")
    }
}

// MARK: - Speaker ID Utilities

extension SegmentAligner {

    /// Parse numeric speaker ID from diarization format (e.g., "speaker_0" -> 0)
    static func parseNumericId(_ speakerId: String) -> Int {
        // Diarization typically uses "speaker_0", "speaker_1", etc.
        if let match = speakerId.range(of: #"\d+$"#, options: .regularExpression),
           let num = Int(speakerId[match]) {
            return num
        }

        // Fallback: hash the string to get a consistent ID
        return abs(speakerId.hashValue % 100)
    }

    /// Format speaker ID for display (e.g., "speaker_0" -> "Speaker 1", "mic_2" -> "Speaker 2 (Local)")
    static func formatSpeakerName(_ speakerId: String) -> String {
        // Strip mic_/sys_ prefix for display
        var cleanId = speakerId
        var sourceLabel = ""
        if speakerId.hasPrefix("mic_") {
            cleanId = String(speakerId.dropFirst(4))
            sourceLabel = " (Local)"
        } else if speakerId.hasPrefix("sys_") {
            cleanId = String(speakerId.dropFirst(4))
            sourceLabel = " (Remote)"
        }

        // Diarization uses 1-based IDs like "1", "2" directly
        if let num = Int(cleanId) {
            return "Speaker \(num)\(sourceLabel)"
        }
        // Legacy format: extract number and add 1
        let numericId = parseNumericId(cleanId)
        return "Speaker \(numericId + 1)\(sourceLabel)"
    }
}

// MARK: - Diagnostics

extension SegmentAligner {

    /// Get diagnostic statistics
    func getStats() -> SegmentAlignerStats {
        lock.lock()
        defer { lock.unlock() }

        let speakerCount = knownSpeakers.count
        let allSegments = micSegments + systemSegments
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
