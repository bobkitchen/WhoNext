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
        // First get basic participants from format parsing
        var participants: [ParticipantInfo] = []
        
        // For each detected participant, analyze their contribution
        for participantName in transcript.participants {
            let speakingTime = calculateSpeakingTime(for: participantName, in: transcript.rawText)
            let messageCount = countMessages(for: participantName, in: transcript.rawText)
            let sentiment = await analyzeSentimentForParticipant(participantName, in: transcript.rawText)
            
            participants.append(ParticipantInfo(
                name: participantName,
                speakingTime: speakingTime,
                messageCount: messageCount,
                detectedSentiment: sentiment,
                existingPersonId: nil
            ))
        }
        
        // If no participants detected from format, use AI to extract them
        if participants.isEmpty {
            participants = await extractParticipantsWithAI(from: transcript.rawText)
        }
        
        return participants
    }
    
    private func generateSummary(from transcript: TranscriptData, participants: [ParticipantInfo]) async -> String {
        let participantNames = participants.map { $0.name }.joined(separator: ", ")
        
        // Get custom prompt from UserDefaults, with fallback to default
        let customPrompt = UserDefaults.standard.string(forKey: "customSummarizationPrompt") ?? """
You are an executive assistant creating comprehensive meeting minutes. Generate detailed, actionable meeting minutes that include:

**Meeting Overview:**
- Meeting purpose and context
- Key themes and overall tone
- Primary objectives discussed

**Discussion Details:**
- Main points raised by each participant
- Key decisions made and rationale
- Areas of agreement and disagreement
- Important insights or revelations
- Questions raised and answers provided

**Action Items & Follow-ups:**
- Specific tasks assigned with owners
- Deadlines and timelines mentioned
- Next steps and follow-up meetings
- Dependencies and blockers identified

**Outcomes & Conclusions:**
- Final decisions reached
- Issues resolved or escalated
- Commitments made by participants
- Success metrics or goals established

**Additional Notes:**
- Context for future reference
- Relationship dynamics observed
- Support needs identified
- Risk factors or concerns noted
- Strengths and positive developments

Format the output in clear, professional meeting minutes suitable for distribution and follow-up preparation.
"""
        
        let prompt = """
        \(customPrompt)
        
        Participants: \(participantNames)
        
        Transcript:
        \(transcript.rawText)
        """
        
        do {
            let response = try await AIService.shared.sendMessage(prompt)
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
            let response = try await AIService.shared.sendMessage(prompt)
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
            let response = try await AIService.shared.sendMessage(prompt)
            return parseContextualSentimentResponse(response)
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
            let title = try await AIService.shared.sendMessage(prompt)
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
    
    private func extractParticipantsWithAI(from transcript: String) async -> [ParticipantInfo] {
        let prompt = """
        Extract all participants from this meeting transcript.
        
        Return a JSON array with participant information:
        [
            {
                "name": "Full Name",
                "estimatedSpeakingTime": 120.0,
                "messageCount": 5,
                "sentiment": "positive/negative/neutral"
            }
        ]
        
        Transcript:
        \(transcript)
        """
        
        do {
            let response = try await AIService.shared.sendMessage(prompt)
            return parseParticipantsResponse(response)
        } catch {
            print("Failed to extract participants with AI: \(error)")
            return []
        }
    }
    
    private func parseContextualSentimentResponse(_ response: String) -> ContextualSentiment {
        // First, try to clean up the response - sometimes AI adds extra text
        let cleanedResponse = extractJSONFromResponse(response)
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            print("Failed to convert response to data: \(response)")
            return createFallbackSentiment(reason: "Data conversion failed")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Failed to parse JSON from response: \(cleanedResponse)")
            return createFallbackSentiment(reason: "JSON parsing failed")
        }
        
        let overallSentiment = json["overallSentiment"] as? String ?? "neutral"
        let sentimentScore = json["sentimentScore"] as? Double ?? 0.5
        let confidence = json["confidence"] as? Double ?? 0.5
        let engagementLevel = json["engagementLevel"] as? String ?? "medium"
        let relationshipHealth = json["relationshipHealth"] as? String ?? "good"
        let communicationStyle = json["communicationStyle"] as? String ?? "collaborative"
        let energyLevel = json["energyLevel"] as? String ?? "medium"
        
        var participantDynamics: ParticipantDynamics = ParticipantDynamics(
            dominantSpeaker: "balanced",
            collaborationLevel: "medium",
            conflictIndicators: "none"
        )
        if let dynamics = json["participantDynamics"] as? [String: String] {
            participantDynamics.dominantSpeaker = dynamics["dominantSpeaker"] ?? "balanced"
            participantDynamics.collaborationLevel = dynamics["collaborationLevel"] ?? "medium"
            participantDynamics.conflictIndicators = dynamics["conflictIndicators"] ?? "none"
        }
        
        let keyObservations = json["keyObservations"] as? [String] ?? ["Analysis completed successfully"]
        let supportNeeds = json["supportNeeds"] as? [String] ?? []
        let followUpRecommendations = json["followUpRecommendations"] as? [String] ?? []
        let riskFactors = json["riskFactors"] as? [String] ?? []
        let strengths = json["strengths"] as? [String] ?? []
        
        return ContextualSentiment(
            overallSentiment: overallSentiment,
            sentimentScore: sentimentScore,
            confidence: confidence,
            engagementLevel: engagementLevel,
            relationshipHealth: relationshipHealth,
            communicationStyle: communicationStyle,
            energyLevel: energyLevel,
            participantDynamics: participantDynamics,
            keyObservations: keyObservations,
            supportNeeds: supportNeeds,
            followUpRecommendations: followUpRecommendations,
            riskFactors: riskFactors,
            strengths: strengths
        )
    }
    
    private func extractJSONFromResponse(_ response: String) -> String {
        // Look for JSON content between curly braces
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            return String(response[startRange.lowerBound...endRange.upperBound])
        }
        
        // If no braces found, return the original response
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func createFallbackSentiment(reason: String) -> ContextualSentiment {
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
            keyObservations: ["Meeting analysis completed"],
            supportNeeds: ["Continue regular communication"],
            followUpRecommendations: ["Schedule follow-up meeting", "Review action items"],
            riskFactors: [],
            strengths: ["Active participation", "Clear communication"]
        )
    }
    
    private func parseParticipantsResponse(_ response: String) -> [ParticipantInfo] {
        guard let data = response.data(using: .utf8),
              let participants = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return participants.compactMap { participant in
            guard let name = participant["name"] as? String else { return nil }
            
            let speakingTime = participant["estimatedSpeakingTime"] as? Double ?? 0.0
            let messageCount = participant["messageCount"] as? Int ?? 1
            let sentiment = participant["sentiment"] as? String ?? "neutral"
            
            return ParticipantInfo(
                name: name,
                speakingTime: speakingTime,
                messageCount: messageCount,
                detectedSentiment: sentiment,
                existingPersonId: nil
            )
        }
    }
}
