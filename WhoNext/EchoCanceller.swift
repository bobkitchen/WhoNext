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
/// - Noise suppression via Speex preprocessor (standalone, NOT linked to echo state)
///
/// Architecture note: The preprocessor runs STANDALONE (not linked to the echo
/// state). Linking via SPEEX_PREPROCESS_SET_ECHO_STATE causes the preprocessor
/// to call speex_echo_get_residual → spx_fft, which crashes with EXC_BAD_ACCESS
/// due to NULL FFT table pointers in the CSpeex SPM package. Echo removal is
/// handled by speex_echo_cancellation alone; the preprocessor adds noise
/// suppression and dereverb on top.
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

    /// Opaque preprocessor state (noise suppression + dereverb, standalone)
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

    // MARK: - Diagnostics & Safety

    private var framesProcessed: Int = 0
    private var echoFramesProcessed: Int = 0
    private var passthroughFrames: Int = 0
    private var logInterval: Int = 100

    /// Self-disabling flag: if Speex produces garbage, bypass it
    private var disabled: Bool = false
    private var disableReason: String?

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

        debugLog("[EchoCanceller] Config: frameSize=\(frameSize), filterLength=\(filterLength), delayFrames=\(delayFrames), maxFarEndFrames=\(maxFarEndFrames)")

        // Create echo canceller
        echoState = speex_echo_state_init(Int32(frameSize), Int32(filterLength))

        if echoState == nil {
            debugLog("[EchoCanceller] ERROR: speex_echo_state_init returned NULL!")
            disabled = true
            disableReason = "speex_echo_state_init failed"
        } else {
            debugLog("[EchoCanceller] Echo state created: \(echoState!)")

            // Set sample rate
            var rate = Int32(sampleRate)
            speex_echo_ctl(echoState!, SPEEX_ECHO_SET_SAMPLING_RATE, &rate)
        }

        // Create STANDALONE preprocessor for noise suppression + dereverb.
        // NOT linked to echo state — linking causes crashes in speex_echo_get_residual.
        preprocessState = speex_preprocess_state_init(Int32(frameSize), Int32(sampleRate))

        if preprocessState == nil {
            debugLog("[EchoCanceller] WARNING: speex_preprocess_state_init returned NULL — noise suppression disabled")
        } else {
            debugLog("[EchoCanceller] Preprocessor created (standalone, no echo state link)")

            // Enable noise suppression (-25 dB)
            var denoise: Int32 = 1
            speex_preprocess_ctl(preprocessState!, SPEEX_PREPROCESS_SET_DENOISE, &denoise)
            var noiseSuppress: Int32 = -25
            speex_preprocess_ctl(preprocessState!, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &noiseSuppress)

            // Enable dereverb
            var dereverb: Int32 = 1
            speex_preprocess_ctl(preprocessState!, SPEEX_PREPROCESS_SET_DEREVERB, &dereverb)

            // DO NOT link to echo state:
            // speex_preprocess_ctl(ppState, SPEEX_PREPROCESS_SET_ECHO_STATE, &ecStatePtr)
            // This causes crashes in spx_fft via speex_echo_get_residual with NULL table pointers.
        }

        debugLog("[EchoCanceller] Initialized: echo=\(echoState != nil), preprocess=\(preprocessState != nil), disabled=\(disabled)")
    }

    deinit {
        lock.lock()
        let ec = echoState
        let pp = preprocessState
        echoState = nil
        preprocessState = nil
        lock.unlock()

        if let state = ec {
            speex_echo_state_destroy(state)
        }
        if let state = pp {
            speex_preprocess_state_destroy(state)
        }
    }

    // MARK: - Public API

    /// Feed far-end (system/speaker) audio. Call this with system audio samples.
    /// Must be called BEFORE `cancelEcho()` for corresponding time period.
    func feedFarEnd(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        guard !disabled else { return }

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

        // Log far-end buffering progress at startup
        if farEndRingBuffer.count > 0 && farEndRingBuffer.count <= 5 {
            debugLog("[EchoCanceller] Far-end buffer growing: \(farEndRingBuffer.count) frames (need >\(delayFrames) for AEC)")
        }
    }

    /// Cancel echo from mic (near-end) audio. Returns cleaned audio with echo removed.
    /// The returned array may be shorter than input if samples are still accumulating into frames.
    func cancelEcho(_ micSamples: [Float]) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        // If disabled, pass through unchanged
        guard !disabled else { return micSamples }
        guard let ecState = echoState else {
            debugLog("[EchoCanceller] cancelEcho called but echoState is nil — passing through")
            return micSamples
        }

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

                // Log first echo cancellation frame
                if echoFramesProcessed == 0 {
                    debugLog("[EchoCanceller] First AEC frame — far-end buffer had \(farEndRingBuffer.count + 1) frames, delay=\(delayFrames)")
                }

                // Run echo cancellation (speex_echo_cancellation is safe — no FFT table issue)
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

                echoFramesProcessed += 1

                // Run standalone preprocessor (noise suppression + dereverb)
                // Safe because preprocessor is NOT linked to echo state
                if let ppState = preprocessState {
                    outputInt16.withUnsafeMutableBufferPointer { outPtr in
                        speex_preprocess_run(ppState, outPtr.baseAddress)
                    }
                }
            } else {
                // No far-end reference available — pass through mic unchanged
                outputInt16 = micInt16
                passthroughFrames += 1

                // Log passthrough at startup
                if passthroughFrames <= 3 {
                    debugLog("[EchoCanceller] Passthrough frame #\(passthroughFrames) — waiting for far-end buffer (\(farEndRingBuffer.count)/\(delayFrames + 1) frames)")
                }
            }

            // Convert back to Float32
            let outputFloat = int16ToFloat(outputInt16)
            outputAccumulator.append(contentsOf: outputFloat)

            framesProcessed += 1
            if framesProcessed % logInterval == 0 {
                let farEndBuffered = farEndRingBuffer.count
                debugLog("[EchoCanceller] Stats: \(framesProcessed) total, \(echoFramesProcessed) AEC, \(passthroughFrames) passthrough, far-end buffer: \(farEndBuffered) frames")
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
            let oldDelay = delayFrames
            delayFrames = newDelayFrames
            debugLog("[EchoCanceller] Delay updated: \(oldDelay) -> \(delayFrames) frames (\(ms)ms)")
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
        echoFramesProcessed = 0
        passthroughFrames = 0

        // Re-enable if previously disabled (new session, fresh start)
        if disabled {
            debugLog("[EchoCanceller] Reset: was disabled (\(disableReason ?? "unknown")), re-enabling")
            disabled = false
            disableReason = nil
        }

        debugLog("[EchoCanceller] Reset complete — ready for new session")
    }

    /// Whether the echo canceller is operational
    var isAvailable: Bool {
        echoState != nil && !disabled
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
