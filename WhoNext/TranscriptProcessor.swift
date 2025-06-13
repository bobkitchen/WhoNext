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
        print("🔍 Detecting transcript format for text preview: \(String(text.prefix(100)))...")
        
        // Check for Zoom patterns
        if lowerText.contains("zoom") || text.contains("00:") || text.contains("PM") || text.contains("AM") {
            print("🔍 Detected format: .zoom")
            return .zoom
        }
        
        // Check for speaker patterns (Name: or [Name]) BEFORE Teams check
        let speakerPatterns = [
            "^[A-Za-z ]+:",
            "\\[[A-Za-z ]+\\]",
            "^[A-Za-z ]+\\s*-"
        ]
        
        for pattern in speakerPatterns {
            if text.range(of: pattern, options: [.regularExpression]) != nil {
                print("🔍 Detected format: .generic (matched pattern: \(pattern))")
                return .generic
            }
        }
        
        // Check for Teams patterns
        if lowerText.contains("teams") || lowerText.contains("microsoft") {
            print("🔍 Detected format: .teams")
            return .teams
        }
        
        print("🔍 Detected format: .manual")
        return .manual
    }
    
    private func extractParticipantNames(from text: String, format: TranscriptFormat) -> [String] {
        var participants = Set<String>()
        let lines = text.components(separatedBy: .newlines)
        print("🔍 Extracting participant names from \(lines.count) lines for format: \(format)")
        
        switch format {
        case .zoom, .generic:
            // Look for "Name:" pattern
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let colonIndex = trimmedLine.firstIndex(of: ":") {
                    let name = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidParticipantName(name) {
                        participants.insert(name)
                        print("🔍 Found participant via colon pattern: '\(name)'")
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
                        if isValidParticipantName(name) {
                            participants.insert(name)
                            print("🔍 Found participant via bracket pattern: '\(name)'")
                        }
                    }
                }
            }
            
        case .manual:
            // For manual notes, try multiple patterns but focus on actual speakers
            let allPatterns = [
                // Colon patterns (most reliable for speakers)
                "^([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*):",
                // Dash patterns
                "^([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*) -",
                // Parenthetical patterns for speaker labels
                "^\\(([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)\\)"
            ]
            
            for pattern in allPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: text) {
                            let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if isValidParticipantName(name) {
                                participants.insert(name)
                                print("🔍 Found participant via pattern '\(pattern)': '\(name)'")
                            }
                        }
                    }
                }
            }
        }
        
        print("🔍 Extracted participants: \(Array(participants).sorted())")
        return Array(participants).sorted()
    }
    
    private func isValidParticipantName(_ name: String) -> Bool {
        // Filter out common non-names
        let invalidNames = ["Meeting", "Transcript", "Zoom", "Teams", "Recording", "Host", "Participant", "Unknown", "System", "Admin", "Moderator"]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation
        guard !trimmedName.isEmpty,
              trimmedName.count >= 2,
              trimmedName.count <= 50,
              !invalidNames.contains(trimmedName),
              !trimmedName.contains("@"),
              !trimmedName.contains("http"),
              !trimmedName.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        // Must contain at least one letter and be a reasonable name length
        guard trimmedName.contains(where: { $0.isLetter }),
              trimmedName.count <= 30 else { // Shorter max length for names
            return false
        }
        
        // Should not contain quotes or other punctuation that suggests it's content, not a name
        guard !trimmedName.contains("\""),
              !trimmedName.contains("'"),
              !trimmedName.contains("?"),
              !trimmedName.contains("!"),
              !trimmedName.contains(".") else {
            return false
        }
        
        return true
    }
    
    private func estimateDuration(from text: String) -> TimeInterval? {
        // Simple estimation based on word count and average speaking pace
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).count
        let averageWordsPerMinute = 150.0
        return TimeInterval((Double(wordCount) / averageWordsPerMinute) * 60)
    }
    
    // MARK: - AI Processing Methods
    
    private func extractParticipants(from transcript: TranscriptData) async -> [ParticipantInfo] {
        print("🔍 Starting participant extraction for format: \(transcript.detectedFormat)")
        print("🔍 Transcript preview: \(String(transcript.rawText.prefix(200)))...")
        
        do {
            print("🔍 Attempting AI participant extraction...")
            let participantNames = try await hybridAI.extractParticipants(from: transcript.rawText)
            print("🔍 AI returned \(participantNames.count) participants: \(participantNames)")
            if !participantNames.isEmpty {
                return await createParticipantInfoWithMatching(from: participantNames)
            }
        } catch {
            print("🔍 AI participant extraction failed: \(error)")
        }
        
        print("🔍 Falling back to manual parsing...")
        // Fallback to simple parsing based on transcript format
        let fallbackNames = extractParticipantNames(from: transcript.rawText, format: transcript.detectedFormat)
        print("🔍 Manual parsing found \(fallbackNames.count) participants: \(fallbackNames)")
        return await createParticipantInfoWithMatching(from: fallbackNames)
    }
    
    private func createParticipantInfoWithMatching(from names: [String]) async -> [ParticipantInfo] {
        var participantInfos: [ParticipantInfo] = []
        
        for name in names {
            // Skip if this is Bob (the user)
            if name.lowercased().contains("bob") {
                print("🔍 Skipping user's own name: \(name)")
                continue
            }
            
            let matchedPerson = await findBestMatch(for: name)
            let participantInfo = ParticipantInfo(
                name: name,
                speakingTime: 0.0,
                messageCount: 0,
                detectedSentiment: "neutral",
                existingPersonId: matchedPerson?.identifier
            )
            participantInfos.append(participantInfo)
            
            if let match = matchedPerson {
                print("🔍 Auto-matched '\(name)' to existing person: '\(match.name ?? "Unknown")' (confidence: high)")
            } else {
                print("🔍 No match found for '\(name)' - will need manual selection")
            }
        }
        
        return participantInfos
    }
    
    private func findBestMatch(for participantName: String) async -> Person? {
        return await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request = NSFetchRequest<Person>(entityName: "Person")
            
            do {
                let allPeople = try context.fetch(request)
                print("🔍 Searching \(allPeople.count) people for match to '\(participantName)'")
                
                var bestMatch: Person?
                var bestScore = 0.0
                
                for person in allPeople {
                    guard let personName = person.name else { continue }
                    
                    let score = calculateNameSimilarity(participantName, personName)
                    print("🔍 Comparing '\(participantName)' vs '\(personName)': score \(String(format: "%.2f", score))")
                    
                    // Require a minimum confidence threshold
                    if score > bestScore && score >= 0.7 {
                        bestScore = score
                        bestMatch = person
                    }
                }
                
                if let match = bestMatch {
                    print("🔍 Best match for '\(participantName)': '\(match.name ?? "Unknown")' (score: \(String(format: "%.2f", bestScore)))")
                }
                
                return bestMatch
            } catch {
                print("🔍 Error fetching people for matching: \(error)")
                return nil
            }
        }
    }
    
    private func calculateNameSimilarity(_ name1: String, _ name2: String) -> Double {
        let cleanName1 = name1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName2 = name2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Exact match
        if cleanName1 == cleanName2 {
            return 1.0
        }
        
        // Check if one name contains the other (for first name matches)
        if cleanName1.contains(cleanName2) || cleanName2.contains(cleanName1) {
            return 0.8
        }
        
        // Split into components and check for partial matches
        let components1 = cleanName1.components(separatedBy: .whitespaces)
        let components2 = cleanName2.components(separatedBy: .whitespaces)
        
        var matchingComponents = 0
        for comp1 in components1 {
            for comp2 in components2 {
                if comp1 == comp2 || comp1.contains(comp2) || comp2.contains(comp1) {
                    matchingComponents += 1
                    break
                }
            }
        }
        
        // Calculate score based on matching components
        let maxComponents = max(components1.count, components2.count)
        return Double(matchingComponents) / Double(maxComponents)
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
