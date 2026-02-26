import Foundation
import CoreData

// MARK: - Metrics Caching

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
    let relationshipType: RelationshipType
    let isOverdue: Bool
    let contextualInsights: [String]
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

// MARK: - Relationship Type Classification

enum RelationshipType {
    case directReport
    case teammate
    case colleague
    case external

    var expectedMeetingFrequencyDays: Int {
        switch self {
        case .directReport: return 10
        case .teammate: return 14
        case .colleague: return 30
        case .external: return 90
        }
    }

    var optimalDurationRange: ClosedRange<Double> {
        switch self {
        case .directReport: return 45...60
        case .teammate: return 30...45
        case .colleague: return 20...45
        case .external: return 30...60
        }
    }

    var overdueThresholdMultiplier: Double {
        switch self {
        case .directReport: return 1.5   // 15 days
        case .teammate: return 2.0       // 28 days
        case .colleague: return 2.0      // 60 days
        case .external: return 2.0       // 180 days
        }
    }

    var healthScoreWeight: Double {
        switch self {
        case .directReport: return 1.0
        case .teammate: return 0.9
        case .colleague: return 0.8
        case .external: return 0.6
        }
    }

    var description: String {
        switch self {
        case .directReport: return "Direct Report"
        case .teammate: return "Teammate"
        case .colleague: return "Colleague"
        case .external: return "External"
        }
    }
}

// MARK: - Conversation Metrics Calculator

class ConversationMetricsCalculator {
    static let shared = ConversationMetricsCalculator()
    
    // MARK: - Caching Properties
    private var metricsCache: [UUID: PersonMetrics] = [:]
    private var cacheTimestamps: [UUID: Date] = [:]
    private var aggregateCache: (averageDuration: Double, totalConversations: Int, averageHealthScore: Double)?
    private var aggregateCacheTimestamp: Date?
    private let cacheExpirationInterval: TimeInterval = 600 // 10 minutes
    
    // MARK: - Caching Methods
    
    private func getCachedMetrics(for personId: UUID) -> PersonMetrics? {
        guard let cached = metricsCache[personId],
              let timestamp = cacheTimestamps[personId],
              Date().timeIntervalSince(timestamp) < cacheExpirationInterval else {
            return nil
        }
        return cached
    }
    
    private func cacheMetrics(_ metrics: PersonMetrics, for personId: UUID) {
        metricsCache[personId] = metrics
        cacheTimestamps[personId] = Date()
    }
    
    func invalidateMetricsCache() {
        metricsCache.removeAll()
        cacheTimestamps.removeAll()
        aggregateCache = nil
        aggregateCacheTimestamp = nil
    }
    
    func invalidateMetricsCache(for personId: UUID) {
        metricsCache.removeValue(forKey: personId)
        cacheTimestamps.removeValue(forKey: personId)
        // Invalidate aggregate cache when individual person metrics change
        aggregateCache = nil
        aggregateCacheTimestamp = nil
    }
    
    // MARK: - Relationship Type Classification
    
    /// Classify relationship type based on person category
    func classifyRelationshipType(for person: Person) -> RelationshipType {
        switch person.category {
        case .directReport: return .directReport
        case .teammate: return .teammate
        case .colleague: return .colleague
        case .external: return .external
        }
    }
    
    // MARK: - Context-Aware Duration Analytics
    
    /// Calculate comprehensive metrics for a person's conversations with relationship context
    func calculateMetrics(for person: Person) -> PersonMetrics? {
        // Check cache first
        if let personId = person.identifier,
           let cached = getCachedMetrics(for: personId) {
            return cached
        }
        
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
        
        let relationshipType = classifyRelationshipType(for: person)
        let metrics = calculateConversationMetrics(validConversations, relationshipType: relationshipType)
        let healthScore = RelationshipHealthCalculator.shared.calculateHealthScore(for: person, relationshipType: relationshipType)
        let trendDirection = RelationshipHealthCalculator.shared.getTrendDirection(for: person)
        let totalConversations = validConversations.count
        let lastConversationDate = validConversations.compactMap { $0.date }.max()
        
        // Calculate days since last conversation
        let daysSinceLastConversation = lastConversationDate.map { 
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 
        } ?? 0
        
        let isOverdue = Double(daysSinceLastConversation) > Double(relationshipType.expectedMeetingFrequencyDays) * relationshipType.overdueThresholdMultiplier
        
        let contextualInsights = generateContextualInsights(for: person, relationshipType: relationshipType, metrics: metrics)
        
        let result = PersonMetrics(
            person: person,
            metrics: metrics,
            healthScore: healthScore,
            trendDirection: trendDirection,
            lastConversationDate: lastConversationDate,
            daysSinceLastConversation: daysSinceLastConversation,
            relationshipType: relationshipType,
            isOverdue: isOverdue,
            contextualInsights: contextualInsights
        )
        
        // Cache the result
        if let personId = person.identifier {
            cacheMetrics(result, for: personId)
        }
        
        return result
    }
    
    /// Calculate metrics for a collection of conversations with relationship context
    private func calculateConversationMetrics(_ conversations: [Conversation], relationshipType: RelationshipType) -> ConversationMetrics {
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
        
        // Determine optimal duration range based on relationship type
        let optimalDurationRange = relationshipType.optimalDurationRange
        
        return ConversationMetrics(
            averageDuration: averageDuration,
            totalDuration: totalDuration,
            conversationCount: conversations.count,
            averageSentimentPerMinute: averageSentimentPerMinute,
            optimalDurationRange: optimalDurationRange
        )
    }
    
    /// Generate contextual insights for a person based on relationship type and metrics
    private func generateContextualInsights(for person: Person, relationshipType: RelationshipType, metrics: ConversationMetrics) -> [String] {
        var insights: [String] = []
        
        // Check for optimal duration insights
        if let optimalInsight = generateOptimalDurationInsight(person, relationshipType: relationshipType, metrics: metrics) {
            insights.append(optimalInsight)
        }
        
        // Check for over/under communication patterns
        if let communicationInsight = generateCommunicationPatternInsight(person, relationshipType: relationshipType, metrics: metrics) {
            insights.append(communicationInsight)
        }
        
        // Check for efficiency improvements
        if let efficiencyInsight = generateEfficiencyInsight(person, relationshipType: relationshipType, metrics: metrics) {
            insights.append(efficiencyInsight)
        }
        
        // Check for relationship alerts
        if let relationshipInsight = generateRelationshipAlert(person, relationshipType: relationshipType, metrics: metrics) {
            insights.append(relationshipInsight)
        }
        
        return insights
    }
    
    // MARK: - Context-Aware Insight Generation Methods
    
    /// Generate optimal duration insight based on relationship type
    private func generateOptimalDurationInsight(_ person: Person, relationshipType: RelationshipType, metrics: ConversationMetrics) -> String? {
        let optimalRange = relationshipType.optimalDurationRange
        let avgDuration = metrics.averageDuration
        
        if avgDuration < optimalRange.lowerBound {
            let shortfall = optimalRange.lowerBound - avgDuration
            return "Consider extending \(relationshipType.description.lowercased()) meetings by ~\(Int(shortfall)) minutes for better engagement"
        } else if avgDuration > optimalRange.upperBound {
            let excess = avgDuration - optimalRange.upperBound
            return "Meetings are running \(Int(excess)) minutes longer than optimal for \(relationshipType.description.lowercased()) relationships"
        }
        
        return nil
    }
    
    /// Generate communication pattern insight based on relationship type
    private func generateCommunicationPatternInsight(_ person: Person, relationshipType: RelationshipType, metrics: ConversationMetrics) -> String? {
        let expectedFrequency = relationshipType.expectedMeetingFrequencyDays
        let lastConversationDays = Calendar.current.dateComponents([.day], from: person.mostRecentContactDate ?? .distantPast, to: Date()).day ?? 0
        let daysSince = lastConversationDays
        
        if daysSince > Int(Double(expectedFrequency) * relationshipType.overdueThresholdMultiplier) {
            switch relationshipType {
            case .directReport:
                return "Direct report check-in is overdue - last conversation was \(daysSince) days ago"
            case .teammate:
                return "Teammate catch-up may be due - last conversation was \(daysSince) days ago"
            case .colleague:
                return "Consider scheduling a catch-up - last conversation was \(daysSince) days ago"
            case .external:
                return "External contact follow-up may be due - last conversation was \(daysSince) days ago"
            }
        }
        
        return nil
    }
    
    /// Generate efficiency insight based on relationship type and conversation patterns
    private func generateEfficiencyInsight(_ person: Person, relationshipType: RelationshipType, metrics: ConversationMetrics) -> String? {
        let sentimentPerMinute = metrics.averageSentimentPerMinute
        
        if sentimentPerMinute < 0.01 && metrics.averageDuration > relationshipType.optimalDurationRange.upperBound {
            switch relationshipType {
            case .directReport:
                return "Consider more structured 1:1 agendas to improve engagement efficiency"
            case .teammate:
                return "Teammate meetings could benefit from more focused agendas"
            case .colleague:
                return "Consider shorter, more focused conversations for better engagement"
            case .external:
                return "External meetings could benefit from tighter preparation"
            }
        }
        
        return nil
    }
    
    /// Generate relationship alert based on sentiment trends and relationship type
    private func generateRelationshipAlert(_ person: Person, relationshipType: RelationshipType, metrics: ConversationMetrics) -> String? {
        let healthScore = RelationshipHealthCalculator.shared.calculateHealthScore(for: person, relationshipType: relationshipType)
        
        if healthScore < 0.4 {
            switch relationshipType {
            case .directReport:
                return "Direct report relationship needs attention - consider additional support or feedback"
            case .teammate:
                return "Teammate relationship showing low engagement - consider reaching out"
            case .colleague:
                return "Relationship health is declining - consider proactive outreach"
            case .external:
                return "External relationship may need a follow-up"
            }
        }
        
        return nil
    }
    
    // MARK: - Legacy Insight Generation (Updated for Compatibility)
    
    /// Generate duration-based insights for a person with relationship context
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
    
    // MARK: - Individual Insight Generators (Updated)
    
    private func generateOptimalDurationInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let optimalRange = personMetrics.relationshipType.optimalDurationRange
        let avgDuration = personMetrics.metrics.averageDuration
        
        if avgDuration < optimalRange.lowerBound {
            let shortfall = optimalRange.lowerBound - avgDuration
            return DurationInsight(
                type: .optimalDuration,
                title: "Extend \(personMetrics.relationshipType.description) Meetings",
                description: "Average duration is \(Int(shortfall)) minutes below optimal range for \(personMetrics.relationshipType.description.lowercased()) relationships",
                actionable: true,
                priority: .medium
            )
        } else if avgDuration > optimalRange.upperBound {
            let excess = avgDuration - optimalRange.upperBound
            return DurationInsight(
                type: .efficiencyImprovement,
                title: "Optimize \(personMetrics.relationshipType.description) Meeting Length",
                description: "Meetings run \(Int(excess)) minutes longer than optimal. Consider more focused agendas",
                actionable: true,
                priority: .low
            )
        }
        
        return nil
    }
    
    private func generateCommunicationPatternInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let daysSince = personMetrics.daysSinceLastConversation
        let relationshipType = personMetrics.relationshipType
        
        if daysSince > Int(Double(relationshipType.expectedMeetingFrequencyDays) * relationshipType.overdueThresholdMultiplier) {
            switch relationshipType {
            case .directReport:
                return DurationInsight(
                    type: .underCommunicating,
                    title: "Direct Report Check-in Overdue",
                    description: "Last conversation was \(daysSince) days ago. Direct reports should be contacted weekly or bi-weekly",
                    actionable: true,
                    priority: .high
                )
            case .teammate:
                return DurationInsight(
                    type: .underCommunicating,
                    title: "Teammate Catch-up Due",
                    description: "Last conversation was \(daysSince) days ago. Consider scheduling a teammate sync",
                    actionable: true,
                    priority: .medium
                )
            case .colleague:
                return DurationInsight(
                    type: .underCommunicating,
                    title: "Long Time Since Last Conversation",
                    description: "Last conversation was \(daysSince) days ago. Consider reaching out",
                    actionable: true,
                    priority: .medium
                )
            case .external:
                return DurationInsight(
                    type: .relationshipAlert,
                    title: "External Follow-up Due",
                    description: "Last conversation was \(daysSince) days ago. Consider a follow-up",
                    actionable: true,
                    priority: .low
                )
            }
        }
        
        return nil
    }
    
    private func generateEfficiencyInsight(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let sentimentPerMinute = personMetrics.metrics.averageSentimentPerMinute
        let avgDuration = personMetrics.metrics.averageDuration
        let relationshipType = personMetrics.relationshipType
        
        if sentimentPerMinute < 0.01 && avgDuration > relationshipType.optimalDurationRange.upperBound {
            return DurationInsight(
                type: .efficiencyImprovement,
                title: "Improve \(relationshipType.description) Meeting Efficiency",
                description: "Low engagement per minute suggests need for more structured approach",
                actionable: true,
                priority: .medium
            )
        }
        
        return nil
    }
    
    private func generateRelationshipAlert(_ personMetrics: PersonMetrics) -> DurationInsight? {
        let healthScore = personMetrics.healthScore
        let relationshipType = personMetrics.relationshipType
        
        if healthScore < 0.4 {
            return DurationInsight(
                type: .relationshipAlert,
                title: "\(relationshipType.description) Relationship Needs Attention",
                description: "Health score is \(String(format: "%.1f", healthScore * 100))%. Consider additional support or feedback",
                actionable: true,
                priority: relationshipType == .directReport ? .high : .medium
            )
        }
        
        return nil
    }
    
    // MARK: - Batch Analytics
    
    /// Calculate metrics for all people with conversations (optimized with prefetching)
    func calculateAllPersonMetrics(context: NSManagedObjectContext) -> [PersonMetrics] {
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "conversations.@count > 0")
        // Prefetch conversations to avoid N+1 queries
        request.relationshipKeyPathsForPrefetching = ["conversations"]
        request.fetchBatchSize = 50
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
        
        do {
            let people = try context.fetch(request)
            return people.compactMap { calculateMetrics(for: $0) }
        } catch {
            print("Failed to fetch people for metrics calculation: \(error)")
            return []
        }
    }
    
    /// Get aggregate statistics across all relationships (cached)
    func getAggregateStatistics(context: NSManagedObjectContext) -> (averageDuration: Double, totalConversations: Int, averageHealthScore: Double) {
        // Check cache first
        if let cached = aggregateCache,
           let timestamp = aggregateCacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheExpirationInterval {
            return cached
        }
        
        let allMetrics = calculateAllPersonMetrics(context: context)
        
        guard !allMetrics.isEmpty else {
            return (0, 0, 0)
        }
        
        let totalDuration = allMetrics.map { $0.metrics.averageDuration }.reduce(0, +)
        let averageDuration = totalDuration / Double(allMetrics.count)
        
        let totalConversations = allMetrics.map { $0.metrics.conversationCount }.reduce(0, +)
        
        let totalHealthScore = allMetrics.map { $0.healthScore }.reduce(0, +)
        let averageHealthScore = totalHealthScore / Double(allMetrics.count)
        
        let result = (averageDuration, totalConversations, averageHealthScore)
        
        // Cache the result
        aggregateCache = result
        aggregateCacheTimestamp = Date()
        
        return result
    }
}
