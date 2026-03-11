import Foundation
#if canImport(AxiiDiarization)
import AxiiDiarization
#endif

// MARK: - Unified Result Type

/// Unified transcription result that works with both WhisperKit and Parakeet engines
struct UnifiedTranscriptionResult: Sendable {
    let text: String
    let timestamp: Date
    let confidence: Float

    /// Per-word timing for potential word-level speaker attribution (Parakeet only)
    let tokenTimings: [UnifiedTokenTiming]?

    struct UnifiedTokenTiming: Sendable {
        let word: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Float
    }
}

// MARK: - Transcription Engine Protocol

/// Protocol for transcription engines (WhisperKit or Parakeet)
/// Allows seamless switching between engines via settings
@MainActor
protocol TranscriptionEngineProtocol: ObservableObject {
    /// Whether the engine is initialized and ready
    var isReady: Bool { get }

    /// Whether currently transcribing
    var isTranscribing: Bool { get }

    /// Last error encountered
    var lastError: Error? { get }

    /// Initialize the engine (downloads models if needed)
    func initialize() async throws

    /// Transcribe an audio chunk
    /// - Parameter audioChunk: Float array at 16kHz mono
    /// - Returns: Transcription result or nil if no valid speech
    func transcribe(audioChunk: [Float]) async throws -> UnifiedTranscriptionResult?

    /// Reset any internal state (call at start of new recording)
    func resetState()
}

// MARK: - Factory

/// Factory to create appropriate transcription engine based on settings
@MainActor
class TranscriptionManagerFactory {

    /// Create a transcription engine based on current settings
    static func createEngine(for settings: TranscriptionSettings) -> any TranscriptionEngineProtocol {
        switch settings.transcriptionEngine {
        case .whisperKit:
            return TranscriptionEngine()
        case .parakeet:
            return ParakeetTranscriber()
        }
    }

    /// Create a transcription engine of specific type
    static func createEngine(type: TranscriptionEngineType) -> any TranscriptionEngineProtocol {
        switch type {
        case .whisperKit:
            return TranscriptionEngine()
        case .parakeet:
            return ParakeetTranscriber()
        }
    }
}

// MARK: - WhisperKit Protocol Conformance

extension TranscriptionEngine: TranscriptionEngineProtocol {

    func initialize() async throws {
        try await initialize(model: selectedModel)
    }

    func transcribe(audioChunk: [Float]) async throws -> UnifiedTranscriptionResult? {
        guard let result = try await transcribeInternal(audioChunk: audioChunk) else {
            return nil
        }
        return UnifiedTranscriptionResult(
            text: result.text,
            timestamp: result.timestamp,
            confidence: result.confidence,
            tokenTimings: result.segmentTimings
        )
    }

    func resetState() {
        // WhisperKit is stateless between chunks - nothing to reset
    }
}

// MARK: - Parakeet Protocol Conformance

extension ParakeetTranscriber: TranscriptionEngineProtocol {

    func transcribe(audioChunk: [Float]) async throws -> UnifiedTranscriptionResult? {
        guard let result = try await transcribeInternal(audioChunk: audioChunk) else {
            return nil
        }

        // Convert Parakeet token timings to unified format
        var unifiedTimings: [UnifiedTranscriptionResult.UnifiedTokenTiming]? = nil

        #if canImport(AxiiDiarization)
        if let timings = result.tokenTimings {
            unifiedTimings = timings.map { timing in
                UnifiedTranscriptionResult.UnifiedTokenTiming(
                    word: timing.token,
                    startTime: timing.startTime,
                    endTime: timing.endTime,
                    confidence: timing.confidence
                )
            }
        }
        #endif

        // Merge BPE sub-word tokens into whole words before returning
        let mergedTimings = unifiedTimings.map { mergeBPETokens($0) }

        return UnifiedTranscriptionResult(
            text: result.text,
            timestamp: result.timestamp,
            confidence: result.confidence,
            tokenTimings: mergedTimings
        )
    }

    /// Merge BPE sub-word tokens into whole words using sentencepiece conventions.
    /// Tokens starting with `▁` (U+2581) mark new word boundaries; others are continuations.
    private func mergeBPETokens(_ timings: [UnifiedTranscriptionResult.UnifiedTokenTiming]) -> [UnifiedTranscriptionResult.UnifiedTokenTiming] {
        guard !timings.isEmpty else { return [] }

        var merged: [UnifiedTranscriptionResult.UnifiedTokenTiming] = []
        var currentWord = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0
        var confidenceSum: Float = 0
        var tokenCount: Float = 0

        for timing in timings {
            let token = timing.word
            if token.hasPrefix("\u{2581}") || currentWord.isEmpty {
                // Flush previous word
                if !currentWord.isEmpty {
                    merged.append(.init(word: currentWord, startTime: currentStart, endTime: currentEnd, confidence: confidenceSum / tokenCount))
                }
                // Start new word (strip ▁ prefix if present; first token may lack it)
                currentWord = token.hasPrefix("\u{2581}") ? String(token.dropFirst()) : token
                currentStart = timing.startTime
                currentEnd = timing.endTime
                confidenceSum = timing.confidence
                tokenCount = 1
            } else {
                // Continuation of current word
                currentWord += token
                currentEnd = timing.endTime
                confidenceSum += timing.confidence
                tokenCount += 1
            }
        }
        // Flush final word
        if !currentWord.isEmpty {
            merged.append(.init(word: currentWord, startTime: currentStart, endTime: currentEnd, confidence: confidenceSum / tokenCount))
        }
        return merged
    }
}
