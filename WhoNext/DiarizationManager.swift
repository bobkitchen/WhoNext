import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Manages speaker diarization using FluidAudio framework
/// Identifies "who spoke when" in audio recordings
#if canImport(FluidAudio)
@MainActor
class DiarizationManager: ObservableObject {
    
    // MARK: - Properties
    
    private var fluidDiarizer: DiarizerManager?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0
    
    // Configuration
    private let config: DiarizerConfig
    @Published var isEnabled: Bool = true
    @Published var enableRealTimeProcessing: Bool = false
    
    // State
    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var processingProgress: Double = 0.0
    
    // Results
    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    
    // Chunk management for streaming
    private let chunkDuration: TimeInterval = 10.0 // 10 seconds for optimal accuracy
    private var streamPosition: TimeInterval = 0.0
    
    // MARK: - Initialization
    
    init(isEnabled: Bool = true, enableRealTimeProcessing: Bool = false) {
        // Configure for better speaker separation
        self.config = DiarizerConfig(
            clusteringThreshold: 0.5,  // Lower threshold for better speaker separation
            minSpeechDuration: 1.0,     // Ignore very short utterances
            minSilenceGap: 0.5          // Natural conversation gaps
        )
        self.isEnabled = isEnabled
        self.enableRealTimeProcessing = enableRealTimeProcessing
        
        print("🎙️ DiarizationManager initialized with real-time: \(enableRealTimeProcessing)")
    }
    
    // MARK: - Setup
    
    /// Initialize the diarizer and download models if needed
    func initialize() async throws {
        print("🔄 [DiarizationManager] Initializing FluidAudio diarizer...")
        
        guard isEnabled else {
            print("⚠️ [DiarizationManager] Diarization is disabled")
            return
        }
        
        do {
            // Download models if needed (one-time setup)
            let models = try await DiarizerModels.downloadIfNeeded()
            print("✅ [DiarizationManager] Models downloaded/verified")
            
            // Create FluidAudio diarizer with our config
            fluidDiarizer = DiarizerManager(config: config)
            fluidDiarizer?.initialize(models: models)
            
            isInitialized = true
            print("✅ [DiarizationManager] FluidAudio diarizer initialized successfully")
        } catch {
            print("❌ [DiarizationManager] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer for diarization
    /// - Parameter buffer: Audio buffer from recording (will be converted to 16kHz mono)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isEnabled, isInitialized else { return }
        
        // Convert audio buffer to Float array at 16kHz
        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            print("⚠️ [DiarizationManager] Failed to convert audio buffer")
            return
        }
        
        // Accumulate audio for batch processing
        audioBuffer.append(contentsOf: floatSamples)
        
        // Check if we have enough audio for a chunk (10 seconds)
        let chunkSamples = Int(sampleRate * Float(chunkDuration))
        
        // Process complete chunks
        while audioBuffer.count >= chunkSamples {
            let chunk = Array(audioBuffer.prefix(chunkSamples))
            audioBuffer.removeFirst(chunkSamples)
            
            // Process in real-time if enabled
            if enableRealTimeProcessing {
                await processChunk(chunk, at: streamPosition)
                streamPosition += chunkDuration
            }
        }
    }
    
    /// Process a single chunk of audio
    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let diarizer = fluidDiarizer else { return }
        
        do {
            let startTime = Date()
            let result = try diarizer.performCompleteDiarization(audioSamples)
            let processingTime = Date().timeIntervalSince(startTime)
            
            print("📊 [DiarizationManager] Processed \(chunkDuration)s chunk in \(String(format: "%.2f", processingTime))s")
            print("👥 [DiarizationManager] Found \(result.speakerCount) speakers with \(result.segments.count) segments")
            
            // Adjust timestamps for stream position
            var adjustedSegments: [TimedSpeakerSegment] = []
            for segment in result.segments {
                let adjusted = TimedSpeakerSegment(
                    speakerId: segment.speakerId,
                    embedding: segment.embedding,
                    startTimeSeconds: Float(position) + segment.startTimeSeconds,
                    endTimeSeconds: Float(position) + segment.endTimeSeconds,
                    qualityScore: segment.qualityScore
                )
                adjustedSegments.append(adjusted)
                
                // Log segment details for debugging
                let duration = segment.endTimeSeconds - segment.startTimeSeconds
                print("  - Speaker \(segment.speakerId): \(String(format: "%.1f", segment.startTimeSeconds))s - \(String(format: "%.1f", segment.endTimeSeconds))s (duration: \(String(format: "%.1f", duration))s, quality: \(String(format: "%.2f", segment.qualityScore)))")
            }
            
            // Update results
            let adjustedResult = DiarizationResult(
                segments: adjustedSegments
            )
            
            await MainActor.run {
                self.lastResult = adjustedResult
                self.updateCurrentSpeakers(from: adjustedResult)
            }
            
        } catch {
            print("❌ [DiarizationManager] Chunk processing failed: \(error)")
            await MainActor.run {
                self.lastError = error
            }
        }
    }
    
    /// Finish processing and get final diarization results
    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized else { return nil }
        
        // Process any remaining audio in buffer
        if !audioBuffer.isEmpty {
            await processRemainingAudio()
        }
        
        return lastResult
    }
    
    /// Process remaining audio that doesn't fill a complete chunk
    private func processRemainingAudio() async {
        guard let diarizer = fluidDiarizer, !audioBuffer.isEmpty else { return }
        
        isProcessing = true
        processingProgress = 0.0
        
        do {
            print("🔄 [DiarizationManager] Processing remaining \(audioBuffer.count) samples...")
            
            // Only process if we have at least 3 seconds of audio
            let minSamples = Int(sampleRate * 3.0)
            guard audioBuffer.count >= minSamples else {
                print("⚠️ [DiarizationManager] Not enough audio for reliable diarization")
                return
            }
            
            let result = try diarizer.performCompleteDiarization(audioBuffer)
            
            // Adjust timestamps for stream position
            var adjustedSegments: [TimedSpeakerSegment] = []
            for segment in result.segments {
                let adjusted = TimedSpeakerSegment(
                    speakerId: segment.speakerId,
                    embedding: segment.embedding,
                    startTimeSeconds: Float(streamPosition) + segment.startTimeSeconds,
                    endTimeSeconds: Float(streamPosition) + segment.endTimeSeconds,
                    qualityScore: segment.qualityScore
                )
                adjustedSegments.append(adjusted)
            }
            
            let adjustedResult = DiarizationResult(
                segments: adjustedSegments
            )
            
            await MainActor.run {
                self.lastResult = adjustedResult
                self.updateCurrentSpeakers(from: adjustedResult)
                self.isProcessing = false
                self.processingProgress = 1.0
            }
            
            // Clear the buffer
            audioBuffer.removeAll()
            
            print("✅ [DiarizationManager] Final diarization complete: \(adjustedResult.speakerCount) speakers")
            
        } catch {
            print("❌ [DiarizationManager] Final processing failed: \(error)")
            await MainActor.run {
                self.lastError = error
                self.isProcessing = false
            }
        }
    }
    
    // MARK: - Speaker Management
    
    /// Update the list of current speakers from results
    private func updateCurrentSpeakers(from result: DiarizationResult) {
        let uniqueSpeakers = Set(result.segments.map { $0.speakerId })
        currentSpeakers = Array(uniqueSpeakers).sorted()
    }
    
    /// Compare two audio segments to determine if they're the same speaker
    /// Note: This functionality requires implementation once FluidAudio provides speaker comparison
    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        guard let _ = fluidDiarizer else {
            throw DiarizationError.notInitialized
        }
        
        // TODO: Implement when FluidAudio provides speaker comparison API
        // For now, return a placeholder similarity score
        return 0.5
    }
    
    // MARK: - Utility Methods
    
    /// Convert AVAudioPCMBuffer to Float array at 16kHz mono
    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate
        
        var samples: [Float] = []
        
        if sourceSampleRate != Double(sampleRate) {
            // Downsample to 16kHz
            let ratio = sourceSampleRate / Double(sampleRate)
            let targetFrameCount = Int(Double(frameCount) / ratio)
            
            for frame in 0..<targetFrameCount {
                let sourceFrame = Int(Double(frame) * ratio)
                if sourceFrame < frameCount {
                    // Average all channels to mono
                    var sample: Float = 0.0
                    for channel in 0..<channelCount {
                        sample += channelData[channel][sourceFrame]
                    }
                    samples.append(sample / Float(channelCount))
                }
            }
        } else {
            // Already at 16kHz, just convert to mono
            for frame in 0..<frameCount {
                var sample: Float = 0.0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                samples.append(sample / Float(channelCount))
            }
        }
        
        return samples
    }
    
    // MARK: - Reset and Cleanup
    
    /// Reset the diarization state
    func reset() {
        audioBuffer.removeAll()
        lastResult = nil
        lastError = nil
        processingProgress = 0.0
        isProcessing = false
        streamPosition = 0.0
        currentSpeakers.removeAll()
        
        print("🔄 [DiarizationManager] Reset complete")
    }
    
    /// Clean up resources
    deinit {
        // Clean up non-MainActor properties only
        audioBuffer.removeAll()
        streamPosition = 0.0
        print("🧹 [DiarizationManager] Cleaned up")
    }
}

// MARK: - Error Types

enum DiarizationError: LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case processingFailed(String)
    case invalidAudioFormat
    case insufficientAudio
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Diarization manager not initialized"
        case .initializationFailed(let message):
            return "Failed to initialize diarization: \(message)"
        case .processingFailed(let message):
            return "Diarization processing failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for diarization"
        case .insufficientAudio:
            return "Not enough audio for reliable diarization (minimum 3 seconds required)"
        }
    }
}

// MARK: - Diarization Result Extensions

extension DiarizationResult {
    /// Number of unique speakers identified in the diarization result
    var speakerCount: Int {
        let uniqueSpeakers = Set(segments.map { $0.speakerId })
        return uniqueSpeakers.count
    }
    
    /// Get segments for a specific time range
    func segments(between startTime: TimeInterval, and endTime: TimeInterval) -> [TimedSpeakerSegment] {
        segments.filter { segment in
            Double(segment.endTimeSeconds) >= startTime && Double(segment.startTimeSeconds) <= endTime
        }
    }
    
    /// Get the dominant speaker in a time range
    func dominantSpeaker(between startTime: TimeInterval, and endTime: TimeInterval) -> String? {
        let relevantSegments = segments(between: startTime, and: endTime)
        
        // Calculate speaking time per speaker
        var speakerTimes: [String: TimeInterval] = [:]
        
        for segment in relevantSegments {
            let overlapStart = max(Double(segment.startTimeSeconds), startTime)
            let overlapEnd = min(Double(segment.endTimeSeconds), endTime)
            let duration = overlapEnd - overlapStart
            
            speakerTimes[segment.speakerId, default: 0] += duration
        }
        
        // Return speaker with most time
        return speakerTimes.max(by: { $0.value < $1.value })?.key
    }
}
#endif