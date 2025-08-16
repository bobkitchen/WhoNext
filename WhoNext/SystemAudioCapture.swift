import Foundation
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import Combine

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
    private var streamOutput: SCStreamOutput?
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
            try await setupSystemAudioCapture()
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
        
        // Notify delegate
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)
    }
    
    // MARK: - Private Methods - System Audio Capture
    
    @available(macOS 13.0, *)
    private func setupSystemAudioCapture() async throws {
        // Get available content (we just need audio, not specific windows)
        let availableContent = try await SCShareableContent.current
        
        // Create stream configuration for audio only
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = false // We want all audio
        streamConfig.sampleRate = Int(sampleRate)
        streamConfig.channelCount = 1
        
        // Create content filter (capture all audio)
        // We need at least one window or display to create a filter
        let filter: SCContentFilter
        if let firstWindow = availableContent.windows.first {
            filter = SCContentFilter(desktopIndependentWindow: firstWindow)
        } else if let firstDisplay = availableContent.displays.first {
            filter = SCContentFilter(display: firstDisplay, excludingWindows: [])
        } else {
            throw AudioCaptureError.noAvailableContent
        }
        
        // Create stream
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        
        // Set up output handler
        let audioOutputHandler = SystemAudioOutputHandler { [weak self] buffer in
            self?.processSystemAudioBuffer(buffer)
        }
        
        try stream?.addStreamOutput(audioOutputHandler, type: .audio, sampleHandlerQueue: .global())
        
        // Start capture
        try await stream?.startCapture()
        
        print("✅ System audio capture configured")
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
        
        // Notify delegate
        onAudioBuffersAvailable?(microphoneBuffer, systemAudioBuffer)
    }
    
    // MARK: - Helper Methods
    
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

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            processSystemAudioBuffer(sampleBuffer)
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("❌ Stream stopped with error: \(error)")
        DispatchQueue.main.async {
            self.captureError = error
            self.isCapturing = false
        }
    }
}

// MARK: - System Audio Output Handler

@available(macOS 13.0, *)
class SystemAudioOutputHandler: NSObject, SCStreamOutput {
    private let audioHandler: (CMSampleBuffer) -> Void
    
    init(audioHandler: @escaping (CMSampleBuffer) -> Void) {
        self.audioHandler = audioHandler
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            audioHandler(sampleBuffer)
        }
    }
}

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