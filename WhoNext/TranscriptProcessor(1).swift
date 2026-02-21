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
    let id: UUID
    let name: String
    let speakingTime: TimeInterval // in seconds
    let messageCount: Int
    let detectedSentiment: String
    let existingPersonId: UUID?
    let isCurrentUser: Bool  // True if user identified this as themselves during recording
    let confidence: Float    // Voice match confidence (0-1)
    let speakerID: Int       // Original speaker ID from diarization
    let voiceEmbedding: [Float]?  // Voice embedding for voice learning

    init(
        id: UUID = UUID(),
        name: String,
        speakingTime: TimeInterval = 0,
        messageCount: Int = 0,
        detectedSentiment: String = "neutral",
        existingPersonId: UUID? = nil,
        isCurrentUser: Bool = false,
        confidence: Float = 0,
        speakerID: Int = 0,
        voiceEmbedding: [Float]? = nil
    ) {
        self.id = id
        self.name = name
        self.speakingTime = speakingTime
        self.messageCount = messageCount
        self.detectedSentiment = detectedSentiment
        self.existingPersonId = existingPersonId
        self.isCurrentUser = isCurrentUser
        self.confidence = confidence
        self.speakerID = speakerID
        self.voiceEmbedding = voiceEmbedding
    }

    /// Create from a SerializableParticipant (pre-identified during recording)
    init(from serializable: SerializableParticipant) {
        self.id = serializable.id
        self.name = serializable.displayName
        self.speakingTime = serializable.totalSpeakingTime
        self.messageCount = 0  // Will be calculated from transcript
        self.detectedSentiment = "neutral"
        self.existingPersonId = serializable.personIdentifier
        self.isCurrentUser = serializable.isCurrentUser
        self.confidence = serializable.confidence
        self.speakerID = serializable.speakerID
        self.voiceEmbedding = serializable.voiceEmbedding
    }

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
    let preIdentifiedParticipants: [SerializableParticipant]?  // Pre-identified from recording
    let userNotes: String?  // User notes taken during recording (Granola-style)
    let recordingDuration: TimeInterval  // Actual recording duration in seconds
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

// MARK: - Processing Phase (for accurate progress tracking)

enum TranscriptProcessingPhase: Int, CaseIterable {
    case idle = 0
    case analyzing = 1
    case participants = 2
    case summary = 3
    case actions = 4
    case sentiment = 5
    case finalizing = 6
    case complete = 7

    var title: String {
        switch self {
        case .idle: return ""
        case .analyzing: return "Analyzing transcript format"
        case .participants: return "Identifying participants"
        case .summary: return "Generating meeting summary"
        case .actions: return "Extracting action items"
        case .sentiment: return "Analyzing sentiment"
        case .finalizing: return "Finalizing"
        case .complete: return "Complete"
        }
    }
}

// MARK: - TranscriptProcessor

@MainActor
class TranscriptProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var currentPhase: TranscriptProcessingPhase = .idle

    private let hybridAI = HybridAIService()

    init() {
    }

    /// Cancel ongoing processing
    func cancelProcessing() {
        isProcessing = false
        processingStatus = ""
        currentPhase = .idle
    }

    // MARK: - Public Methods

    /// Process a transcript with optional pre-identified participants from recording
    /// - Parameters:
    ///   - rawText: The raw transcript text
    ///   - preIdentifiedParticipants: Optional participants already identified during recording
    ///   - userNotes: Optional user notes taken during recording (Granola-style)
    /// - Returns: A ProcessedTranscript or nil on failure
    func processTranscript(_ rawText: String, preIdentifiedParticipants: [SerializableParticipant]? = nil, userNotes: String? = nil, recordingDuration: TimeInterval = 0) async -> ProcessedTranscript? {
        isProcessing = true
        currentPhase = .analyzing
        print("📊 TranscriptProcessor: Starting processing")

        do {
            // Step 1: Parse and detect format
            currentPhase = .analyzing
            processingStatus = "Analyzing transcript format..."
            print("📊 TranscriptProcessor: Phase 1 - Analyzing")
            let transcriptData = parseTranscript(rawText)

            // Step 2: Extract participants (use pre-identified if available)
            currentPhase = .participants
            processingStatus = "Identifying participants..."
            print("📊 TranscriptProcessor: Phase 2 - Participants")
            let participants: [ParticipantInfo]
            if let preIdentified = preIdentifiedParticipants, !preIdentified.isEmpty {
                // Use pre-identified participants from recording
                participants = preIdentified.map { ParticipantInfo(from: $0) }
                print("📝 Using \(participants.count) pre-identified participants from recording")
            } else {
                // Fall back to extraction from transcript
                participants = await extractParticipants(from: transcriptData)
            }

            // Step 3: Generate summary (incorporating user notes if provided)
            currentPhase = .summary
            processingStatus = "Generating summary..."
            print("📊 TranscriptProcessor: Phase 3 - Summary")
            let summary = await generateSummary(from: transcriptData, participants: participants, userNotes: userNotes)

            // Step 4: Extract action items
            currentPhase = .actions
            processingStatus = "Extracting action items..."
            print("📊 TranscriptProcessor: Phase 4 - Actions")
            let actionItems = await extractActionItems(from: transcriptData)

            // Step 5: Analyze sentiment with full context
            currentPhase = .sentiment
            processingStatus = "Analyzing sentiment..."
            print("📊 TranscriptProcessor: Phase 5 - Sentiment")
            let sentimentAnalysis = await analyzeContextualSentiment(from: transcriptData, participants: participants)

            // Step 6: Generate suggested title
            currentPhase = .finalizing
            processingStatus = "Finalizing..."
            print("📊 TranscriptProcessor: Phase 6 - Finalizing")
            let suggestedTitle = await generateTitle(from: summary, participants: participants)

            let processedTranscript = ProcessedTranscript(
                summary: summary,
                participants: participants,
                keyPoints: [],
                actionItems: actionItems,
                sentimentAnalysis: sentimentAnalysis,
                suggestedTitle: suggestedTitle,
                originalTranscript: transcriptData,
                preIdentifiedParticipants: preIdentifiedParticipants,
                userNotes: userNotes,
                recordingDuration: recordingDuration
            )

            currentPhase = .complete
            isProcessing = false
            processingStatus = "Complete"
            print("📊 TranscriptProcessor: Processing complete!")
            return processedTranscript

        } catch {
            ErrorManager.shared.handle(error, context: "Failed to process transcript")
            currentPhase = .idle
            isProcessing = false
            print("📊 TranscriptProcessor: Processing failed with error: \(error)")
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

    // MARK: - Participant Validation

    /// Validates that extracted participant names actually appear as speaker labels in the transcript
    /// This prevents names mentioned in conversation from being incorrectly identified as participants
    private func validateParticipantsAsSpeakers(_ participants: [String], in transcript: String) -> [String] {
        let lines = transcript.components(separatedBy: .newlines)
        var validatedParticipants: [String] = []

        // Build a set of actual speaker labels from the transcript
        var actualSpeakerLabels = Set<String>()

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            // Check for "Name:" pattern at the start of line
            if let colonIndex = trimmedLine.firstIndex(of: ":") {
                let potentialLabel = String(trimmedLine[..<colonIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Validate it looks like a speaker label (not a timestamp or URL)
                if isValidParticipantName(potentialLabel) {
                    actualSpeakerLabels.insert(potentialLabel.lowercased())
                    print("🔍 Found speaker label: '\(potentialLabel)'")
                }
            }

            // Also check for "[Name]" pattern
            if let bracketPattern = try? NSRegularExpression(pattern: "^\\[([^\\]]+)\\]") {
                let range = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                if let match = bracketPattern.firstMatch(in: trimmedLine, range: range),
                   let nameRange = Range(match.range(at: 1), in: trimmedLine) {
                    let potentialLabel = String(trimmedLine[nameRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidParticipantName(potentialLabel) {
                        actualSpeakerLabels.insert(potentialLabel.lowercased())
                        print("🔍 Found bracketed speaker label: '\(potentialLabel)'")
                    }
                }
            }
        }

        print("🔍 Actual speaker labels found in transcript: \(actualSpeakerLabels)")

        // Validate each extracted participant against actual speaker labels
        for participant in participants {
            let participantLower = participant.lowercased()

            // Check for exact match
            if actualSpeakerLabels.contains(participantLower) {
                validatedParticipants.append(participant)
                print("✅ Validated participant: '\(participant)' (exact match)")
                continue
            }

            // Check if participant name is contained in any speaker label (for "Speaker 1" vs "Speaker")
            var foundMatch = false
            for label in actualSpeakerLabels {
                if label.contains(participantLower) || participantLower.contains(label) {
                    validatedParticipants.append(participant)
                    print("✅ Validated participant: '\(participant)' (partial match with '\(label)')")
                    foundMatch = true
                    break
                }
            }

            if !foundMatch {
                print("❌ Rejected participant: '\(participant)' (not found as speaker label)")
            }
        }

        return validatedParticipants
    }

    /// Constrains participant count based on voice analysis metadata if available
    private func constrainByVoiceAnalysis(_ participants: [String], transcript: String) -> [String] {
        // Check for voice analysis metadata
        guard transcript.contains("[Voice Analysis:") else {
            return participants
        }

        // Extract speaker count from metadata
        let voiceSpeakerCount: Int
        if let match = transcript.range(of: #"\[Voice Analysis: (\d+) speaker"#, options: .regularExpression) {
            let numberPart = transcript[match]
            if let number = numberPart.firstMatch(of: /\d+/) {
                voiceSpeakerCount = Int(number.output) ?? 0
            } else {
                voiceSpeakerCount = 0
            }
        } else {
            voiceSpeakerCount = 0
        }

        guard voiceSpeakerCount > 0 else { return participants }

        print("🎤 Voice analysis detected \(voiceSpeakerCount) speaker(s)")

        // If we have more participants than voice-detected speakers, trim to match
        if participants.count > voiceSpeakerCount {
            print("⚠️ Trimming participants from \(participants.count) to \(voiceSpeakerCount) based on voice analysis")
            return Array(participants.prefix(voiceSpeakerCount))
        }

        return participants
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
        
        // Check for voice analysis metadata
        var voiceDetectedSpeakerCount = 0
        if transcript.rawText.contains("[Voice Analysis:") {
            // Extract speaker count from metadata
            if let match = transcript.rawText.range(of: #"\[Voice Analysis: (\d+) speaker"#, options: .regularExpression) {
                let numberPart = transcript.rawText[match]
                if let number = numberPart.firstMatch(of: /\d+/) {
                    voiceDetectedSpeakerCount = Int(number.output) ?? 0
                }
            }
            print("🎤 Voice analysis metadata found: \(voiceDetectedSpeakerCount) speaker(s)")
        }
        
        // If voice analysis detected only 1 speaker, short-circuit the extraction
        if voiceDetectedSpeakerCount == 1 {
            print("🎤 Single speaker detected by voice analysis, extracting single participant")
            
            // Try to find the speaker name from the transcript
            var speakerName = "Speaker"
            
            // Look for pattern like "Bob: " at the beginning of actual content
            let lines = transcript.rawText.components(separatedBy: .newlines)
            for line in lines {
                if !line.isEmpty && !line.starts(with: "[") {
                    if let colonIndex = line.firstIndex(of: ":") {
                        speakerName = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
            
            print("🎤 Single speaker identified as: \(speakerName)")
            return await createParticipantInfoWithMatching(from: [speakerName])
        }
        
        // Otherwise, proceed with normal AI extraction
        do {
            print("🔍 Attempting AI participant extraction...")
            var participantNames = try await hybridAI.extractParticipants(from: transcript.rawText)
            print("🔍 AI returned \(participantNames.count) participants: \(participantNames)")

            // CRITICAL: Validate that extracted names actually appear as speaker labels
            // This prevents names mentioned in conversation from being incorrectly identified
            participantNames = validateParticipantsAsSpeakers(participantNames, in: transcript.rawText)
            print("🔍 After validation: \(participantNames.count) participants: \(participantNames)")

            // Constrain by voice analysis speaker count if available
            participantNames = constrainByVoiceAnalysis(participantNames, transcript: transcript.rawText)
            print("🔍 After voice constraint: \(participantNames.count) participants: \(participantNames)")

            if !participantNames.isEmpty {
                return await createParticipantInfoWithMatching(from: participantNames)
            }
        } catch {
            print("🔍 AI participant extraction failed: \(error)")
        }

        print("🔍 Falling back to manual parsing...")
        // Fallback to simple parsing based on transcript format
        var fallbackNames = extractParticipantNames(from: transcript.rawText, format: transcript.detectedFormat)
        print("🔍 Manual parsing found \(fallbackNames.count) participants: \(fallbackNames)")

        // Also validate manual parsing results
        fallbackNames = validateParticipantsAsSpeakers(fallbackNames, in: transcript.rawText)
        print("🔍 After validation: \(fallbackNames.count) participants: \(fallbackNames)")

        // Constrain by voice analysis
        fallbackNames = constrainByVoiceAnalysis(fallbackNames, transcript: transcript.rawText)
        print("🔍 After voice constraint: \(fallbackNames.count) participants: \(fallbackNames)")

        return await createParticipantInfoWithMatching(from: fallbackNames)
    }
    
    private func createParticipantInfoWithMatching(from names: [String]) async -> [ParticipantInfo] {
        var participantInfos: [ParticipantInfo] = []

        for name in names {
            // Skip if this is the current user
            if UserProfile.shared.isCurrentUser(name) {
                print("🔍 Skipping current user: \(name)")
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
    
    private func generateSummary(from transcript: TranscriptData, participants: [ParticipantInfo], userNotes: String? = nil) async -> String {
        let participantNames = participants.map { $0.name }.joined(separator: ", ")

        do {
            // Use enhanced summary generation that incorporates user notes if available
            let response = try await hybridAI.generateMeetingSummary(transcript: transcript.rawText, userNotes: userNotes)
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
