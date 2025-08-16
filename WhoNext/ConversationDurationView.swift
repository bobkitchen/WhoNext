import SwiftUI
import CoreData

// MARK: - Duration Analytics UI

struct ConversationDurationView: View {
    let person: Person
    @State private var personMetrics: PersonMetrics?
    @State private var insights: [DurationInsight] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.accentColor)
                Text("Conversation Analytics")
                    .font(.headline)
                Spacer()
            }
            
            if let metrics = personMetrics {
                VStack(alignment: .leading, spacing: 8) {
                    // Duration metrics
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(metrics.metrics.averageDuration)) min")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTotalDuration(metrics.metrics.totalDuration))
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                    }
                    
                    // Health and trend indicators
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Relationship Health")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                healthIndicator(score: metrics.healthScore)
                                Text(healthLabel(score: metrics.healthScore))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Trend")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                trendIndicator(direction: metrics.trendDirection)
                                Text(metrics.trendDirection.capitalized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    
                    // Insights
                    if !insights.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Insights")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(insights.prefix(3), id: \.title) { insight in
                                InsightRowView(insight: insight)
                            }
                        }
                    }
                    
                    // Last conversation info
                    if let lastDate = metrics.lastConversationDate {
                        Divider()
                        
                        HStack {
                            Text("Last conversation:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatLastConversationDate(lastDate))
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            if metrics.daysSinceLastConversation > 7 {
                                Text("(\(metrics.daysSinceLastConversation) days ago)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No conversation data available for analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Add more conversations with duration tracking to see analytics")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
        .onAppear {
            loadMetrics()
        }
        .onChange(of: person.conversations?.count) { oldValue, newValue in
            loadMetrics()
        }
    }
    
    private func loadMetrics() {
        personMetrics = ConversationMetricsCalculator.shared.calculateMetrics(for: person)
        
        if let metrics = personMetrics {
            insights = ConversationMetricsCalculator.shared.generateInsights(for: metrics)
        }
    }
    
    private func healthIndicator(score: Double) -> some View {
        Circle()
            .fill(healthColor(score: score))
            .frame(width: 8, height: 8)
    }
    
    private func healthColor(score: Double) -> Color {
        if score >= 0.7 {
            return .green
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func healthLabel(score: Double) -> String {
        if score >= 0.7 {
            return "Good"
        } else if score >= 0.4 {
            return "Fair"
        } else {
            return "Needs Attention"
        }
    }
    
    private func trendIndicator(direction: String) -> some View {
        switch direction {
        case "improving":
            Image(systemName: "arrow.up.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case "declining":
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        default:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }
    
    private func formatTotalDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let remainingMinutes = Int(minutes) % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(Int(minutes))m"
        }
    }
    
    private func formatLastConversationDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Insight Row View

struct InsightRowView: View {
    let insight: DurationInsight
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            priorityIndicator
            
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(insight.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(priorityColor.opacity(0.1))
        )
    }
    
    @ViewBuilder
    private var priorityIndicator: some View {
        switch insight.priority {
        case .high:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
        case .medium:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .low:
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.blue)
                .font(.caption)
        }
    }
    
    private var priorityColor: Color {
        switch insight.priority {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .blue
        }
    }
}

// MARK: - Compact Duration Summary View

struct CompactDurationSummaryView: View {
    let person: Person
    @State private var averageDuration: Double = 0
    @State private var healthScore: Double = 0.5
    
    var body: some View {
        HStack(spacing: 12) {
            // Duration
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(Int(averageDuration))m avg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Health indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 6, height: 6)
                Text(healthLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadSummary()
        }
        .onChange(of: person.conversations?.count) { oldValue, newValue in
            loadSummary()
        }
    }
    
    private func loadSummary() {
        if let metrics = ConversationMetricsCalculator.shared.calculateMetrics(for: person) {
            averageDuration = metrics.metrics.averageDuration
            healthScore = metrics.healthScore
        }
    }
    
    private var healthColor: Color {
        if healthScore >= 0.7 {
            return .green
        } else if healthScore >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var healthLabel: String {
        if healthScore >= 0.7 {
            return "Good"
        } else if healthScore >= 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
}
