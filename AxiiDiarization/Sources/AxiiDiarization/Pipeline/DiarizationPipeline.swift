import Foundation
import CoreML

/// Loads CoreML models and creates diarization sessions.
public final class DiarizationPipeline: @unchecked Sendable {

    let sortformerModel: SortformerModel
    let wespeakerModel: WeSpeakerModel
    let windowDuration: Double
    let clusteringThreshold: Float

    /// Initialize the pipeline by loading both CoreML models.
    /// - Parameters:
    ///   - sortformerModelPath: Path to the compiled `.mlmodelc` for Sortformer v2.1
    ///   - embModelPath: Path to the compiled `.mlmodelc` for WeSpeaker ResNet34
    ///   - windowDuration: Processing window length in seconds
    ///   - clusteringThreshold: Cosine similarity threshold for speaker clustering (0–1)
    public init(sortformerModelPath: String, embModelPath: String,
                windowDuration: Double = 10.0, clusteringThreshold: Float = 0.30) throws {

        let sortformerURL = URL(fileURLWithPath: sortformerModelPath)
        let embURL = URL(fileURLWithPath: embModelPath)

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        self.sortformerModel = try SortformerModel(modelURL: sortformerURL, configuration: config)
        self.wespeakerModel = try WeSpeakerModel(modelURL: embURL, configuration: config)
        self.windowDuration = windowDuration
        self.clusteringThreshold = clusteringThreshold
    }

    /// Create a new diarization session (no known speakers).
    public func createSession() -> DiarizationSession {
        DiarizationSession(pipeline: self, knownSpeakers: [])
    }

    /// Create a session pre-loaded with known speaker profiles for guided diarization.
    public func createSession(knownSpeakers: [any SpeakerProfile]) -> DiarizationSession {
        DiarizationSession(pipeline: self, knownSpeakers: knownSpeakers)
    }
}
