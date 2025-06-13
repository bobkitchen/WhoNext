import Foundation
import SwiftUI

// MARK: - Data Models

enum TranscriptFormat: String, CaseIterable {
    case zoom = "zoom"
    case teams = "teams"
    case generic = "generic"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .generic: return "Generic Format"
        case .manual: return "Manual Notes"
        }
    }
}

struct TranscriptData {
    let rawText: String
    let detectedFormat: TranscriptFormat
    let participants: [String]
    let timestamp: Date
    let estimatedDuration: TimeInterval?
}

struct ParticipantInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let speakingTime: TimeInterval // in seconds
    let messageCount: Int
    let detectedSentiment: String
    let existingPersonId: UUID?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: ParticipantInfo, rhs: ParticipantInfo) -> Bool {
        return lhs.name == rhs.name
    }
}

struct ProcessedTranscript {
    let summary: String
    let participants: [ParticipantInfo]
    let keyPoints: [String]
    let actionItems: [String]
    let sentimentAnalysis: ContextualSentiment
    let suggestedTitle: String
    let originalTranscript: TranscriptData
}

struct ContextualSentiment {
    let overallSentiment: String
    let sentimentScore: Double
    let confidence: Double
    let engagementLevel: String
    let relationshipHealth: String
    let communicationStyle: String
    let energyLevel: String
    let participantDynamics: ParticipantDynamics
    let keyObservations: [String]
    let supportNeeds: [String]
    let followUpRecommendations: [String]
    let riskFactors: [String]
    let strengths: [String]
}

struct ParticipantDynamics {
    var dominantSpeaker: String
    var collaborationLevel: String
    var conflictIndicators: String
}

struct SentimentScore {
    let positive: Double
    let negative: Double
    let neutral: Double
    let dominant: String
    let confidence: Double
}

// MARK: - TranscriptProcessor

@MainActor
class TranscriptProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var error: String?
    
    private let hybridAI = HybridAIService()
    
    init() {
    }
    
    // MARK: - Public Methods
    
    func processTranscript(_ rawText: String) async -> ProcessedTranscript? {
        isProcessing = true
        error = nil
        
        do {
            // Step 1: Parse and detect format
            processingStatus = "Analyzing transcript format..."
            let transcriptData = parseTranscript(rawText)
            
            // Step 2: Extract participants
            processingStatus = "Identifying participants..."
            let participants = await extractParticipants(from: transcriptData)
            
            // Step 3: Generate summary
            processingStatus = "Generating summary..."
            let summary = await generateSummary(from: transcriptData, participants: participants)
            
            // Step 4: Extract action items
            processingStatus = "Extracting action items..."
            let actionItems = await extractActionItems(from: transcriptData)
            
            // Step 5: Analyze sentiment with full context
            processingStatus = "Analyzing sentiment..."
            let sentimentAnalysis = await analyzeContextualSentiment(from: transcriptData, participants: participants)
            
            // Step 6: Generate suggested title
            processingStatus = "Finalizing..."
            let suggestedTitle = await generateTitle(from: summary, participants: participants)
            
            let processedTranscript = ProcessedTranscript(
                summary: summary,
                participants: participants,
                keyPoints: [],
                actionItems: actionItems,
                sentimentAnalysis: sentimentAnalysis,
                suggestedTitle: suggestedTitle,
                originalTranscript: transcriptData
            )
            
            isProcessing = false
            processingStatus = "Complete"
            return processedTranscript
            
        } catch {
            self.error = "Processing failed: \(error.localizedDescription)"
            isProcessing = false
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func parseTranscript(_ rawText: String) -> TranscriptData {
        let format = detectTranscriptFormat(rawText)
        let participants = extractParticipantNames(from: rawText, format: format)
        
        return TranscriptData(
            rawText: rawText,
            detectedFormat: format,
            participants: participants,
            timestamp: Date(),
            estimatedDuration: estimateDuration(from: rawText)
        )
    }
    
    public func detectTranscriptFormat(_ text: String) -> TranscriptFormat {
        let lowerText = text.lowercased()
        
        // Check for Zoom patterns
        if lowerText.contains("zoom") || text.contains("00:") || text.contains("PM") || text.contains("AM") {
            return .zoom
        }
        
        // Check for Teams patterns
        if lowerText.contains("teams") || lowerText.contains("microsoft") {
            return .teams
        }
        
        // Check for speaker patterns (Name: or [Name])
        let speakerPatterns = [
            "^[A-Za-z ]+:",
            "\\[[A-Za-z ]+\\]",
            "^[A-Za-z ]+\\s*-"
        ]
        
        for pattern in speakerPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return .generic
            }
        }
        
        return .manual
    }
    
    private func extractParticipantNames(from text: String, format: TranscriptFormat) -> [String] {
        var participants = Set<String>()
        let lines = text.components(separatedBy: .newlines)
        
        switch format {
        case .zoom, .generic:
            // Look for "Name:" pattern
            for line in lines {
                if let colonIndex = line.firstIndex(of: ":") {
                    let name = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && name.count < 50 { // Reasonable name length
                        participants.insert(name)
                    }
                }
            }
            
        case .teams:
            // Look for "[Name]" pattern
            let bracketPattern = "\\[([A-Za-z ]+)\\]"
            if let regex = try? NSRegularExpression(pattern: bracketPattern) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: text) {
                        let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        participants.insert(name)
                    }
                }
            }
            
        case .manual:
            // For manual notes, we'll let AI extract participants
            break
        }
        
        return Array(participants).sorted()
    }
    
    private func estimateDuration(from text: String) -> TimeInterval? {
        // Simple estimation based on word count and average speaking pace
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).count
        let averageWordsPerMinute = 150.0
        return TimeInterval((Double(wordCount) / averageWordsPerMinute) * 60)
    }
    
    // MARK: - AI Processing Methods
    
    private func extractParticipants(from transcript: TranscriptData) async -> [ParticipantInfo] {
        do {
            let participantNames = try await hybridAI.extractParticipants(from: transcript.rawText)
            return participantNames.map { name in
                ParticipantInfo(
                    name: name,
                    speakingTime: 0.0,
                    messageCount: 0,
                    detectedSentiment: "neutral",
                    existingPersonId: nil
                )
            }
        } catch {
            print("Failed to extract participants with AI: \(error)")
            return []
        }
    }
    
    private func generateSummary(from transcript: TranscriptData, participants: [ParticipantInfo]) async -> String {
        let participantNames = participants.map { $0.name }.joined(separator: ", ")
        
        do {
            let response = try await hybridAI.generateMeetingSummary(transcript: transcript.rawText)
            return response.isEmpty ? "Unable to generate summary" : response
        } catch {
            print("Failed to generate summary: \(error)")
            return "Summary generation failed. Please review transcript manually."
        }
    }
    
    private func extractActionItems(from transcript: TranscriptData) async -> [String] {
        let prompt = """
        Analyze this meeting transcript and extract specific action items.
        
        Format your response as a JSON array:
        [
            "Action item 1",
            "Action item 2"
        ]
        
        Only include concrete, specific tasks, follow-ups, or commitments mentioned.
        
        Transcript:
        \(transcript.rawText)
        """
        
        do {
            let response = try await hybridAI.sendMessage(prompt, context: "")
            guard let data = response.data(using: .utf8),
                  let actionItems = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                return ["Unable to extract action items"]
            }
            
            return actionItems
        } catch {
            print("Failed to extract action items: \(error)")
            return ["Review transcript for action items"]
        }
    }
    
    private func analyzeContextualSentiment(from transcript: TranscriptData, participants: [ParticipantInfo]) async -> ContextualSentiment {
        let participantNames = participants.map { $0.name }.joined(separator: ", ")
        
        let prompt = """
        Analyze this meeting transcript for comprehensive relationship and engagement insights.
        
        Participants: \(participantNames)
        
        IMPORTANT: Respond ONLY with valid JSON in the exact format below. Do not include any additional text, explanations, or markdown formatting.
        
        {
            "overallSentiment": "positive/neutral/negative",
            "sentimentScore": 0.75,
            "confidence": 0.85,
            "engagementLevel": "high/medium/low",
            "relationshipHealth": "excellent/good/fair/concerning",
            "communicationStyle": "collaborative/directive/passive/tense",
            "energyLevel": "high/medium/low",
            "participantDynamics": {
                "dominantSpeaker": "participant name or 'balanced'",
                "collaborationLevel": "high/medium/low",
                "conflictIndicators": "none/minor/moderate/significant"
            },
            "keyObservations": [
                "Specific observation about relationship dynamics",
                "Note about engagement patterns",
                "Insight about communication effectiveness"
            ],
            "supportNeeds": [
                "Areas where participants may need support",
                "Relationship maintenance suggestions"
            ],
            "followUpRecommendations": [
                "Specific recommendations for next interaction",
                "Relationship building opportunities"
            ],
            "riskFactors": [
                "Any concerning patterns or issues to monitor"
            ],
            "strengths": [
                "Positive aspects of the relationship/interaction"
            ]
        }
        
        Focus on actionable insights that would help in relationship management and future interactions. Ensure all arrays contain at least one meaningful item.
        
        Transcript:
        \(transcript.rawText)
        """
        
        do {
            return try await hybridAI.analyzeSentiment(text: transcript.rawText)
        } catch {
            print("Failed to analyze contextual sentiment: \(error)")
            return ContextualSentiment(
                overallSentiment: "neutral",
                sentimentScore: 0.5,
                confidence: 0.5,
                engagementLevel: "medium",
                relationshipHealth: "good",
                communicationStyle: "collaborative",
                energyLevel: "medium",
                participantDynamics: ParticipantDynamics(
                    dominantSpeaker: "balanced",
                    collaborationLevel: "medium",
                    conflictIndicators: "none"
                ),
                keyObservations: ["Analysis unavailable"],
                supportNeeds: [],
                followUpRecommendations: [],
                riskFactors: [],
                strengths: []
            )
        }
    }
    
    private func generateTitle(from summary: String, participants: [ParticipantInfo]) async -> String {
        let participantNames = participants.map { $0.name }.joined(separator: ", ")
        
        let prompt = """
        Generate a concise, professional meeting title based on this summary and participant list.
        
        The title should:
        - Be 3-8 words maximum
        - Capture the main purpose or topic
        - Be suitable for a calendar entry
        - Not include participant names unless it's a 1:1 meeting
        
        Summary: \(summary)
        Participants: \(participantNames)
        
        Return only the title, no additional text.
        """
        
        do {
            let title = try await hybridAI.sendMessage(prompt, context: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Failed to generate title: \(error)")
            return participants.count == 2 ? "Meeting with \(participantNames)" : "Team Meeting"
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateSpeakingTime(for participant: String, in transcript: String) -> TimeInterval {
        // Estimate speaking time based on message count and length
        let lines = transcript.components(separatedBy: .newlines)
        var participantLines = 0
        var totalWords = 0
        
        for line in lines {
            if line.contains(participant) {
                participantLines += 1
                totalWords += line.components(separatedBy: .whitespaces).count
            }
        }
        
        // Rough estimate: 150 words per minute
        return TimeInterval(Double(totalWords) / 150.0 * 60.0)
    }
    
    private func countMessages(for participant: String, in transcript: String) -> Int {
        let lines = transcript.components(separatedBy: .newlines)
        return lines.filter { $0.contains(participant) }.count
    }
    
    private func analyzeSentimentForParticipant(_ participant: String, in transcript: String) async -> String {
        // Extract participant's messages
        let lines = transcript.components(separatedBy: .newlines)
        let participantMessages = lines.filter { $0.contains(participant) }.joined(separator: " ")
        
        if participantMessages.isEmpty {
            return "neutral"
        }
        
        // Use the sentiment analysis service
        let sentimentService = SentimentAnalysisService.shared
        let result = sentimentService.performBasicSentimentAnalysis(participantMessages)
        return result.label
    }
}
