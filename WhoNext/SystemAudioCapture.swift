import Foundation
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import Combine
import AppKit
import Accelerate

/// Capture mode for audio sources
enum CaptureMode {
    case full              // Both microphone and system audio
    case microphoneOnly    // Only microphone (system audio permission denied or failed)
    case systemAudioOnly   // Only system audio (microphone permission denied)
    case none              // No audio capture available
}

/// Captures both microphone and system audio for two-way conversation detection
/// Uses AVAudioEngine for microphone and ScreenCaptureKit for system audio on macOS 13+
class SystemAudioCapture: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isCapturing: Bool = false
    @Published var microphoneLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0
    @Published var captureError: Error?
    @Published var captureMode: CaptureMode = .none
    
    // MARK: - Audio Engine Components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mixerNode: AVAudioMixerNode?
    
    // MARK: - Screen Capture for System Audio
    private var stream: SCStream?
    
    // MARK: - Audio Buffers
    private var microphoneBuffer: AVAudioPCMBuffer?
    private var systemAudioBuffer: AVAudioPCMBuffer?
    private let bufferSize: AVAudioFrameCount = 4096
    
    // MARK: - Format Settings
    private let sampleRate: Double = 16000 // 16kHz for speech
    let audioFormat: AVAudioFormat
    
    // MARK: - Retry Logic
    private var systemAudioRetryCount = 0
    private let maxRetries = 3
    private var retryTask: Task<Void, Never>?

    // MARK: - Callbacks (Deprecated - use AsyncStreams instead)
    var onAudioBuffersAvailable: ((AVAudioPCMBuffer?, AVAudioPCMBuffer?) -> Void)?
    var onMixedAudioAvailable: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - AsyncStream Architecture

    /// Stream of audio buffer pairs (microphone, system audio)
    private(set) lazy var audioBuffersStream: AsyncStream<(mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?)> = {
        let (stream, continuation) = AsyncStream<(mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?)>.makeStream(
            bufferingPolicy: .bufferingNewest(50)  // Buffer up to 50 frames (~3 seconds at 16kHz)
        )
        self.audioBuffersContinuation = continuation
        return stream
    }()

    /// Stream of mixed audio buffers (ready for transcription)
    private(set) lazy var mixedAudioStream: AsyncStream<AVAudioPCMBuffer> = {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(50)
        )
        self.mixedAudioContinuation = continuation
        return stream
    }()

    private var audioBuffersContinuation: AsyncStream<(mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?)>.Continuation?
    private var mixedAudioContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // MARK: - First Buffer Synchronization
    // Used to ensure detection doesn't start until audio is actually flowing
    private var hasReceivedFirstBuffer = false
    private var firstBufferContinuation: CheckedContinuation<Void, Never>?

    /// Waits until the first valid audio buffer is received
    /// Call this after startCapture() to ensure audio is flowing before starting detection
    func waitForFirstBuffer() async {
        // If we already have a buffer, return immediately
        if hasReceivedFirstBuffer {
            return
        }

        // Wait for the first buffer with a timeout
        await withCheckedContinuation { continuation in
            self.firstBufferContinuation = continuation

            // Timeout after 3 seconds to avoid hanging indefinitely
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !self.hasReceivedFirstBuffer {
                    print("⚠️ [AudioCapture] Timeout waiting for first buffer, proceeding anyway")
                    self.firstBufferContinuation?.resume()
                    self.firstBufferContinuation = nil
                }
            }
        }
    }

    // MARK: - Initialization
    override init() {
        // Create audio format for speech processing (16kHz, mono)
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start capturing both microphone and system audio
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        print("🎙️ Starting audio capture...")
        
        // Request permissions
        try await requestPermissions()
        
        // Set up microphone capture
        var micSetupSuccess = false
        do {
            try setupMicrophoneCapture()
            micSetupSuccess = true
        } catch {
            print("❌ Microphone setup failed: \(error.localizedDescription)")
        }

        // Set up system audio capture (macOS 13+) with retry logic
        var systemAudioSetupSuccess = false
        if #available(macOS 13.0, *) {
            // Check for screen recording permission
            let hasPermission = await checkScreenRecordingPermission()
            if hasPermission {
                systemAudioSetupSuccess = await setupSystemAudioCaptureWithRetry()
            } else {
                print("⚠️ Screen recording permission not granted")
                print("🎙️ Using microphone-only recording mode")
            }
        } else {
            print("⚠️ System audio capture requires macOS 13 or later")
        }

        // Update capture mode based on what succeeded
        await MainActor.run {
            if micSetupSuccess && systemAudioSetupSuccess {
                self.captureMode = .full
            } else if micSetupSuccess {
                self.captureMode = .microphoneOnly
            } else if systemAudioSetupSuccess {
                self.captureMode = .systemAudioOnly
            } else {
                self.captureMode = .none
            }
        }
        
        // Start the audio engine
        try startAudioEngine()
        
        DispatchQueue.main.async {
            self.isCapturing = true
        }
    }
    
    /// Stop capturing audio
    func stopCapture() {
        guard isCapturing else { return }

        print("🛑 Stopping audio capture...")

        // Stop audio engine first
        audioEngine?.stop()

        // Remove tap before releasing engine
        audioEngine?.inputNode.removeTap(onBus: 0)

        // Stop screen capture stream
        if #available(macOS 13.0, *) {
            stream?.stopCapture { error in
                if let error = error {
                    print("❌ Error stopping stream: \(error)")
                }
            }
            stream = nil
        }

        // Finish AsyncStream continuations
        audioBuffersContinuation?.finish()
        mixedAudioContinuation?.finish()
        audioBuffersContinuation = nil
        mixedAudioContinuation = nil

        // Reset first buffer tracking for next capture session
        hasReceivedFirstBuffer = false
        firstBufferContinuation = nil

        // CRITICAL: Release audio session to restore normal audio behavior
        // This allows Bluetooth devices (AirPods) to switch back to A2DP profile
        releaseAudioSession()

        DispatchQueue.main.async {
            self.isCapturing = false
            self.microphoneLevel = 0.0
            self.systemAudioLevel = 0.0
            self.captureMode = .none
        }

        print("✅ Audio capture fully stopped and resources released")
    }
    
    /// Get the next audio chunk for processing
    func getAudioChunk() -> (mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?) {
        return (microphoneBuffer, systemAudioBuffer)
    }
    
    // MARK: - Private Methods - Permissions
    
    private func requestPermissions() async throws {
        // Request microphone permission
        let micPermission = await AVCaptureDevice.requestAccess(for: .audio)
        guard micPermission else {
            throw AudioCaptureError.microphonePermissionDenied
        }
        
        // Request screen recording permission for system audio
        if #available(macOS 13.0, *) {
            // Screen recording permission is handled by ScreenCaptureKit
            // It will prompt automatically when we try to capture
        }
    }
    
    // MARK: - Private Methods - Microphone Capture

    /// Configure audio session for recording (macOS 14+)
    private func configureAudioSession() {
        if #available(macOS 14.0, *) {
            // Use AVAudioApplication for macOS 14+ to properly configure audio behavior
            let audioApp = AVAudioApplication.shared
            do {
                // Set recording configuration that minimizes impact on playback
                try audioApp.setInputMuted(false)
                print("✅ Audio application configured for recording")
            } catch {
                print("⚠️ Could not configure audio application: \(error)")
            }
        }

        // Note: On macOS, when using Bluetooth headphones (AirPods), the system
        // automatically switches from A2DP (high quality stereo) to HFP (hands-free
        // profile with mic support). This can change audio characteristics.
        // This is OS-level behavior and cannot be fully prevented, but we ensure
        // proper cleanup when stopping to restore normal operation.
    }

    /// Release audio session configuration
    private func releaseAudioSession() {
        if #available(macOS 14.0, *) {
            // Reset any audio application state
            print("🔄 Audio session released")
        }

        // Force release of audio resources to allow Bluetooth profile to switch back
        audioEngine?.reset()
        audioEngine = nil
        inputNode = nil
        mixerNode = nil

        print("✅ Audio resources fully released")
    }

    private func setupMicrophoneCapture() throws {
        // Configure audio session before setting up the engine
        configureAudioSession()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioCaptureError.audioEngineInitFailed
        }

        inputNode = audioEngine.inputNode
        mixerNode = AVAudioMixerNode()
        audioEngine.attach(mixerNode!)

        // Connect input to mixer
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        audioEngine.connect(inputNode!, to: mixerNode!, format: inputFormat)

        // Install tap on input node to capture microphone audio
        inputNode!.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processMicrophoneBuffer(buffer)
        }

        print("✅ Microphone capture configured")
    }

    private func startAudioEngine() throws {
        guard let audioEngine = audioEngine else { return }

        audioEngine.prepare()
        try audioEngine.start()

        print("✅ Audio engine started")
    }
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        // Signal first buffer received (for sync with detection startup)
        if !hasReceivedFirstBuffer {
            hasReceivedFirstBuffer = true
            firstBufferContinuation?.resume()
            firstBufferContinuation = nil
            print("✅ [AudioCapture] First buffer received, audio is flowing")
        }

        // Store buffer for analysis
        microphoneBuffer = buffer

        // Calculate audio level for UI
        let level = calculateAudioLevel(buffer)
        
        DispatchQueue.main.async {
            self.microphoneLevel = level
        }
        
        // Notify delegate with separate buffers (deprecated callback)
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)

        // Yield to AsyncStream (modern approach)
        audioBuffersContinuation?.yield((mic: microphoneBuffer, system: systemAudioBuffer))

        // Also provide mixed audio for transcription
        if let mixedBuffer = mixAudioBuffers(mic: microphoneBuffer, system: systemAudioBuffer) {
            onMixedAudioAvailable?(mixedBuffer)  // Deprecated callback
            mixedAudioContinuation?.yield(mixedBuffer)  // AsyncStream
        }
    }
    
    // MARK: - Private Methods - System Audio Capture

    /// Set up system audio with fast retry logic (optimized for quick startup)
    @available(macOS 13.0, *)
    private func setupSystemAudioCaptureWithRetry() async -> Bool {
        systemAudioRetryCount = 0

        while systemAudioRetryCount <= maxRetries {
            do {
                try await setupSystemAudioCapture()
                print("✅ System audio setup succeeded")
                systemAudioRetryCount = 0  // Reset on success
                return true
            } catch {
                systemAudioRetryCount += 1

                if systemAudioRetryCount <= maxRetries {
                    // Fast retry: 200ms, 500ms, 1s (instead of 2s, 4s, 8s)
                    let delayMs: UInt64 = systemAudioRetryCount == 1 ? 200 : (systemAudioRetryCount == 2 ? 500 : 1000)
                    print("⚠️ System audio setup failed (attempt \(systemAudioRetryCount)/\(maxRetries)): \(error.localizedDescription)")
                    print("🔄 Retrying in \(delayMs)ms...")

                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                } else {
                    print("❌ System audio setup failed after \(maxRetries) attempts")
                    print("🎙️ Permanently falling back to microphone-only mode")
                }
            }
        }

        return false
    }

    @available(macOS 13.0, *)
    private func setupSystemAudioCapture() async throws {
        // Get available content
        let availableContent = try await SCShareableContent.current
        
        // Create audio-only stream configuration
        let streamConfig = SCStreamConfiguration()
        
        // Audio configuration
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = true
        streamConfig.sampleRate = Int(sampleRate)
        streamConfig.channelCount = 1
        
        // Disable video capture entirely by setting width/height to 1
        // This is the minimum allowed and signals we don't want video
        streamConfig.width = 1
        streamConfig.height = 1
        streamConfig.minimumFrameInterval = CMTime(value: 600, timescale: 1) // 10 minutes between frames
        streamConfig.queueDepth = 1
        streamConfig.showsCursor = false
        
        // Create filter for audio capture
        // For audio-only capture, we need to provide a filter but we're not actually capturing video
        let filter: SCContentFilter
        
        // Use the primary display for the filter (required even for audio-only)
        guard let display = availableContent.displays.first else {
            throw AudioCaptureError.noAvailableContent
        }
        
        // Create filter with empty exclusions since we're only capturing audio
        filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        // Create stream without delegate
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        
        // Ensure stream was created successfully
        guard stream != nil else {
            throw AudioCaptureError.streamCreationFailed
        }
        
        // Create dedicated queue for audio processing
        let audioQueue = DispatchQueue(label: "com.whonext.audio.system", qos: .userInitiated, attributes: .concurrent)
        
        // Add ourselves as the stream output for audio only
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        
        // Start the capture with completion handler
        let captureStarted = await withCheckedContinuation { continuation in
            stream?.startCapture { error in
                if let error = error {
                    print("❌ SCStream start failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
        
        guard captureStarted else {
            stream = nil
            throw AudioCaptureError.streamCreationFailed
        }
        
        print("✅ System audio capture started (audio-only mode)")
    }
    
    @available(macOS 13.0, *)
    private func checkScreenRecordingPermission() async -> Bool {
        // Try to create a test stream to check permission
        do {
            let content = try await SCShareableContent.current
            // If we can get content, we have permission
            return !content.displays.isEmpty
        } catch {
            // Permission not granted or other error
            print("🔒 Screen recording permission not granted: \(error.localizedDescription)")
            // Don't show alert here - it's handled by MeetingRecordingEngine
            return false
        }
    }
    
    private func processSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let buffer = convertToAudioBuffer(sampleBuffer) else { return }
        
        // Store buffer for analysis
        systemAudioBuffer = buffer
        
        // Calculate audio level for UI
        let level = calculateAudioLevel(buffer)
        
        DispatchQueue.main.async {
            self.systemAudioLevel = level
        }
        
        // Notify delegate with separate buffers (deprecated callback)
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)

        // Yield to AsyncStream (modern approach)
        audioBuffersContinuation?.yield((mic: microphoneBuffer, system: systemAudioBuffer))

        // Also provide mixed audio for transcription
        if let mixedBuffer = mixAudioBuffers(mic: microphoneBuffer, system: systemAudioBuffer) {
            onMixedAudioAvailable?(mixedBuffer)  // Deprecated callback
            mixedAudioContinuation?.yield(mixedBuffer)  // AsyncStream
        }
    }
    
    // MARK: - Helper Methods
    
    /// Mix microphone and system audio buffers into a single buffer
    func mixAudioBuffers(mic: AVAudioPCMBuffer?, system: AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        // If we only have one buffer, return it directly (no mixing needed)
        if mic == nil && system == nil {
            return nil
        } else if mic == nil {
            return system
        } else if system == nil {
            return mic
        }
        
        guard let micBuffer = mic, let systemBuffer = system else { return mic ?? system }
        
        // Ensure both buffers have the same format
        guard micBuffer.format.sampleRate == systemBuffer.format.sampleRate,
              micBuffer.format.channelCount == systemBuffer.format.channelCount else {
            // Convert to common format if needed
            return convertAndMixBuffers(micBuffer, systemBuffer)
        }
        
        // Create output buffer with the longer frame length
        let frameLength = max(micBuffer.frameLength, systemBuffer.frameLength)
        guard let mixedBuffer = AVAudioPCMBuffer(
            pcmFormat: micBuffer.format,
            frameCapacity: frameLength
        ) else { return nil }
        
        mixedBuffer.frameLength = frameLength
        
        // Mix the audio data using Accelerate framework for SIMD performance
        if let micData = micBuffer.floatChannelData,
           let systemData = systemBuffer.floatChannelData,
           let mixedData = mixedBuffer.floatChannelData {

            let channelCount = Int(micBuffer.format.channelCount)

            for channel in 0..<channelCount {
                let micLen = Int(micBuffer.frameLength)
                let sysLen = Int(systemBuffer.frameLength)
                let outLen = Int(frameLength)

                // Use vDSP for vectorized audio mixing (5-10x faster than loops)
                if micLen == sysLen && micLen == outLen {
                    // Simple case: same length, just add and average
                    vDSP_vadd(micData[channel], 1, systemData[channel], 1, mixedData[channel], 1, vDSP_Length(outLen))
                    var scale: Float = 0.5 // Average to prevent clipping
                    vDSP_vsmul(mixedData[channel], 1, &scale, mixedData[channel], 1, vDSP_Length(outLen))
                } else {
                    // Different lengths: copy and mix carefully
                    // Zero out the buffer first
                    vDSP_vclr(mixedData[channel], 1, vDSP_Length(outLen))

                    // Add mic data (up to its length)
                    if micLen > 0 {
                        vDSP_vadd(mixedData[channel], 1, micData[channel], 1, mixedData[channel], 1, vDSP_Length(micLen))
                    }

                    // Add system data (up to its length)
                    if sysLen > 0 {
                        vDSP_vadd(mixedData[channel], 1, systemData[channel], 1, mixedData[channel], 1, vDSP_Length(sysLen))
                    }

                    // Average the overlapping region
                    let overlapLen = min(micLen, sysLen)
                    if overlapLen > 0 {
                        var scale: Float = 0.5
                        vDSP_vsmul(mixedData[channel], 1, &scale, mixedData[channel], 1, vDSP_Length(overlapLen))
                    }
                }

                // Clip to valid range [-1.0, 1.0] using vDSP
                var lowerBound: Float = -1.0
                var upperBound: Float = 1.0
                vDSP_vclip(mixedData[channel], 1, &lowerBound, &upperBound, mixedData[channel], 1, vDSP_Length(outLen))
            }
        }
        
        return mixedBuffer
    }
    
    private func convertAndMixBuffers(_ mic: AVAudioPCMBuffer, _ system: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Convert both to common format (16kHz mono)
        guard let convertedMic = convertToFormat(mic, targetFormat: audioFormat),
              let convertedSystem = convertToFormat(system, targetFormat: audioFormat) else {
            return nil
        }
        
        return mixAudioBuffers(mic: convertedMic, system: convertedSystem)
    }
    
    private func convertToFormat(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }
        
        let outputFrameCapacity = UInt32(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        return error == nil ? outputBuffer : nil
    }
    
    private func calculateAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var totalLevel: Float = 0.0
        
        for channel in 0..<channelCount {
            var channelLevel: Float = 0.0
            for frame in 0..<frameLength {
                let sample = channelData[channel][frame]
                channelLevel += abs(sample)
            }
            totalLevel += channelLevel / Float(frameLength)
        }
        
        return totalLevel / Float(channelCount)
    }
    
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        guard let asbd = asbd else { return nil }
        
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame,
            interleaved: false
        )
        
        guard let format = format else { return nil }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy audio data
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        
        return buffer
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio samples, completely ignore any video samples
        guard type == .audio else { return }
        processSystemAudioBuffer(sampleBuffer)
    }
}

// SystemAudioOutputHandler removed - using SystemAudioCapture directly as SCStreamOutput

// MARK: - Error Types

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case audioEngineInitFailed
    case streamCreationFailed
    case formatConversionFailed
    case noAvailableContent
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please grant access in System Settings."
        case .screenRecordingPermissionDenied:
            return "Screen recording permission denied. Please grant access in System Settings to capture system audio."
        case .audioEngineInitFailed:
            return "Failed to initialize audio engine."
        case .streamCreationFailed:
            return "Failed to create audio capture stream."
        case .formatConversionFailed:
            return "Failed to convert audio format."
        case .noAvailableContent:
            return "No available windows or displays to capture audio from."
        }
    }
}