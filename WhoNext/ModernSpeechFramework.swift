import Foundation
import AVFoundation
import Speech
import CoreMedia

/// Modern speech transcription implementation
/// Uses SFSpeechRecognizer as fallback until new APIs are in SDK headers
@available(macOS 26.0, *)
@MainActor
class ModernSpeechFramework {
    
    // MARK: - Properties
    
    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Buffer management
    private let converter = BufferConverter()
    private var audioFormat: AVAudioFormat?
    
    // Transcription state
    private var isTranscribing = false
    
    // Results
    private var accumulatedTranscript: String = ""
    private var lastPartialResult: String = ""
    
    // Audio accumulation for better transcription
    private var audioBufferAccumulator: [AVAudioPCMBuffer] = []
    private var accumulationStartTime: Date?
    private let accumulationDuration: TimeInterval = 30.0 // 30 seconds
    private let maxAccumulationDuration: TimeInterval = 60.0 // 60 seconds max
    
    // MARK: - Initialization
    
    init(locale: Locale = .current) {
        self.locale = locale
        print("[ModernSpeech] Initializing with locale: \(locale.identifier)")
        
        // Set up recognizer
        if let recognizer = SFSpeechRecognizer(locale: locale) {
            self.recognizer = recognizer
            print("[ModernSpeech] SFSpeechRecognizer created for locale: \(locale.identifier)")
        } else {
            // Fallback to en-US if locale not supported
            self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            print("[ModernSpeech] Fallback to en-US recognizer")
        }
        
        // Set up audio format for 16kHz mono, which is optimal for speech
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
    }
    
    // MARK: - Setup
    
    /// Initialize the speech recognizer
    func initialize() async throws {
        print("[ModernSpeech] Starting initialization...")
        
        // Request authorization if needed
        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            throw ModernSpeechError.transcriptionFailed("Speech recognition not authorized")
        }
        
        // Check recognizer availability
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw ModernSpeechError.languageNotSupported
        }
        
        print("[ModernSpeech] Speech recognizer ready and authorized")
        isTranscribing = true
    }
    
    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer by accumulating and transcribing
    func processAudioStream(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Ensure recognizer is available (start transcription if needed)
        guard recognizer != nil else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        // Auto-start transcription if not already running
        if !isTranscribing {
            isTranscribing = true
        }
        
        // Start accumulation if needed
        if accumulationStartTime == nil {
            accumulationStartTime = Date()
            startNewRecognitionRequest()
        }
        
        // Convert buffer to optimal format
        let convertedBuffer: AVAudioPCMBuffer
        if let targetFormat = audioFormat {
            convertedBuffer = try converter.convertBuffer(buffer, to: targetFormat)
        } else {
            convertedBuffer = buffer
        }
        
        // Add to accumulator
        audioBufferAccumulator.append(convertedBuffer)
        
        // Append to recognition request
        recognitionRequest?.append(convertedBuffer)
        
        // Check if we should process accumulated audio
        let elapsedTime = Date().timeIntervalSince(accumulationStartTime ?? Date())
        
        // Process if we've accumulated enough audio or hit the max duration
        if elapsedTime >= accumulationDuration || elapsedTime >= maxAccumulationDuration {
            print("[ModernSpeech] Processing accumulated audio (\(Int(elapsedTime))s)")
            try await processAccumulatedAudio()
        }
        
        return accumulatedTranscript
    }
    
    private func startNewRecognitionRequest() {
        // Cancel existing task if any
        recognitionTask?.cancel()
        
        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = false
        recognitionRequest?.taskHint = .dictation
        
        guard let recognitionRequest = recognitionRequest,
              let recognizer = recognizer else { return }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                if result.isFinal {
                    // Final result - add to accumulated transcript
                    if !transcription.isEmpty {
                        if !self.accumulatedTranscript.isEmpty {
                            self.accumulatedTranscript += " "
                        }
                        self.accumulatedTranscript += transcription
                        print("[ModernSpeech] Final segment: '\(transcription)'")
                    }
                    self.lastPartialResult = ""
                } else {
                    // Partial result - store for display but don't accumulate yet
                    self.lastPartialResult = transcription
                    if transcription.count > 10 { // Only log meaningful partials
                        print("[ModernSpeech] Partial: '\(transcription.suffix(50))...'")
                    }
                }
            }
            
            if let error = error {
                print("[ModernSpeech] Recognition error: \(error.localizedDescription)")
            }
        }
        
        print("[ModernSpeech] Started new recognition request")
    }
    
    private func processAccumulatedAudio() async throws {
        // End current request to get final result
        recognitionRequest?.endAudio()
        
        // Wait a bit for final result
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Clear accumulator
        audioBufferAccumulator.removeAll()
        accumulationStartTime = Date()
        
        // Start new request for next batch
        startNewRecognitionRequest()
        
        // Re-process any remaining buffers
        for buffer in audioBufferAccumulator {
            recognitionRequest?.append(buffer)
        }
    }
    
    /// Process an entire audio file
    func transcribeFile(at url: URL) async throws -> String {
        print("[ModernSpeech] Transcribing file: \(url.lastPathComponent)")
        
        guard let recognizer = recognizer else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    // MARK: - State Management
    
    /// Start transcription
    func startTranscription() async throws {
        guard !isTranscribing else { return }
        
        print("[ModernSpeech] Starting transcription...")
        
        // Initialize if not already done
        if recognizer == nil {
            try await initialize()
        }
        
        isTranscribing = true
        accumulatedTranscript = ""
        lastPartialResult = ""
        audioBufferAccumulator.removeAll()
        accumulationStartTime = nil
        
        // Start recognition
        startNewRecognitionRequest()
    }
    
    /// Stop transcription and finalize
    func stopTranscription() async throws {
        guard isTranscribing else { return }
        
        print("[ModernSpeech] Stopping transcription...")
        
        // Process any remaining audio
        if !audioBufferAccumulator.isEmpty {
            try await processAccumulatedAudio()
        }
        
        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        
        // Wait for final results
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        isTranscribing = false
        
        print("[ModernSpeech] Transcription stopped")
        print("[ModernSpeech] Final transcript: \(accumulatedTranscript)")
    }
    
    /// Reset the transcriber
    func reset() {
        print("[ModernSpeech] Resetting...")
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        accumulatedTranscript = ""
        lastPartialResult = ""
        audioBufferAccumulator.removeAll()
        accumulationStartTime = nil
        isTranscribing = false
        
        // Reinitialize recognizer if needed (don't destroy it)
        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: locale)
        }
        
        print("[ModernSpeech] Reset complete")
    }
    
    // MARK: - Results
    
    /// Get the current transcript
    func getCurrentTranscript() -> String {
        // Combine accumulated and current partial
        if !lastPartialResult.isEmpty {
            if !accumulatedTranscript.isEmpty {
                return accumulatedTranscript + " " + lastPartialResult
            }
            return lastPartialResult
        }
        return accumulatedTranscript
    }
    
    /// Get finalized transcript only
    func getFinalizedTranscript() -> String {
        return accumulatedTranscript
    }
    
    /// Flush any remaining audio and get final transcription
    func flushAndTranscribe() async -> String {
        print("[ModernSpeech] Flushing audio buffer...")
        
        if isTranscribing {
            try? await stopTranscription()
        }
        
        return getFinalizedTranscript()
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        print("[ModernSpeech] Cleaning up...")
        
        if isTranscribing {
            try? await stopTranscription()
        }
        
        recognizer = nil
        
        print("[ModernSpeech] Cleanup complete")
    }
    
    deinit {
        recognitionTask?.cancel()
    }
}

// MARK: - Errors

enum ModernSpeechError: LocalizedError {
    case languageNotSupported
    case transcriptionFailed(String)
    case transcriberNotInitialized
    case assetDownloadFailed
    
    var errorDescription: String? {
        switch self {
        case .languageNotSupported:
            return "The selected language is not supported for transcription"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .transcriberNotInitialized:
            return "Speech transcriber is not initialized"
        case .assetDownloadFailed:
            return "Failed to download required speech assets"
        }
    }
}