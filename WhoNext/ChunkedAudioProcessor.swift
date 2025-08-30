import Foundation
import AVFoundation
import Speech

/// Processes audio in 60-second chunks for optimal transcription accuracy
/// Based on the approach used by Quill Meetings and similar professional apps
@MainActor
class ChunkedAudioProcessor: ObservableObject {
    
    // MARK: - Properties
    
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    @Published var currentChunkIndex: Int = 0
    @Published var totalChunks: Int = 0
    @Published var lastError: Error?
    
    // Configuration
    private let chunkDuration: TimeInterval = 60.0 // 60-second chunks
    private let overlapDuration: TimeInterval = 2.0 // 2-second overlap for continuity
    private let minChunkDuration: TimeInterval = 5.0 // Minimum chunk size to process
    
    // Audio buffering
    private var audioBuffer: [AVAudioPCMBuffer] = []
    private var accumulatedDuration: TimeInterval = 0.0
    private let sampleRate: Double = 16000.0 // 16kHz for speech
    
    // Transcription
    private var modernSpeechFramework: Any? // ModernSpeechFramework for macOS 26+
    private var transcriptChunks: [TranscriptChunk] = []
    
    // Diarization
    #if canImport(FluidAudio)
    private var diarizationManager: DiarizationManager?
    #endif
    
    // Processing queue
    private let processingQueue = DispatchQueue(label: "com.whonext.chunkedaudio", qos: .userInitiated)
    private var chunkProcessingTasks: [Task<Void, Error>] = []
    
    // MARK: - Initialization
    
    init(enableDiarization: Bool = true) {
        setupTranscription(enableDiarization: enableDiarization)
        
        #if canImport(FluidAudio)
        if enableDiarization {
            diarizationManager = DiarizationManager(
                isEnabled: true,
                enableRealTimeProcessing: false // Process chunks, not real-time
            )
        }
        #endif
    }
    
    private func setupTranscription(enableDiarization: Bool) {
        if #available(macOS 26.0, *) {
            Task {
                modernSpeechFramework = ModernSpeechFramework(enableDiarization: enableDiarization)
                if let framework = modernSpeechFramework as? ModernSpeechFramework {
                    try? await framework.initialize()
                    print("✅ ChunkedAudioProcessor: Speech framework initialized")
                }
            }
        }
    }
    
    // MARK: - Audio Input
    
    /// Add audio buffer to the accumulator
    func addAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioBuffer.append(buffer)
        
        // Calculate accumulated duration
        let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
        accumulatedDuration += bufferDuration
        
        // Check if we have enough for a chunk
        if accumulatedDuration >= chunkDuration {
            Task {
                await processAccumulatedAudio()
            }
        }
    }
    
    /// Process accumulated audio as a chunk
    private func processAccumulatedAudio() async {
        guard accumulatedDuration >= minChunkDuration else { return }
        
        // Extract chunk from buffer
        let chunk = extractChunk(duration: min(chunkDuration, accumulatedDuration))
        guard let audioChunk = chunk else { return }
        
        // Reset accumulator for next chunk (keeping overlap)
        if accumulatedDuration > chunkDuration {
            // Keep last 2 seconds for overlap
            let overlapSamples = Int(overlapDuration * sampleRate)
            audioBuffer = Array(audioBuffer.suffix(overlapSamples / 1024)) // Approximate buffer count
            accumulatedDuration = overlapDuration
        } else {
            audioBuffer.removeAll()
            accumulatedDuration = 0
        }
        
        // Process the chunk
        currentChunkIndex += 1
        await processChunk(audioChunk, index: currentChunkIndex)
    }
    
    /// Extract a chunk of audio from the buffer
    private func extractChunk(duration: TimeInterval) -> AVAudioPCMBuffer? {
        guard !audioBuffer.isEmpty else { return nil }
        
        let format = audioBuffer.first!.format
        let totalFrames = AVAudioFrameCount(duration * format.sampleRate)
        
        guard let combinedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: totalFrames
        ) else { return nil }
        
        var currentFrame: AVAudioFrameCount = 0
        
        for buffer in audioBuffer {
            let framesToCopy = min(buffer.frameLength, totalFrames - currentFrame)
            
            if framesToCopy > 0 {
                // Copy audio data
                if let srcData = buffer.floatChannelData,
                   let dstData = combinedBuffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        let src = srcData[channel]
                        let dst = dstData[channel].advanced(by: Int(currentFrame))
                        dst.update(from: src, count: Int(framesToCopy))
                    }
                }
                
                currentFrame += framesToCopy
            }
            
            if currentFrame >= totalFrames {
                break
            }
        }
        
        combinedBuffer.frameLength = currentFrame
        return combinedBuffer
    }
    
    // MARK: - Chunk Processing
    
    /// Process a single audio chunk
    private func processChunk(_ buffer: AVAudioPCMBuffer, index: Int) async {
        let startTime = Date()
        let chunkStartTime = TimeInterval(index - 1) * (chunkDuration - overlapDuration)
        
        print("🔄 Processing chunk #\(index) (t=\(Int(chunkStartTime))s)")
        
        do {
            // 1. Transcribe the chunk
            let transcription = try await transcribeChunk(buffer)
            
            // 2. Perform diarization if enabled
            var speakerSegments: [SpeakerSegment] = []
            #if canImport(FluidAudio)
            if let diarizer = diarizationManager {
                speakerSegments = await diarizeChunk(buffer, using: diarizer)
            }
            #endif
            
            // 3. Align transcription with speakers
            let alignedSegments = alignTranscriptionWithSpeakers(
                transcription: transcription,
                speakers: speakerSegments,
                chunkStartTime: chunkStartTime
            )
            
            // 4. Store the processed chunk
            let chunk = TranscriptChunk(
                index: index,
                startTime: chunkStartTime,
                duration: min(chunkDuration, accumulatedDuration),
                transcript: transcription,
                segments: alignedSegments,
                processingTime: Date().timeIntervalSince(startTime)
            )
            
            transcriptChunks.append(chunk)
            
            // Update progress
            await MainActor.run {
                self.processingProgress = Double(index) / Double(max(totalChunks, 1))
            }
            
            print("✅ Chunk #\(index) processed in \(String(format: "%.2f", chunk.processingTime))s")
            print("   - Words: \(transcription.split(separator: " ").count)")
            print("   - Speakers: \(Set(speakerSegments.map { $0.speakerId }).count)")
            
        } catch {
            print("❌ Failed to process chunk #\(index): \(error)")
            await MainActor.run {
                self.lastError = error
            }
        }
    }
    
    /// Transcribe an audio chunk
    private func transcribeChunk(_ buffer: AVAudioPCMBuffer) async throws -> String {
        guard #available(macOS 26.0, *),
              let framework = modernSpeechFramework as? ModernSpeechFramework else {
            throw ChunkProcessingError.transcriptionUnavailable
        }
        
        // Process through speech framework
        let transcript = try await framework.processAudioStream(buffer)
        return transcript
    }
    
    /// Diarize an audio chunk
    #if canImport(FluidAudio)
    private func diarizeChunk(_ buffer: AVAudioPCMBuffer, using diarizer: DiarizationManager) async -> [SpeakerSegment] {
        await diarizer.processAudioBuffer(buffer)
        
        if let result = await diarizer.finishProcessing() {
            return result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    confidence: segment.qualityScore
                )
            }
        }
        
        return []
    }
    #endif
    
    /// Align transcription with speaker segments
    private func alignTranscriptionWithSpeakers(
        transcription: String,
        speakers: [SpeakerSegment],
        chunkStartTime: TimeInterval
    ) -> [AlignedSegment] {
        guard !speakers.isEmpty else {
            // No speaker info, return as single segment
            return [AlignedSegment(
                text: transcription,
                speaker: nil,
                startTime: chunkStartTime,
                endTime: chunkStartTime + chunkDuration
            )]
        }
        
        // Simple word-based alignment
        let words = transcription.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        
        let wordsPerSecond = Double(words.count) / chunkDuration
        var alignedSegments: [AlignedSegment] = []
        
        for speaker in speakers {
            let relativeStart = speaker.startTime
            let relativeEnd = speaker.endTime
            
            let startWordIndex = Int(relativeStart * wordsPerSecond)
            let endWordIndex = min(Int(relativeEnd * wordsPerSecond), words.count)
            
            if startWordIndex < words.count && startWordIndex < endWordIndex {
                let segmentWords = words[startWordIndex..<endWordIndex]
                let segmentText = segmentWords.joined(separator: " ")
                
                alignedSegments.append(AlignedSegment(
                    text: segmentText,
                    speaker: "Speaker \(speaker.speakerId)",
                    startTime: chunkStartTime + speaker.startTime,
                    endTime: chunkStartTime + speaker.endTime
                ))
            }
        }
        
        return alignedSegments
    }
    
    // MARK: - Finalization
    
    /// Finish processing and get final results
    func finishProcessing() async -> ProcessedMeeting {
        isProcessing = true
        
        // Process any remaining audio
        if accumulatedDuration >= minChunkDuration {
            await processAccumulatedAudio()
        }
        
        // Wait for all chunks to complete
        for task in chunkProcessingTasks {
            _ = try? await task.value
        }
        
        // Combine all chunks into final transcript
        let fullTranscript = combineChunks()
        
        isProcessing = false
        
        return ProcessedMeeting(
            transcript: fullTranscript,
            chunks: transcriptChunks,
            totalDuration: transcriptChunks.last?.startTime ?? 0 + (transcriptChunks.last?.duration ?? 0),
            processingTime: transcriptChunks.reduce(0) { $0 + $1.processingTime }
        )
    }
    
    /// Combine all chunks into a single transcript
    private func combineChunks() -> String {
        transcriptChunks
            .sorted { $0.index < $1.index }
            .flatMap { $0.segments }
            .map { segment in
                if let speaker = segment.speaker {
                    return "\(speaker): \(segment.text)"
                } else {
                    return segment.text
                }
            }
            .joined(separator: "\n")
    }
    
    /// Reset for new recording
    func reset() {
        audioBuffer.removeAll()
        accumulatedDuration = 0
        transcriptChunks.removeAll()
        currentChunkIndex = 0
        totalChunks = 0
        processingProgress = 0
        lastError = nil
        
        // Cancel pending tasks
        for task in chunkProcessingTasks {
            task.cancel()
        }
        chunkProcessingTasks.removeAll()
        
        // Reset speech framework
        if #available(macOS 26.0, *),
           let framework = modernSpeechFramework as? ModernSpeechFramework {
            framework.reset()
        }
        
        // Reset diarization
        #if canImport(FluidAudio)
        diarizationManager?.reset()
        #endif
        
        print("♻️ ChunkedAudioProcessor reset")
    }
}

// MARK: - Supporting Types

struct TranscriptChunk {
    let index: Int
    let startTime: TimeInterval
    let duration: TimeInterval
    let transcript: String
    let segments: [AlignedSegment]
    let processingTime: TimeInterval
}

struct SpeakerSegment {
    let speakerId: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

struct AlignedSegment {
    let text: String
    let speaker: String?
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct ProcessedMeeting {
    let transcript: String
    let chunks: [TranscriptChunk]
    let totalDuration: TimeInterval
    let processingTime: TimeInterval
}

enum ChunkProcessingError: LocalizedError {
    case transcriptionUnavailable
    case invalidAudioFormat
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .transcriptionUnavailable:
            return "Transcription service not available"
        case .invalidAudioFormat:
            return "Invalid audio format for processing"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        }
    }
}