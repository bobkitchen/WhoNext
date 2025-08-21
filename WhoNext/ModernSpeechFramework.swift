import Foundation
import AVFoundation
import Speech
import CoreMedia
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Modern speech transcription using macOS 26's new Speech framework APIs
/// Implements the correct AsyncStream pattern based on working apps (yap, swift-scribe)
/// Now includes speaker diarization via FluidAudio integration
@available(macOS 26.0, iOS 26.0, *)
@MainActor
class ModernSpeechFramework {
    
    // MARK: - Properties
    
    private var speechTranscriber: SpeechTranscriber?
    private var speechAnalyzer: SpeechAnalyzer?
    private let locale: Locale
    private var isTranscribing = false
    
    // AsyncStream for audio input (the correct pattern)
    private var inputStream: AsyncStream<AnalyzerInput>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    
    // Buffer converter for format conversion
    private var audioConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    
    // Accumulated transcript
    private var accumulatedTranscript: String = ""
    
    // Recognition task
    private var recognitionTask: Task<Void, Error>?
    
    // Speaker diarization support
    #if canImport(FluidAudio)
    private var diarizationManager: DiarizationManager?
    #endif
    private var diarizationEnabled: Bool = false
    private var speakerSegments: [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] = []
    private var recordingStartTime: Date?
    
    // MARK: - Initialization
    
    init(locale: Locale = .current, enableDiarization: Bool = false) {
        self.locale = locale
        self.diarizationEnabled = enableDiarization
        print("🎙️ Initializing Modern Speech Framework for locale: \(locale.identifier)")
        print("👥 Speaker diarization: \(enableDiarization ? "Enabled" : "Disabled")")
        
        #if canImport(FluidAudio)
        if enableDiarization {
            // Initialize diarization manager on MainActor
            diarizationManager = DiarizationManager(
                isEnabled: true,
                enableRealTimeProcessing: true
            )
        }
        #endif
    }
    
    // MARK: - Setup
    
    /// Initialize the speech transcriber and analyzer using the correct pattern
    func initialize() async throws {
        print("🔄 Starting speech framework initialization...")
        
        // Initialize diarization if enabled
        #if canImport(FluidAudio)
        if diarizationEnabled, let diarizer = diarizationManager {
            do {
                try await diarizer.initialize()
                print("✅ Speaker diarization initialized")
            } catch {
                print("⚠️ Diarization initialization failed: \(error)")
                print("⚠️ Continuing with transcription only")
                diarizationEnabled = false
            }
        }
        #endif
        
        // Check if locale is supported
        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard supportedLocales.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) else {
            print("❌ Locale not supported: \(locale.identifier)")
            print("📝 Supported locales: \(supportedLocales.map { $0.identifier })")
            throw ModernSpeechError.languageNotSupported
        }
        
        // Deallocate any previously allocated locales (clean slate)
        for allocatedLocale in await AssetInventory.allocatedLocales {
            await AssetInventory.deallocate(locale: allocatedLocale)
        }
        
        // Allocate assets for the locale
        print("📦 Allocating assets for locale: \(locale.identifier)")
        try await AssetInventory.allocate(locale: locale)
        
        // Create transcriber with appropriate options
        speechTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults], // Get both volatile and final results
            attributeOptions: []
        )
        
        guard let transcriber = speechTranscriber else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        // Check if assets need to be downloaded
        let installedLocales = Set(await SpeechTranscriber.installedLocales)
        if !installedLocales.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                print("📥 Downloading speech assets for \(locale.identifier)...")
                try await request.downloadAndInstall()
                print("✅ Speech assets downloaded")
            }
        }
        
        // Create the analyzer with the transcriber module
        speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
        
        // Get the best available audio format for the analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        guard analyzerFormat != nil else {
            throw ModernSpeechError.transcriptionFailed("No compatible audio format found")
        }
        
        print("🎵 Analyzer format: \(String(describing: analyzerFormat))")
        
        // Create the AsyncStream for audio input
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputStream = stream
        inputContinuation = continuation
        
        // Start the recognition task to listen for results
        recognitionTask = Task {
            print("👂 Starting to listen for transcription results...")
            var resultCount = 0
            
            for try await result in transcriber.results {
                resultCount += 1
                let text = String(result.text.characters)
                
                if result.isFinal {
                    // Final result - add to accumulated transcript
                    if !text.isEmpty {
                        if !accumulatedTranscript.isEmpty {
                            accumulatedTranscript += " "
                        }
                        accumulatedTranscript += text
                        print("✅ Final result #\(resultCount): \(text.prefix(50))...")
                        print("📊 Total transcript: \(accumulatedTranscript.split(separator: " ").count) words")
                    }
                } else {
                    // Volatile result - could use for live display
                    print("🔄 Volatile result #\(resultCount): \(text.prefix(50))...")
                }
            }
            
            print("🏁 Recognition task completed after \(resultCount) results")
        }
        
        // Start the analyzer with the input stream
        if let analyzer = speechAnalyzer, let stream = inputStream {
            try await analyzer.start(inputSequence: stream)
            print("✅ Speech analyzer started with input stream")
        }
        
        print("✅ Modern Speech Framework initialized successfully")
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer by streaming it to the analyzer
    func processAudioStream(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Record start time if not set
        if recordingStartTime == nil {
            recordingStartTime = Date()
        }
        
        // Process audio for diarization if enabled
        #if canImport(FluidAudio)
        if diarizationEnabled, let diarizer = diarizationManager {
            await diarizer.processAudioBuffer(buffer)
        }
        #endif
        
        guard let continuation = inputContinuation,
              let analyzerFormat = analyzerFormat else {
            return accumulatedTranscript
        }
        
        // Convert buffer to analyzer format if needed
        let convertedBuffer: AVAudioPCMBuffer
        if buffer.format != analyzerFormat {
            convertedBuffer = try convertBuffer(buffer, to: analyzerFormat)
        } else {
            convertedBuffer = buffer
        }
        
        // Create AnalyzerInput and yield to stream
        let input = AnalyzerInput(buffer: convertedBuffer)
        continuation.yield(input)
        
        // Return current accumulated transcript
        return accumulatedTranscript
    }
    
    /// Convert audio buffer to target format using proper calculation
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        
        // Create converter if needed or format changed
        if audioConverter == nil || audioConverter?.outputFormat != targetFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            audioConverter?.primeMethod = .none // Avoid timestamp drift
        }
        
        guard let converter = audioConverter else {
            throw ModernSpeechError.transcriptionFailed("Failed to create audio converter")
        }
        
        // Calculate output frame capacity using the correct formula from swift-scribe
        let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCapacity
        ) else {
            throw ModernSpeechError.transcriptionFailed("Failed to create output buffer")
        }
        
        // Perform conversion
        var error: NSError?
        var bufferProcessed = false
        
        let status = converter.convert(to: outputBuffer, error: &error) { _, statusPointer in
            if bufferProcessed {
                statusPointer.pointee = .noDataNow
                return nil
            } else {
                statusPointer.pointee = .haveData
                bufferProcessed = true
                return buffer
            }
        }
        
        guard status != .error else {
            throw ModernSpeechError.transcriptionFailed("Conversion failed: \(error?.localizedDescription ?? "unknown")")
        }
        
        return outputBuffer
    }
    
    // MARK: - Transcription Control
    
    /// Force transcription of any remaining audio and get final transcript
    func flushAndTranscribe() async -> String {
        print("🔄 Flushing transcription...")
        
        // Finish the input stream
        inputContinuation?.finish()
        
        // Finalize the analyzer
        if let analyzer = speechAnalyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        
        // Wait a moment for final results
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Get final diarization results if enabled
        #if canImport(FluidAudio)
        if diarizationEnabled, let diarizer = diarizationManager {
            if let diarizationResult = await diarizer.finishProcessing() {
                print("👥 Diarization complete: \(diarizationResult.speakerCount) speakers identified")
                await alignTranscriptWithSpeakers(diarizationResult)
            }
        }
        #endif
        
        let finalTranscript = accumulatedTranscript
        
        if !finalTranscript.isEmpty {
            print("✅ Final transcript: \(finalTranscript.split(separator: " ").count) words")
            if !speakerSegments.isEmpty {
                print("👥 Speaker segments: \(speakerSegments.count)")
            }
        } else {
            print("⚠️ No transcript available")
        }
        
        return finalTranscript
    }
    
    /// Stop streaming transcription
    func stopStreamingTranscription() {
        isTranscribing = false
        inputContinuation?.finish()
        recognitionTask?.cancel()
        recognitionTask = nil
        print("🛑 Stopped streaming transcription")
    }
    
    /// Reset the transcriber for a new session
    func reset() {
        accumulatedTranscript = ""
        isTranscribing = false
        speakerSegments.removeAll()
        recordingStartTime = nil
        
        // Cancel existing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Finish the old input stream
        inputContinuation?.finish()
        
        // The analyzer cannot be restarted once finalized
        // We need to create a completely new analyzer and transcriber
        Task {
            do {
                // Create new transcriber (reuse existing locale and options)
                let transcriber = SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults],
                    attributeOptions: []
                )
                speechTranscriber = transcriber
                
                // Create new analyzer with the transcriber
                speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
                
                // Create new AsyncStream for audio input
                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                inputStream = stream
                inputContinuation = continuation
                
                // Start the new analyzer with the new stream
                if let analyzer = speechAnalyzer, let stream = inputStream {
                    try await analyzer.start(inputSequence: stream)
                    print("✅ Created new Speech analyzer and started with input stream")
                }
                
                // Start new recognition task to listen for results
                recognitionTask = Task {
                    print("👂 Started listening for transcription results...")
                    var resultCount = 0
                    
                    for try await result in transcriber.results {
                        resultCount += 1
                        let text = String(result.text.characters)
                        
                        if result.isFinal {
                            // Final result - add to accumulated transcript
                            if !text.isEmpty {
                                if !accumulatedTranscript.isEmpty {
                                    accumulatedTranscript += " "
                                }
                                accumulatedTranscript += text
                                print("✅ Final result #\(resultCount): \(text.prefix(50))...")
                                print("📊 Total transcript: \(accumulatedTranscript.split(separator: " ").count) words")
                            }
                        } else {
                            // Volatile result - could use for live display
                            print("🔄 Volatile result #\(resultCount): \(text.prefix(50))...")
                        }
                    }
                    
                    print("🏁 Recognition task completed after \(resultCount) results")
                }
                
                print("✅ Speech framework fully reset and ready for new recording")
                
            } catch {
                print("❌ Failed to reset speech framework: \(error)")
            }
        }
        
        #if canImport(FluidAudio)
        diarizationManager?.reset()
        #endif
        print("🔄 Reset transcriber and diarization")
    }
    
    // MARK: - Helper Methods for Compatibility
    
    /// Transcribe an audio file (for compatibility)
    func transcribeAudioFile(_ url: URL) async throws -> String {
        guard let transcriber = speechTranscriber else {
            throw ModernSpeechError.transcriberNotInitialized
        }
        
        // Create a separate analyzer for file transcription
        let fileAnalyzer = SpeechAnalyzer(modules: [transcriber])
        
        // Open audio file
        let audioFile = try AVAudioFile(forReading: url)
        
        // Start analysis
        try await fileAnalyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        
        // Collect transcription results
        var fullTranscript = ""
        for try await result in transcriber.results {
            fullTranscript += String(result.text.characters)
        }
        
        print("✅ File transcription complete: \(fullTranscript.prefix(100))...")
        return fullTranscript
    }
    
    /// Get current transcript without processing
    func getCurrentTranscript() -> String {
        return accumulatedTranscript
    }
    
    /// Get speaker-attributed segments
    func getSpeakerSegments() -> [(text: String, speaker: String?, startTime: TimeInterval, endTime: TimeInterval)] {
        return speakerSegments
    }
    
    // MARK: - Speaker Alignment
    
    /// Align transcript with speaker diarization results
    #if canImport(FluidAudio)
    private func alignTranscriptWithSpeakers(_ diarizationResult: DiarizationResult) async {
        guard let startTime = recordingStartTime else { return }
        
        // Simple alignment: distribute text across speaker segments
        // In production, you'd want more sophisticated alignment using timestamps
        let words = accumulatedTranscript.split(separator: " ")
        guard !words.isEmpty else { return }
        
        let recordingDuration = Date().timeIntervalSince(startTime)
        let wordsPerSecond = Double(words.count) / recordingDuration
        
        speakerSegments.removeAll()
        
        for segment in diarizationResult.segments {
            let segmentDuration = Double(segment.endTimeSeconds - segment.startTimeSeconds)
            let wordCount = Int(segmentDuration * wordsPerSecond)
            
            // Calculate word indices for this segment
            let startWordIndex = Int(Double(segment.startTimeSeconds) * wordsPerSecond)
            let endWordIndex = min(startWordIndex + wordCount, words.count)
            
            if startWordIndex < words.count && startWordIndex < endWordIndex {
                let segmentWords = words[startWordIndex..<endWordIndex]
                let segmentText = segmentWords.joined(separator: " ")
                
                speakerSegments.append((
                    text: segmentText,
                    speaker: "Speaker \(segment.speakerId)",
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds)
                ))
            }
        }
        
        print("📊 Aligned \(speakerSegments.count) speaker segments with transcript")
    }
    #endif
    
    // MARK: - Language Support
    
    /// Check if a specific language is supported
    static func isLanguageSupported(_ locale: Locale) async -> Bool {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        return supportedLocales.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47))
    }
    
    /// Get all supported languages
    static var supportedLanguages: [Locale] {
        get async {
            await SpeechTranscriber.supportedLocales
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Cancel recognition task
        recognitionTask?.cancel()
        
        // Finish input stream
        inputContinuation?.finish()
        
        // Deallocate assets
        Task {
            for locale in await AssetInventory.allocatedLocales {
                await AssetInventory.deallocate(locale: locale)
            }
        }
        
        print("🧹 Modern Speech Framework cleaned up")
    }
}

// MARK: - Errors

enum ModernSpeechError: LocalizedError {
    case languageNotSupported
    case transcriberNotInitialized
    case transcriptionFailed(String)
    case assetDownloadFailed
    
    var errorDescription: String? {
        switch self {
        case .languageNotSupported:
            return "Language not supported for transcription"
        case .transcriberNotInitialized:
            return "Speech transcriber not initialized"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .assetDownloadFailed:
            return "Failed to download speech assets"
        }
    }
}