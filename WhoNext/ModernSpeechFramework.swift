import Foundation
import AVFoundation
import Speech
import CoreMedia

/// Modern speech transcription implementation using new macOS 26 Speech APIs
/// Based on patterns from YAP and Swift Scribe implementations
@available(macOS 26.0, *)
@MainActor
class ModernSpeechFramework {
    
    // MARK: - Properties
    
    private let locale: Locale
    
    // New Speech API components
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), any Error>?
    
    // AsyncStream for audio input
    private var inputStream: AsyncStream<AnalyzerInput>
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    
    // Buffer management
    private let converter = BufferConverter()
    private var analyzerFormat: AVAudioFormat?
    
    // Audio chunking (Removed for real-time processing)
    // private var audioChunkBuffer: [AVAudioPCMBuffer] = []
    // private var chunkStartTime: Date = Date()
    // private let chunkDuration: TimeInterval = 30.0 
    // private var accumulatedFrameCount: AVAudioFrameCount = 0
    
    // Transcription state
    private var isTranscribing = false
    
    // Results
    private var finalizedTranscript: String = ""
    private var volatileTranscript: String = ""
    
    // Advanced features
    private var transcriptionSegments: [SpeechTranscriptionSegment] = []
    private var speakerAttributions: [SpeakerAttribution] = []
    private var currentSpeakerId: Int = 0
    
    // MARK: - Initialization
    
    init(locale: Locale = .current) {
        self.locale = locale
        print("[ModernSpeech] Initializing with locale: \(locale.identifier)")
        
        // Create AsyncStream for audio input
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputStream = stream
        self.inputContinuation = continuation
    }
    
    // MARK: - Setup
    
    /// Initialize the speech recognizer using new APIs
    func initialize() async throws {
        print("[ModernSpeech] Starting initialization with new Speech APIs...")
        
        // Deallocate any existing locales first (like yap does)
        let allocatedLocales = await AssetInventory.reservedLocales
        for locale in allocatedLocales {
            await AssetInventory.release(reservedLocale: locale)
        }
        
        // Create SpeechTranscriber with advanced options
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        
        guard let transcriber = transcriber else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        print("[ModernSpeech] SpeechTranscriber created successfully")
        
        // Create SpeechAnalyzer with transcriber module
        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("[ModernSpeech] SpeechAnalyzer created with transcriber module")
        
        // Ensure language model is available
        try await ensureLanguageModel(for: transcriber, locale: locale)
        
        // Get best audio format for the analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        print("[ModernSpeech] Best audio format: \(String(describing: analyzerFormat))")
        
        guard analyzerFormat != nil else {
            throw ModernSpeechError.languageNotSupported
        }
        
        // Start the analyzer with input stream FIRST
        try await analyzer?.start(inputSequence: inputStream)
        print("[ModernSpeech] SpeechAnalyzer started successfully")
        
        // THEN create recognition task to listen for results
        startRecognitionTask()
        
        isTranscribing = true
    }
    
    /// Start the recognition task to listen for transcription results
    private func startRecognitionTask() {
        recognizerTask = Task { [weak self] in
            guard let self = self else { return }
            guard let transcriber = self.transcriber else { 
                print("[ModernSpeech] No transcriber available for recognition task")
                return 
            }
            
            print("[ModernSpeech] Recognition task started, listening for results...")
            
            do {
                var resultCount = 0
                
                // Keep the task alive and listening
                for try await result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    
                    // Process the result on the main actor to update UI
                    await MainActor.run {
                        // Extract advanced features
                        let confidence: Float = 1.0 // Default confidence (API doesn't expose it yet)
                        // Time range tracking would be done manually based on buffer timing
                        let timeRange: (start: TimeInterval, end: TimeInterval)? = nil
                        let speakerId: Int? = nil // Speaker attribution not yet available
                        
                        // Create transcription segment
                        let segment = SpeechTranscriptionSegment(
                            text: String(text.characters),
                            startTime: timeRange?.start ?? 0,
                            endTime: timeRange?.end ?? 0,
                            confidence: confidence,
                            isFinal: result.isFinal,
                            speakerId: speakerId,
                            alternatives: []  // Alternatives not available in current API
                        )
                        
                        // Store segment
                        self.transcriptionSegments.append(segment)
                        
                        // Handle speaker changes
                        if let speakerId = speakerId, speakerId != self.currentSpeakerId {
                            self.currentSpeakerId = speakerId
                            self.handleSpeakerChange(speakerId: speakerId, at: timeRange?.start ?? 0)
                        }
                        
                        if result.isFinal {
                            // Final result - add to finalized transcript
                            let textString = String(text.characters)
                            if !textString.isEmpty {
                                // Format the 30-second chunk for readability
                                let formattedText = self.formatTranscriptChunk(textString)
                                
                                if !self.finalizedTranscript.isEmpty {
                                    // Add paragraph break between 30-second chunks
                                    if !self.finalizedTranscript.hasSuffix("\n\n") {
                                        self.finalizedTranscript += "\n\n"
                                    }
                                }
                                self.finalizedTranscript += formattedText
                                self.volatileTranscript = ""
                                
                                // Safe string preview for logging
                                let preview = self.safeStringPreview(textString, maxLength: 50)
                                let wordCount = textString.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                                print("[ModernSpeech] Final segment #\(resultCount): '\(preview)' (\(wordCount) words)")
                            }
                        } else {
                            // Volatile result - store for display
                            let textString = String(text.characters)
                            self.volatileTranscript = textString
                            if !textString.isEmpty {
                                // Safe string preview for logging
                                let preview = self.safeStringPreview(textString, maxLength: 50)
                                print("[ModernSpeech] Partial #\(resultCount): '\(preview)'")
                            }
                        }
                    }
                }
                
                print("[ModernSpeech] Recognition task completed after \(resultCount) results")
            } catch {
                print("[ModernSpeech] Recognition error: \(error.localizedDescription)")
                print("[ModernSpeech] Error details: \(error)")
                
                // Restart recognition task if it fails
                if self.isTranscribing {
                    print("[ModernSpeech] Restarting recognition task...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.startRecognitionTask()
                    }
                }
            }
        }
    }
    
    /// Ensure language model is available and reserved
    private func ensureLanguageModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("[ModernSpeech] Ensuring language model for locale: \(locale.identifier)")
        
        // Check if download is needed
        if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            print("[ModernSpeech] Downloading required speech assets...")
            try await installRequest.downloadAndInstall()
            print("[ModernSpeech] Speech assets downloaded successfully")
        }
        
        // Check supported locales
        let supportedLocales = await SpeechTranscriber.supportedLocales
        print("[ModernSpeech] Supported locales: \(supportedLocales.map { $0.identifier })")
        
        guard supportedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            // Try fallback to en-US
            let fallbackLocale = Locale(identifier: "en-US")
            if supportedLocales.contains(where: { $0.identifier(.bcp47) == fallbackLocale.identifier(.bcp47) }) {
                print("[ModernSpeech] Using fallback locale: en-US")
                try await allocateLocale(fallbackLocale)
                return
            }
            throw ModernSpeechError.languageNotSupported
        }
        
        // Allocate the locale
        try await allocateLocale(locale)
    }
    
    /// Allocate locale for speech recognition using correct API
    private func allocateLocale(_ locale: Locale) async throws {
        print("[ModernSpeech] Allocating locale: \(locale.identifier)")
        
        // Check if locale is already allocated
        let allocatedLocales = await AssetInventory.reservedLocales
        if !allocatedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            // Allocate the locale using the correct API
            try await AssetInventory.reserve(locale: locale)
            print("[ModernSpeech] Locale allocated successfully: \(locale.identifier)")
        } else {
            print("[ModernSpeech] Locale already allocated: \(locale.identifier)")
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer - stream immediately to analyzer
    func processAudioStream(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Ensure analyzer is initialized
        if analyzer == nil {
            print("[ModernSpeech] Analyzer not initialized, initializing now...")
            try await initialize()
        }
        
        guard let analyzerFormat = analyzerFormat else {
            print("[ModernSpeech] No analyzer format available")
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        // Convert buffer to optimal format
        let convertedBuffer = try converter.convertBuffer(buffer, to: analyzerFormat)
        
        // Stream immediately to analyzer
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputContinuation.yield(input)
        
        return getCurrentTranscript()
    }
    
    // processAccumulatedChunk removed - streaming immediately now
    
    /// Process an entire audio file
    func transcribeFile(at url: URL) async throws -> String {
        print("[ModernSpeech] Transcribing file: \(url.lastPathComponent)")
        
        // Ensure initialized
        if analyzer == nil {
            try await initialize()
        }
        
        guard let analyzer = analyzer else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        // Open audio file
        let audioFile = try AVAudioFile(forReading: url)
        
        // Start analyzer with file input
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        
        // Wait for transcription to complete
        var finalTranscript = ""
        if let transcriber = transcriber {
            for try await result in transcriber.results {
                if result.isFinal {
                    finalTranscript += String(result.text.characters)
                }
            }
        }
        
        return finalTranscript
    }
    
    // MARK: - State Management
    
    /// Start transcription
    func startTranscription() async throws {
        guard !isTranscribing else { 
            print("[ModernSpeech] Already transcribing, ignoring start request")
            return 
        }
        
        print("[ModernSpeech] Starting transcription...")
        
        // Reset transcripts
        finalizedTranscript = ""
        volatileTranscript = ""
        transcriptionSegments.removeAll()
        
        // Create new input stream for this session
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputStream = stream
        self.inputContinuation = continuation
        
        // Always recreate analyzer and transcriber for new session
        // The analyzer can't be restarted once it's finished
        print("[ModernSpeech] Creating new analyzer for session...")
        
        // Cancel any existing recognition task
        recognizerTask?.cancel()
        recognizerTask = nil
        
        // Clean up existing analyzer
        if analyzer != nil {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            analyzer = nil
            transcriber = nil
        }
        
        // Create fresh transcriber and analyzer
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        
        guard let transcriber = transcriber else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        analyzer = SpeechAnalyzer(modules: [transcriber])
        
        // Start analyzer with new stream
        try await analyzer?.start(inputSequence: inputStream)
        print("[ModernSpeech] New SpeechAnalyzer started successfully")
        
        // Start recognition task
        startRecognitionTask()
        
        isTranscribing = true
    }
    
    /// Stop transcription and finalize
    func stopTranscription() async throws {
        guard isTranscribing else { return }
        
        print("[ModernSpeech] Stopping transcription...")
        
        isTranscribing = false
        
        // Process any remaining audio in the buffer - REMOVED (streaming immediately)
        // if !audioChunkBuffer.isEmpty {
        //     print("[ModernSpeech] Processing final chunk (\(audioChunkBuffer.count) buffers)")
        //     await processAccumulatedChunk()
        // }
        
        // Finish the input stream
        inputContinuation.finish()
        
        // Give time for any pending results to process
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second for final processing
        
        // Finalize the analyzer if it exists and isn't already finished
        if analyzer != nil {
            do {
                try await analyzer?.finalizeAndFinishThroughEndOfInput()
            } catch {
                print("[ModernSpeech] Analyzer already finished or error: \(error)")
            }
        }
        
        // Cancel recognition task
        recognizerTask?.cancel()
        recognizerTask = nil
        
        // Clean up
        analyzer = nil
        transcriber = nil
        // audioChunkBuffer.removeAll()
        // accumulatedFrameCount = 0
        
        print("[ModernSpeech] Transcription stopped")
        print("[ModernSpeech] Final transcript: \(finalizedTranscript)")
        print("[ModernSpeech] Total segments: \(transcriptionSegments.count)")
    }
    
    /// Reset the transcriber
    func reset() {
        print("[ModernSpeech] Resetting...")
        
        // Cancel ongoing tasks
        recognizerTask?.cancel()
        recognizerTask = nil
        
        // Clear transcripts
        finalizedTranscript = ""
        volatileTranscript = ""
        transcriptionSegments.removeAll()
        speakerAttributions.removeAll()
        currentSpeakerId = 0
        isTranscribing = false
        
        // Clear audio buffers
        // audioChunkBuffer.removeAll()
        // accumulatedFrameCount = 0
        // chunkStartTime = Date()
        
        // Finish current stream
        inputContinuation.finish()
        
        // Clean up analyzer and transcriber
        // They will be recreated on next startTranscription
        analyzer = nil
        transcriber = nil
        
        // Create new input stream
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputStream = stream
        self.inputContinuation = continuation
        
        print("[ModernSpeech] Reset complete")
    }
    
    // MARK: - Results
    
    /// Get the current transcript (finalized + volatile)
    func getCurrentTranscript() -> String {
        if !volatileTranscript.isEmpty {
            if !finalizedTranscript.isEmpty {
                return finalizedTranscript + " " + volatileTranscript
            }
            return volatileTranscript
        }
        return finalizedTranscript
    }
    
    /// Get finalized transcript only
    func getFinalizedTranscript() -> String {
        return finalizedTranscript
    }
    
    /// Get transcription segments with metadata
    func getTranscriptionSegments() -> [SpeechTranscriptionSegment] {
        return transcriptionSegments
    }
    
    /// Get speaker attributions
    func getSpeakerAttributions() -> [SpeakerAttribution] {
        return speakerAttributions
    }
    
    /// Get average confidence score
    func getAverageConfidence() -> Float {
        guard !transcriptionSegments.isEmpty else { return 0.0 }
        let totalConfidence = transcriptionSegments.reduce(0) { $0 + $1.confidence }
        return totalConfidence / Float(transcriptionSegments.count)
    }
    
    // MARK: - Helper Methods
    
    /// Extract alternative transcriptions from result
    private func extractAlternatives(from result: SpeechTranscriber.Result) -> [AlternativeTranscription] {
        // If the API provides alternatives, extract them
        // For now, return empty array as placeholder
        return []
    }
    
    /// Format transcript chunk with proper paragraph breaks
    private func formatTranscriptChunk(_ text: String) -> String {
        // Clean up the text first
        var formatted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Safely apply regex replacements with error handling
        do {
            // Add paragraph breaks after sentences for better readability
            // Look for sentence endings followed by capital letters
            let sentenceEndPattern1 = try NSRegularExpression(pattern: "\\. ([A-Z])", options: [])
            formatted = sentenceEndPattern1.stringByReplacingMatches(
                in: formatted, 
                range: NSRange(formatted.startIndex..., in: formatted), 
                withTemplate: ".\n\n$1"
            )
            
            let sentenceEndPattern2 = try NSRegularExpression(pattern: "\\? ([A-Z])", options: [])
            formatted = sentenceEndPattern2.stringByReplacingMatches(
                in: formatted,
                range: NSRange(formatted.startIndex..., in: formatted),
                withTemplate: "?\n\n$1"
            )
            
            let sentenceEndPattern3 = try NSRegularExpression(pattern: "\\! ([A-Z])", options: [])
            formatted = sentenceEndPattern3.stringByReplacingMatches(
                in: formatted,
                range: NSRange(formatted.startIndex..., in: formatted),
                withTemplate: "!\n\n$1"
            )
            
            // Also break on common speech patterns that indicate topic changes
            let topicChangePattern = try NSRegularExpression(
                pattern: "(\\.) (So |And |But |Now |Well |Okay |Alright )",
                options: [.caseInsensitive]
            )
            formatted = topicChangePattern.stringByReplacingMatches(
                in: formatted,
                range: NSRange(formatted.startIndex..., in: formatted),
                withTemplate: "$1\n\n$2"
            )
        } catch {
            // If regex fails, return the original formatted text
            print("[ModernSpeech] Regex formatting failed: \(error), returning unformatted text")
        }
        
        return formatted
    }
    
    /// Safely create a preview of a string without index out of bounds issues
    private func safeStringPreview(_ text: String, maxLength: Int) -> String {
        guard !text.isEmpty else { return "" }
        
        // Use safe string slicing to avoid index out of bounds
        if text.count <= maxLength {
            return text
        }
        
        // Convert to array to safely handle Unicode
        let chars = Array(text)
        let safeLength = min(maxLength, chars.count)
        let preview = String(chars[0..<safeLength])
        return preview + "..."
    }
    
    /// Handle speaker change event
    private func handleSpeakerChange(speakerId: Int, at time: TimeInterval) {
        print("[ModernSpeech] Speaker changed to ID: \(speakerId) at \(time)s")
        
        // Create speaker attribution entry
        let attribution = SpeakerAttribution(
            speakerId: speakerId,
            startTime: time,
            endTime: time, // Will be updated when speaker changes again
            voiceCharacteristics: nil // Could be extracted if API provides
        )
        
        // Update previous speaker's end time if exists
        if !speakerAttributions.isEmpty {
            var lastAttribution = speakerAttributions.removeLast()
            lastAttribution = SpeakerAttribution(
                speakerId: lastAttribution.speakerId,
                startTime: lastAttribution.startTime,
                endTime: time,
                voiceCharacteristics: lastAttribution.voiceCharacteristics
            )
            speakerAttributions.append(lastAttribution)
        }
        
        speakerAttributions.append(attribution)
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
        
        // Deallocate locale using correct API
        let allocatedLocales = await AssetInventory.reservedLocales
        for locale in allocatedLocales {
            if locale.identifier(.bcp47) == self.locale.identifier(.bcp47) {
                await AssetInventory.release(reservedLocale: locale)
                print("[ModernSpeech] Deallocated locale: \(locale.identifier)")
            }
        }
        
        transcriber = nil
        analyzer = nil
        
        print("[ModernSpeech] Cleanup complete")
    }
    
    deinit {
        recognizerTask?.cancel()
        inputContinuation.finish()
    }
}

// MARK: - Data Structures

/// Represents a segment of transcribed text with metadata
struct SpeechTranscriptionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    let isFinal: Bool
    let speakerId: Int?
    let alternatives: [AlternativeTranscription]
}

/// Alternative transcription with confidence score
struct AlternativeTranscription {
    let text: String
    let confidence: Float
}

/// Speaker attribution information
struct SpeakerAttribution {
    let speakerId: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let voiceCharacteristics: VoiceCharacteristics?
}

/// Voice characteristics for speaker identification
struct VoiceCharacteristics {
    let pitch: Float
    let speakingRate: Float
    let volumeLevel: Float
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