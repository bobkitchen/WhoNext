import Foundation
import CoreData

// MARK: - Duration Analytics Models

struct ConversationMetrics {
    let averageDuration: Double // in minutes
    let totalDuration: Double // in minutes
    let conversationCount: Int
    let averageSentimentPerMinute: Double
    let optimalDurationRange: ClosedRange<Double> // suggested duration range
}

struct PersonMetrics {
    let person: Person
    let metrics: ConversationMetrics
    let healthScore: Double
    let trendDirection: String
    let lastConversationDate: Date?
    let daysSinceLastConversation: Int
}

struct DurationInsight {
    let type: InsightType
    let title: String
    let description: String
    let actionable: Bool
    let priority: Priority
    
    enum InsightType {
        case optimalDuration
        case overCommunicating
        case underCommunicating
        case efficiencyImprovement
        case relationshipAlert
    }
    
    enum Priority {
        case high, medium, low
    }
}

// MARK: - Conversation Metrics Calculator

class ConversationMetricsCalculator {
    static let shared = ConversationMetricsCalculator()
    
    // MARK: - Duration Analytics
    
    /// Calculate comprehensive metrics for a person's conversations
    func calculateMetrics(for person: Person) -> PersonMetrics? {
        guard let conversations = person.conversations?.allObjects as? [Conversation],
              !conversations.isEmpty else {
            return nil
        }
        
        let validConversations = conversations.filter { conversation in
            let duration = conversation.value(forKey: "duration") as? Int32 ?? 0
            return duration > 0 || !(conversation.notes?.isEmpty ?? true)
        }
        
        guard !validConversations.isEmpty else {
            return nil
        }
        
        let metrics = calculateConversationMetrics(validConversations)
        let healthScore = RelationshipHealthCalculator.shared.calculateHealthScore(for: person)
        let trendDirection = RelationshipHealthCalculator.shared.getTrendDirection(for: person)
        let totalConversations = validConversations.count
        let lastConversationDate = validConversations.compactMap { $0.date }.max()
        
        // Calculate days since last conversation
        let daysSinceLastConversation = lastConversationDate.map { 
            Calendar.current.dateInterval(of: .day, for: $0)?.duration ?? 0 
        } ?? 0
        
        return PersonMetrics(
            person: person,
            metrics: metrics,
            healthScore: healthScore,
            trendDirection: trendDirection,
            lastConversationDate: lastConversationDate,
            daysSinceLastConversation: Int(daysSinceLastConversation / 86400) // Convert seconds to days
        )
    }
    
    /// Calculate metrics for a collection of conversations
    private func calculateConversationMetrics(_ conversations: [Conversation]) -> ConversationMetrics {
        let durations = conversations.map { conversation in
            let duration = conversation.value(forKey: "duration") as? Int32 ?? 0
            return Double(duration)
        }
        let totalDuration = durations.reduce(0, +)
        let averageDuration = totalDuration / Double(conversations.count)
        
        // Calculate sentiment per minute
        let sentimentPerMinuteValues = conversations.compactMap { conversation -> Double? in
            guard let sentimentScore = conversation.value(forKey: "sentimentScore") as? Double else { return nil }
            let duration = conversation.value(forKey: "duration") as? Int32 ?? 0
            guard duration > 0 else { return nil }
            return sentimentScore / Double(duration)
        }
        
        let averageSentimentPerMinute = sentimentPerMinuteValues.isEmpty ? 0.0 : 
            sentimentPerMinuteValues.reduce(0, +) / Double(sentimentPerMinuteValues.count)
        
        // Determine optimal duration range based on historical data
        let optimalDurationRange = calculateOptimalDurationRange(conversations)
        
        return ConversationMetrics(
            averageDuration: averageDuration,
            totalDuration: totalDuration,
            conversationCount: conversations.count,
            averageSentimentPerMinute: averageSentimentPerMinute,
            optimalDurationRange: optimalDurationRange
        )
    }
    
    /// Calculate optimal conversation duration range based on sentiment correlation
    private func calculateOptimalDurationRange(_ conversations: [Conversation]) -> ClosedRange<Double> {
        // Find conversations with highest sentiment scores
        let positiveConversations = conversations.filter { conversation in
            guard let sentimentScore = conversation.value(forKey: "sentimentScore") as? Double else { return false }
            return sentimentScore > 0.3
        }
        
        if positiveConversations.count >= 3 {
            let positiveDurations = positiveConversations.map { conversation in
                let duration = conversation.value(forKey: "duration") as? Int32 ?? 0
                return Double(duration)
            }.sorted()
            let lowerBound = positiveDurations[positiveDurations.count / 4] // 25th percentile
            let upperBound = positiveDurations[positiveDurations.count * 3 / 4] // 75th percentile
            return max(15, lowerBound)...min(120, upperBound) // Reasonable bounds
        } else {
            return 30.0...60.0 // Default range
        }
    }
    
    // MARK: - Insights Generation
    
    /// Generate duration-based insights for a person
    func generateInsights(for personMetrics: PersonMetrics) -> [DurationInsight] {
        var insights: [DurationInsight] = []
        
        // Check for optimal duration insights
        if let optimalInsight = generateOptimalDurationInsight(personMetrics) {
            insights.append(optimalInsight)
        }
        
        // Check for over/under communication patterns
        if let communicationInsight = generateCommunicationPatternInsight(personMetrics) {
            insights.append(communicationInsight)
        }
        
        // Check for efficiency improvements
        if let efficiencyInsight = generateEfficiencyInsight(personMetrics) {
            insights.append(efficiencyInsight)
        }
        
        // Check for relationship alerts
        if let relationshipInsight = generateRelationshipAlert(personMetrics) {
            insights.append(relationshipInsight)
        }
        
        return insights
    }
    
    private func generateOptimalDurationInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let metrics = personMetrics.metrics
        let currentAverage = metrics.averageDuration
        let optimalRange = metrics.optimalDurationRange
        
        if currentAverage < optimalRange.lowerBound {
            return DurationInsight(
                type: .optimalDuration,
                title: "Consider Longer Conversations",
                description: "Your conversations with \(personMetrics.person.name ?? "this person") average \(Int(currentAverage)) minutes. Data suggests \(Int(optimalRange.lowerBound))-\(Int(optimalRange.upperBound)) minutes yields better outcomes.",
                actionable: true,
                priority: .medium
            )
        } else if currentAverage > optimalRange.upperBound {
            return DurationInsight(
                type: .optimalDuration,
                title: "Conversations May Be Too Long",
                description: "Your conversations average \(Int(currentAverage)) minutes. Consider more focused \(Int(optimalRange.lowerBound))-\(Int(optimalRange.upperBound)) minute sessions for better efficiency.",
                actionable: true,
                priority: .medium
            )
        }
        
        return nil
    }
    
    private func generateCommunicationPatternInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let daysSince = personMetrics.daysSinceLastConversation
        let isDirectReport = personMetrics.person.isDirectReport
        
        if isDirectReport && daysSince > 14 {
            return DurationInsight(
                type: .underCommunicating,
                title: "Direct Report Check-in Overdue",
                description: "It's been \(daysSince) days since your last conversation with \(personMetrics.person.name ?? "this direct report"). Consider scheduling a check-in.",
                actionable: true,
                priority: .high
            )
        } else if daysSince > 30 {
            return DurationInsight(
                type: .underCommunicating,
                title: "Long Time Since Last Conversation",
                description: "It's been \(daysSince) days since your last conversation. Consider reaching out to maintain the relationship.",
                actionable: true,
                priority: .medium
            )
        }
        
        return nil
    }
    
    private func generateEfficiencyInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let sentimentPerMinute = personMetrics.metrics.averageSentimentPerMinute
        
        if sentimentPerMinute < 0.01 && personMetrics.metrics.averageDuration > 60 {
            return DurationInsight(
                type: .efficiencyImprovement,
                title: "Consider Shorter, More Focused Meetings",
                description: "Long conversations with low sentiment per minute suggest meetings could be more efficient. Try shorter, agenda-driven sessions.",
                actionable: true,
                priority: .medium
            )
        }
        
        return nil
    }
    
    private func generateRelationshipAlert(_ personMetrics: PersonMetrics) -> DurationInsight? {
        if personMetrics.healthScore < 0.3 && personMetrics.trendDirection == "declining" {
            return DurationInsight(
                type: .relationshipAlert,
                title: "Relationship Needs Attention",
                description: "Declining sentiment trend with \(personMetrics.person.name ?? "this person"). Consider scheduling a one-on-one to address any concerns.",
                actionable: true,
                priority: .high
            )
        }
        
        return nil
    }
    
    // MARK: - Batch Analytics
    
    /// Calculate metrics for all people with conversations
    func calculateAllPersonMetrics(context: NSManagedObjectContext) -> [PersonMetrics] {
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "conversations.@count > 0")
        
        do {
            let people = try context.fetch(request)
            return people.compactMap { calculateMetrics(for: $0) }
        } catch {
            print("Failed to fetch people for metrics calculation: \(error)")
            return []
        }
    }
    
    /// Get aggregate statistics across all relationships
    func getAggregateStatistics(context: NSManagedObjectContext) -> (averageDuration: Double, totalConversations: Int, averageHealthScore: Double) {
        let allMetrics = calculateAllPersonMetrics(context: context)
        
        guard !allMetrics.isEmpty else {
            return (0, 0, 0)
        }
        
        let totalDuration = allMetrics.map { $0.metrics.averageDuration }.reduce(0, +)
        let averageDuration = totalDuration / Double(allMetrics.count)
        
        let totalConversations = allMetrics.map { $0.metrics.conversationCount }.reduce(0, +)
        
        let totalHealthScore = allMetrics.map { $0.healthScore }.reduce(0, +)
        let averageHealthScore = totalHealthScore / Double(allMetrics.count)
        
        return (averageDuration, totalConversations, averageHealthScore)
    }
}
