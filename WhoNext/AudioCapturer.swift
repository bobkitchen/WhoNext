import Foundation
import AVFoundation
import ScreenCaptureKit

/// Clean audio capture with separate streams for mic and system audio
/// CRITICAL: All buffers are deep-copied to prevent memory corruption
@MainActor
class AudioCapturer: NSObject, ObservableObject {

    // MARK: - Capture Mode

    enum CaptureMode: String {
        case microphoneOnly = "Microphone Only"
        case full = "Full Audio"
    }

    // MARK: - Published State

    @Published var isCapturing = false
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0
    @Published var lastError: Error?
    @Published private(set) var captureMode: CaptureMode = .full

    // MARK: - Audio Streams

    /// Microphone audio stream (16kHz mono)
    private(set) var micStream: AsyncStream<AVAudioPCMBuffer>!
    private var micContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// System audio stream (16kHz mono)
    private(set) var systemStream: AsyncStream<AVAudioPCMBuffer>!
    private var systemContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // Target format: 16kHz mono for WhisperKit
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1

    // MARK: - Initialization

    override init() {
        super.init()
        setupStreams()
    }

    private func setupStreams() {
        // Create mic stream
        micStream = AsyncStream { [weak self] continuation in
            self?.micContinuation = continuation
        }

        // Create system stream
        systemStream = AsyncStream { [weak self] continuation in
            self?.systemContinuation = continuation
        }
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        guard !isCapturing else { return }

        print("[AudioCapturer] Starting capture...")

        // Reset streams for new capture session
        setupStreams()

        // Start mic capture
        try await startMicrophoneCapture()

        // Try to start system audio capture (may fail without permission)
        do {
            try await startSystemAudioCapture()
            captureMode = .full
            print("[AudioCapturer] Full audio capture (mic + system)")
        } catch {
            // System audio failed - continue with mic only
            captureMode = .microphoneOnly
            print("[AudioCapturer] Screen recording permission denied - microphone only mode")
        }

        isCapturing = true
        print("[AudioCapturer] Capture started successfully in \(captureMode.rawValue) mode")
    }

    func stopCapture() {
        guard isCapturing else { return }

        print("[AudioCapturer] Stopping capture...")

        // Stop mic
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        // Stop system audio
        scStream?.stopCapture { error in
            if let error {
                print("[AudioCapturer] Error stopping SCStream: \(error)")
            }
        }
        scStream = nil
        streamOutput = nil

        // Finish streams
        micContinuation?.finish()
        systemContinuation?.finish()

        isCapturing = false
        print("[AudioCapturer] Capture stopped")
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() async throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[AudioCapturer] Mic input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create target format (16kHz mono)
        guard let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: targetChannels
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Convert to 16kHz mono
            if let converted = self.convertBuffer(buffer, using: converter, to: targetFormat) {
                // CRITICAL: Deep copy before yielding
                if let copy = self.deepCopy(converted) {
                    // Calculate level
                    let level = self.calculateRMS(copy)
                    Task { @MainActor in
                        self.micLevel = level
                    }

                    // Yield to stream
                    self.micContinuation?.yield(copy)
                }
            }
        }

        // Start engine
        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        print("[AudioCapturer] Microphone capture started")
    }

    // MARK: - System Audio Capture

    private func startSystemAudioCapture() async throws {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Get first display
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        // Create filter for display (we only want audio, but need display for SCStream)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream for audio only
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = Int(targetChannels)

        // Minimal video config (required but we won't use it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Create stream output handler
        let output = AudioStreamOutput { [weak self] buffer in
            guard let self else { return }

            // CRITICAL: Deep copy before yielding
            if let copy = self.deepCopy(buffer) {
                // Calculate level
                let level = self.calculateRMS(copy)
                Task { @MainActor in
                    self.systemLevel = level
                }

                // Yield to stream
                self.systemContinuation?.yield(copy)
            }
        }
        self.streamOutput = output

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.scStream = stream
        print("[AudioCapturer] System audio capture started")
    }

    // MARK: - Buffer Conversion

    private func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // Calculate output frame count
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            print("[AudioCapturer] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    // MARK: - Deep Copy (CRITICAL)

    /// Deep copy a buffer to prevent memory corruption from buffer reuse
    private func deepCopy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        copy.frameLength = buffer.frameLength

        // Copy all channel data
        if let srcData = buffer.floatChannelData, let dstData = copy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dstData[channel], srcData[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        return copy
    }

    // MARK: - Audio Analysis

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let samples = channelData[0]
        let count = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }

        return sqrt(sum / Float(count))
    }
}

// MARK: - Stream Output Handler

private class AudioStreamOutput: NSObject, SCStreamOutput {
    private let handler: (AVAudioPCMBuffer) -> Void
    private var logCounter = 0

    init(handler: @escaping (AVAudioPCMBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let buffer = convertToPCMBuffer(sampleBuffer) else {
            logCounter += 1
            if logCounter % 100 == 1 {
                print("[AudioStreamOutput] Failed to convert CMSampleBuffer to PCMBuffer")
            }
            return
        }

        handler(buffer)
    }

    private func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }

        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let asbd = asbdPointer.pointee
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let sourceSampleRate = asbd.mSampleRate
        let targetSampleRate: Double = 16000.0

        // Log format occasionally
        if logCounter % 500 == 0 {
            print("[AudioStreamOutput] System audio format: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame) ch, \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
        }
        logCounter += 1

        // Calculate output frame count after resampling
        let resampleRatio = targetSampleRate / sourceSampleRate
        let outputFrameCount = Int(Double(frameCount) * resampleRatio)

        // Create a float format for output (16kHz mono)
        guard let floatFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            return nil
        }

        // Get the raw audio data from CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return nil
        }

        // ScreenCaptureKit typically delivers 32-bit float audio
        // But we need to handle various formats

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let is32Bit = asbd.mBitsPerChannel == 32
        let is16Bit = asbd.mBitsPerChannel == 16
        let channelCount = Int(asbd.mChannelsPerFrame)

        // First convert to float array at source sample rate
        var sourceFloats = [Float](repeating: 0, count: frameCount)

        // Convert based on source format
        if isFloat && is32Bit {
            // 32-bit float
            let floatData = data.withMemoryRebound(to: Float.self, capacity: frameCount * channelCount) { $0 }

            if channelCount == 1 {
                for i in 0..<frameCount {
                    sourceFloats[i] = floatData[i]
                }
            } else {
                // Downmix stereo to mono
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += floatData[i * channelCount + ch]
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else if is16Bit {
            // 16-bit integer - convert to float
            let int16Data = data.withMemoryRebound(to: Int16.self, capacity: frameCount * channelCount) { $0 }

            if channelCount == 1 {
                for i in 0..<frameCount {
                    sourceFloats[i] = Float(int16Data[i]) / 32768.0
                }
            } else {
                // Downmix stereo to mono
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(int16Data[i * channelCount + ch]) / 32768.0
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else if is32Bit {
            // 32-bit integer - convert to float
            let int32Data = data.withMemoryRebound(to: Int32.self, capacity: frameCount * channelCount) { $0 }

            if channelCount == 1 {
                for i in 0..<frameCount {
                    sourceFloats[i] = Float(int32Data[i]) / Float(Int32.max)
                }
            } else {
                // Downmix stereo to mono
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(int32Data[i * channelCount + ch]) / Float(Int32.max)
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else {
            print("[AudioStreamOutput] Unsupported format: \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
            return nil
        }

        // Now resample from source rate to 16kHz using linear interpolation
        var resampledFloats = [Float](repeating: 0, count: outputFrameCount)

        for i in 0..<outputFrameCount {
            let sourcePosition = Double(i) / resampleRatio
            let sourceIndex = Int(sourcePosition)
            let fraction = Float(sourcePosition - Double(sourceIndex))

            if sourceIndex + 1 < frameCount {
                // Linear interpolation
                resampledFloats[i] = sourceFloats[sourceIndex] * (1 - fraction) + sourceFloats[sourceIndex + 1] * fraction
            } else if sourceIndex < frameCount {
                resampledFloats[i] = sourceFloats[sourceIndex]
            }
        }

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: AVAudioFrameCount(outputFrameCount)) else {
            return nil
        }
        outputBuffer.frameLength = AVAudioFrameCount(outputFrameCount)

        guard let outputData = outputBuffer.floatChannelData?[0] else {
            return nil
        }

        // Copy resampled data to output buffer
        for i in 0..<outputFrameCount {
            outputData[i] = resampledFloats[i]
        }

        return outputBuffer
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case noDisplayAvailable
    case captureStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .noDisplayAvailable:
            return "No display available for system audio capture"
        case .captureStartFailed(let reason):
            return "Failed to start capture: \(reason)"
        }
    }
}

// MARK: - Compatibility Alias

/// Alias for backward compatibility with existing UI code
typealias SystemAudioCapture = AudioCapturer
