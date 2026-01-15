import Foundation
import AVFoundation

/// Accumulates audio into 15-second chunks for optimal WhisperKit processing
/// Handles mic and system audio separately, mixes only when emitting
actor AudioChunkBuffer {

    // MARK: - Configuration

    /// Target duration for each chunk (WhisperKit optimal)
    private let targetDuration: TimeInterval = 15.0

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
    /// - Returns: Mixed audio chunk if 15 seconds accumulated, nil otherwise
    func addMicAudio(_ samples: [Float]) -> [Float]? {
        micBuffer.append(contentsOf: samples)
        return checkAndEmitChunk()
    }

    /// Add system audio samples
    /// - Returns: Mixed audio chunk if 15 seconds accumulated, nil otherwise
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
        // Need at least targetDuration from either source
        let maxDuration = max(micDuration, systemDuration)

        guard maxDuration >= targetDuration else {
            return nil
        }

        // Mix and emit
        let chunk = mixBuffers()

        // Keep overlap for continuity
        trimBuffers()

        // Log emission
        let chunkDuration = Double(chunk.count) / sampleRate
        print("[AudioChunkBuffer] Emitting \(String(format: "%.1f", chunkDuration))s chunk (\(chunk.count) samples)")

        return chunk
    }

    private func mixBuffers() -> [Float] {
        // Determine output length (use the longer buffer)
        let outputLength = max(micBuffer.count, systemBuffer.count)
        guard outputLength > 0 else { return [] }

        var mixed = [Float](repeating: 0, count: outputLength)

        let hasMic = !micBuffer.isEmpty && micBuffer.contains { abs($0) > 0.001 }
        let hasSystem = !systemBuffer.isEmpty && systemBuffer.contains { abs($0) > 0.001 }

        if hasMic && hasSystem {
            // Both sources have audio - mix them
            for i in 0..<outputLength {
                let micSample = i < micBuffer.count ? micBuffer[i] : 0
                let systemSample = i < systemBuffer.count ? systemBuffer[i] : 0

                // Mix without halving (old bug!) - use peak normalization instead
                let rawMix = micSample + systemSample
                mixed[i] = rawMix
            }

            // Apply soft clipping if needed (prevents harsh distortion)
            let peak = mixed.max { abs($0) < abs($1) }.map { abs($0) } ?? 0
            if peak > 0.95 {
                let scale = 0.95 / peak
                for i in 0..<mixed.count {
                    mixed[i] *= scale
                }
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
