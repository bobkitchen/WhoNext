import Foundation
import AVFoundation

// MARK: - WhoNext Diarization Bridge Types
//
// Engine-agnostic types used throughout the app for diarization results.
// Decouples SegmentAligner, MeetingTypeDetector, EnergyGateDetector,
// SpeakerStabilizer, LiveMeeting, and all UI code from any specific
// diarization engine.

// MARK: - Diarization Engine Protocol

/// Abstraction over diarization backends (AxiiDiarization, FluidAudio, etc.).
/// SimpleRecordingEngine talks to this protocol, not concrete backends.
@MainActor
protocol DiarizationEngine: AnyObject {
    var lastResult: DiarizationResult? { get }
    var currentSpeakers: [String] { get }
    var totalSpeakerCount: Int { get }
    var userSpeakerId: String? { get }
    var lastError: Error? { get }

    func initialize() async throws
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async
    func finishProcessing() async -> DiarizationResult?
    func matchAgainstCache(embedding: [Float]) -> String?
    func preloadKnownSpeakers(_ knownSpeakers: [(id: String, name: String, embedding: [Float])])
    func mergeCacheSpeakers(sourceId: String, destinationId: String) -> [Float]?
    func reset()
}

/// A time-bounded speaker segment with optional embedding.
struct TimedSpeakerSegment: Sendable {
    let speakerId: String
    let embedding: [Float]
    let startTimeSeconds: Float
    let endTimeSeconds: Float
    let qualityScore: Float

    init(speakerId: String, embedding: [Float] = [], startTimeSeconds: Float, endTimeSeconds: Float, qualityScore: Float = 1.0) {
        self.speakerId = speakerId
        self.embedding = embedding
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.qualityScore = qualityScore
    }
}

/// Aggregated diarization output: segments + per-speaker embeddings.
struct DiarizationResult: Sendable {
    let segments: [TimedSpeakerSegment]
    let speakerEmbeddings: [String: [Float]]?

    /// Backward-compat alias used by callers that still reference legacy naming.
    /// Will be removed when all callers migrate to `speakerEmbeddings`.
    var speakerDatabase: [String: [Float]]? { speakerEmbeddings }

    init(segments: [TimedSpeakerSegment], speakerEmbeddings: [String: [Float]]?) {
        self.segments = segments
        self.speakerEmbeddings = speakerEmbeddings
    }

    /// Backward-compat init matching legacy DiarizationResult shape.
    init(segments: [TimedSpeakerSegment], speakerDatabase: [String: [Float]]?, timings: Any? = nil) {
        self.segments = segments
        self.speakerEmbeddings = speakerDatabase
    }

    /// Convenience: number of unique speakers in segments
    var speakerCount: Int {
        Set(segments.map { $0.speakerId }).count
    }

    /// Get segments for a specific time range
    func segments(between startTime: TimeInterval, and endTime: TimeInterval) -> [TimedSpeakerSegment] {
        segments.filter { segment in
            Double(segment.endTimeSeconds) >= startTime && Double(segment.startTimeSeconds) <= endTime
        }
    }

    /// Find the speaker with the most overlap in a time range.
    func dominantSpeaker(between start: TimeInterval, and end: TimeInterval) -> String? {
        var speakerTimes: [String: Double] = [:]
        for seg in segments {
            let segStart = Double(seg.startTimeSeconds)
            let segEnd = Double(seg.endTimeSeconds)
            let overlap = max(0, min(end, segEnd) - max(start, segStart))
            if overlap > 0 {
                speakerTimes[seg.speakerId, default: 0] += overlap
            }
        }
        return speakerTimes.max(by: { $0.value < $1.value })?.key
    }
}
