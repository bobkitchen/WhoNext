import Foundation

// MARK: - Relationship Trend

enum RelationshipTrend: String, Codable {
    case improving
    case stable
    case declining

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    var displayText: String {
        rawValue.capitalized
    }
}

// MARK: - Engagement Quality

enum EngagementQuality: String, Codable {
    case productive
    case routine
    case challenging

    var icon: String {
        switch self {
        case .productive: return "checkmark.circle.fill"
        case .routine: return "circle.fill"
        case .challenging: return "exclamationmark.circle.fill"
        }
    }

    var displayText: String {
        rawValue.capitalized
    }
}

// MARK: - Displayable Sentiment

/// Simplified sentiment wrapper for UI display
/// Maps the complex ContextualSentiment to actionable, displayable data
struct DisplayableSentiment {
    let trend: RelationshipTrend
    let quality: EngagementQuality
    let daysOverdue: Int?
    let pendingActionCount: Int
    let keyTopics: [String]
    let preparationNote: String?

    // MARK: - Factory Methods

    /// Create from PersonMetrics (the primary source)
    static func from(_ metrics: PersonMetrics) -> DisplayableSentiment {
        // Map trend direction
        let trend: RelationshipTrend
        switch metrics.trendDirection {
        case "improving": trend = .improving
        case "declining": trend = .declining
        default: trend = .stable
        }

        // Determine engagement quality based on health score
        let quality: EngagementQuality
        if metrics.healthScore >= 0.7 {
            quality = .productive
        } else if metrics.healthScore >= 0.4 {
            quality = .routine
        } else {
            quality = .challenging
        }

        // Calculate days overdue if applicable
        let daysOverdue: Int?
        if metrics.isOverdue {
            let expectedDays = metrics.relationshipType.expectedMeetingFrequencyDays
            let overdueBy = metrics.daysSinceLastConversation - expectedDays
            daysOverdue = max(0, overdueBy)
        } else {
            daysOverdue = nil
        }

        // Extract key topics from contextual insights (first 3)
        let keyTopics = Array(metrics.contextualInsights.prefix(3))

        // Generate preparation note
        let preparationNote: String?
        if metrics.isOverdue {
            preparationNote = "Reconnection overdue - review last conversation before reaching out"
        } else if metrics.healthScore < 0.4 {
            preparationNote = "Relationship needs attention - consider addressing concerns"
        } else if trend == .declining {
            preparationNote = "Recent interactions showing decline - prepare supportive approach"
        } else {
            preparationNote = nil
        }

        return DisplayableSentiment(
            trend: trend,
            quality: quality,
            daysOverdue: daysOverdue,
            pendingActionCount: 0, // Will be populated from ActionItem queries
            keyTopics: keyTopics,
            preparationNote: preparationNote
        )
    }

    /// Create from ContextualSentiment (for backward compatibility)
    static func from(_ sentiment: ContextualSentiment, daysSinceContact: Int, contactFrequency: Int) -> DisplayableSentiment {
        // Map relationship health to trend
        let trend: RelationshipTrend
        switch sentiment.relationshipHealth.lowercased() {
        case "improving", "strong", "excellent": trend = .improving
        case "declining", "weak", "poor": trend = .declining
        default: trend = .stable
        }

        // Map engagement level to quality
        let quality: EngagementQuality
        switch sentiment.engagementLevel.lowercased() {
        case "high", "excellent", "productive": quality = .productive
        case "low", "poor", "concerning": quality = .challenging
        default: quality = .routine
        }

        // Calculate overdue
        let daysOverdue: Int?
        if daysSinceContact > contactFrequency {
            daysOverdue = daysSinceContact - contactFrequency
        } else {
            daysOverdue = nil
        }

        // Key observations as topics
        let keyTopics = Array(sentiment.keyObservations.prefix(3))

        // Generate prep note from follow-up recommendations
        let preparationNote = sentiment.followUpRecommendations.first

        return DisplayableSentiment(
            trend: trend,
            quality: quality,
            daysOverdue: daysOverdue,
            pendingActionCount: 0,
            keyTopics: keyTopics,
            preparationNote: preparationNote
        )
    }

    // MARK: - Display Helpers

    var isOverdue: Bool {
        daysOverdue != nil && daysOverdue! > 0
    }

    var overdueText: String? {
        guard let days = daysOverdue, days > 0 else { return nil }
        return "\(days) days overdue"
    }

    var hasPendingActions: Bool {
        pendingActionCount > 0
    }

    var actionCountText: String {
        if pendingActionCount == 0 {
            return "No pending actions"
        } else if pendingActionCount == 1 {
            return "1 pending action"
        } else {
            return "\(pendingActionCount) pending actions"
        }
    }
}
