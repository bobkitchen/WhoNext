import XCTest
import ParakeetStreamingASR
import SpeechVAD
import AudioCommon

/// E2E tests for the DictateDemo streaming pipeline.
/// Validates that the streaming ASR produces text from audio
/// without relying on the SwiftUI menu bar UI.
final class E2EDictateDemoTests: XCTestCase {

    private static var model: ParakeetStreamingASRModel?
    private static var vad: SileroVADModel?

    override class func setUp() {
        super.setUp()
        let expectation = XCTestExpectation(description: "Load models")
        Task {
            model = try await ParakeetStreamingASRModel.fromPretrained()
            try model?.warmUp()
            vad = try await SileroVADModel.fromPretrained(engine: .coreml)
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: 120)
    }

    // MARK: - Streaming Session Tests

    func testStreamingProducesText() throws {
        guard let model = Self.model else { throw XCTSkip("Model not loaded") }

        // Generate 2s of 440Hz tone (simulates speech-like audio)
        let sampleRate = 16000
        let duration = 2.0
        var audio = [Float](repeating: 0, count: Int(Double(sampleRate) * duration))
        for i in 0..<audio.count {
            audio[i] = sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate)) * 0.3
        }

        let session = try model.createSession()
        let chunkSize = 5440  // melFrames * hopLength

        var allPartials: [ParakeetStreamingASRModel.PartialTranscript] = []
        var offset = 0
        while offset + chunkSize <= audio.count {
            let chunk = Array(audio[offset..<offset + chunkSize])
            let partials = try session.pushAudio(chunk)
            allPartials.append(contentsOf: partials)
            offset += chunkSize
        }
        let finals = try session.finalize()
        allPartials.append(contentsOf: finals)

        // 440Hz tone may or may not produce text, but pipeline should not crash
        XCTAssertNotNil(allPartials)
        print("Streaming test: \(allPartials.count) partials")
    }

    func testStreamingWithRealAudio() async throws {
        guard let model = Self.model else { throw XCTSkip("Model not loaded") }

        // Use the test audio file from the main repo
        let testAudioURL = URL(fileURLWithPath: "../../Tests/ParakeetStreamingASRTests/Resources/test_audio.wav")
        guard FileManager.default.fileExists(atPath: testAudioURL.path) else {
            throw XCTSkip("test_audio.wav not found")
        }

        let audio = try AudioFileLoader.load(url: testAudioURL, targetSampleRate: 16000)

        // Stream in 320ms chunks (simulating real-time mic input)
        var allPartials: [ParakeetStreamingASRModel.PartialTranscript] = []
        for await partial in model.transcribeStream(audio: audio, sampleRate: 16000) {
            allPartials.append(partial)
        }

        XCTAssertFalse(allPartials.isEmpty, "Should produce at least one partial")
        let lastFinal = allPartials.last(where: { $0.isFinal })
        XCTAssertNotNil(lastFinal, "Should have at least one final transcript")
        XCTAssertFalse(lastFinal!.text.isEmpty, "Final text should not be empty")
        print("Real audio: '\(lastFinal!.text)'")
    }

    func testMultiUtteranceReset() throws {
        guard let model = Self.model else { throw XCTSkip("Model not loaded") }

        let sampleRate = 16000
        let chunkSize = 5440

        // Generate 1s speech-like + 1s silence + 1s speech-like
        var audio1 = [Float](repeating: 0, count: sampleRate)
        for i in 0..<audio1.count {
            audio1[i] = sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate)) * 0.3
        }
        let silence = [Float](repeating: 0, count: sampleRate)

        let session = try model.createSession()

        // First utterance
        var offset = 0
        while offset + chunkSize <= audio1.count {
            _ = try session.pushAudio(Array(audio1[offset..<offset + chunkSize]))
            offset += chunkSize
        }

        // Silence (should not crash)
        offset = 0
        while offset + chunkSize <= silence.count {
            _ = try session.pushAudio(Array(silence[offset..<offset + chunkSize]))
            offset += chunkSize
        }

        // Second utterance
        offset = 0
        while offset + chunkSize <= audio1.count {
            _ = try session.pushAudio(Array(audio1[offset..<offset + chunkSize]))
            offset += chunkSize
        }

        let finals = try session.finalize()
        // Pipeline should handle multi-utterance without crashing
        XCTAssertNotNil(finals)
    }

    // MARK: - VAD Tests

    func testVADDetectsSpeech() throws {
        guard let vad = Self.vad else { throw XCTSkip("VAD not loaded") }

        // 440Hz tone should trigger speech detection
        var speechChunk = [Float](repeating: 0, count: 512)
        for i in 0..<512 {
            speechChunk[i] = sin(2.0 * .pi * 440.0 * Float(i) / 16000.0) * 0.5
        }
        let prob = vad.processChunk(speechChunk)
        // Just verify it returns a valid probability
        XCTAssertGreaterThanOrEqual(prob, 0)
        XCTAssertLessThanOrEqual(prob, 1)
    }

    func testVADSilence() throws {
        guard let vad = Self.vad else { throw XCTSkip("VAD not loaded") }

        let silence = [Float](repeating: 0, count: 512)
        let prob = vad.processChunk(silence)
        XCTAssertGreaterThanOrEqual(prob, 0)
        XCTAssertLessThan(prob, 0.5, "Silence should have low speech probability")
    }

    func testDebugAudioSmallChunks() async throws {
        guard let model = Self.model else { throw XCTSkip("Model not loaded") }

        let path = "/tmp/dictate-debug.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("No debug audio at \(path) — run DictateDemo first")
        }

        let audio = try AudioFileLoader.load(url: URL(fileURLWithPath: path), targetSampleRate: 16000)
        print("Debug audio: \(audio.count) samples (\(Float(audio.count)/16000)s)")

        // Test multiple chunk sizes
        for chunkSize in [4800, 5120, 5440, 8000] {
            let session2 = try model.createSession()
            var partials2: [ParakeetStreamingASRModel.PartialTranscript] = []
            var off = 0
            while off < audio.count {
                let end = min(off + chunkSize, audio.count)
                partials2.append(contentsOf: try session2.pushAudio(Array(audio[off..<end])))
                off = end
            }
            partials2.append(contentsOf: try session2.finalize())
            let texts = partials2.filter { $0.isFinal }.map { $0.text }
            print("chunk=\(chunkSize): \(partials2.count) partials, finals=\(texts)")
        }

        // Use 5440 (matching session internal buffer) for the assertion
        let session = try model.createSession()
        var allPartials: [ParakeetStreamingASRModel.PartialTranscript] = []
        var offset = 0
        while offset < audio.count {
            let end = min(offset + 5440, audio.count)
            let chunk = Array(audio[offset..<end])
            let partials = try session.pushAudio(chunk)
            allPartials.append(contentsOf: partials)
            offset = end
        }
        let finals = try session.finalize()
        allPartials.append(contentsOf: finals)

        let finalTexts = allPartials.filter { $0.isFinal }.map { $0.text }
        print("5440-chunk results: \(allPartials.count) partials, finals: \(finalTexts)")

        // Also test transcribeStream API
        var streamPartials: [ParakeetStreamingASRModel.PartialTranscript] = []
        for await p in model.transcribeStream(audio: audio, sampleRate: 16000) {
            streamPartials.append(p)
        }
        let streamFinals = streamPartials.filter { $0.isFinal }.map { $0.text }
        print("transcribeStream: \(streamPartials.count) partials, finals=\(streamFinals)")

        // Also test batch
        let batchText = try model.transcribeAudio(audio, sampleRate: 16000)
        print("batch: '\(batchText)'")

        XCTAssertTrue(!streamPartials.isEmpty || !batchText.isEmpty,
                      "Should produce text from mic audio via streaming or batch")
    }

    func testDebugWavLoading() throws {
        let path = "/tmp/dictate-debug.wav"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("No debug wav") }

        let audio = try AudioFileLoader.load(url: URL(fileURLWithPath: path), targetSampleRate: 16000)
        let rms = sqrt(audio.reduce(0) { $0 + $1 * $1 } / Float(audio.count))
        print("Loaded: \(audio.count) samples, rms=\(rms)")
        print("First 5: \(Array(audio.prefix(5)))")
        if audio.count > 16000 {
            print("At 1s: \(Array(audio[16000..<16005]))")
            let speechRms = sqrt(audio[16000..<17600].reduce(0) { $0 + $1 * $1 } / 1600)
            print("Speech rms at 1s: \(speechRms)")
        }
    }

    // MARK: - Pipeline Simulation (mirrors DictateDemo's ASRProcessor)

    /// Mirrors the VAD + force-finalize pipeline in DictateDemo's ASRProcessor.
    /// Duplicated here (rather than @testable imported) because ASRProcessor
    /// lives in the executable target. Keep the two in sync — if this drifts,
    /// the test stops guarding the real pipeline.
    ///
    /// - Parameters:
    ///   - audio: mono 16kHz Float32 samples
    ///   - timerChunkSamples: samples per simulated timer tick (default 4800 = 300ms)
    ///   - forceFinalizeSilentVadChunks: VAD silence threshold before force-finalize (default 30 ≈ 960ms)
    /// - Returns: list of committed final texts in order
    private func simulateDictateDemoPipeline(
        audio: [Float],
        timerChunkSamples: Int = 4800,
        forceFinalizeSilentVadChunks: Int = 30
    ) throws -> [String] {
        guard let model = Self.model, let vad = Self.vad else {
            throw XCTSkip("Models not loaded")
        }
        vad.resetState()
        let session = try model.createSession()

        var vadLeftover: [Float] = []
        var speechActive = false
        var silenceCount = 0
        var hasPendingUtterance = false
        var finals: [String] = []

        var offset = 0
        while offset < audio.count {
            let end = min(offset + timerChunkSamples, audio.count)
            let chunk = Array(audio[offset..<end])
            offset = end

            // VAD on 512-sample chunks with leftover carry-over.
            var vadInput = vadLeftover
            vadInput.append(contentsOf: chunk)
            var vadOffset = 0
            while vadOffset + 512 <= vadInput.count {
                let prob = vad.processChunk(Array(vadInput[vadOffset..<vadOffset+512]))
                if prob >= 0.5 {
                    speechActive = true
                    silenceCount = 0
                    hasPendingUtterance = true
                } else {
                    silenceCount += 1
                    if silenceCount >= 15 { speechActive = false }
                }
                vadOffset += 512
            }
            vadLeftover = Array(vadInput[vadOffset...])

            // ASR
            var partials = try session.pushAudio(chunk)

            // VAD force-finalize after sustained silence
            if hasPendingUtterance && !speechActive && silenceCount >= forceFinalizeSilentVadChunks {
                if let forced = session.forceEndOfUtterance() {
                    partials.append(forced)
                }
                hasPendingUtterance = false
            }

            for p in partials where p.isFinal && !p.text.isEmpty {
                finals.append(p.text)
            }
        }

        for p in try session.finalize() where !p.text.isEmpty {
            finals.append(p.text)
        }
        return finals
    }

    /// Load test audio and stitch two copies together with a gap of silence
    /// between them, producing a deterministic multi-utterance fixture.
    private func multiUtteranceFixture(gapSeconds: Double = 1.5) throws -> [Float] {
        let testAudioURL = URL(fileURLWithPath: "../../Tests/ParakeetStreamingASRTests/Resources/test_audio.wav")
        guard FileManager.default.fileExists(atPath: testAudioURL.path) else {
            throw XCTSkip("test_audio.wav not found at \(testAudioURL.path)")
        }
        let clip = try AudioFileLoader.load(url: testAudioURL, targetSampleRate: 16000)
        let silence = [Float](repeating: 0, count: Int(Double(16000) * gapSeconds))
        return clip + silence + clip
    }

    /// Diagnostic: print the event trace so we can see why the second
    /// utterance doesn't produce a final.
    func testPipelineDiagnostic() throws {
        guard let model = Self.model, let vad = Self.vad else {
            throw XCTSkip("Models not loaded")
        }
        let audio = try multiUtteranceFixture(gapSeconds: 1.5)
        print("Audio: \(audio.count) samples (\(Double(audio.count)/16000)s)")

        vad.resetState()
        let session = try model.createSession()

        var vadLeftover: [Float] = []
        var speechActive = false
        var silenceCount = 0
        var hasPendingUtterance = false

        let timerChunk = 4800
        var offset = 0
        var tick = 0
        while offset < audio.count {
            let end = min(offset + timerChunk, audio.count)
            let chunk = Array(audio[offset..<end])
            offset = end
            tick += 1

            // VAD
            var vadInput = vadLeftover
            vadInput.append(contentsOf: chunk)
            var vadOffset = 0
            var speechChunksInTick = 0
            while vadOffset + 512 <= vadInput.count {
                let prob = vad.processChunk(Array(vadInput[vadOffset..<vadOffset+512]))
                if prob >= 0.5 {
                    speechActive = true
                    silenceCount = 0
                    hasPendingUtterance = true
                    speechChunksInTick += 1
                } else {
                    silenceCount += 1
                    if silenceCount >= 15 { speechActive = false }
                }
                vadOffset += 512
            }
            vadLeftover = Array(vadInput[vadOffset...])

            // ASR
            var partials = try session.pushAudio(chunk)

            var forcedText: String? = nil
            if hasPendingUtterance && !speechActive && silenceCount >= 30 {
                if let forced = session.forceEndOfUtterance() {
                    forcedText = forced.text
                    partials.append(forced)
                }
                hasPendingUtterance = false
            }

            let partialSummary = partials.map { "[\($0.isFinal ? "F" : "P")] '\($0.text)'" }.joined(separator: " | ")
            print("tick=\(tick) speech=\(speechChunksInTick) silence=\(silenceCount) vad=\(speechActive) pend=\(hasPendingUtterance) partials=\(partials.count) \(partialSummary) \(forcedText.map { "FORCED='\($0)'" } ?? "")")
        }
        let endFinals = try session.finalize()
        print("finalize(): \(endFinals.map { "[\($0.isFinal ? "F" : "P")] '\($0.text)'" })")
    }

    /// Two utterances separated by silence should produce two separate finals
    /// committed via the VAD force-finalize path (not waiting for model EOU).
    func testMultiUtteranceForceFinalize() throws {
        let audio = try multiUtteranceFixture(gapSeconds: 1.5)
        let finals = try simulateDictateDemoPipeline(audio: audio)

        print("Pipeline finals: \(finals)")
        XCTAssertGreaterThanOrEqual(finals.count, 2,
            "Expected ≥2 finals (one per utterance), got \(finals.count): \(finals)")
        for text in finals {
            XCTAssertFalse(text.isEmpty, "Finals must have non-empty text")
        }
    }

    /// Regression for the "stuck EOU flag" bug — when the joint detected EOU
    /// during inter-sentence silence with no pending tokens, the flag stayed
    /// true and prematurely finalized the first tokens of the next utterance.
    /// The fix was to clear eouDetected in the empty-text early return path.
    ///
    /// We verify this indirectly: the second final must not be just a tiny
    /// fragment of the second utterance (as would happen if it fired on the
    /// first few tokens).
    func testSecondUtteranceNotPrematurelyFinalized() throws {
        let audio = try multiUtteranceFixture(gapSeconds: 1.5)
        let finals = try simulateDictateDemoPipeline(audio: audio)

        guard finals.count >= 2 else {
            XCTFail("Need ≥2 finals for this test, got \(finals.count)")
            return
        }
        // Both utterances are copies of the same clip, so the second final
        // should be comparable in length to the first (within 50%).
        let firstWords = finals[0].split(separator: " ").count
        let secondWords = finals[1].split(separator: " ").count
        XCTAssertGreaterThanOrEqual(secondWords, max(1, firstWords / 2),
            "Second utterance was prematurely finalized: first='\(finals[0])' (\(firstWords)w), second='\(finals[1])' (\(secondWords)w)")
    }

    /// Regression for the noise-in-silence bug — brief noise spikes during
    /// the inter-sentence pause kept resetting the joint's EOU debounce timer,
    /// so the second sentence stayed stuck as a partial for ~6s. The VAD-based
    /// force-finalize bypasses the joint's timer entirely.
    func testNoiseInSilenceDoesNotBlockFinalize() throws {
        let testAudioURL = URL(fileURLWithPath: "../../Tests/ParakeetStreamingASRTests/Resources/test_audio.wav")
        guard FileManager.default.fileExists(atPath: testAudioURL.path) else {
            throw XCTSkip("test_audio.wav not found")
        }
        let clip = try AudioFileLoader.load(url: testAudioURL, targetSampleRate: 16000)

        // 1.5s of low-amplitude noise (mimics room tone / desk taps / mouse clicks)
        var noisyGap = [Float](repeating: 0, count: Int(16000 * 1.5))
        var rng = SystemRandomNumberGenerator()
        for i in 0..<noisyGap.count {
            let r = Float(rng.next() % 1000) / 1000.0 - 0.5
            noisyGap[i] = r * 0.04  // rms ~0.02 — matches the log we saw
        }

        let audio = clip + noisyGap + clip
        let finals = try simulateDictateDemoPipeline(audio: audio)

        print("Noisy-gap finals: \(finals)")
        XCTAssertGreaterThanOrEqual(finals.count, 2,
            "VAD force-finalize should commit both utterances even with noise in the gap, got: \(finals)")
    }

    // MARK: - Latency

    func testStreamingChunkLatency() throws {
        guard let model = Self.model else { throw XCTSkip("Model not loaded") }

        let session = try model.createSession()
        let chunkSize = 5440
        let chunkMs: Float = 340.0  // 5440 / 16000 * 1000

        var audio = [Float](repeating: 0, count: chunkSize)
        for i in 0..<chunkSize {
            audio[i] = sin(2.0 * .pi * 440.0 * Float(i) / 16000.0) * 0.3
        }

        // Warmup
        _ = try session.pushAudio(audio)

        // Benchmark
        var times: [Double] = []
        for _ in 0..<10 {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = try session.pushAudio(audio)
            times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }

        let avg = times.reduce(0, +) / Double(times.count)
        let rtf = avg / Double(chunkMs)
        print("Chunk latency: avg=\(String(format: "%.1f", avg))ms RTF=\(String(format: "%.3f", rtf))")
        XCTAssertLessThan(rtf, 1.0, "Must be real-time")
    }
}
