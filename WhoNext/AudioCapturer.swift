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
    @Published private(set) var isEchoCancellationActive: Bool = false

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
            // Log the ACTUAL error — don't assume it's always permission denial
            let nsError = error as NSError
            print("[AudioCapturer] ⚠️ System audio capture FAILED:")
            print("[AudioCapturer]   Error: \(error.localizedDescription)")
            print("[AudioCapturer]   Domain: \(nsError.domain), Code: \(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("[AudioCapturer]   Underlying: \(underlying.domain) code \(underlying.code): \(underlying.localizedDescription)")
            }

            // Retry once after a brief delay — SCShareableContent can transiently fail
            // right after app launch even with permissions granted
            do {
                try await Task.sleep(for: .milliseconds(500))
                try await startSystemAudioCapture()
                captureMode = .full
                print("[AudioCapturer] Full audio capture (mic + system) — succeeded on retry")
            } catch {
                captureMode = .microphoneOnly
                let retryError = error as NSError
                print("[AudioCapturer] ⚠️ System audio retry also failed: \(retryError.domain) code \(retryError.code): \(retryError.localizedDescription)")
                print("[AudioCapturer] Falling back to microphone only mode")
            }
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

        isEchoCancellationActive = false
        isCapturing = false
        print("[AudioCapturer] Capture stopped")
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() async throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Enable AEC (Acoustic Echo Cancellation) via Voice Processing
        // Must be called while engine is stopped. Eliminates remote speaker bleed from mic.
        // Can fail with aggregate device errors (e.g., AirPods mic + external speakers).
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            isEchoCancellationActive = true
            print("[AudioCapturer] ✅ AEC enabled (Voice Processing)")
        } catch {
            isEchoCancellationActive = false
            print("[AudioCapturer] ⚠️ AEC failed: \(error.localizedDescription)")
        }

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

    /// Cached converter for resampling (created lazily based on source format)
    private var cachedConverter: AVAudioConverter?
    private var cachedSourceFormat: AVAudioFormat?
    private let converterLock = NSLock()

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
        let channelCount = Int(asbd.mChannelsPerFrame)

        // Log format occasionally
        if logCounter % 500 == 0 {
            print("[AudioStreamOutput] System audio format: \(sourceSampleRate)Hz, \(channelCount) ch, \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
        }
        logCounter += 1

        // Create source format (mono float at source rate) for intermediate buffer
        guard let sourceMonoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceSampleRate,
            channels: 1
        ) else {
            return nil
        }

        // Create target format (16kHz mono)
        guard let targetFormat = AVAudioFormat(
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

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let is32Bit = asbd.mBitsPerChannel == 32
        let is16Bit = asbd.mBitsPerChannel == 16

        // First convert to mono float array at source sample rate
        var sourceFloats = [Float](repeating: 0, count: frameCount)

        if isFloat && is32Bit {
            let floatData = data.withMemoryRebound(to: Float.self, capacity: frameCount * channelCount) { $0 }
            if channelCount == 1 {
                memcpy(&sourceFloats, floatData, frameCount * MemoryLayout<Float>.size)
            } else {
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += floatData[i * channelCount + ch]
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else if is16Bit {
            let int16Data = data.withMemoryRebound(to: Int16.self, capacity: frameCount * channelCount) { $0 }
            if channelCount == 1 {
                for i in 0..<frameCount {
                    sourceFloats[i] = Float(int16Data[i]) / 32768.0
                }
            } else {
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(int16Data[i * channelCount + ch]) / 32768.0
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else if is32Bit {
            let int32Data = data.withMemoryRebound(to: Int32.self, capacity: frameCount * channelCount) { $0 }
            if channelCount == 1 {
                for i in 0..<frameCount {
                    sourceFloats[i] = Float(int32Data[i]) / 2147483648.0
                }
            } else {
                for i in 0..<frameCount {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += Float(int32Data[i * channelCount + ch]) / 2147483648.0
                    }
                    sourceFloats[i] = sum / Float(channelCount)
                }
            }
        } else {
            print("[AudioStreamOutput] Unsupported format: \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
            return nil
        }

        // Create source buffer at source sample rate (mono)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceMonoFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)
        if let channelData = sourceBuffer.floatChannelData {
            memcpy(channelData[0], &sourceFloats, frameCount * MemoryLayout<Float>.size)
        }

        // If already at target rate, return directly
        if abs(sourceSampleRate - targetSampleRate) < 1.0 {
            return sourceBuffer
        }

        // Use AVAudioConverter for proper sample rate conversion (anti-aliased)
        converterLock.lock()
        defer { converterLock.unlock() }

        if cachedConverter == nil || cachedSourceFormat?.sampleRate != sourceSampleRate {
            cachedConverter = AVAudioConverter(from: sourceMonoFormat, to: targetFormat)
            cachedSourceFormat = sourceMonoFormat
        }

        guard let converter = cachedConverter else {
            return nil
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let conversionStatus = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if conversionStatus == .error || error != nil {
            // Fallback: return source buffer without resampling rather than returning nil
            return sourceBuffer
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
