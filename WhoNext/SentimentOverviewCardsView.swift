import CoreData
import SwiftUI

// MARK: - Sentiment Overview Cards

struct SentimentOverviewCardsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var overviewData: SentimentOverviewData?
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading analytics...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let data = overviewData {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // Overall Health Card
                    SentimentMetricCard(
                        title: "Overall Health",
                        value: data.healthLabel,
                        subtitle: "\(data.analyzedRelationships) relationships",
                        icon: "heart.fill",
                        color: data.healthColor,
                        trend: data.healthTrend
                    )
                    
                    // Average Duration Card
                    SentimentMetricCard(
                        title: "Avg Duration",
                        value: "\(Int(data.averageDuration))m",
                        subtitle: "per conversation",
                        icon: "clock.fill",
                        color: .blue,
                        trend: data.durationTrend
                    )
                    
                    // Engagement Card
                    SentimentMetricCard(
                        title: "High Engagement",
                        value: "\(data.highEngagementCount)",
                        subtitle: "conversations",
                        icon: "flame.fill",
                        color: .orange,
                        trend: data.engagementTrend
                    )
                }
                
                // Priority insights
                if !data.priorityInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority Actions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.top, 8)
                        
                        ForEach(data.priorityInsights.prefix(2), id: \.title) { insight in
                            CompactInsightRowView(insight: insight)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No analytics data available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Add conversations with duration tracking to see insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            loadOverviewData()
        }
    }
    
    private func loadOverviewData() {
        isLoading = true
        
        Task {
            let metrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: viewContext)
            let stats = ConversationMetricsCalculator.shared.getAggregateStatistics(context: viewContext)
            
            // Collect priority insights
            var allInsights: [DurationInsight] = []
            for personMetric in metrics {
                let insights = ConversationMetricsCalculator.shared.generateInsights(for: personMetric)
                allInsights.append(contentsOf: insights.filter { $0.priority == .high || $0.priority == .medium })
            }
            
            let sortedInsights = allInsights.sorted { lhs, rhs in
                let lhsPriority = priorityValue(lhs.priority)
                let rhsPriority = priorityValue(rhs.priority)
                return lhsPriority > rhsPriority
            }
            
            // Calculate engagement metrics
            let highEngagementCount = metrics.filter { personMetric in
                guard let conversations = personMetric.person.conversations?.allObjects as? [Conversation] else { return false }
                let highEngagementConversations = conversations.filter { conversation in
                    (conversation.value(forKey: "engagementLevel") as? String) == "high" 
                }
                return !highEngagementConversations.isEmpty
            }.count
            
            let data = SentimentOverviewData(
                analyzedRelationships: metrics.count,
                averageHealthScore: stats.averageHealthScore,
                averageDuration: stats.averageDuration,
                highEngagementCount: highEngagementCount,
                priorityInsights: Array(sortedInsights.prefix(3))
            )
            
            await MainActor.run {
                self.overviewData = data
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
}

// MARK: - Overview Data Model

struct SentimentOverviewData {
    let analyzedRelationships: Int
    let averageHealthScore: Double
    let averageDuration: Double
    let highEngagementCount: Int
    let priorityInsights: [DurationInsight]
    
    var healthLabel: String {
        if averageHealthScore >= 0.7 {
            return "Good"
        } else if averageHealthScore >= 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    var healthColor: Color {
        if averageHealthScore >= 0.7 {
            return .green
        } else if averageHealthScore >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    // Placeholder trends - in a real implementation, these would be calculated from historical data
    var healthTrend: TrendDirection { .stable }
    var durationTrend: TrendDirection { .stable }
    var engagementTrend: TrendDirection { .stable }
}

enum TrendDirection {
    case up, down, stable
}

// MARK: - Sentiment Metric Card

struct SentimentMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let trend: TrendDirection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
                
                trendIndicator
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var trendIndicator: some View {
        switch trend {
        case .up:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .down:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        case .stable:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }
}

// MARK: - Compact Insight Row

struct CompactInsightRowView: View {
    let insight: DurationInsight
    
    var body: some View {
        HStack(spacing: 8) {
            priorityIndicator
            
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(insight.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if insight.actionable {
                Image(systemName: "chevron.right")
                    .foregroundColor(.accentColor)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(priorityBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    @ViewBuilder
    private var priorityIndicator: some View {
        switch insight.priority {
        case .high:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
        case .medium:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        case .low:
            Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
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
}
