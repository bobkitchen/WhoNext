import Foundation
import AVFoundation

// MARK: - Parakeet MLX Transcriber
/// Local speech-to-text transcription using Parakeet TDT model
/// This uses the actual Parakeet model, NOT Apple's Speech Recognition
class ParakeetMLXTranscriber {
    
    // MARK: - Properties
    private let parakeetModel: ParakeetTDTModel
    private var isModelLoaded = false
    private let audioProcessor = AudioProcessor()
    
    // Configuration
    private let sampleRate: Double = 16000
    private let chunkDuration: Double = 30.0 // Process 30 second chunks
    
    // MARK: - Initialization
    
    init() {
        self.parakeetModel = ParakeetTDTModel()
        print("🦜 Initializing Parakeet MLX Transcriber (real model, not Speech Recognition)")
    }
    
    // MARK: - Public Methods
    
    /// Check if the model is available and loaded
    var isAvailable: Bool {
        return isModelLoaded
    }
    
    /// Load the model if not already loaded
    func loadModel() async throws {
        guard !isModelLoaded else { return }
        
        do {
            try await parakeetModel.loadModel()
            isModelLoaded = true
            print("✅ Parakeet TDT model loaded and ready for transcription")
        } catch {
            print("❌ Failed to load Parakeet model: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Transcribe audio data
    func transcribe(_ audioData: Data) async throws -> TranscriptionResult {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        
        // Convert data to audio buffer
        guard let buffer = audioProcessor.dataToBuffer(audioData) else {
            throw TranscriptionError.invalidAudioData
        }
        
        // Resample to 16kHz if needed
        guard let resampledBuffer = audioProcessor.resample(buffer, to: sampleRate) else {
            throw TranscriptionError.invalidAudioData
        }
        
        // Run Parakeet transcription
        return try await parakeetModel.transcribe(resampledBuffer)
    }
    
    /// Transcribe audio buffer
    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }
        
        // Resample to 16kHz if needed
        guard let resampledBuffer = audioProcessor.resample(buffer, to: sampleRate) else {
            throw TranscriptionError.invalidAudioData
        }
        
        // Run Parakeet transcription
        return try await parakeetModel.transcribe(resampledBuffer)
    }
}

// MARK: - Audio Processing

private class AudioProcessor {
    
    /// Convert Data to AVAudioPCMBuffer
    func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        // Create audio format (16kHz, mono)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        
        // Calculate frame capacity
        let frameCapacity = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        
        buffer.frameLength = frameCapacity
        
        // Copy data to buffer
        data.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                buffer.floatChannelData?.pointee.update(
                    from: baseAddress.assumingMemoryBound(to: Float.self),
                    count: Int(frameCapacity)
                )
            }
        }
        
        return buffer
    }
    
    /// Resample audio to target sample rate
    func resample(_ buffer: AVAudioPCMBuffer, to targetSampleRate: Double) -> AVAudioPCMBuffer? {
        let inputFormat = buffer.format
        
        // If already at target sample rate, return as is
        if abs(inputFormat.sampleRate - targetSampleRate) < 0.01 {
            return buffer
        }
        
        // Create output format
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("Failed to create output format")
            return nil
        }
        
        // Calculate output frame capacity
        let outputFrameCapacity = UInt32(Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate)
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            print("Failed to create output buffer")
            return nil
        }
        
        // Use AVAudioConverter for resampling
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create audio converter")
            return nil
        }
        
        // Prepare input block
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        var error: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &error,
            withInputFrom: inputBlock
        )
        
        if status == .error {
            print("Conversion error: \(error?.localizedDescription ?? "Unknown")")
            return nil
        }
        
        return outputBuffer
    }
}

// MARK: - Error Types

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case invalidAudioData
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Parakeet model is not loaded"
        case .invalidAudioData:
            return "Invalid audio data provided"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}