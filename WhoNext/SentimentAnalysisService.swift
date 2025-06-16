import Foundation
import NaturalLanguage
import CoreData

// MARK: - Sentiment Analysis Models

struct SentimentResult {
    let score: Double // -1.0 (negative) to 1.0 (positive)
    let label: String // "positive", "negative", "neutral"
    let confidence: Double // 0.0 to 1.0
}

struct ConversationAnalysis {
    let sentimentResult: SentimentResult
    let qualityScore: Double // 0.0 to 1.0
    let engagementLevel: String // "high", "medium", "low"
    let keyTopics: [String]
    let analysisVersion: String
}

enum SentimentAnalysisError: Error {
    case invalidInput
    case analysisFailure
    case modelUnavailable
    
    var localizedDescription: String {
        switch self {
        case .invalidInput:
            return "Invalid input provided for sentiment analysis"
        case .analysisFailure:
            return "Failed to analyze sentiment"
        case .modelUnavailable:
            return "Sentiment analysis model is not available"
        }
    }
}

// MARK: - Sentiment Analysis Service

class SentimentAnalysisService {
    static let shared = SentimentAnalysisService()
    
    private let sentimentPredictor: NLModel?
    public let currentAnalysisVersion = "1.0"
    
    /// Whether sentiment analysis is available on this device
    public var isAvailable: Bool {
        return sentimentPredictor != nil
    }
    
    init() {
        // Initialize Apple's Natural Language sentiment classifier
        // Note: This uses a basic approach - in production you might want a custom model
        do {
            // Try to load the built-in sentiment classifier
            if let modelURL = Bundle.main.url(forResource: "SentimentClassifier", withExtension: "mlmodelc") {
                self.sentimentPredictor = try NLModel(contentsOf: modelURL)
            } else {
                // Fallback to basic sentiment analysis without custom model
                self.sentimentPredictor = nil
                print("⚠️ Custom sentiment model not found, using basic analysis")
            }
        } catch {
            self.sentimentPredictor = nil
            print("⚠️ Failed to load sentiment model: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Analyze sentiment for a conversation's summary and notes
    func analyzeConversation(summary: String?, notes: String?) async -> ConversationAnalysis? {
        let combinedText = buildAnalysisText(summary: summary, notes: notes)
        guard !combinedText.isEmpty else { return nil }
        
        let sentimentResult = performBasicSentimentAnalysis(combinedText)
        let qualityScore = calculateQualityScore(text: combinedText, sentiment: sentimentResult)
        let engagementLevel = determineEngagementLevel(text: combinedText, sentiment: sentimentResult)
        let keyTopics = extractKeyTopics(text: combinedText)
        
        return ConversationAnalysis(
            sentimentResult: sentimentResult,
            qualityScore: qualityScore,
            engagementLevel: engagementLevel,
            keyTopics: keyTopics,
            analysisVersion: currentAnalysisVersion
        )
    }
    
    /// Batch analyze multiple conversations
    func batchAnalyzeConversations(_ conversations: [Conversation]) async -> [UUID: ConversationAnalysis] {
        var results: [UUID: ConversationAnalysis] = [:]
        
        for conversation in conversations {
            guard let uuid = conversation.uuid else { continue }
            
            if let analysis = await analyzeConversation(
                summary: conversation.summary,
                notes: conversation.notes
            ) {
                results[uuid] = analysis
            }
        }
        
        return results
    }
    
    /// Batch analyze multiple conversations with progress callback
    func batchAnalyzeConversations(_ conversations: [Conversation], context: NSManagedObjectContext, progressCallback: @escaping (Int, Int) -> Void) async {
        let conversationsNeedingAnalysis = conversations
            .filter { conversation in
                let lastAnalysis = conversation.value(forKey: "lastSentimentAnalysis") as? Date
                return lastAnalysis == nil
            }
        
        for (index, conversation) in conversationsNeedingAnalysis.enumerated() {
            if let analysis = await analyzeConversation(summary: conversation.summary, notes: conversation.notes) {
                updateConversationWithAnalysis(conversation, analysis: analysis, context: context)
            }
            
            progressCallback(index + 1, conversationsNeedingAnalysis.count)
        }
    }
    
    /// Update conversation with analysis results
    func updateConversationWithAnalysis(_ conversation: Conversation, analysis: ConversationAnalysis, context: NSManagedObjectContext) {
        conversation.setValue(analysis.sentimentResult.score, forKey: "sentimentScore")
        conversation.setValue(analysis.sentimentResult.label, forKey: "sentimentLabel")
        conversation.setValue(analysis.qualityScore, forKey: "qualityScore")
        conversation.setValue(analysis.engagementLevel, forKey: "engagementLevel")
        conversation.setValue(analysis.keyTopics, forKey: "keyTopics")
        conversation.setValue(Date(), forKey: "lastSentimentAnalysis")
        conversation.setValue(analysis.analysisVersion, forKey: "analysisVersion")
        
        do {
            try context.save()
        } catch {
            print("Failed to save conversation analysis: \(error)")
        }
    }
    
    /// AI-powered sentiment analysis for more sophisticated results
    func analyzeConversationWithAI(summary: String?, notes: String?) async -> ConversationAnalysis? {
        let combinedText = buildAnalysisText(summary: summary, notes: notes)
        guard !combinedText.isEmpty else { return nil }
        
        let prompt = """
        Analyze the sentiment and quality of this conversation summary and notes.
        
        Provide detailed analysis including:
        1. Sentiment score (-1.0 to 1.0, where -1 is very negative, 0 is neutral, 1 is very positive)
        2. Confidence level (0.0 to 1.0)
        3. Quality assessment (0.0 to 1.0, based on depth, engagement, and outcomes)
        4. Engagement level (high/medium/low)
        5. Key topics discussed
        
        Format as JSON:
        {
            "sentimentScore": 0.0,
            "sentimentLabel": "positive/negative/neutral",
            "confidence": 0.0,
            "qualityScore": 0.0,
            "engagementLevel": "high/medium/low",
            "keyTopics": ["topic1", "topic2", "topic3"],
            "reasoning": "Brief explanation of the analysis"
        }
        
        Text to analyze:
        \(combinedText)
        """
        
        do {
            let response = try await AIService.shared.sendMessage(prompt)
            return parseAISentimentResponse(response, originalText: combinedText)
        } catch {
            print("AI sentiment analysis failed, falling back to basic analysis: \(error)")
            return await analyzeConversation(summary: summary, notes: notes)
        }
    }
    
    /// Enhanced batch analysis using AI when available
    func batchAnalyzeConversationsWithAI(_ conversations: [Conversation], context: NSManagedObjectContext, progressCallback: @escaping (Int, Int) -> Void) async {
        let conversationsNeedingAnalysis = conversations
            .filter { conversation in
                let lastAnalysis = conversation.value(forKey: "lastSentimentAnalysis") as? Date
                let analysisVersion = conversation.value(forKey: "analysisVersion") as? String
                return lastAnalysis == nil || analysisVersion != currentAnalysisVersion
            }
        
        print("🤖 Starting AI-powered sentiment analysis for \(conversationsNeedingAnalysis.count) conversations")
        
        for (index, conversation) in conversationsNeedingAnalysis.enumerated() {
            // Try AI analysis first, fallback to basic if it fails
            var analysis: ConversationAnalysis?
            
            if !AIService.shared.apiKey.isEmpty {
                analysis = await analyzeConversationWithAI(summary: conversation.summary, notes: conversation.notes)
            }
            
            // Fallback to basic analysis if AI fails
            if analysis == nil {
                analysis = await analyzeConversation(summary: conversation.summary, notes: conversation.notes)
            }
            
            if let analysis = analysis {
                updateConversationWithAnalysis(conversation, analysis: analysis, context: context)
            }
            
            progressCallback(index + 1, conversationsNeedingAnalysis.count)
            
            // Small delay to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        print("✅ Completed sentiment analysis for \(conversationsNeedingAnalysis.count) conversations")
    }
    
    // MARK: - Private Analysis Methods
    
    private func buildAnalysisText(summary: String?, notes: String?) -> String {
        var components: [String] = []
        
        if let summary = summary, !summary.isEmpty {
            components.append(summary)
        }
        
        if let notes = notes, !notes.isEmpty {
            components.append(notes)
        }
        
        return components.joined(separator: " ")
    }
    
    /// Basic sentiment analysis using Apple's Natural Language framework
    public func performBasicSentimentAnalysis(_ text: String) -> SentimentResult {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        let score: Double
        let label: String
        let confidence: Double
        
        if let sentiment = sentiment {
            // Convert sentiment score to our format
            if let scoreValue = Double(sentiment.rawValue) {
                score = scoreValue
                label = scoreValue > 0.1 ? "positive" : (scoreValue < -0.1 ? "negative" : "neutral")
                confidence = abs(scoreValue) // Use absolute value as confidence
            } else {
                score = 0.0
                label = "neutral"
                confidence = 0.5
            }
        } else {
            score = 0.0
            label = "neutral"
            confidence = 0.5
        }
        
        return SentimentResult(score: score, label: label, confidence: confidence)
    }
    
    private func calculateQualityScore(text: String, sentiment: SentimentResult) -> Double {
        var qualityScore = 0.5 // Base score
        
        // Factor in sentiment (positive conversations tend to be higher quality)
        if sentiment.score > 0 {
            qualityScore += sentiment.score * 0.3
        }
        
        // Factor in text length (longer conversations might indicate deeper engagement)
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        if wordCount > 50 {
            qualityScore += 0.2
        } else if wordCount < 20 {
            qualityScore -= 0.1
        }
        
        // Factor in confidence of sentiment analysis
        qualityScore += sentiment.confidence * 0.2
        
        return max(0.0, min(1.0, qualityScore))
    }
    
    private func determineEngagementLevel(text: String, sentiment: SentimentResult) -> String {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let hasActionItems = text.lowercased().contains("action") || text.lowercased().contains("follow up") || text.lowercased().contains("next steps")
        
        // High engagement: Long conversation with positive sentiment or action items
        if (wordCount > 100 && sentiment.score > 0.2) || hasActionItems {
            return "high"
        }
        
        // Low engagement: Short conversation with negative sentiment
        if wordCount < 30 && sentiment.score < -0.2 {
            return "low"
        }
        
        return "medium"
    }
    
    private func extractKeyTopics(text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var topics: Set<String> = []
        
        // Extract named entities as potential topics
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if tag != nil {
                let token = String(text[tokenRange])
                if token.count > 2 && !token.allSatisfy({ $0.isNumber }) {
                    topics.insert(token.lowercased())
                }
            }
            return true
        }
        
        // Add common business/meeting keywords if present
        let businessKeywords = ["project", "deadline", "budget", "team", "client", "meeting", "presentation", "review", "planning", "strategy"]
        for keyword in businessKeywords {
            if text.lowercased().contains(keyword) {
                topics.insert(keyword)
            }
        }
        
        let topicsArray = Array(topics)
        let limitedTopics = topicsArray.count > 10 ? Array(topicsArray[0..<10]) : topicsArray
        return limitedTopics.map { String($0) }
    }
    
    // MARK: - AI Response Parsing
    
    private func parseAISentimentResponse(_ response: String, originalText: String) -> ConversationAnalysis? {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Failed to parse AI sentiment response, using fallback")
            return parseAISentimentFallback(response, originalText: originalText)
        }
        
        let sentimentScore = json["sentimentScore"] as? Double ?? 0.0
        let sentimentLabel = json["sentimentLabel"] as? String ?? "neutral"
        let confidence = json["confidence"] as? Double ?? 0.5
        let qualityScore = json["qualityScore"] as? Double ?? 0.5
        let engagementLevel = json["engagementLevel"] as? String ?? "medium"
        let keyTopics = json["keyTopics"] as? [String] ?? []
        
        let sentimentResult = SentimentResult(
            score: sentimentScore,
            label: sentimentLabel,
            confidence: confidence
        )
        
        return ConversationAnalysis(
            sentimentResult: sentimentResult,
            qualityScore: qualityScore,
            engagementLevel: engagementLevel,
            keyTopics: keyTopics,
            analysisVersion: currentAnalysisVersion
        )
    }
    
    private func parseAISentimentFallback(_ response: String, originalText: String) -> ConversationAnalysis? {
        // Extract sentiment information from unstructured response
        let lines = response.components(separatedBy: .newlines)
        var sentimentScore = 0.0
        var confidence = 0.5
        var qualityScore = 0.5
        var engagementLevel = "medium"
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("positive") {
                sentimentScore = 0.5
            } else if lowercased.contains("negative") {
                sentimentScore = -0.5
            } else if lowercased.contains("very positive") || lowercased.contains("highly positive") {
                sentimentScore = 0.8
            } else if lowercased.contains("very negative") || lowercased.contains("highly negative") {
                sentimentScore = -0.8
            }
            
            if lowercased.contains("high") && lowercased.contains("confidence") {
                confidence = 0.8
            } else if lowercased.contains("low") && lowercased.contains("confidence") {
                confidence = 0.3
            }
            
            if lowercased.contains("high") && lowercased.contains("quality") {
                qualityScore = 0.8
            } else if lowercased.contains("low") && lowercased.contains("quality") {
                qualityScore = 0.3
            }
            
            if lowercased.contains("high engagement") {
                engagementLevel = "high"
            } else if lowercased.contains("low engagement") {
                engagementLevel = "low"
            }
        }
        
        let sentimentLabel = sentimentScore > 0.1 ? "positive" : (sentimentScore < -0.1 ? "negative" : "neutral")
        let keyTopics = extractKeyTopics(text: originalText)
        
        let sentimentResult = SentimentResult(
            score: sentimentScore,
            label: sentimentLabel,
            confidence: confidence
        )
        
        return ConversationAnalysis(
            sentimentResult: sentimentResult,
            qualityScore: qualityScore,
            engagementLevel: engagementLevel,
            keyTopics: keyTopics,
            analysisVersion: currentAnalysisVersion
        )
    }
}

// MARK: - Relationship Health Calculator

class RelationshipHealthCalculator {
    static let shared = RelationshipHealthCalculator()
    
    /// Calculate overall relationship health score for a person (legacy method)
    func calculateHealthScore(for person: Person) -> Double {
        return calculateHealthScore(for: person, relationshipType: .other)
    }
    
    /// Calculate context-aware relationship health score for a person
    func calculateHealthScore(for person: Person, relationshipType: RelationshipType) -> Double {
        guard let conversations = person.conversations?.allObjects as? [Conversation],
              !conversations.isEmpty else {
            return 0.5 // Neutral score for no data
        }
        
        let recentConversations = conversations
            .filter { conversation in
                let lastAnalysis = conversation.value(forKey: "lastSentimentAnalysis") as? Date
                return lastAnalysis != nil
            }
            .sorted { ($0.value(forKey: "date") as? Date ?? Date.distantPast) > ($1.value(forKey: "date") as? Date ?? Date.distantPast) }
            .prefix(10) // Consider last 10 analyzed conversations
        
        guard !recentConversations.isEmpty else {
            return 0.5
        }
        
        // Calculate average sentiment with recency weighting
        var weightedSentimentSum = 0.0
        var totalWeight = 0.0
        
        for (index, conversation) in recentConversations.enumerated() {
            let weight = 1.0 / Double(index + 1) // More recent conversations have higher weight
            weightedSentimentSum += (conversation.value(forKey: "sentimentScore") as? Double ?? 0.0) * weight
            totalWeight += weight
        }
        
        let averageSentiment = weightedSentimentSum / totalWeight
        
        // Convert sentiment (-1 to 1) to health score (0 to 1)
        var baseHealthScore = (averageSentiment + 1.0) / 2.0
        
        // Apply relationship type context adjustments
        baseHealthScore = applyRelationshipTypeAdjustments(
            baseScore: baseHealthScore,
            person: person,
            relationshipType: relationshipType,
            conversations: Array(recentConversations)
        )
        
        // Apply relationship type weighting
        return baseHealthScore * relationshipType.healthScoreWeight
    }
    
    /// Apply relationship type-specific adjustments to health score
    private func applyRelationshipTypeAdjustments(
        baseScore: Double,
        person: Person,
        relationshipType: RelationshipType,
        conversations: [Conversation]
    ) -> Double {
        var adjustedScore = baseScore
        
        // Check meeting frequency adherence
        let daysSinceLastConversation = getDaysSinceLastConversation(person: person)
        let expectedFrequency = relationshipType.expectedMeetingFrequencyDays
        let overdueThreshold = Double(expectedFrequency) * relationshipType.overdueThresholdMultiplier
        
        if daysSinceLastConversation > overdueThreshold {
            // Penalize overdue conversations more severely for direct reports
            let overduePenalty = relationshipType == .directReport ? 0.3 : 0.2
            adjustedScore -= overduePenalty
        }
        
        // Check duration alignment with relationship type
        let averageDuration = conversations.map { conversation in
            Double(conversation.value(forKey: "duration") as? Int32 ?? 0)
        }.reduce(0, +) / Double(conversations.count)
        
        let optimalRange = relationshipType.optimalDurationRange
        if averageDuration < optimalRange.lowerBound || averageDuration > optimalRange.upperBound {
            // Small penalty for duration misalignment
            adjustedScore -= 0.1
        }
        
        // Relationship type specific bonuses/penalties
        switch relationshipType {
        case .directReport:
            // Direct reports should have more consistent communication
            let consistencyBonus = calculateConsistencyBonus(conversations: conversations)
            adjustedScore += consistencyBonus
            
        case .skipLevel:
            // Skip level meetings should focus on feedback - check for engagement
            let engagementBonus = calculateEngagementBonus(conversations: conversations)
            adjustedScore += engagementBonus
            
        case .other:
            // No specific adjustments for other relationships
            break
        }
        
        // Ensure score stays within bounds
        return max(0.0, min(1.0, adjustedScore))
    }
    
    /// Calculate consistency bonus for direct reports based on regular meeting patterns
    private func calculateConsistencyBonus(conversations: [Conversation]) -> Double {
        guard conversations.count >= 3 else { return 0.0 }
        
        let dates = conversations.compactMap { $0.value(forKey: "date") as? Date }.sorted(by: >)
        guard dates.count >= 3 else { return 0.0 }
        
        // Calculate intervals between meetings
        var intervals: [TimeInterval] = []
        for i in 0..<(dates.count - 1) {
            intervals.append(dates[i].timeIntervalSince(dates[i + 1]))
        }
        
        // Check consistency (lower standard deviation = more consistent)
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let standardDeviation = sqrt(variance)
        
        // Convert to days and calculate bonus (more consistent = higher bonus)
        let avgDays = avgInterval / 86400 // Convert seconds to days
        let stdDevDays = standardDeviation / 86400
        
        // Bonus for consistency (max 0.1 bonus)
        if avgDays <= 14 && stdDevDays <= 3 { // Weekly/bi-weekly with low variation
            return 0.1
        } else if avgDays <= 21 && stdDevDays <= 5 { // Somewhat consistent
            return 0.05
        }
        
        return 0.0
    }
    
    /// Calculate engagement bonus for skip level meetings based on conversation depth
    private func calculateEngagementBonus(conversations: [Conversation]) -> Double {
        guard !conversations.isEmpty else { return 0.0 }
        
        // Check for meaningful duration (skip levels should be substantial)
        let averageDuration = conversations.map { conversation in
            Double(conversation.value(forKey: "duration") as? Int32 ?? 0)
        }.reduce(0, +) / Double(conversations.count)
        
        // Check for sentiment depth (skip levels should surface real feedback)
        let sentimentVariance = calculateSentimentVariance(conversations: conversations)
        
        var bonus = 0.0
        
        // Bonus for appropriate duration (25-35 minutes optimal for skip levels)
        if averageDuration >= 25 && averageDuration <= 35 {
            bonus += 0.05
        }
        
        // Bonus for sentiment variance (indicates real feedback, not just pleasantries)
        if sentimentVariance > 0.1 {
            bonus += 0.05
        }
        
        return bonus
    }
    
    /// Calculate sentiment variance to detect meaningful feedback sessions
    private func calculateSentimentVariance(conversations: [Conversation]) -> Double {
        let sentiments = conversations.compactMap { $0.value(forKey: "sentimentScore") as? Double }
        guard sentiments.count > 1 else { return 0.0 }
        
        let average = sentiments.reduce(0, +) / Double(sentiments.count)
        let variance = sentiments.map { pow($0 - average, 2) }.reduce(0, +) / Double(sentiments.count)
        
        return variance
    }
    
    /// Get days since last conversation
    private func getDaysSinceLastConversation(person: Person) -> Double {
        guard let lastDate = person.lastContactDate else { return Double.infinity }
        return Date().timeIntervalSince(lastDate) / 86400 // Convert to days
    }
    
    /// Get trend direction for relationship
    func getTrendDirection(for person: Person) -> String {
        guard let conversations = person.conversations?.allObjects as? [Conversation],
              conversations.count >= 3 else {
            return "stable"
        }
        
        let recentConversations = conversations
            .filter { conversation in
                let lastAnalysis = conversation.value(forKey: "lastSentimentAnalysis") as? Date
                return lastAnalysis != nil
            }
            .sorted { ($0.value(forKey: "date") as? Date ?? Date.distantPast) > ($1.value(forKey: "date") as? Date ?? Date.distantPast) }
            .prefix(5)
        
        guard recentConversations.count >= 3 else {
            return "stable"
        }
        
        let recentAvg = Array(recentConversations.prefix(2)).map { $0.value(forKey: "sentimentScore") as? Double ?? 0.0 }.reduce(0, +) / 2.0
        let olderAvg = Array(recentConversations.suffix(2)).map { $0.value(forKey: "sentimentScore") as? Double ?? 0.0 }.reduce(0, +) / 2.0
        
        let difference = recentAvg - olderAvg
        
        if difference > 0.2 {
            return "improving"
        } else if difference < -0.2 {
            return "declining"
        } else {
            return "stable"
        }
    }
}
