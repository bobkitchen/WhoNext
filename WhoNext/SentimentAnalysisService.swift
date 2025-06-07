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
    private func performBasicSentimentAnalysis(_ text: String) -> SentimentResult {
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
            if let tag = tag {
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
        
        return Array(topics.prefix(5)) // Limit to top 5 topics
    }
}

// MARK: - Relationship Health Calculator

class RelationshipHealthCalculator {
    static let shared = RelationshipHealthCalculator()
    
    /// Calculate overall relationship health score for a person
    func calculateHealthScore(for person: Person) -> Double {
        guard let conversations = person.conversations?.allObjects as? [Conversation],
              !conversations.isEmpty else {
            return 0.5 // Neutral score for no data
        }
        
        let recentConversations = conversations
            .filter { $0.value(forKey: "lastSentimentAnalysis") != nil }
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
        return (averageSentiment + 1.0) / 2.0
    }
    
    /// Get trend direction for relationship
    func getTrendDirection(for person: Person) -> String {
        guard let conversations = person.conversations?.allObjects as? [Conversation],
              conversations.count >= 3 else {
            return "stable"
        }
        
        let recentConversations = conversations
            .filter { $0.value(forKey: "lastSentimentAnalysis") != nil }
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
