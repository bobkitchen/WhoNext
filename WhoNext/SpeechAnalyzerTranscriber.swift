import Foundation
import AVFoundation
import Speech

/// Native speech transcription using macOS 26's Speech framework APIs
/// Based on the WWDC session "Bring advanced speech-to-text to your app with SpeechAnalyzer"
@available(macOS 26.0, iOS 26.0, *)
class NativeSpeechTranscriber {
    
    // MARK: - Properties
    
    private var speechTranscriber: Any? // Will be SpeechTranscriber
    private var speechAnalyzer: Any? // Will be SpeechAnalyzer
    private var inputBuilder: Any? // Stream input builder
    private var isInitialized = false
    private let locale: Locale
    private var transcriptionTask: Task<Void, Never>?
    
    // Buffer management for better speech detection
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private let minBufferDuration: TimeInterval = 1.0 // Minimum 1 second of audio
    private let maxBufferDuration: TimeInterval = 10.0 // Maximum 10 seconds
    private var accumulatedDuration: TimeInterval = 0
    
    // MARK: - Initialization
    
    init(locale: Locale = .current) {
        self.locale = locale
        print("🎙️ Initializing Native Speech Transcriber for locale: \(locale.identifier)")
        
        // Try to initialize with runtime APIs
        Task {
            await tryInitializeRuntimeAPIs()
        }
    }
    
    // MARK: - Setup
    
    /// Try to initialize the macOS 26 Speech APIs via runtime lookup
    private func tryInitializeRuntimeAPIs() async {
        // Attempt to use dlopen to load the Speech framework dynamically
        let speechFrameworkPath = "/System/Library/Frameworks/Speech.framework/Speech"
        guard let handle = dlopen(speechFrameworkPath, RTLD_NOW) else {
            print("⚠️ Could not dynamically load Speech framework")
            return
        }
        defer { dlclose(handle) }
        
        // Try to find the classes via runtime
        if let transciberClass = NSClassFromString("Speech.SpeechTranscriber") ??
                                 NSClassFromString("SpeechTranscriber") {
            print("✅ Found SpeechTranscriber class via runtime")
            
            // Try to create instance using performSelector
            if transciberClass.responds(to: NSSelectorFromString("alloc")) {
                print("✅ SpeechTranscriber responds to alloc")
                // We found the class but can't instantiate without proper headers
                // Mark as available for future SDK updates
            }
        }
        
        if let analyzerClass = NSClassFromString("Speech.SpeechAnalyzer") ??
                               NSClassFromString("SpeechAnalyzer") {
            print("✅ Found SpeechAnalyzer class via runtime")
        }
        
        // Check for AssetInventory
        if let inventoryClass = NSClassFromString("Speech.AssetInventory") ??
                                NSClassFromString("AssetInventory") {
            print("✅ Found AssetInventory class via runtime")
        }
    }
    
    /// Initialize the speech transcriber and analyzer using runtime lookup
    func initialize() async throws {
        guard !isInitialized else { return }
        
        // For now, we use SFSpeechRecognizer which is available and works
        // The macOS 26 APIs exist but require SDK updates to use properly
        isInitialized = true
        print("✅ Using SFSpeechRecognizer for transcription (macOS 26 APIs pending SDK update)")
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio buffer to text using native APIs
    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Check if this buffer has speech energy
        if let energy = calculateAudioEnergy(buffer) {
            if energy < -50 {
                // Skip silent buffers but keep accumulating time
                let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
                print("🔇 Skipping silent buffer (\(String(format: "%.2f", energy)) dB, \(String(format: "%.2f", bufferDuration))s)")
                return ""
            }
        }
        
        // Add buffer to queue to accumulate enough audio for reliable transcription
        audioBufferQueue.append(buffer)
        
        // Calculate accumulated duration
        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        accumulatedDuration += bufferDuration
        
        // Check if we have enough audio to transcribe
        if accumulatedDuration < minBufferDuration {
            print("⏳ Accumulating audio: \(String(format: "%.2f", accumulatedDuration))s / \(minBufferDuration)s")
            return "" // Return empty string while accumulating
        }
        
        // If we've exceeded max duration or have enough, process the buffers
        if accumulatedDuration >= minBufferDuration || accumulatedDuration >= maxBufferDuration {
            // Combine all buffers
            guard let combinedBuffer = combineBuffers(audioBufferQueue) else {
                audioBufferQueue.removeAll()
                accumulatedDuration = 0
                throw SpeechAnalyzerError.invalidAudioBuffer
            }
            
            // Clear the queue
            audioBufferQueue.removeAll()
            accumulatedDuration = 0
            
            // Transcribe the combined buffer
            return try await transcribeUsingSFSpeechRecognizer(combinedBuffer)
        }
        
        return ""
    }
    
    /// Combine multiple audio buffers into one
    private func combineBuffers(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }
        
        let format = buffers[0].format
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        
        guard let combinedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            return nil
        }
        
        var currentFrame: AVAudioFrameCount = 0
        for buffer in buffers {
            let frameLength = buffer.frameLength
            
            // Copy audio data
            if let srcData = buffer.floatChannelData,
               let dstData = combinedBuffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    let src = srcData[channel]
                    let dst = dstData[channel].advanced(by: Int(currentFrame))
                    memcpy(dst, src, Int(frameLength) * MemoryLayout<Float>.size)
                }
            }
            
            currentFrame += frameLength
        }
        
        combinedBuffer.frameLength = AVAudioFrameCount(totalFrames)
        return combinedBuffer
    }
    
    // MARK: - Fallback Implementation using SFSpeechRecognizer
    
    private func transcribeUsingSFSpeechRecognizer(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Check minimum audio duration
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        print("🎤 Processing audio buffer: \(String(format: "%.2f", duration)) seconds, \(buffer.frameLength) frames")
        
        // Validate audio contains actual sound
        if let energy = calculateAudioEnergy(buffer) {
            print("🔊 Audio energy: \(String(format: "%.2f", energy)) dB")
            if energy < -50 {
                print("⚠️ Audio buffer contains silence or very low energy (< -50 dB)")
                // Don't attempt transcription on silent audio
                return ""
            }
        }
        
        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            // Request authorization
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume()
                }
            }
            
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw SpeechAnalyzerError.authorizationDenied
            }
        }
        
        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechAnalyzerError.languageNotSupported
        }
        
        guard recognizer.isAvailable else {
            throw SpeechAnalyzerError.recognizerNotAvailable
        }
        
        // Check if on-device recognition is supported
        if recognizer.supportsOnDeviceRecognition {
            print("✅ Using on-device speech recognition")
        } else {
            print("⚠️ On-device recognition not supported, using server")
        }
        
        // Create a recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        
        // Configure for on-device if available
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        // Configure request options
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        
        // Add context if needed
        if #available(macOS 13.0, iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Create temporary file for audio
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp_audio_\(UUID().uuidString).wav")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Write buffer to file
        try writeBufferToFile(buffer, to: tempURL)
        
        // Create file request instead of buffer request for better reliability
        let fileRequest = SFSpeechURLRecognitionRequest(url: tempURL)
        fileRequest.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            fileRequest.requiresOnDeviceRecognition = true
        }
        
        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: fileRequest) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result {
                    if result.isFinal {
                        let transcription = result.bestTranscription.formattedString
                        print("✅ Transcription: \(transcription)")
                        continuation.resume(returning: transcription)
                    }
                } else {
                    continuation.resume(returning: "[No speech detected]")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate audio energy in dB
    private func calculateAudioEnergy(_ buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var totalEnergy: Float = 0
        var sampleCount = 0
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                totalEnergy += sample * sample
                sampleCount += 1
            }
        }
        
        guard sampleCount > 0 else { return nil }
        
        // Calculate RMS (Root Mean Square)
        let rms = sqrt(totalEnergy / Float(sampleCount))
        
        // Convert to dB (20 * log10(rms))
        // Avoid log of 0 by using a minimum value
        let dB = 20 * log10(max(rms, 1e-10))
        
        return dB
    }
    
    /// Write audio buffer to a WAV file
    private func writeBufferToFile(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let audioFile = try AVAudioFile(forWriting: url, settings: settings)
        try audioFile.write(from: buffer)
    }
    
    // MARK: - Language Support
    
    /// Check if a specific language is supported for transcription
    static func isLanguageSupported(_ locale: Locale) -> Bool {
        return SFSpeechRecognizer(locale: locale) != nil
    }
    
    /// Get all supported languages for transcription
    static var supportedLanguages: [Locale] {
        return SFSpeechRecognizer.supportedLocales().map { Locale(identifier: $0.identifier) }
    }
    
    // MARK: - Cleanup
    
    deinit {
        transcriptionTask?.cancel()
        print("🧹 Native Speech Transcriber cleaned up")
    }
}

// Import dynamic linker for runtime loading
import Darwin

// MARK: - Supporting Types

/// Native transcription result with segments and confidence
struct NativeTranscriptionResult {
    let text: String
    let segments: [NativeTranscriptionSegment]
    let confidence: Float
}

/// A segment of transcribed text with timing information
struct NativeTranscriptionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

// MARK: - Errors

enum SpeechAnalyzerError: LocalizedError {
    case initializationFailed
    case analyzerNotAvailable
    case transcriptionFailed(String)
    case invalidAudioBuffer
    case languageNotSupported
    case assetAllocationFailed
    case authorizationDenied
    case recognizerNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize Speech Analyzer"
        case .analyzerNotAvailable:
            return "Speech Analyzer is not available"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidAudioBuffer:
            return "Invalid audio buffer format"
        case .languageNotSupported:
            return "Language not supported for transcription"
        case .assetAllocationFailed:
            return "Failed to allocate language model assets"
        case .authorizationDenied:
            return "Speech recognition authorization denied"
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        }
    }
}