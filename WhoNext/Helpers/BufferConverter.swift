import AVFoundation
import Foundation
import os

/// Converts audio buffers between different PCM formats
/// Required for compatibility with SpeechAnalyzer's expected format
/// Thread-safe: creates a new converter for each conversion to avoid race conditions
class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    /// Converts an audio buffer to the specified format
    /// - Parameters:
    ///   - buffer: The input PCM buffer to convert
    ///   - format: The target audio format
    /// - Returns: A converted PCM buffer in the target format
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format

        // If formats match, return original buffer
        guard inputFormat != format else {
            return buffer
        }

        // Create a fresh converter for each call to ensure thread safety
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw Error.failedToCreateConverter
        }
        // Sacrifice quality of first samples to avoid timestamp drift
        converter.primeMethod = .none

        // Calculate frame capacity for output buffer
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        
        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        let bufferProcessedLock = OSAllocatedUnfairLock(initialState: false)

        let status = converter.convert(to: conversionBuffer, error: &nsError) { packetCount, inputStatusPointer in
            let wasProcessed = bufferProcessedLock.withLock { bufferProcessed in
                let wasProcessed = bufferProcessed
                bufferProcessed = true
                return wasProcessed
            }
            inputStatusPointer.pointee = wasProcessed ? .noDataNow : .haveData
            return wasProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}