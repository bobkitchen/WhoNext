import Foundation

/// Safe transcript processing to avoid index out of bounds errors
@available(macOS 26.0, *)
class SafeTranscriptProcessor {
    private var processedFinalizedCount = 0
    private var lastProcessedText = ""
    
    /// Process transcription segments safely
    func processTranscriptionUpdate(
        framework: Any, // ModernSpeechFramework
        currentMeeting: LiveMeeting?,
        recordingStartTime: Date?
    ) async throws {
        guard let modernFramework = framework as? ModernSpeechFramework else { return }
        
        // Get all segments from the framework
        let allSegments = await modernFramework.getTranscriptionSegments()
        
        // Filter to only finalized segments
        let finalizedSegments = allSegments.filter { $0.isFinal }
        
        // Process only new finalized segments
        if finalizedSegments.count > processedFinalizedCount {
            let newSegments = Array(finalizedSegments[processedFinalizedCount..<finalizedSegments.count])
            
            for segment in newSegments {
                // Skip very short segments (less than 3 words) unless they're the end of a sentence
                let wordCount = segment.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                let endsWithPunctuation = segment.text.trimmingCharacters(in: .whitespaces)
                    .last?.isPunctuation ?? false
                
                if wordCount < 3 && !endsWithPunctuation {
                    continue
                }
                
                // Create transcript segment
                let transcriptSegment = TranscriptSegment(
                    text: segment.text,
                    timestamp: segment.startTime,
                    speakerID: segment.speakerId.map { String($0) },
                    speakerName: nil,
                    confidence: segment.confidence,
                    isFinalized: true
                )
                
                await MainActor.run {
                    currentMeeting?.addTranscriptSegment(transcriptSegment)
                    print("📝 New segment #\(currentMeeting?.transcript.count ?? 0): \(wordCount) words")
                }
            }
            
            // Update processed count
            processedFinalizedCount = finalizedSegments.count
            
            // Log total progress
            if !newSegments.isEmpty {
                let totalWords = finalizedSegments
                    .map { $0.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count }
                    .reduce(0, +)
                print("📊 Total transcript: \(totalWords) words in \(finalizedSegments.count) segments")
            }
        }
    }
    
    /// Reset for new recording session
    func reset() {
        processedFinalizedCount = 0
        lastProcessedText = ""
    }
}