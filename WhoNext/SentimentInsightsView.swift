import CoreData
import SwiftUI

// MARK: - Sentiment Insights Dashboard

struct SentimentInsightsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var allPersonMetrics: [PersonMetrics] = []
    @State private var aggregateStats: (averageDuration: Double, totalConversations: Int, averageHealthScore: Double) = (0, 0, 0)
    @State private var priorityInsights: [DurationInsight] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Relationship Insights")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("AI-powered analytics for your conversations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Refresh") {
                        loadInsights()
                    }
                    .buttonStyle(.bordered)
                }
                
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Analyzing conversations...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Aggregate Statistics
                    aggregateStatsSection
                    
                    // Priority Insights
                    if !priorityInsights.isEmpty {
                        priorityInsightsSection
                    }
                    
                    // Relationship Health Overview
                    relationshipHealthSection
                    
                    // Background Processing Status
                    SentimentProcessingStatusView()
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadInsights()
        }
    }
    
    // MARK: - Aggregate Statistics Section
    
    @ViewBuilder
    private var aggregateStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                StatCardView(
                    title: "Average Duration",
                    value: "\(Int(aggregateStats.averageDuration))m",
                    icon: "clock",
                    color: .blue
                )
                
                StatCardView(
                    title: "Total Conversations",
                    value: "\(aggregateStats.totalConversations)",
                    icon: "bubble.left.and.bubble.right",
                    color: .green
                )
                
                StatCardView(
                    title: "Average Health",
                    value: healthScoreLabel(aggregateStats.averageHealthScore),
                    icon: "heart.fill",
                    color: healthScoreColor(aggregateStats.averageHealthScore)
                )
            }
        }
    }
    
    // MARK: - Priority Insights Section
    
    @ViewBuilder
    private var priorityInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Priority Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(priorityInsights.prefix(5), id: \.title) { insight in
                    PriorityInsightRowView(insight: insight)
                }
            }
        }
    }
    
    // MARK: - Relationship Health Section
    
    @ViewBuilder
    private var relationshipHealthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relationship Health")
                .font(.headline)
                .fontWeight(.semibold)
            
            if allPersonMetrics.isEmpty {
                Text("No relationship data available")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(allPersonMetrics.prefix(6), id: \.person.objectID) { personMetrics in
                        RelationshipHealthCardView(personMetrics: personMetrics)
                    }
                }
                
                if allPersonMetrics.count > 6 {
                    Text("And \(allPersonMetrics.count - 6) more relationships...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadInsights() {
        isLoading = true
        
        Task {
            let metrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: viewContext)
            let stats = ConversationMetricsCalculator.shared.getAggregateStatistics(context: viewContext)
            
            // Collect all insights and prioritize them
            var allInsights: [DurationInsight] = []
            for personMetric in metrics {
                let insights = ConversationMetricsCalculator.shared.generateInsights(for: personMetric)
                allInsights.append(contentsOf: insights)
            }
            
            // Sort by priority (high first) and limit to top insights
            let sortedInsights = allInsights.sorted { lhs, rhs in
                let lhsPriority = priorityValue(lhs.priority)
                let rhsPriority = priorityValue(rhs.priority)
                return lhsPriority > rhsPriority
            }
            
            await MainActor.run {
                self.allPersonMetrics = metrics.sorted { $0.healthScore < $1.healthScore } // Show concerning relationships first
                self.aggregateStats = stats
                self.priorityInsights = Array(sortedInsights.prefix(5))
                self.isLoading = false
            }
        }
    }
    
    private func priorityValue(_ priority: DurationInsight.Priority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
    
    private func healthScoreLabel(_ score: Double) -> String {
        if score >= 0.7 {
            return "Good"
        } else if score >= 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    private func healthScoreColor(_ score: Double) -> Color {
        if score >= 0.7 {
            return .green
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Stat Card View

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Priority Insight Row View

struct PriorityInsightRowView: View {
    let insight: DurationInsight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            priorityIndicator
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            Spacer()
            
            if insight.actionable {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.accentColor)
                    .font(.title3)
            }
        }
        .padding(16)
        .background(priorityBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(priorityBorderColor, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var priorityIndicator: some View {
        switch insight.priority {
        case .high:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)
        case .medium:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.title3)
        case .low:
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.blue)
                .font(.title3)
        }
    }
    
    private var priorityBackgroundColor: Color {
        switch insight.priority {
        case .high:
            return Color.red.opacity(0.05)
        case .medium:
            return Color.orange.opacity(0.05)
        case .low:
            return Color.blue.opacity(0.05)
        }
    }
    
    private var priorityBorderColor: Color {
        switch insight.priority {
        case .high:
            return Color.red.opacity(0.2)
        case .medium:
            return Color.orange.opacity(0.2)
        case .low:
            return Color.blue.opacity(0.2)
        }
    }
}

// MARK: - Relationship Health Card View

struct RelationshipHealthCardView: View {
    let personMetrics: PersonMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(personMetrics.person.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
            }
            
            if let role = personMetrics.person.role, !role.isEmpty {
                Text(role)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack {
                Text("\(Int(personMetrics.metrics.averageDuration))m avg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(trendLabel)
                    .font(.caption2)
                    .foregroundColor(trendColor)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(healthColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var healthColor: Color {
        if personMetrics.healthScore >= 0.7 {
            return .green
        } else if personMetrics.healthScore >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var trendLabel: String {
        switch personMetrics.trendDirection {
        case "improving":
            return "↗ Improving"
        case "declining":
            return "↘ Declining"
        default:
            return "→ Stable"
        }
    }
    
    private var trendColor: Color {
        switch personMetrics.trendDirection {
        case "improving":
            return .green
        case "declining":
            return .red
        default:
            return .secondary
        }
    }
}
