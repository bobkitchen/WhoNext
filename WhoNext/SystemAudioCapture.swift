import Foundation
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import Combine
import AppKit

/// Captures both microphone and system audio for two-way conversation detection
/// Uses AVAudioEngine for microphone and ScreenCaptureKit for system audio on macOS 13+
class SystemAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isCapturing: Bool = false
    @Published var microphoneLevel: Float = 0.0
    @Published var systemAudioLevel: Float = 0.0
    @Published var captureError: Error?
    
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
    
    // MARK: - Callbacks
    var onAudioBuffersAvailable: ((AVAudioPCMBuffer?, AVAudioPCMBuffer?) -> Void)?
    var onMixedAudioAvailable: ((AVAudioPCMBuffer) -> Void)?
    
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
        try setupMicrophoneCapture()
        
        // Set up system audio capture (macOS 13+)
        if #available(macOS 13.0, *) {
            // Check for screen recording permission
            let hasPermission = await checkScreenRecordingPermission()
            if hasPermission {
                do {
                    try await setupSystemAudioCapture()
                } catch {
                    print("⚠️ System audio setup failed: \(error.localizedDescription)")
                    print("🎙️ Falling back to microphone-only mode")
                }
            } else {
                print("⚠️ Screen recording permission not granted")
                print("🎙️ Using microphone-only recording mode")
            }
        } else {
            print("⚠️ System audio capture requires macOS 13 or later")
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
        
        // Stop audio engine
        audioEngine?.stop()
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
        
        DispatchQueue.main.async {
            self.isCapturing = false
            self.microphoneLevel = 0.0
            self.systemAudioLevel = 0.0
        }
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
    
    private func setupMicrophoneCapture() throws {
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
        // Store buffer for analysis
        microphoneBuffer = buffer
        
        // Calculate audio level for UI
        let level = calculateAudioLevel(buffer)
        
        DispatchQueue.main.async {
            self.microphoneLevel = level
        }
        
        // Notify delegate with separate buffers
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)
        
        // Also provide mixed audio for transcription
        if let mixedBuffer = mixAudioBuffers(mic: microphoneBuffer, system: systemAudioBuffer) {
            onMixedAudioAvailable?(mixedBuffer)
        }
    }
    
    // MARK: - Private Methods - System Audio Capture
    
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
        
        // Notify delegate with separate buffers
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)
        
        // Also provide mixed audio for transcription
        if let mixedBuffer = mixAudioBuffers(mic: microphoneBuffer, system: systemAudioBuffer) {
            onMixedAudioAvailable?(mixedBuffer)
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
        
        // Mix the audio data
        if let micData = micBuffer.floatChannelData,
           let systemData = systemBuffer.floatChannelData,
           let mixedData = mixedBuffer.floatChannelData {
            
            let channelCount = Int(micBuffer.format.channelCount)
            
            for channel in 0..<channelCount {
                for frame in 0..<Int(frameLength) {
                    var mixedSample: Float = 0.0
                    var sourceCount: Float = 0.0
                    
                    // Add microphone sample if available
                    if frame < Int(micBuffer.frameLength) {
                        mixedSample += micData[channel][frame]
                        sourceCount += 1.0
                    }
                    
                    // Add system audio sample if available
                    if frame < Int(systemBuffer.frameLength) {
                        mixedSample += systemData[channel][frame]
                        sourceCount += 1.0
                    }
                    
                    // Normalize if we have multiple sources to prevent clipping
                    // But don't reduce volume if only one source is active at this frame
                    if sourceCount > 1.0 {
                        mixedSample /= sourceCount
                    }
                    
                    // Clip to valid range
                    mixedSample = max(-1.0, min(1.0, mixedSample))
                    mixedData[channel][frame] = mixedSample
                }
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