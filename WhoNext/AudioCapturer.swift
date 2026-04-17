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

    /// Which mechanism is currently providing system audio.
    /// Process tap gives clean per-app audio; screen capture gives the whole system mix.
    enum SystemAudioSource: Equatable {
        case none
        case processTap(appName: String, pid: pid_t)
        case screenCapture
    }
    @Published private(set) var systemAudioSource: SystemAudioSource = .none

    // MARK: - Audio Streams

    /// Microphone audio stream (16kHz mono) — raw mic including echo
    private(set) var micStream: AsyncStream<AVAudioPCMBuffer>!
    private var micContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// System audio stream (16kHz mono)
    private(set) var systemStream: AsyncStream<AVAudioPCMBuffer>!
    private var systemContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// Echo-cancelled mic stream (16kHz mono) — local voice only, echo removed.
    /// Available when `isEchoCancellationActive == true`. Used for diarization
    /// so that stream identity = speaker identity (mic = local, system = remote).
    private(set) var cleanMicStream: AsyncStream<AVAudioPCMBuffer>!
    private var cleanMicContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // MARK: - Echo Cancellation

    /// SpeexDSP echo canceller — removes system audio echo from mic signal
    private let echoCanceller = EchoCanceller()

    // MARK: - Process Tap (preferred path for meeting apps)

    /// Core Audio process tap — captures clean per-app audio from Zoom/Teams/etc.
    /// When active, the system audio stream contains ONLY the meeting app's output.
    private let processTapCapturer = ProcessTapCapturer()

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var videoSinkOutput: VideoSinkOutput?

    // Target format: 16kHz mono for WhisperKit
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1

    // MARK: - Initialization

    override init() {
        super.init()
        setupStreams()
    }

    private func setupStreams() {
        // Create mic stream (raw, includes echo)
        micStream = AsyncStream { [weak self] continuation in
            self?.micContinuation = continuation
        }

        // Create system stream
        systemStream = AsyncStream { [weak self] continuation in
            self?.systemContinuation = continuation
        }

        // Create echo-cancelled mic stream
        cleanMicStream = AsyncStream { [weak self] continuation in
            self?.cleanMicContinuation = continuation
        }
    }

    // MARK: - Capture Control

    func startCapture() async throws {
        guard !isCapturing else { return }

        debugLog("[AudioCapturer] Starting capture...")

        // Reset streams for new capture session
        setupStreams()

        // Reset echo canceller BEFORE starting mic capture to avoid race
        // where the first mic audio callback hits stale/uninitialized state
        echoCanceller.reset()

        // Start mic capture
        try await startMicrophoneCapture()

        // Try to start system audio capture (may fail without permission)
        do {
            try await startSystemAudioCapture()
            captureMode = .full
            // AEC is active when we have both mic + system streams
            isEchoCancellationActive = echoCanceller.isAvailable
            debugLog("[AudioCapturer] Full audio capture (mic + system), AEC: \(isEchoCancellationActive)")
        } catch {
            // Log the ACTUAL error — don't assume it's always permission denial
            let nsError = error as NSError
            debugLog("[AudioCapturer] ⚠️ System audio capture FAILED:")
            print("[AudioCapturer]   Error: \(error.localizedDescription)")
            print("[AudioCapturer]   Domain: \(nsError.domain), Code: \(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                debugLog("[AudioCapturer]   Underlying: \(underlying.domain) code \(underlying.code): \(underlying.localizedDescription)")
            }

            // Retry once after a brief delay — SCShareableContent can transiently fail
            // right after app launch even with permissions granted
            do {
                try await Task.sleep(for: .milliseconds(500))
                try await startSystemAudioCapture()
                captureMode = .full
                isEchoCancellationActive = echoCanceller.isAvailable
                debugLog("[AudioCapturer] Full audio capture (mic + system) — succeeded on retry, AEC: \(isEchoCancellationActive)")
            } catch {
                captureMode = .microphoneOnly
                let retryError = error as NSError
                print("[AudioCapturer] ⚠️ System audio retry also failed: \(retryError.domain) code \(retryError.code): \(retryError.localizedDescription)")
                debugLog("[AudioCapturer] Falling back to microphone only mode")
            }
        }

        isCapturing = true
        debugLog("[AudioCapturer] Capture started successfully in \(captureMode.rawValue) mode")
    }

    func stopCapture() {
        guard isCapturing else { return }

        debugLog("[AudioCapturer] Stopping capture...")

        // Stop mic
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        // Stop process tap (if active)
        if processTapCapturer.isActive {
            processTapCapturer.stop()
        }

        // Stop system audio
        scStream?.stopCapture { error in
            if let error {
                print("[AudioCapturer] Error stopping SCStream: \(error)")
            }
        }
        scStream = nil
        streamOutput = nil
        videoSinkOutput = nil
        systemAudioSource = .none

        // Finish streams
        micContinuation?.finish()
        systemContinuation?.finish()
        cleanMicContinuation?.finish()

        // Reset echo canceller
        echoCanceller.reset()
        isEchoCancellationActive = false
        isCapturing = false
        debugLog("[AudioCapturer] Capture stopped")
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() async throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Apple's Voice Processing disabled — causes persistent DSP fault state on macOS
        // because Zoom/Teams own the audio output. Using SpeexDSP AEC instead.
        debugLog("[AudioCapturer] Apple Voice Processing disabled — SpeexDSP AEC active")

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        debugLog("[AudioCapturer] Mic input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

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

                    // Yield raw mic to stream (for transcription — includes all speech)
                    self.micContinuation?.yield(copy)

                    // Echo cancellation: feed mic to AEC and yield cleaned output
                    if self.echoCanceller.isAvailable,
                       let channelData = copy.floatChannelData {
                        let frameCount = Int(copy.frameLength)
                        let micSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

                        let cleanedSamples = self.echoCanceller.cancelEcho(micSamples)

                        if !cleanedSamples.isEmpty,
                           let cleanBuffer = self.createBuffer(from: cleanedSamples, format: targetFormat) {
                            self.cleanMicContinuation?.yield(cleanBuffer)
                        }
                    }
                }
            }
        }

        // Start engine
        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        debugLog("[AudioCapturer] Microphone capture started")
    }

    // MARK: - System Audio Capture

    /// Common processing for a system-audio buffer: deep-copy, update level,
    /// yield to `systemStream`, and feed the AEC far-end reference.
    private func processSystemAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // CRITICAL: Deep copy before yielding. Both the SCStream path and the
        // process-tap path reuse their backing storage between callbacks.
        guard let copy = self.deepCopy(buffer) else { return }

        let level = self.calculateRMS(copy)
        Task { @MainActor in
            self.systemLevel = level
        }

        self.systemContinuation?.yield(copy)

        if self.echoCanceller.isAvailable,
           let channelData = copy.floatChannelData {
            let frameCount = Int(copy.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            self.echoCanceller.feedFarEnd(samples)
        }
    }

    private func startSystemAudioCapture() async throws {
        // Prefer Core Audio process tap (macOS 14.4+): clean per-app audio with no
        // contamination from music, browser tabs, or notifications. Falls back to
        // SCStream if no meeting app is running or the tap can't be created.
        do {
            let process = try processTapCapturer.start { [weak self] buffer in
                guard let self else { return }
                self.processSystemAudioBuffer(buffer)
            }
            systemAudioSource = .processTap(appName: process.displayName, pid: process.pid)
            debugLog("[AudioCapturer] ✅ System audio via process tap: \(process.displayName) (pid=\(process.pid))")
            return
        } catch {
            // Expected when no meeting app is running or permission hasn't been granted yet.
            debugLog("[AudioCapturer] Process tap unavailable (\(error.localizedDescription)) — falling back to SCStream")
        }

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
            self?.processSystemAudioBuffer(buffer)
        }
        self.streamOutput = output

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        // Sink video frames to suppress "_SCStream_RemoteVideoQueueOperationHandlerWithError" spam.
        // SCStream requires video but we only use audio; without a video handler macOS logs
        // "stream output NOT found. Dropping frame" on every frame.
        let videoSink = VideoSinkOutput()
        self.videoSinkOutput = videoSink
        try stream.addStreamOutput(videoSink, type: .screen, sampleHandlerQueue: .global(qos: .background))

        try await stream.startCapture()

        self.scStream = stream
        self.systemAudioSource = .screenCapture
        debugLog("[AudioCapturer] System audio capture started via SCStream (whole-system mix)")
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
            debugLog("[AudioCapturer] Conversion error: \(error?.localizedDescription ?? "unknown")")
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

    // MARK: - Buffer Creation

    /// Create an AVAudioPCMBuffer from a Float array (for echo-cancelled output)
    private func createBuffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { srcPtr in
                memcpy(channelData[0], srcPtr.baseAddress!, samples.count * MemoryLayout<Float>.size)
            }
        }
        return buffer
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
            debugLog("[AudioStreamOutput] System audio format: \(sourceSampleRate)Hz, \(channelCount) ch, \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
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
            debugLog("[AudioStreamOutput] Unsupported format: \(asbd.mBitsPerChannel) bits, flags: \(asbd.mFormatFlags)")
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

// MARK: - Video Sink (suppresses SCStream frame-drop warnings)

/// Minimal SCStreamOutput that silently consumes video frames.
/// SCStream mandates video capture but we only need audio; without a registered
/// video handler macOS logs "stream output NOT found. Dropping frame" per frame.
private class VideoSinkOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Intentionally empty — frames are discarded.
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
