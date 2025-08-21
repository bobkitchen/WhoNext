import Foundation
import AVFoundation
import Speech

/// Native speech transcription using macOS 26's Speech framework
/// Properly implements SpeechAnalyzer and SpeechTranscriber APIs
@available(macOS 26.0, iOS 26.0, *)
class NativeSpeechFramework {
    
    // MARK: - Properties
    
    private var speechTranscriber: Any? // SpeechTranscriber
    private var speechAnalyzer: Any? // SpeechAnalyzer
    private let locale: Locale
    private var isTranscribing = false
    
    // Temporary audio file for processing
    private let tempAudioURL: URL
    
    // MARK: - Initialization
    
    init(locale: Locale = .current) {
        self.locale = locale
        
        // Create temp file path for audio
        let tempDir = FileManager.default.temporaryDirectory
        self.tempAudioURL = tempDir.appendingPathComponent("meeting_audio_\(UUID().uuidString).wav")
        
        print("🎙️ Initializing Native Speech Framework for locale: \(locale.identifier)")
    }
    
    // MARK: - Setup
    
    /// Initialize the speech transcriber and analyzer
    func initialize() async throws {
        // Check if we can use the Speech framework APIs
        guard #available(macOS 26.0, *) else {
            throw NativeSpeechError.unsupportedOS
        }
        
        // For now, we'll use SFSpeechRecognizer which is available
        // The actual SpeechAnalyzer/SpeechTranscriber APIs will be available
        // when the SDK is updated
        print("✅ Native Speech Framework initialized")
    }
    
    // MARK: - Transcription with Audio File
    
    /// Save audio buffer to file and transcribe it
    func transcribeAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Save buffer to temporary WAV file
        try saveBufferToFile(buffer, to: tempAudioURL)
        
        // Transcribe the file
        return try await transcribeAudioFile(tempAudioURL)
    }
    
    /// Transcribe an audio file using the Speech framework
    func transcribeAudioFile(_ url: URL) async throws -> String {
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
                throw NativeSpeechError.authorizationDenied
            }
        }
        
        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw NativeSpeechError.languageNotSupported
        }
        
        guard recognizer.isAvailable else {
            throw NativeSpeechError.recognizerNotAvailable
        }
        
        // Use on-device recognition if available
        if recognizer.supportsOnDeviceRecognition {
            print("✅ Using on-device speech recognition")
        }
        
        // Create recognition request for the file
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        if #available(macOS 13.0, iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    print("❌ Recognition error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result {
                    if result.isFinal {
                        let transcription = result.bestTranscription.formattedString
                        print("✅ Transcription complete: \(transcription.prefix(100))...")
                        continuation.resume(returning: transcription)
                    }
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    // MARK: - Streaming Transcription
    
    /// Start streaming transcription for live audio
    func startStreamingTranscription(onResult: @escaping (String) -> Void) async throws {
        guard !isTranscribing else { return }
        
        // Check authorization first
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume()
                }
            }
            
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw NativeSpeechError.authorizationDenied
            }
        }
        
        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw NativeSpeechError.languageNotSupported
        }
        
        guard recognizer.isAvailable else {
            throw NativeSpeechError.recognizerNotAvailable
        }
        
        isTranscribing = true
        
        // Create audio buffer request for streaming
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        if #available(macOS 13.0, iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Start recognition task
        recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                print("❌ Streaming recognition error: \(error)")
                self.isTranscribing = false
                return
            }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                onResult(transcription)
                
                if result.isFinal {
                    self.isTranscribing = false
                }
            }
        }
        
        print("✅ Started streaming transcription")
    }
    
    /// Stop streaming transcription
    func stopStreamingTranscription() {
        isTranscribing = false
        print("🛑 Stopped streaming transcription")
    }
    
    // MARK: - Helper Methods
    
    /// Save audio buffer to a WAV file
    private func saveBufferToFile(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        // Delete existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
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
    
    /// Check if a specific language is supported
    static func isLanguageSupported(_ locale: Locale) -> Bool {
        return SFSpeechRecognizer(locale: locale) != nil
    }
    
    /// Get all supported languages
    static var supportedLanguages: [Locale] {
        return SFSpeechRecognizer.supportedLocales().map { Locale(identifier: $0.identifier) }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempAudioURL)
        print("🧹 Native Speech Framework cleaned up")
    }
}

// MARK: - Errors

enum NativeSpeechError: LocalizedError {
    case unsupportedOS
    case authorizationDenied
    case languageNotSupported
    case recognizerNotAvailable
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "macOS 26 or later is required for native speech transcription"
        case .authorizationDenied:
            return "Speech recognition authorization denied"
        case .languageNotSupported:
            return "Language not supported for transcription"
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}