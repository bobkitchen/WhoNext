import Foundation

// MARK: - Speaker Profile Protocol

/// Protocol for providing known speaker embeddings to guide diarization.
public protocol SpeakerProfile {
    var id: String { get }
    var embeddings: [[Float]] { get }
}

// MARK: - Speaker

/// Represents a detected speaker in a diarization segment.
public struct Speaker: Sendable {
    public let id: String
    public let embedding: [Float]?

    public init(id: String, embedding: [Float]?) {
        self.id = id
        self.embedding = embedding
    }
}

// MARK: - Speaker Identification

/// How a speaker was identified in a segment.
public enum SpeakerIdentification: Sendable {
    case unknown
    case autoMatched(speakerID: String, confidence: Float)
    case pinned(speakerID: String)
}

// MARK: - Diarization Segment

/// A time-bounded segment attributed to a single speaker.
public struct DiarizationSegment: Sendable {
    public let start: Double
    public let end: Double
    public let speaker: Speaker
    public let identification: SpeakerIdentification

    public init(start: Double, end: Double, speaker: Speaker, identification: SpeakerIdentification) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.identification = identification
    }
}

// MARK: - Result

/// The output of a diarization session's `process()` or `finalize()` call.
public struct AxiiDiarizationResult: Sendable {
    public let segments: [DiarizationSegment]

    public init(segments: [DiarizationSegment]) {
        self.segments = segments
    }
}
