import Foundation
import AVFoundation
import CoreML
import SwiftUI

/// Protocol for transcription pipeline delegate
protocol TranscriptionPipelineDelegate: AnyObject {
    func transcriptionPipeline(_ pipeline: HybridTranscriptionPipeline, didTranscribe segment: TranscriptSegment)
    func transcriptionPipeline(_ pipeline: HybridTranscriptionPipeline, didIdentifySpeaker speaker: IdentifiedParticipant)
}

/// Hybrid transcription pipeline using Parakeet-MLX for real-time local transcription
/// and Whisper API for refinement and accuracy improvement
class HybridTranscriptionPipeline: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isProcessing: Bool = false
    @Published var transcriptionProgress: Double = 0.0
    @Published var currentTranscript: String = ""
    @Published var processingSpeed: Double = 1.0 // Real-time factor
    
    // MARK: - Delegate
    weak var delegate: TranscriptionPipelineDelegate?
    
    // MARK: - Parakeet Components
    private var parakeetModel: ParakeetMLXModel?
    private let parakeetQueue = DispatchQueue(label: "com.whonext.parakeet", qos: .userInitiated)
    
    // MARK: - Whisper Components
    private let whisperService = WhisperAPIService()
    private var whisperRefinementQueue: [PendingRefinement] = []
    private let whisperQueue = DispatchQueue(label: "com.whonext.whisper", qos: .background)
    
    // MARK: - Audio Processing
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioSegments: [AudioSegment] = []
    private let segmentDuration: TimeInterval = 5.0 // Process 5-second chunks
    private var currentSegmentStartTime: TimeInterval = 0
    
    // MARK: - Speaker Identification
    private var speakerIdentifier: SpeakerIdentifier
    private var identifiedSpeakers: [UUID: IdentifiedParticipant] = [:]
    
    // MARK: - Configuration
    @AppStorage("useLocalTranscription") private var useLocalTranscription: Bool = true
    @AppStorage("whisperRefinementEnabled") private var whisperRefinementEnabled: Bool = true
    @AppStorage("speakerDiarizationEnabled") private var speakerDiarizationEnabled: Bool = true
    
    // MARK: - Initialization
    
    init() {
        self.speakerIdentifier = SpeakerIdentifier()
        setupParakeet()
    }
    
    // MARK: - Setup
    
    private func setupParakeet() {
        // Initialize Parakeet-MLX model (placeholder for now)
        // TODO: Integrate actual Parakeet-MLX when available
        parakeetModel = ParakeetMLXModel()
        print("✅ Parakeet-MLX model placeholder loaded")
        
        // Note: Local transcription disabled until Parakeet is integrated
        // User can control via Settings
    }
    
    // MARK: - Public Methods
    
    /// Process an audio chunk for transcription
    func processAudioChunk(_ buffer: AVAudioPCMBuffer) async {
        guard buffer.frameLength > 0 else { return }
        
        // Add to audio segments
        let segment = AudioSegment(
            buffer: buffer,
            timestamp: currentSegmentStartTime
        )
        audioSegments.append(segment)
        
        // Process when we have enough audio (5 seconds)
        let totalDuration = audioSegments.reduce(0) { $0 + $1.duration }
        if totalDuration >= segmentDuration {
            await processAccumulatedAudio()
        }
    }
    
    /// Finalize and return the complete transcript
    func finalizeTranscript() async -> [TranscriptSegment] {
        // Process any remaining audio
        if !audioSegments.isEmpty {
            await processAccumulatedAudio()
        }
        
        // Wait for all Whisper refinements to complete
        await processWhisperQueue()
        
        // Return final transcript
        return compileFinalTranscript()
    }
    
    // MARK: - Private Methods - Audio Processing
    
    private func processAccumulatedAudio() async {
        let segmentsToProcess = audioSegments
        audioSegments.removeAll()
        
        // Combine buffers
        guard let combinedBuffer = combineAudioBuffers(segmentsToProcess) else { return }
        
        // Update progress
        await MainActor.run {
            self.isProcessing = true
        }
        
        // Step 1: Local transcription with Parakeet
        if useLocalTranscription, let parakeetModel = parakeetModel {
            await processWithParakeet(combinedBuffer, timestamp: currentSegmentStartTime)
        } else {
            // Fall back to direct Whisper processing
            await processWithWhisper(combinedBuffer, timestamp: currentSegmentStartTime)
        }
        
        // Update segment start time
        currentSegmentStartTime += segmentDuration
        
        await MainActor.run {
            self.isProcessing = false
        }
    }
    
    private func processWithParakeet(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval) async {
        await withCheckedContinuation { continuation in
            parakeetQueue.async { [weak self] in
                guard let self = self, let model = self.parakeetModel else {
                    continuation.resume()
                    return
                }
                
                let startTime = Date()
                
                do {
                    // Convert audio buffer to format required by Parakeet
                    let audioData = self.convertBufferToData(buffer)
                    
                    // Run Parakeet inference
                    let transcription = try model.transcribe(audioData)
                    
                    // Calculate processing speed
                    let processingTime = Date().timeIntervalSince(startTime)
                    let audioLength = Double(buffer.frameLength) / buffer.format.sampleRate
                    let speed = audioLength / processingTime
                    
                    Task { @MainActor in
                        self.processingSpeed = speed
                        self.currentTranscript = transcription.text
                    }
                    
                    // Create transcript segment
                    let segment = TranscriptSegment(
                        text: transcription.text,
                        timestamp: timestamp,
                        speakerID: nil,
                        speakerName: nil,
                        confidence: transcription.confidence,
                        isFinalized: false
                    )
                    
                    // Notify delegate
                    Task { @MainActor in
                        self.delegate?.transcriptionPipeline(self, didTranscribe: segment)
                    }
                    
                    // Queue for Whisper refinement if enabled
                    if self.whisperRefinementEnabled {
                        self.queueForWhisperRefinement(buffer, segment: segment)
                    }
                    
                    // Perform speaker diarization if enabled
                    if self.speakerDiarizationEnabled {
                        self.performSpeakerDiarization(buffer, segment: segment)
                    }
                    
                    print("🦜 Parakeet transcription: \"\(transcription.text)\" (confidence: \(transcription.confidence), speed: \(String(format: "%.1fx", speed)))")
                    
                } catch {
                    print("❌ Parakeet transcription failed: \(error)")
                    // Fall back to Whisper
                    Task {
                        await self.processWithWhisper(buffer, timestamp: timestamp)
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    private func processWithWhisper(_ buffer: AVAudioPCMBuffer, timestamp: TimeInterval) async {
        do {
            // Convert buffer to audio file for Whisper API
            let audioData = convertBufferToData(buffer)
            
            // Call Whisper API
            let transcriptionResult = try await whisperService.transcribe(audioData)
            
            // Create transcript segment
            let segment = TranscriptSegment(
                text: transcriptionResult,
                timestamp: timestamp,
                speakerID: nil,
                speakerName: nil,
                confidence: 0.95, // Whisper typically has high confidence
                isFinalized: true
            )
            
            // Notify delegate
            await MainActor.run {
                self.currentTranscript = transcriptionResult
                self.delegate?.transcriptionPipeline(self, didTranscribe: segment)
            }
            
            print("🎯 Whisper transcription: \"\(transcriptionResult)\"")
            
        } catch {
            print("❌ Whisper transcription failed: \(error)")
        }
    }
    
    // MARK: - Private Methods - Whisper Refinement
    
    private func queueForWhisperRefinement(_ buffer: AVAudioPCMBuffer, segment: TranscriptSegment) {
        let refinement = PendingRefinement(
            audioBuffer: buffer,
            originalSegment: segment,
            queuedAt: Date()
        )
        
        whisperQueue.async { [weak self] in
            self?.whisperRefinementQueue.append(refinement)
            
            // Process queue if not too backed up
            if self?.whisperRefinementQueue.count ?? 0 < 5 {
                Task {
                    await self?.processWhisperQueue()
                }
            }
        }
    }
    
    private func processWhisperQueue() async {
        while !whisperRefinementQueue.isEmpty {
            let refinement = whisperRefinementQueue.removeFirst()
            
            do {
                let audioData = convertBufferToData(refinement.audioBuffer)
                let whisperResult = try await whisperService.transcribe(audioData)
                
                // Create refined segment
                let refinedSegment = TranscriptSegment(
                    text: whisperResult,
                    timestamp: refinement.originalSegment.timestamp,
                    speakerID: refinement.originalSegment.speakerID,
                    speakerName: refinement.originalSegment.speakerName,
                    confidence: 0.95,
                    isFinalized: true
                )
                
                // Notify delegate of refinement
                await MainActor.run {
                    self.delegate?.transcriptionPipeline(self, didTranscribe: refinedSegment)
                }
                
                print("✨ Whisper refinement: \"\(refinement.originalSegment.text)\" → \"\(whisperResult)\"")
                
            } catch {
                print("❌ Whisper refinement failed: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods - Speaker Diarization
    
    private func performSpeakerDiarization(_ buffer: AVAudioPCMBuffer, segment: TranscriptSegment) {
        speakerIdentifier.identifySpeaker(from: buffer) { [weak self] speakerID, confidence in
            guard let self = self else { return }
            
            // Get or create participant
            let participant: IdentifiedParticipant
            if let existing = self.identifiedSpeakers[speakerID] {
                participant = existing
                participant.confidence = confidence
            } else {
                participant = IdentifiedParticipant()
                participant.confidence = confidence
                self.identifiedSpeakers[speakerID] = participant
            }
            
            // Update segment with speaker info
            var updatedSegment = segment
            updatedSegment = TranscriptSegment(
                text: segment.text,
                timestamp: segment.timestamp,
                speakerID: speakerID.uuidString,
                speakerName: participant.displayName,
                confidence: segment.confidence,
                isFinalized: segment.isFinalized
            )
            
            Task { @MainActor in
                self.delegate?.transcriptionPipeline(self, didIdentifySpeaker: participant)
                self.delegate?.transcriptionPipeline(self, didTranscribe: updatedSegment)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func combineAudioBuffers(_ segments: [AudioSegment]) -> AVAudioPCMBuffer? {
        guard !segments.isEmpty else { return nil }
        
        let format = segments[0].buffer.format
        let totalFrames = segments.reduce(0) { $0 + Int($1.buffer.frameLength) }
        
        guard let combinedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            return nil
        }
        
        var currentFrame: AVAudioFrameCount = 0
        for segment in segments {
            let frameLength = segment.buffer.frameLength
            
            // Copy audio data
            if let srcData = segment.buffer.floatChannelData,
               let dstData = combinedBuffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    let src = srcData[channel]
                    let dst = dstData[channel].advanced(by: Int(currentFrame))
                    memcpy(dst, src, Int(frameLength) * MemoryLayout<Float>.size)
                }
            }
            
            currentFrame += frameLength
        }
        
        combinedBuffer.frameLength = AVAudioFrameCount(totalFrames)
        return combinedBuffer
    }
    
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let audioData = NSMutableData()
        
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    var sample = channelData[channel][frame]
                    audioData.append(Data(bytes: &sample, count: MemoryLayout<Float>.size))
                }
            }
        }
        
        return audioData as Data
    }
    
    private func compileFinalTranscript() -> [TranscriptSegment] {
        // This would compile all segments, preferring finalized versions
        // Implementation depends on how segments are stored
        return []
    }
}

// MARK: - Supporting Types

struct AudioSegment {
    let buffer: AVAudioPCMBuffer
    let timestamp: TimeInterval
    
    var duration: TimeInterval {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }
}

struct PendingRefinement {
    let audioBuffer: AVAudioPCMBuffer
    let originalSegment: TranscriptSegment
    let queuedAt: Date
}

// MARK: - Parakeet MLX Model Wrapper

class ParakeetMLXModel {
    private var model: Any? // Will be the actual MLX model
    
    init() {
        // Placeholder initialization
    }
    
    func transcribe(_ audioData: Data) throws -> (text: String, confidence: Float) {
        // TODO: Actual inference with MLX
        // This is a placeholder for the actual Parakeet inference
        
        // For now, return placeholder
        return (text: "[Parakeet transcription placeholder]", confidence: 0.85)
    }
}

// MARK: - Whisper API Service

class WhisperAPIService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    
    init() {
        // Get API key from secure storage
        self.apiKey = SecureStorage.getAPIKey(for: .openai)
    }
    
    func transcribe(_ audioData: Data) async throws -> String {
        // Create temporary audio file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Create multipart request
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Make request
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse response
        struct WhisperResponse: Codable {
            let text: String
        }
        
        let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return response.text
    }
}

// MARK: - Speaker Identifier

class SpeakerIdentifier {
    func identifySpeaker(from buffer: AVAudioPCMBuffer, completion: @escaping (UUID, Float) -> Void) {
        // TODO: Implement speaker identification using voice prints
        // For now, return a placeholder speaker ID
        
        DispatchQueue.global().async {
            let speakerID = UUID()
            let confidence: Float = 0.75
            completion(speakerID, confidence)
        }
    }
}