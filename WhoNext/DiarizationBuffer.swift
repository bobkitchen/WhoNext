import Foundation
import AVFoundation

/// Accumulates audio into 10-second chunks for optimal FluidAudio diarization processing
/// Tracks timing information to align diarization results with transcription
actor DiarizationBuffer {

    // MARK: - Configuration

    /// Target duration for each chunk (FluidAudio optimal is 10s)
    private let targetDuration: TimeInterval = 10.0

    /// Overlap duration for speaker continuity across chunks
    private let overlapDuration: TimeInterval = 1.0

    /// Sample rate (16kHz for FluidAudio)
    private let sampleRate: Double = 16000.0

    // MARK: - Buffers

    private var buffer: [Float] = []
    private var chunkStartTime: TimeInterval = 0
    private var isFirstChunk = true

    // MARK: - Computed Properties

    private var targetSamples: Int {
        Int(targetDuration * sampleRate)
    }

    private var overlapSamples: Int {
        Int(overlapDuration * sampleRate)
    }

    private var currentDuration: TimeInterval {
        Double(buffer.count) / sampleRate
    }

    // MARK: - Public Interface

    /// Add audio samples and return chunk if 10 seconds accumulated
    /// - Parameters:
    ///   - samples: Float array of audio samples at 16kHz
    ///   - recordingElapsed: Current recording duration (for timing)
    /// - Returns: Tuple of (chunk samples, start time) if chunk ready, nil otherwise
    func addSamples(_ samples: [Float], recordingElapsed: TimeInterval) -> (chunk: [Float], startTime: TimeInterval)? {
        // Track start time of current chunk
        if buffer.isEmpty {
            chunkStartTime = recordingElapsed - (Double(samples.count) / sampleRate)
            if chunkStartTime < 0 { chunkStartTime = 0 }
        }

        buffer.append(contentsOf: samples)

        return checkAndEmitChunk()
    }

    /// Add samples from AVAudioPCMBuffer
    func addBuffer(_ audioBuffer: AVAudioPCMBuffer, recordingElapsed: TimeInterval) -> (chunk: [Float], startTime: TimeInterval)? {
        let samples = extractSamples(from: audioBuffer)
        return addSamples(samples, recordingElapsed: recordingElapsed)
    }

    /// Force emit current buffer (for end of recording)
    func flush() -> (chunk: [Float], startTime: TimeInterval)? {
        guard !buffer.isEmpty else { return nil }

        let chunk = buffer
        let startTime = chunkStartTime

        buffer.removeAll()
        isFirstChunk = true

        let chunkDuration = Double(chunk.count) / sampleRate
        print("[DiarizationBuffer] Flushing \(String(format: "%.1f", chunkDuration))s chunk at \(String(format: "%.1f", startTime))s")

        return (chunk: chunk, startTime: startTime)
    }

    /// Clear all buffers
    func reset() {
        buffer.removeAll()
        chunkStartTime = 0
        isFirstChunk = true
    }

    /// Current buffer duration for diagnostics
    func getDuration() -> TimeInterval {
        currentDuration
    }

    // MARK: - Private Methods

    private func checkAndEmitChunk() -> (chunk: [Float], startTime: TimeInterval)? {
        guard buffer.count >= targetSamples else {
            return nil
        }

        // Extract chunk
        let chunk = Array(buffer.prefix(targetSamples))
        let startTime = chunkStartTime

        // Keep overlap for speaker continuity
        if buffer.count > overlapSamples {
            buffer = Array(buffer.suffix(overlapSamples))
        } else {
            buffer.removeAll()
        }

        // Update start time for next chunk (accounts for overlap)
        chunkStartTime = startTime + targetDuration - overlapDuration

        let chunkDuration = Double(chunk.count) / sampleRate
        print("[DiarizationBuffer] Emitting \(String(format: "%.1f", chunkDuration))s chunk at \(String(format: "%.1f", startTime))s")

        isFirstChunk = false
        return (chunk: chunk, startTime: startTime)
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

extension DiarizationBuffer {

    /// Get current buffer statistics
    func getStats() -> DiarizationBufferStats {
        let rms = calculateRMS(buffer)

        return DiarizationBufferStats(
            duration: currentDuration,
            sampleCount: buffer.count,
            rms: rms,
            startTime: chunkStartTime
        )
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

struct DiarizationBufferStats: Sendable {
    let duration: TimeInterval
    let sampleCount: Int
    let rms: Float
    let startTime: TimeInterval

    var description: String {
        """
        Duration: \(String(format: "%.1f", duration))s (\(sampleCount) samples)
        RMS: \(String(format: "%.4f", rms))
        Start time: \(String(format: "%.1f", startTime))s
        """
    }
}
