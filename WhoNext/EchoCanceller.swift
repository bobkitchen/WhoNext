import Foundation
import speex.dsp

/// Echo canceller using SpeexDSP's acoustic echo cancellation (AEC).
///
/// Takes two inputs — mic audio (near-end, contains echo) and system audio
/// (far-end, the echo source) — and outputs echo-cancelled mic audio containing
/// only the local speaker's voice.
///
/// SpeexDSP operates on fixed-size frames of Int16 samples. This wrapper handles:
/// - Float32 ↔ Int16 conversion (our pipeline uses Float32)
/// - Frame-based processing (accumulates samples into fixed-size frames)
/// - Far-end ring buffer with delay compensation
/// - Noise suppression via Speex preprocessor
///
/// Usage:
///   1. Feed system audio (far-end) via `feedFarEnd(_:)` — call frequently
///   2. Cancel echo from mic audio via `cancelEcho(_:)` — returns cleaned samples
///   System audio should be fed BEFORE the corresponding mic frame for best results.
final class EchoCanceller: @unchecked Sendable {

    // MARK: - Configuration

    /// Samples per processing frame (10ms at 16kHz)
    private let frameSize: Int

    /// Echo tail length in samples (how far back AEC looks for echoes)
    private let filterLength: Int

    /// Sample rate (must match both streams)
    private let sampleRate: Int

    // MARK: - SpeexDSP State

    /// Opaque echo canceller state
    private var echoState: OpaquePointer?

    /// Opaque preprocessor state (noise suppression + dereverb)
    private var preprocessState: OpaquePointer?

    // MARK: - Buffers

    /// Accumulated mic samples waiting to fill a frame
    private var micAccumulator: [Float] = []

    /// Accumulated far-end samples waiting to fill a frame
    private var farEndAccumulator: [Float] = []

    /// Ring buffer of far-end frames for delay compensation
    private var farEndRingBuffer: [[Int16]] = []

    /// Maximum number of far-end frames to buffer (covers up to ~200ms delay)
    private let maxFarEndFrames: Int

    /// Estimated delay in frames between far-end playback and mic pickup
    private var delayFrames: Int

    /// Output accumulator for returning variable-length results
    private var outputAccumulator: [Float] = []

    /// Thread safety
    private let lock = NSLock()

    // MARK: - Diagnostics

    private var framesProcessed: Int = 0
    private var logInterval: Int = 100

    // MARK: - Init

    /// Initialize the echo canceller.
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (default 16000 Hz)
    ///   - frameDurationMs: Processing frame duration in ms (default 10ms)
    ///   - filterLengthMs: Echo tail length in ms (default 300ms — covers typical laptop echo)
    ///   - delayMs: Estimated delay between far-end playback and mic pickup (default 40ms)
    init(sampleRate: Int = 16000,
         frameDurationMs: Int = 10,
         filterLengthMs: Int = 300,
         delayMs: Int = 40) {

        self.sampleRate = sampleRate
        self.frameSize = sampleRate * frameDurationMs / 1000   // 160 samples at 16kHz/10ms
        self.filterLength = sampleRate * filterLengthMs / 1000 // 4800 samples at 16kHz/300ms
        self.delayFrames = delayMs / frameDurationMs           // 4 frames at 40ms/10ms
        self.maxFarEndFrames = sampleRate * 200 / 1000 / frameSize // ~200ms worth of frames

        // Create echo canceller
        echoState = speex_echo_state_init(Int32(frameSize), Int32(filterLength))

        // Set sample rate
        if let state = echoState {
            var rate = Int32(sampleRate)
            speex_echo_ctl(state, SPEEX_ECHO_SET_SAMPLING_RATE, &rate)
        }

        // Create preprocessor for noise suppression
        preprocessState = speex_preprocess_state_init(Int32(frameSize), Int32(sampleRate))

        if let ppState = preprocessState, let ecState = echoState {
            // Link preprocessor to echo canceller
            var ecStatePtr = ecState
            speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_ECHO_STATE, &ecStatePtr)

            // Enable noise suppression (-25 dB)
            var denoise: Int32 = 1
            speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_DENOISE, &denoise)
            var noiseSuppress: Int32 = -25
            speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &noiseSuppress)

            // Enable dereverb
            var dereverb: Int32 = 1
            speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_DEREVERB, &dereverb)
        }

        debugLog("[EchoCanceller] Initialized: frameSize=\(frameSize), filterLength=\(filterLength), delayFrames=\(delayFrames)")
    }

    deinit {
        if let state = echoState {
            speex_echo_state_destroy(state)
        }
        if let state = preprocessState {
            speex_preprocess_state_destroy(state)
        }
    }

    // MARK: - Public API

    /// Feed far-end (system/speaker) audio. Call this with system audio samples.
    /// Must be called BEFORE `cancelEcho()` for corresponding time period.
    func feedFarEnd(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        farEndAccumulator.append(contentsOf: samples)

        // Process complete frames into the ring buffer
        while farEndAccumulator.count >= frameSize {
            let frame = Array(farEndAccumulator.prefix(frameSize))
            farEndAccumulator = Array(farEndAccumulator.dropFirst(frameSize))

            let int16Frame = floatToInt16(frame)
            farEndRingBuffer.append(int16Frame)

            // Cap ring buffer size
            if farEndRingBuffer.count > maxFarEndFrames {
                farEndRingBuffer.removeFirst()
            }
        }
    }

    /// Cancel echo from mic (near-end) audio. Returns cleaned audio with echo removed.
    /// The returned array may be shorter than input if samples are still accumulating into frames.
    func cancelEcho(_ micSamples: [Float]) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        guard let ecState = echoState else { return micSamples }

        micAccumulator.append(contentsOf: micSamples)
        outputAccumulator.removeAll()

        // Process complete frames
        while micAccumulator.count >= frameSize {
            let micFrame = Array(micAccumulator.prefix(frameSize))
            micAccumulator = Array(micAccumulator.dropFirst(frameSize))

            let micInt16 = floatToInt16(micFrame)
            var outputInt16 = [Int16](repeating: 0, count: frameSize)

            // Get the far-end frame accounting for delay
            if farEndRingBuffer.count > delayFrames {
                let farEndFrame = farEndRingBuffer.removeFirst()

                // Run echo cancellation
                micInt16.withUnsafeBufferPointer { micPtr in
                    farEndFrame.withUnsafeBufferPointer { farPtr in
                        outputInt16.withUnsafeMutableBufferPointer { outPtr in
                            speex_echo_cancellation(
                                ecState,
                                micPtr.baseAddress,
                                farPtr.baseAddress,
                                outPtr.baseAddress
                            )
                        }
                    }
                }

                // Run preprocessor (noise suppression + dereverb)
                if let ppState = preprocessState {
                    outputInt16.withUnsafeMutableBufferPointer { outPtr in
                        speex_preprocess_run(ppState, outPtr.baseAddress)
                    }
                }
            } else {
                // No far-end reference available — pass through mic unchanged
                // This happens at startup before enough system audio is buffered
                outputInt16 = micInt16
            }

            // Convert back to Float32
            let outputFloat = int16ToFloat(outputInt16)
            outputAccumulator.append(contentsOf: outputFloat)

            framesProcessed += 1
            if framesProcessed % logInterval == 0 {
                let farEndBuffered = farEndRingBuffer.count
                debugLog("[EchoCanceller] Processed \(framesProcessed) frames, far-end buffer: \(farEndBuffered) frames")
            }
        }

        return outputAccumulator
    }

    /// Update the estimated delay between far-end playback and mic pickup.
    /// Call this when `LeakageDetector` provides an updated cross-correlation lag.
    func updateDelay(ms: Int) {
        lock.lock()
        defer { lock.unlock() }

        let frameDurationMs = frameSize * 1000 / sampleRate
        let newDelayFrames = max(0, ms / frameDurationMs)
        if newDelayFrames != delayFrames {
            delayFrames = newDelayFrames
            debugLog("[EchoCanceller] Delay updated to \(ms)ms (\(delayFrames) frames)")
        }
    }

    /// Reset echo canceller state. Call between recordings.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        if let state = echoState {
            speex_echo_state_reset(state)
        }

        micAccumulator.removeAll()
        farEndAccumulator.removeAll()
        farEndRingBuffer.removeAll()
        outputAccumulator.removeAll()
        framesProcessed = 0

        debugLog("[EchoCanceller] Reset")
    }

    /// Whether the echo canceller is operational
    var isAvailable: Bool {
        echoState != nil
    }

    // MARK: - Private Helpers

    /// Convert Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
    private func floatToInt16(_ samples: [Float]) -> [Int16] {
        samples.map { sample in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * 32767.0)
        }
    }

    /// Convert Int16 [-32768, 32767] to Float32 [-1.0, 1.0]
    private func int16ToFloat(_ samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32768.0 }
    }
}
