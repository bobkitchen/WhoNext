import Foundation
import AVFoundation

/// Accumulates audio into 10-second chunks for WhisperKit processing.
/// Handles mic and system audio separately, mixes only when emitting.
actor AudioChunkBuffer {

    // MARK: - Configuration

    /// Hard ceiling for chunk duration. Long chunks give the transcriber enough
    /// acoustic context to produce coherent sentences, but they also bound
    /// end-to-end latency. We emit at this point no matter what.
    private let targetDuration: TimeInterval = 10.0

    /// Minimum audio accumulated before we'll consider an early emit. Below this,
    /// a chunk has too little context for Parakeet to transcribe cleanly.
    private let earlyEmitMinDuration: TimeInterval = 4.0

    /// If the trailing portion of both streams has been silent for at least this
    /// long, a natural pause (likely a speaker boundary) has occurred and we flush
    /// early. This is what cuts perceived speaker-switch latency roughly in half
    /// without splitting words — pauses are already sentence boundaries.
    private let silenceTailDuration: TimeInterval = 0.8

    /// RMS threshold below which audio is considered silent (voice VAD).
    /// Tuned against post-AEC mic floor; system stream noise floor is lower still.
    private let silenceRMSThreshold: Float = 0.005

    /// Overlap duration for continuity between chunks
    private let overlapDuration: TimeInterval = 1.0

    /// Sample rate (16kHz for WhisperKit)
    private let sampleRate: Double = 16000.0

    // MARK: - Buffers

    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []

    // MARK: - Computed Properties

    private var targetSamples: Int {
        Int(targetDuration * sampleRate)
    }

    private var overlapSamples: Int {
        Int(overlapDuration * sampleRate)
    }

    private var micDuration: TimeInterval {
        Double(micBuffer.count) / sampleRate
    }

    private var systemDuration: TimeInterval {
        Double(systemBuffer.count) / sampleRate
    }

    // MARK: - Public Interface

    /// Add microphone audio samples
    /// - Returns: Mixed audio chunk if target duration accumulated, nil otherwise
    func addMicAudio(_ samples: [Float]) -> [Float]? {
        micBuffer.append(contentsOf: samples)
        return checkAndEmitChunk()
    }

    /// Add system audio samples
    /// - Returns: Mixed audio chunk if target duration accumulated, nil otherwise
    func addSystemAudio(_ samples: [Float]) -> [Float]? {
        systemBuffer.append(contentsOf: samples)
        return checkAndEmitChunk()
    }

    /// Add samples from AVAudioPCMBuffer (convenience method)
    func addBuffer(_ buffer: AVAudioPCMBuffer, isMic: Bool) -> [Float]? {
        let samples = extractSamples(from: buffer)
        return isMic ? addMicAudio(samples) : addSystemAudio(samples)
    }

    /// Force emit current buffer (for end of recording)
    func flush() -> [Float]? {
        guard micBuffer.count > 0 || systemBuffer.count > 0 else {
            return nil
        }

        let chunk = mixBuffers()
        micBuffer.removeAll()
        systemBuffer.removeAll()
        return chunk
    }

    /// Clear all buffers
    func reset() {
        micBuffer.removeAll()
        systemBuffer.removeAll()
    }

    /// Current buffer durations for diagnostics
    func getDurations() -> (mic: TimeInterval, system: TimeInterval) {
        (micDuration, systemDuration)
    }

    // MARK: - Private Methods

    private func checkAndEmitChunk() -> [Float]? {
        let maxDuration = max(micDuration, systemDuration)

        // Hard ceiling: always emit at the target duration to cap latency.
        if maxDuration >= targetDuration {
            return emit(reason: "target duration")
        }

        // Early emit on silence boundary: when we have enough audio for the
        // transcriber to work with AND both streams are silent at the tail, a
        // speaker has likely finished. Flushing here cuts perceived latency at
        // speaker transitions (the times the user actually notices).
        if maxDuration >= earlyEmitMinDuration, hasSilentTailOnBothStreams() {
            return emit(reason: "silence boundary")
        }

        return nil
    }

    private func emit(reason: String) -> [Float] {
        let chunk = mixBuffers()
        trimBuffers()
        let chunkDuration = Double(chunk.count) / sampleRate
        debugLog("[AudioChunkBuffer] Emitting \(String(format: "%.1f", chunkDuration))s chunk — \(reason)")
        return chunk
    }

    /// True iff the trailing `silenceTailDuration` of both mic and system buffers
    /// is below the RMS silence threshold. A stream with no audio buffered at all
    /// is considered silent (it can't be producing speech).
    private func hasSilentTailOnBothStreams() -> Bool {
        let tailSamples = Int(silenceTailDuration * sampleRate)
        return isTailSilent(micBuffer, tailSamples: tailSamples) &&
               isTailSilent(systemBuffer, tailSamples: tailSamples)
    }

    private func isTailSilent(_ buffer: [Float], tailSamples: Int) -> Bool {
        guard buffer.count >= tailSamples else {
            // Not enough samples yet — treat as silent (no recent activity on this stream).
            return true
        }
        let start = buffer.count - tailSamples
        var sumSquares: Float = 0
        for i in start..<buffer.count {
            sumSquares += buffer[i] * buffer[i]
        }
        let rms = sqrt(sumSquares / Float(tailSamples))
        return rms < silenceRMSThreshold
    }

    private func mixBuffers() -> [Float] {
        // Determine output length (use the longer buffer)
        let outputLength = max(micBuffer.count, systemBuffer.count)
        guard outputLength > 0 else { return [] }

        var mixed = [Float](repeating: 0, count: outputLength)

        let hasMic = !micBuffer.isEmpty && micBuffer.contains { abs($0) > 0.0001 }
        let hasSystem = !systemBuffer.isEmpty && systemBuffer.contains { abs($0) > 0.0001 }

        if hasMic && hasSystem {
            // Both sources have audio - adaptive mixing to avoid crushing quiet AEC signals.
            // Estimate peak amplitude to decide if attenuation is needed.
            var peakEstimate: Float = 0
            let sampleStep = max(outputLength / 200, 1)  // Sample ~200 points for speed
            for i in stride(from: 0, to: outputLength, by: sampleStep) {
                let micSample = i < micBuffer.count ? abs(micBuffer[i]) : 0
                let systemSample = i < systemBuffer.count ? abs(systemBuffer[i]) : 0
                peakEstimate = max(peakEstimate, micSample + systemSample)
            }

            // Only attenuate if combined signal risks clipping
            let gain: Float = peakEstimate > 0.8 ? 0.5 : 1.0

            for i in 0..<outputLength {
                let micSample = i < micBuffer.count ? micBuffer[i] : 0
                let systemSample = i < systemBuffer.count ? systemBuffer[i] : 0
                mixed[i] = min(max((micSample + systemSample) * gain, -1.0), 1.0)
            }

        } else if hasMic {
            // Mic only - use directly
            mixed = Array(micBuffer.prefix(outputLength))

        } else if hasSystem {
            // System only - use directly
            mixed = Array(systemBuffer.prefix(outputLength))

        } else {
            // Silence - return zeros
            return mixed
        }

        return mixed
    }

    private func trimBuffers() {
        // Keep overlap for continuity
        if micBuffer.count > overlapSamples {
            micBuffer = Array(micBuffer.suffix(overlapSamples))
        }
        if systemBuffer.count > overlapSamples {
            systemBuffer = Array(systemBuffer.suffix(overlapSamples))
        }
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let count = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: count)

        // Use first channel (mono)
        memcpy(&samples, channelData[0], count * MemoryLayout<Float>.size)

        return samples
    }
}

// MARK: - Diagnostics Extension

extension AudioChunkBuffer {

    /// Get current buffer statistics
    func getStats() -> BufferStats {
        let micRMS = calculateRMS(micBuffer)
        let systemRMS = calculateRMS(systemBuffer)

        return BufferStats(
            micDuration: micDuration,
            systemDuration: systemDuration,
            micRMS: micRMS,
            systemRMS: systemRMS,
            micSamples: micBuffer.count,
            systemSamples: systemBuffer.count
        )
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

struct BufferStats: Sendable {
    let micDuration: TimeInterval
    let systemDuration: TimeInterval
    let micRMS: Float
    let systemRMS: Float
    let micSamples: Int
    let systemSamples: Int

    var description: String {
        """
        Mic: \(String(format: "%.1f", micDuration))s (\(micSamples) samples, RMS: \(String(format: "%.4f", micRMS)))
        System: \(String(format: "%.1f", systemDuration))s (\(systemSamples) samples, RMS: \(String(format: "%.4f", systemRMS)))
        """
    }
}
