import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Clean WhisperKit transcription with hallucination filtering
/// Processes 15-second audio chunks and returns clean text
@MainActor
class TranscriptionEngine: ObservableObject {

    // MARK: - Published State

    @Published var isReady = false
    @Published var isTranscribing = false
    @Published var modelDownloadProgress: Double = 0
    @Published var lastError: Error?

    // MARK: - Configuration

    var selectedModel: String = "base.en"

    // MARK: - Private Properties

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif

    // Known hallucination patterns to filter
    private let hallucinationPatterns = [
        "Isn't it?",
        "isn't it?",
        "(humming)",
        "(mimics",
        "(laughing)",
        "(laughs)",
        "(sighs)",
        "(coughs)",
        "(clears throat)",
        "[MUSIC]",
        "[BLANK_AUDIO]",
        "[silence]",
        "[Silence]",
        "Thank you for watching",
        "Thanks for watching",
        "Please subscribe",
        "Subscribe",
        "Like and subscribe",
        "Don't forget to subscribe",
        "Hit the bell",
        "Leave a comment",
        "See you next time",
        "Goodbye",
        "Bye bye",
        "The end",
        "Shhh",
        "..."
    ]

    // Repetitive pattern indicators
    private let repetitiveThreshold = 3  // Same phrase repeated 3+ times = garbage

    // MARK: - Initialization

    func initialize(model: String? = nil) async throws {
        if let model {
            selectedModel = model
        }

        print("[TranscriptionEngine] Initializing with model: \(selectedModel)")

        #if canImport(WhisperKit)
        do {
            whisperKit = try await WhisperKit(
                model: selectedModel,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )

            isReady = true
            print("[TranscriptionEngine] Ready with model: \(selectedModel)")

        } catch {
            lastError = error
            print("[TranscriptionEngine] Failed to initialize: \(error)")
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
        #else
        print("[TranscriptionEngine] WhisperKit not available")
        throw TranscriptionEngineError.serviceUnavailable
        #endif
    }

    // MARK: - Transcription

    /// Transcribe an audio chunk
    /// - Parameter audioChunk: Float array of audio samples at 16kHz
    /// - Returns: Transcription result, or nil if no valid speech
    func transcribe(audioChunk: [Float]) async throws -> EngineTranscriptionResult? {
        guard isReady else {
            throw TranscriptionEngineError.notReady
        }

        #if canImport(WhisperKit)
        guard let whisperKit else {
            throw TranscriptionEngineError.notReady
        }

        isTranscribing = true
        defer { isTranscribing = false }

        // Log audio stats
        let rms = calculateRMS(audioChunk)
        let peak = audioChunk.max { abs($0) < abs($1) }.map { abs($0) } ?? 0
        print("[TranscriptionEngine] Processing \(audioChunk.count) samples, RMS: \(String(format: "%.4f", rms)), Peak: \(String(format: "%.4f", peak))")

        // Check for silence
        if rms < 0.005 {
            print("[TranscriptionEngine] Audio appears silent, skipping")
            return nil
        }

        // Configure decoding options
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            temperature: 0.0,  // Greedy decoding for consistency
            temperatureFallbackCount: 0,
            sampleLength: 224,  // Max tokens per segment
            topK: 5,
            usePrefillPrompt: false,
            usePrefillCache: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            suppressBlank: true,
            supressTokens: nil,
            compressionRatioThreshold: 2.4,  // Filter repetitive garbage
            logProbThreshold: -1.0,          // Filter low-confidence
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: 0.3           // Lower = more permissive speech detection (0.6 was too strict)
        )

        // Transcribe
        let results = try await whisperKit.transcribe(audioArray: audioChunk, decodeOptions: options)

        // Extract and filter text
        var rawText = ""
        for result in results {
            rawText += result.text
        }

        // Apply hallucination filter
        let cleanedText = filterHallucinations(rawText)

        if cleanedText.isEmpty {
            print("[TranscriptionEngine] No valid speech after filtering")
            return nil
        }

        print("[TranscriptionEngine] Transcribed: \"\(cleanedText.prefix(100))\"")

        return EngineTranscriptionResult(
            text: cleanedText,
            timestamp: Date(),
            confidence: 1.0
        )

        #else
        throw TranscriptionEngineError.serviceUnavailable
        #endif
    }

    // MARK: - Hallucination Filtering

    private func filterHallucinations(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove empty or very short text
        if cleaned.count < 2 {
            return ""
        }

        // Check for exact hallucination patterns
        for pattern in hallucinationPatterns {
            // If entire text is just a hallucination pattern
            if cleaned.lowercased() == pattern.lowercased() {
                return ""
            }

            // If text is mostly just the pattern
            if cleaned.count < pattern.count + 10 &&
               cleaned.lowercased().contains(pattern.lowercased()) {
                return ""
            }

            // Remove pattern from longer text
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .caseInsensitive
            )
        }

        // Check for repetitive patterns (e.g., "word word word word")
        if isRepetitive(cleaned) {
            return ""
        }

        // Check for all-punctuation garbage
        let alphanumeric = cleaned.filter { $0.isLetter || $0.isNumber }
        if alphanumeric.count < 3 {
            return ""
        }

        // Clean up extra whitespace
        cleaned = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func isRepetitive(_ text: String) -> Bool {
        let words = text.lowercased().split(separator: " ").map { String($0) }

        guard words.count >= 4 else { return false }

        // Check if same word repeated too many times
        var wordCounts: [String: Int] = [:]
        for word in words {
            wordCounts[word, default: 0] += 1
        }

        for (word, count) in wordCounts {
            // Skip common words
            let commonWords = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "is", "it"]
            if commonWords.contains(word) { continue }

            // If any word appears too many times relative to text length
            if count >= repetitiveThreshold && Double(count) / Double(words.count) > 0.4 {
                return true
            }
        }

        // Check for phrase repetition (e.g., "hello hello hello")
        if words.count >= 3 {
            var consecutiveRepeats = 1
            for i in 1..<words.count {
                if words[i] == words[i - 1] {
                    consecutiveRepeats += 1
                    if consecutiveRepeats >= repetitiveThreshold {
                        return true
                    }
                } else {
                    consecutiveRepeats = 1
                }
            }
        }

        return false
    }

    // MARK: - Helpers

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

// MARK: - Supporting Types

/// Internal result type - converted to TranscriptSegment by SimpleRecordingEngine
struct EngineTranscriptionResult: Sendable {
    let text: String
    let timestamp: Date
    let confidence: Float
}

enum TranscriptionEngineError: Error, LocalizedError {
    case notReady
    case serviceUnavailable
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Transcription engine not ready. Call initialize() first."
        case .serviceUnavailable:
            return "WhisperKit is not available on this device."
        case .modelLoadFailed(let reason):
            return "Failed to load Whisper model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
