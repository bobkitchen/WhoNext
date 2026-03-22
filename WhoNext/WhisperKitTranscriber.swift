import Foundation
import AVFoundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Manages speech-to-text transcription using WhisperKit
/// Provides real-time streaming transcription with word-level timestamps
@MainActor
class WhisperKitTranscriber: ObservableObject {

    // MARK: - Published Properties

    @Published var isReady = false
    @Published var isTranscribing = false
    @Published var currentTranscript = ""
    @Published var lastError: Error?
    @Published var modelDownloadProgress: Double = 0.0
    @Published var isDownloadingModel = false

    // MARK: - Configuration

    /// Available Whisper models with size/speed tradeoffs
    enum WhisperModel: String, CaseIterable {
        case tiny = "tiny.en"       // ~30MB, fastest, lower accuracy
        case base = "base.en"       // ~70MB, good balance (default)
        case small = "small.en"     // ~200MB, better accuracy
        case large = "large-v3"     // ~1.5GB, best accuracy, slowest

        var displayName: String {
            switch self {
            case .tiny: return "Tiny (Fast)"
            case .base: return "Base (Balanced)"
            case .small: return "Small (Accurate)"
            case .large: return "Large (Best)"
            }
        }

        var estimatedSize: String {
            switch self {
            case .tiny: return "~30 MB"
            case .base: return "~70 MB"
            case .small: return "~200 MB"
            case .large: return "~1.5 GB"
            }
        }
    }

    var selectedModel: WhisperModel = .base

    // MARK: - Private Properties

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif
    private var modelLoaded = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    // Buffering for streaming transcription
    private let minBufferDuration: TimeInterval = 1.0   // Minimum audio before transcription
    private let maxBufferDuration: TimeInterval = 30.0  // Maximum buffer size

    // Track transcription timing for speaker attribution
    private var transcriptionStartTime: Date?
    private var lastTranscriptionTime: TimeInterval = 0

    // MARK: - Initialization

    init(model: WhisperModel = .base) {
        self.selectedModel = model
        debugLog("📱 [WhisperKitTranscriber] Initialized with model: \(model.rawValue)")
    }

    // MARK: - Model Management

    /// Initialize WhisperKit and download model if needed
    func initialize() async throws {
        debugLog("🔄 [WhisperKitTranscriber] Initializing with model: \(selectedModel.rawValue)")

        #if canImport(WhisperKit)
        do {
            isDownloadingModel = true

            // Create WhisperKit instance - this will download model if needed
            whisperKit = try await WhisperKit(
                model: selectedModel.rawValue,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true,
                download: true
            )

            modelLoaded = true
            isReady = true
            isDownloadingModel = false
            debugLog("✅ [WhisperKitTranscriber] WhisperKit ready with model: \(selectedModel.rawValue)")

        } catch {
            isDownloadingModel = false
            lastError = error
            print("❌ [WhisperKitTranscriber] Failed to initialize: \(error)")
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
        #else
        debugLog("⚠️ [WhisperKitTranscriber] WhisperKit not available")
        throw TranscriptionError.serviceUnavailable
        #endif
    }

    /// Check if a model is downloaded
    func isModelDownloaded() -> Bool {
        #if canImport(WhisperKit)
        // Check if model files exist in the cache directory
        let modelPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml")
        return FileManager.default.fileExists(atPath: modelPath.path)
        #else
        return false
        #endif
    }

    // MARK: - Transcription

    /// Start a new transcription session
    func startTranscribing() {
        guard isReady else {
            debugLog("⚠️ [WhisperKitTranscriber] Not ready - call initialize() first")
            return
        }

        isTranscribing = true
        currentTranscript = ""
        audioBuffer = []
        transcriptionStartTime = Date()
        lastTranscriptionTime = 0
        debugLog("🎙️ [WhisperKitTranscriber] Started transcription session")
    }

    /// Process audio buffer and return transcription
    /// - Parameter buffer: Audio buffer from recording
    /// - Returns: Transcribed text with timing information
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        guard isTranscribing, isReady else {
            debugLog("⚠️ [WhisperKitTranscriber] processAudioBuffer called but not ready - isTranscribing: \(isTranscribing), isReady: \(isReady)")
            throw TranscriptionError.notReady
        }

        #if canImport(WhisperKit)
        guard let whisperKit else {
            debugLog("⚠️ [WhisperKitTranscriber] processAudioBuffer - whisperKit is nil")
            throw TranscriptionError.notReady
        }

        // Convert buffer to Float array at 16kHz
        let samples = convertBufferToFloatArray(buffer)
        audioBuffer.append(contentsOf: samples)

        // Calculate buffer duration
        let bufferDuration = Double(audioBuffer.count) / Double(sampleRate)

        // Only transcribe if we have enough audio (log periodically)
        guard bufferDuration >= minBufferDuration else {
            // Log buffer accumulation every ~5 seconds
            if Int(bufferDuration * 10) % 50 == 0 && bufferDuration > 0.1 {
                debugLog("📊 [WhisperKitTranscriber] Buffering audio: \(String(format: "%.1f", bufferDuration))s / \(minBufferDuration)s needed")
            }
            return TranscriptionResult(text: "", segments: [], timestamp: lastTranscriptionTime)
        }

        // Limit buffer size to prevent memory issues
        if bufferDuration > maxBufferDuration {
            let samplesToKeep = Int(maxBufferDuration * Double(sampleRate))
            audioBuffer = Array(audioBuffer.suffix(samplesToKeep))
        }

        // Calculate audio statistics for logging
        let sumOfSquares = audioBuffer.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(audioBuffer.count))
        let maxSample = audioBuffer.max() ?? 0
        let minSample = audioBuffer.min() ?? 0

        debugLog("🎙️ [WhisperKitTranscriber] Transcribing \(String(format: "%.1f", bufferDuration))s of audio (\(audioBuffer.count) samples)")
        debugLog("📊 [WhisperKitTranscriber] Buffer stats - RMS: \(String(format: "%.6f", rms)), Range: [\(String(format: "%.4f", minSample)), \(String(format: "%.4f", maxSample))]")

        // NOTE: Removed audio normalization - it was causing clipping and distortion
        // which made Whisper hallucinate. The audio pipeline should deliver proper levels.

        // Check if audio might have issues
        if rms < 0.001 {
            debugLog("⚠️ [WhisperKitTranscriber] Audio appears to be silence (RMS < 0.001)")
        } else if minSample <= -0.99 || maxSample >= 0.99 {
            debugLog("⚠️ [WhisperKitTranscriber] Audio may be clipping (peaks at limits)")
        }

        // Transcribe the audio with explicit options
        let startTime = lastTranscriptionTime
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            temperature: 0.0,  // Greedy decoding for consistency
            skipSpecialTokens: true,
            noSpeechThreshold: 0.6
        )
        let results = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)

        // Extract text and segments
        var fullText = ""
        var segments: [WhisperSegment] = []

        for result in results {
            fullText += result.text

            // Convert WhisperKit segments to our format
            for segment in result.segments {
                let transcriptSegment = WhisperSegment(
                    text: segment.text,
                    startTime: startTime + Double(segment.start),
                    endTime: startTime + Double(segment.end),
                    confidence: 1.0 // WhisperKit doesn't provide per-segment confidence
                )
                segments.append(transcriptSegment)
            }
        }

        // Update tracking
        lastTranscriptionTime = startTime + bufferDuration
        currentTranscript += fullText

        // Log result
        if !fullText.isEmpty {
            debugLog("✅ [WhisperKitTranscriber] Transcribed: \"\(fullText.prefix(100))...\"")
        } else {
            debugLog("📝 [WhisperKitTranscriber] No speech detected in this segment")
        }

        // Clear processed audio (keep small overlap for continuity)
        let overlapSamples = Int(0.5 * Double(sampleRate))
        if audioBuffer.count > overlapSamples {
            audioBuffer = Array(audioBuffer.suffix(overlapSamples))
        }

        return TranscriptionResult(text: fullText, segments: segments, timestamp: startTime)

        #else
        throw TranscriptionError.serviceUnavailable
        #endif
    }

    /// Stop transcription session
    func stopTranscribing() {
        isTranscribing = false
        audioBuffer = []
        debugLog("🛑 [WhisperKitTranscriber] Stopped transcription session")
    }

    /// Transcribe a complete audio file
    /// - Parameter url: Path to audio file
    /// - Returns: Full transcription result
    func transcribeFile(_ url: URL) async throws -> TranscriptionResult {
        guard isReady else {
            throw TranscriptionError.notReady
        }

        #if canImport(WhisperKit)
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        debugLog("📄 [WhisperKitTranscriber] Transcribing file: \(url.lastPathComponent)")

        let results = try await whisperKit.transcribe(audioPath: url.path)

        var fullText = ""
        var segments: [WhisperSegment] = []

        for result in results {
            fullText += result.text

            for segment in result.segments {
                let transcriptSegment = WhisperSegment(
                    text: segment.text,
                    startTime: Double(segment.start),
                    endTime: Double(segment.end),
                    confidence: 1.0
                )
                segments.append(transcriptSegment)
            }
        }

        return TranscriptionResult(text: fullText, segments: segments, timestamp: 0)

        #else
        throw TranscriptionError.serviceUnavailable
        #endif
    }

    // MARK: - Audio Conversion

    private var audioBufferDiagnosticCounter: Int = 0
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Convert AVAudioPCMBuffer to Float array at 16kHz mono using WhisperKit's AudioProcessor
    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        #if canImport(WhisperKit)
        let inputSampleRate = buffer.format.sampleRate
        let channelCount = buffer.format.channelCount
        let frameLength = buffer.frameLength

        // Log audio format occasionally (every ~100 calls)
        if audioBufferDiagnosticCounter % 100 == 0 {
            debugLog("📊 [WhisperKitTranscriber] Input audio format: \(inputSampleRate)Hz, \(channelCount) channel(s), \(frameLength) frames")
        }
        audioBufferDiagnosticCounter += 1

        // Resample to 16kHz mono if needed (WhisperKit requires 16kHz)
        var bufferToConvert = buffer
        let targetSampleRate: Double = 16000.0

        if inputSampleRate != targetSampleRate || channelCount != 1 {
            // Use WhisperKit's resampleAudio to convert to 16kHz mono
            if let resampledBuffer = AudioProcessor.resampleAudio(
                fromBuffer: buffer,
                toSampleRate: targetSampleRate,
                channelCount: 1
            ) {
                bufferToConvert = resampledBuffer
                if audioBufferDiagnosticCounter % 100 == 1 {
                    debugLog("📊 [WhisperKitTranscriber] Resampled from \(inputSampleRate)Hz \(channelCount)ch to \(targetSampleRate)Hz mono: \(frameLength) → \(resampledBuffer.frameLength) frames")
                }
            } else {
                print("⚠️ [WhisperKitTranscriber] Failed to resample audio buffer")
            }
        }

        // Use WhisperKit's built-in converter to extract float array
        let samples = AudioProcessor.convertBufferToArray(buffer: bufferToConvert)

        // Calculate RMS level for diagnostics
        if audioBufferDiagnosticCounter % 100 == 1 && !samples.isEmpty {
            let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumOfSquares / Float(samples.count))
            let maxSample = samples.max() ?? 0
            let minSample = samples.min() ?? 0
            debugLog("📊 [WhisperKitTranscriber] After conversion: \(samples.count) samples at 16kHz, RMS: \(String(format: "%.6f", rms)), Range: [\(String(format: "%.4f", minSample)), \(String(format: "%.4f", maxSample))]")
        }

        return samples
        #else
        return []
        #endif
    }
}

// MARK: - Supporting Types

struct TranscriptionResult: Sendable {
    let text: String
    let segments: [WhisperSegment]
    let timestamp: TimeInterval

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Segment from WhisperKit transcription with word-level timing
/// Note: Different from the app's WhisperSegment (in LiveMeeting.swift) which uses single timestamp
struct WhisperSegment: Sendable, Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    var speakerID: String?

    var duration: TimeInterval {
        endTime - startTime
    }

    var formattedTimeRange: String {
        let startMinutes = Int(startTime) / 60
        let startSeconds = Int(startTime) % 60
        let endMinutes = Int(endTime) / 60
        let endSeconds = Int(endTime) % 60
        return String(format: "%02d:%02d - %02d:%02d", startMinutes, startSeconds, endMinutes, endSeconds)
    }
}

enum TranscriptionError: Error, LocalizedError {
    case notReady
    case serviceUnavailable
    case modelLoadFailed(String)
    case audioConversionFailed
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Transcriber not ready. Call initialize() first."
        case .serviceUnavailable:
            return "WhisperKit is not available on this device."
        case .modelLoadFailed(let reason):
            return "Failed to load Whisper model: \(reason)"
        case .audioConversionFailed:
            return "Failed to convert audio format."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
