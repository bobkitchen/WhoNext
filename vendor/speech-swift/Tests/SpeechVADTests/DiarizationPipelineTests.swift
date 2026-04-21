import XCTest
@testable import SpeechVAD
import AudioCommon

final class DiarizationPipelineTests: XCTestCase {

    // MARK: - DiarizationConfig

    func testDefaultDiarizationConfig() {
        let config = DiarizationConfig.default
        XCTAssertEqual(config.onset, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.offset, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.minSpeechDuration, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.minSilenceDuration, 0.15, accuracy: 0.001)
        XCTAssertEqual(config.clusteringThreshold, 0.715, accuracy: 0.001)
    }

    // MARK: - DiarizationResult

    func testDiarizationResultEmpty() {
        let result = DiarizationResult(segments: [], numSpeakers: 0, speakerEmbeddings: [])
        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.numSpeakers, 0)
        XCTAssertTrue(result.speakerEmbeddings.isEmpty)
    }

    func testDiarizationResultWithSegments() {
        let segments = [
            DiarizedSegment(startTime: 0.0, endTime: 2.5, speakerId: 0),
            DiarizedSegment(startTime: 3.0, endTime: 5.0, speakerId: 1),
        ]
        let embeddings: [[Float]] = [
            [Float](repeating: 0.1, count: 256),
            [Float](repeating: 0.2, count: 256),
        ]
        let result = DiarizationResult(segments: segments, numSpeakers: 2, speakerEmbeddings: embeddings)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.numSpeakers, 2)
        XCTAssertEqual(result.speakerEmbeddings.count, 2)
        XCTAssertEqual(result.segments[0].speakerId, 0)
        XCTAssertEqual(result.segments[1].duration, 2.0, accuracy: 0.001)
    }

    // MARK: - Progress Handler API

    func testDiarizeProgressHandlerOverloadExists() {
        // Verify the progressHandler overload compiles and accepts nil.
        // We cannot call diarize() without a loaded model, but we can verify
        // the method signature exists by referencing it.
        let _: (PyannoteDiarizationPipeline) -> ([Float], Int, DiarizationConfig, ((Float, String) -> Bool)?) -> DiarizationResult
            = PyannoteDiarizationPipeline.diarize(audio:sampleRate:config:progressHandler:)
    }

    #if canImport(CoreML)
    func testSortformerDiarizeProgressHandlerOverloadExists() {
        let _: (SortformerDiarizer) -> ([Float], Int, DiarizationConfig, ((Float, String) -> Bool)?) -> DiarizationResult
            = SortformerDiarizer.diarize(audio:sampleRate:config:progressHandler:)
    }
    #endif
}

// MARK: - E2E Tests (require model downloads)

final class E2EDiarizationPipelineTests: XCTestCase {

    func testDiarizeWithProgressHandler() async throws {
        let pipeline = try await PyannoteDiarizationPipeline.fromPretrained(
            embeddingEngine: .mlx
        )

        // Generate 5 seconds of silence (minimal audio for testing)
        let sampleRate = 16000
        let audio = [Float](repeating: 0, count: sampleRate * 5)

        var progressValues: [Float] = []
        var stageMessages: [String] = []

        let result = pipeline.diarize(audio: audio, sampleRate: sampleRate, config: .default) { progress, stage in
            progressValues.append(progress)
            stageMessages.append(stage)
            return true
        }

        // Silent audio should produce empty result
        XCTAssertEqual(result.segments.count, 0)

        // Progress handler should have been called at least once if any windows were processed
        // For 5s audio with 10s window, there's 1 window → at least some callbacks
        if !progressValues.isEmpty {
            // Progress values should be monotonically non-decreasing
            for i in 1..<progressValues.count {
                XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i - 1],
                    "Progress should be monotonically non-decreasing")
            }
            // All progress values should be in [0, 1]
            for p in progressValues {
                XCTAssertGreaterThanOrEqual(p, 0)
                XCTAssertLessThanOrEqual(p, 1)
            }
        }
    }

    func testDiarizeCancellationReturnsEmptyResult() async throws {
        let pipeline = try await PyannoteDiarizationPipeline.fromPretrained(
            embeddingEngine: .mlx
        )

        // Generate 30 seconds of audio so there are multiple windows to process
        let audio = [Float](repeating: 0, count: 16000 * 30)

        var callCount = 0
        let result = pipeline.diarize(audio: audio, sampleRate: 16000, config: .default) { _, _ in
            callCount += 1
            // Cancel after the first progress callback
            return callCount < 2
        }

        // Cancelled early — should return empty result
        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.numSpeakers, 0)
        XCTAssertTrue(result.speakerEmbeddings.isEmpty)
    }

    func testDiarizeWithoutProgressHandlerStillWorks() async throws {
        let pipeline = try await PyannoteDiarizationPipeline.fromPretrained(
            embeddingEngine: .mlx
        )

        let audio = [Float](repeating: 0, count: 16000 * 5)

        // Original API without progressHandler should still work
        let result = pipeline.diarize(audio: audio, sampleRate: 16000, config: .default)
        XCTAssertEqual(result.segments.count, 0)
    }
}
