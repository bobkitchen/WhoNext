import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// FluidAudio Parakeet TDT v3 transcription engine
/// Processes audio chunks and returns clean text with per-word timing
/// Uses the same FluidAudio framework as diarization, consolidating ML dependencies
@MainActor
class ParakeetTranscriber: ObservableObject {

    // MARK: - Published State

    @Published var isReady = false
    @Published var isTranscribing = false
    @Published var modelDownloadProgress: Double = 0
    @Published var lastError: Error?

    // MARK: - Configuration

    /// Model version: v2 = English only, v3 = Multilingual (25 languages)
    #if canImport(FluidAudio)
    var modelVersion: AsrModelVersion = .v3
    #endif

    // MARK: - Private Properties

    #if canImport(FluidAudio)
    private var asrManager: AsrManager?
    private var models: AsrModels?
    #endif

    // Audio requirements
    private let sampleRate: Double = 16000.0
    private let minimumDurationSeconds: Double = 1.5  // Parakeet minimum requirement

    // Hallucination patterns (proven from WhisperKit experience)
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

    // Repetitive pattern detection
    private let repetitiveThreshold = 3

    // MARK: - Initialization

    init() {
        print("[ParakeetTranscriber] Initialized")
    }

    /// Initialize with model download
    func initialize() async throws {
        #if canImport(FluidAudio)
        print("[ParakeetTranscriber] Initializing with Parakeet TDT \(modelVersion == .v3 ? "v3 (Multilingual)" : "v2 (English)")...")

        do {
            // Download and load models (auto-downloads from HuggingFace if needed)
            print("[ParakeetTranscriber] Downloading/loading ASR models...")
            models = try await AsrModels.downloadAndLoad(version: modelVersion)
            print("[ParakeetTranscriber] ASR models loaded successfully")

            // Create and initialize ASR manager
            asrManager = AsrManager()
            try await asrManager?.initialize(models: models!)

            isReady = true
            print("[ParakeetTranscriber] Ready with Parakeet TDT \(modelVersion == .v3 ? "v3" : "v2")")

        } catch {
            lastError = error
            print("[ParakeetTranscriber] Failed to initialize: \(error)")
            throw ParakeetTranscriberError.modelLoadFailed(error.localizedDescription)
        }
        #else
        print("[ParakeetTranscriber] FluidAudio not available")
        throw ParakeetTranscriberError.serviceUnavailable
        #endif
    }

    // MARK: - Transcription

    /// Transcribe an audio chunk (internal implementation)
    /// - Parameter audioChunk: Float array of audio samples at 16kHz mono
    /// - Returns: Transcription result with per-word timing, or nil if no valid speech
    func transcribeInternal(audioChunk: [Float]) async throws -> ParakeetTranscriptionResult? {
        guard isReady else {
            throw ParakeetTranscriberError.notReady
        }

        #if canImport(FluidAudio)
        guard let asr = asrManager else {
            throw ParakeetTranscriberError.notReady
        }

        isTranscribing = true
        defer { isTranscribing = false }

        // Calculate audio stats
        let rms = calculateRMS(audioChunk)
        let duration = Double(audioChunk.count) / sampleRate
        print("[ParakeetTranscriber] Processing \(audioChunk.count) samples (\(String(format: "%.1f", duration))s), RMS: \(String(format: "%.4f", rms))")

        // Check for silence
        if rms < 0.001 {
            print("[ParakeetTranscriber] Audio appears silent, skipping")
            return nil
        }

        // Normalize audio to target RMS for consistent Parakeet input
        let normalizedAudio = normalizeAudio(audioChunk, targetRMS: 0.05)

        // Pad short audio with silence (Parakeet requires >= 1.5s)
        var processableAudio = normalizedAudio
        if duration < minimumDurationSeconds {
            let neededSamples = Int(minimumDurationSeconds * sampleRate) - audioChunk.count
            processableAudio.append(contentsOf: [Float](repeating: 0, count: neededSamples))
            print("[ParakeetTranscriber] Padded audio from \(String(format: "%.1f", duration))s to \(minimumDurationSeconds)s")
        }

        // Transcribe
        let result = try await asr.transcribe(processableAudio, source: .microphone)

        // Filter hallucinations
        let cleanedText = filterHallucinations(result.text)

        if cleanedText.isEmpty {
            print("[ParakeetTranscriber] No valid speech after filtering")
            return nil
        }

        // Log performance
        let rtfx = result.duration / result.processingTime
        print("[ParakeetTranscriber] Transcribed in \(String(format: "%.2f", result.processingTime))s (\(String(format: "%.1f", rtfx))x real-time): \"\(cleanedText.prefix(100))\"")

        return ParakeetTranscriptionResult(
            text: cleanedText,
            timestamp: Date(),
            confidence: result.confidence,
            processingTime: result.processingTime,
            tokenTimings: result.tokenTimings
        )
        #else
        throw ParakeetTranscriberError.serviceUnavailable
        #endif
    }

    /// Reset transcription state (call at start of new recording)
    func resetState() {
        #if canImport(FluidAudio)
        asrManager?.resetState()
        #endif
        print("[ParakeetTranscriber] State reset")
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

        // Check for repetitive patterns
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

        // Check for phrase repetition
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

    /// Normalize audio to a target RMS level for consistent Parakeet input.
    /// Caps gain at 100x to avoid amplifying pure noise. Uses tanh soft-clipping.
    private func normalizeAudio(_ samples: [Float], targetRMS: Float = 0.05) -> [Float] {
        let currentRMS = calculateRMS(samples)
        guard currentRMS > 0 else { return samples }

        let gain = min(targetRMS / currentRMS, 100.0)  // Cap at 100x
        if gain < 1.1 { return samples }  // Already at target level

        print("[ParakeetTranscriber] Normalizing audio: RMS \(String(format: "%.4f", currentRMS)) → \(String(format: "%.4f", targetRMS)) (gain: \(String(format: "%.1f", gain))x)")

        return samples.map { sample in
            let amplified = sample * gain
            return tanh(amplified)
        }
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

// MARK: - Result Type

/// Result from Parakeet transcription
/// Includes per-word timing for potential word-level speaker attribution
struct ParakeetTranscriptionResult: Sendable {
    let text: String
    let timestamp: Date
    let confidence: Float
    let processingTime: TimeInterval

    #if canImport(FluidAudio)
    let tokenTimings: [TokenTiming]?
    #else
    let tokenTimings: [(token: String, startTime: TimeInterval, endTime: TimeInterval)]?
    #endif
}

// MARK: - Error Types

enum ParakeetTranscriberError: Error, LocalizedError {
    case notReady
    case serviceUnavailable
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Parakeet transcriber not ready. Call initialize() first."
        case .serviceUnavailable:
            return "FluidAudio is not available on this device."
        case .modelLoadFailed(let reason):
            return "Failed to load Parakeet model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
