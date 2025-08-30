import Foundation
import AVFoundation
import Speech
import CoreMedia

/// Modern speech transcription using macOS 26's new Speech framework APIs
/// Requires compilation with CommandLineTools SDK and Swift 6.2
@available(macOS 26.0, *)
@MainActor
class NewSpeechFramework {
    
    // MARK: - Properties
    
    // Core Speech API components
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private let locale: Locale
    
    // AsyncStream for audio streaming
    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    
    // Buffer converter for format conversion
    private let converter = BufferConverter()
    private var analyzerFormat: AVAudioFormat?
    
    // Transcription state
    private var isTranscribing = false
    private var recognitionTask: Task<Void, Error>?
    
    // Results
    private var volatileTranscript: AttributedString = ""
    private var finalizedTranscript: AttributedString = ""
    private var accumulatedTranscript: String = ""
    
    // Progress tracking
    var downloadProgress: Progress?
    
    // MARK: - Initialization
    
    init(locale: Locale = .current) {
        self.locale = locale
        print("[NewSpeech] Initializing with locale: \(locale.identifier)")
        
        // Create AsyncStream for audio input
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }
    
    // MARK: - Setup
    
    /// Initialize the speech transcriber and analyzer
    func initialize() async throws {
        print("[NewSpeech] Starting initialization...")
        
        // Create transcriber with options
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        
        guard let transcriber else {
            print("[NewSpeech] ERROR - Failed to create SpeechTranscriber")
            throw NewSpeechError.transcriberNotInitialized
        }
        print("[NewSpeech] SpeechTranscriber created successfully")
        
        // Create analyzer with transcriber module
        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("[NewSpeech] SpeechAnalyzer created with transcriber module")
        
        // Ensure language model is available
        try await ensureModel(transcriber: transcriber, locale: locale)
        
        // Get best audio format for analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        print("[NewSpeech] Best audio format: \(String(describing: analyzerFormat))")
        
        guard analyzerFormat != nil else {
            print("[NewSpeech] ERROR - No compatible audio format found")
            throw NewSpeechError.transcriptionFailed("No compatible audio format")
        }
        
        // Start recognition task to process results
        startRecognitionTask()
        
        // Start analyzer with input stream
        try await analyzer?.start(inputSequence: inputSequence)
        print("[NewSpeech] SpeechAnalyzer started successfully")
        
        isTranscribing = true
    }
    
    // MARK: - Model Management
    
    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("[NewSpeech] Checking model availability for locale: \(locale.identifier)")
        
        // Check for required downloads first
        try await downloadIfNeeded(for: transcriber)
        
        // Check supported locales
        let supportedLocales = await SpeechTranscriber.supportedLocales
        print("[NewSpeech] Found \(supportedLocales.count) supported locales")
        
        // Verify locale is supported
        var localeToUse = locale
        if await isSupported(locale: locale) {
            print("[NewSpeech] Locale is supported: \(locale.identifier)")
        } else {
            // Try fallback locales
            let fallbackLocales = [
                Locale(identifier: "en-US"),
                Locale(identifier: "en-GB"),
                Locale(identifier: "en"),
                Locale.current
            ]
            
            var foundSupported = false
            for fallback in fallbackLocales {
                if await isSupported(locale: fallback) {
                    print("[NewSpeech] Using fallback locale: \(fallback.identifier)")
                    localeToUse = fallback
                    foundSupported = true
                    break
                }
            }
            
            guard foundSupported else {
                throw NewSpeechError.languageNotSupported
            }
        }
        
        // Check if installed
        if await isInstalled(locale: localeToUse) {
            print("[NewSpeech] Model already installed for locale: \(localeToUse.identifier)")
        } else {
            print("[NewSpeech] Model not installed for locale: \(localeToUse.identifier)")
        }
        
        // Reserve locale resources (using correct API)
        try await reserveLocale(locale: localeToUse)
    }
    
    private func isSupported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier == locale.identifier || $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }
    
    private func isInstalled(locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier == locale.identifier || $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }
    
    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        print("[NewSpeech] Checking if download is needed...")
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            print("[NewSpeech] Download required, starting asset installation...")
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
            print("[NewSpeech] Asset download and installation completed")
        } else {
            print("[NewSpeech] No download needed")
        }
    }
    
    private func reserveLocale(locale: Locale) async throws {
        print("[NewSpeech] Checking if locale is already reserved: \(locale.identifier)")
        let reserved = await AssetInventory.reservedLocales
        
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            print("[NewSpeech] Locale already reserved: \(locale.identifier)")
            return
        }
        
        print("[NewSpeech] Reserving locale: \(locale.identifier)")
        let success = try await AssetInventory.reserve(locale: locale)
        if success {
            print("[NewSpeech] Locale reserved successfully: \(locale.identifier)")
        } else {
            print("[NewSpeech] Failed to reserve locale: \(locale.identifier)")
        }
    }
    
    // MARK: - Recognition Task
    
    private func startRecognitionTask() {
        recognitionTask = Task {
            print("[NewSpeech] Starting recognition task...")
            
            guard let transcriber else { return }
            
            do {
                var resultCount = 0
                for try await result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    
                    if result.isFinal {
                        // Finalized text - add to permanent transcript
                        finalizedTranscript += text
                        volatileTranscript = ""
                        accumulatedTranscript = String(finalizedTranscript.characters)
                        print("[NewSpeech] Finalized segment \(resultCount): '\(String(text.characters))'")
                    } else {
                        // Volatile text - temporary, will be replaced
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.5)
                        print("[NewSpeech] Volatile segment \(resultCount): '\(String(text.characters))'")
                    }
                }
                print("[NewSpeech] Recognition task completed after \(resultCount) results")
            } catch {
                print("[NewSpeech] ERROR - Recognition failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer by streaming it to the analyzer
    func processAudioStream(_ buffer: AVAudioPCMBuffer) async throws -> String {
        guard let analyzerFormat else {
            throw NewSpeechError.transcriberNotInitialized
        }
        
        // Convert buffer to analyzer format
        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        
        // Create AnalyzerInput and yield to stream
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
        
        // Return current accumulated transcript
        return getCurrentTranscript()
    }
    
    /// Process an entire audio file
    func transcribeFile(at url: URL) async throws -> String {
        print("[NewSpeech] Transcribing file: \(url.lastPathComponent)")
        
        // For file transcription, create a new transcriber and analyzer
        let fileTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        
        let fileAnalyzer = SpeechAnalyzer(modules: [fileTranscriber])
        
        // Start analyzer with file
        let audioFile = try AVAudioFile(forReading: url)
        try await fileAnalyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        
        // Collect results
        var transcript = AttributedString()
        for try await result in fileTranscriber.results {
            transcript += result.text
        }
        
        return String(transcript.characters)
    }
    
    // MARK: - State Management
    
    /// Start transcription
    func startTranscription() async throws {
        guard !isTranscribing else { return }
        
        print("[NewSpeech] Starting transcription...")
        
        // Initialize if not already done
        if analyzer == nil {
            try await initialize()
        }
        
        isTranscribing = true
        
        // Reset transcripts
        volatileTranscript = ""
        finalizedTranscript = ""
        accumulatedTranscript = ""
    }
    
    /// Stop transcription and finalize
    func stopTranscription() async throws {
        guard isTranscribing else { return }
        
        print("[NewSpeech] Stopping transcription...")
        
        // Finish input stream
        inputBuilder.finish()
        
        // Finalize analyzer
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isTranscribing = false
        
        print("[NewSpeech] Transcription stopped and finalized")
    }
    
    /// Reset the transcriber
    func reset() {
        print("[NewSpeech] Resetting...")
        
        volatileTranscript = ""
        finalizedTranscript = ""
        accumulatedTranscript = ""
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        print("[NewSpeech] Reset complete")
    }
    
    // MARK: - Results
    
    /// Get the current transcript
    func getCurrentTranscript() -> String {
        // Combine finalized and volatile text
        let combined = finalizedTranscript + volatileTranscript
        return String(combined.characters)
    }
    
    /// Get finalized transcript only
    func getFinalizedTranscript() -> String {
        return String(finalizedTranscript.characters)
    }
    
    /// Flush any remaining audio and get final transcription
    func flushAndTranscribe() async -> String {
        print("[NewSpeech] Flushing audio buffer...")
        
        if isTranscribing {
            try? await stopTranscription()
        }
        
        return getFinalizedTranscript()
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        print("[NewSpeech] Cleaning up...")
        
        // Stop transcription if running
        if isTranscribing {
            try? await stopTranscription()
        }
        
        // Release reserved resources (using correct API)
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }
        
        print("[NewSpeech] Cleanup complete")
    }
    
    deinit {
        recognitionTask?.cancel()
        inputBuilder.finish()
    }
}

// MARK: - Errors

enum NewSpeechError: LocalizedError {
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