import SwiftUI
import CoreData
import AppKit

struct AnalyticsView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Person.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var people: FetchedResults<Person>
    
    @State private var selectedTimeframe: TimelineView.TimeFrame = .week
    @State private var showLowHealthDetail = false
    @State private var showOverdueDetail = false
    @State private var lowHealthWindowController: NSWindowController?
    @State private var overdueWindowController: NSWindowController?
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Insights")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Text("AI-powered insights into your relationships and conversations")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                
                // Sentiment Analysis Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sentiment Analysis")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    let metrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: self.viewContext)
                    let stats = computeAggregateStats(from: metrics)
                    
                    // Aggregate Statistics
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        StatCardView(
                            title: "Avg Duration",
                            value: String(format: "%.1f min", stats.averageDuration),
                            icon: "clock.fill",
                            color: .blue
                        )
                        
                        StatCardView(
                            title: "Total Conversations",
                            value: "\(stats.totalConversations)",
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .green
                        )
                        
                        StatCardView(
                            title: "Avg Health Score",
                            value: String(format: "%.1f", stats.averageHealthScore),
                            icon: "heart.fill",
                            color: .red
                        )
                    }
                    
                    // Priority Insights
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Priority Insights")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 16) {
                            // Low Health Score Alert
                            Button(action: {
                                openLowHealthScoreWindow(metrics: metrics)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Low Health Score Alert")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("4 relationships showing health scores")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(16)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Overdue Conversations
                            Button(action: {
                                openOverdueConversationsWindow(metrics: metrics)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.orange)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Overdue Conversations")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("2 people haven't been contacted in 30+ days")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(16)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Health Score Graph
                    if !metrics.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Health Score Graph")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            HealthScoreGraphView(healthScoreData: generateHealthScoreData(from: metrics))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 32)
                
                // Timeline Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "timeline.selection")
                            .font(.title3)
                            .foregroundColor(.blue)
                        Text("Activity Timeline")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("Recent conversations and meetings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 16)
                        
                        Picker("", selection: $selectedTimeframe) {
                            Text("Week").tag(TimelineView.TimeFrame.week)
                            Text("Month").tag(TimelineView.TimeFrame.month)
                            Text("Quarter").tag(TimelineView.TimeFrame.quarter)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 32)
                    
                    // Timeline with safer implementation
                    TimelineView(people: Array(people), timeframe: selectedTimeframe) { person in
                        // Navigate to the person in People tab
                        appStateManager.selectedTab = .people
                        appStateManager.selectedPerson = person
                        appStateManager.selectedPersonID = person.identifier
                    }
                    .padding(.horizontal, 32)
                }
                
                // Heat Map Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "grid.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                        Text("Activity Heat Map")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("Conversation patterns over the last 12 weeks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    ActivityHeatMapView(people: Array(people))
                        .padding(.horizontal, 32)
                }
                
                Spacer(minLength: 40)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func computeAggregateStats(from metrics: [PersonMetrics]) -> (averageDuration: Double, totalConversations: Int, averageHealthScore: Double) {
        guard !metrics.isEmpty else {
            return (0, 0, 0)
        }
        
        let totalDuration = metrics.reduce(0.0) { $0 + $1.metrics.averageDuration }
        let averageDuration = totalDuration / Double(metrics.count)
        
        let totalConversations = metrics.reduce(0) { $0 + $1.metrics.conversationCount }
        
        let totalHealthScore = metrics.reduce(0.0) { $0 + $1.healthScore }
        let averageHealthScore = totalHealthScore / Double(metrics.count)
        
        return (averageDuration, totalConversations, averageHealthScore)
    }
    
    private func generatePriorityInsights(from metrics: [PersonMetrics]) -> [PriorityInsight] {
        var insights: [PriorityInsight] = []
        
        // Find people with low health scores (using healthScore as proxy for engagement)
        let lowHealthPeople = metrics.filter { $0.healthScore < 0.3 }
        if !lowHealthPeople.isEmpty {
            insights.append(PriorityInsight(
                title: "Low Health Score Alert",
                description: "\(lowHealthPeople.count) relationships showing concerning health scores",
                type: .lowEngagement,
                priority: .high
            ))
        }
        
        // Find people not spoken to recently
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let stalePeople = metrics.filter { metric in
            guard let lastDate = metric.lastConversationDate else { return true }
            return lastDate < thirtyDaysAgo
        }
        
        if !stalePeople.isEmpty {
            insights.append(PriorityInsight(
                title: "Overdue Conversations",
                description: "\(stalePeople.count) people haven't been contacted in 30+ days",
                type: .overdueConversations,
                priority: .high
            ))
        }
        
        return insights
    }
    
    private func generateHealthScoreData(from metrics: [PersonMetrics]) -> [HealthScoreDataPoint] {
        let calendar = Calendar.current
        var weeklyData: [Date: (totalScore: Double, count: Int)] = [:]
        
        // Get all conversations from all people to determine actual data range
        let allConversations = metrics.flatMap { metric in
            metric.person.conversationsArray
        }
        
        // If no conversations, return empty data
        guard !allConversations.isEmpty else {
            return []
        }
        
        // Find the earliest conversation date to determine our data range
        // Note: These values are computed but not currently used in the chart rendering
        // They could be used for axis configuration in future improvements
        
        // Group conversations by week and calculate health scores for each week
        for conversation in allConversations {
            guard let conversationDate = conversation.date,
                  let weekStart = calendar.dateInterval(of: .weekOfYear, for: conversationDate)?.start else {
                continue
            }
            
            // Calculate health score for this person for this week
            if let person = conversation.person {
                let healthScore = RelationshipHealthCalculator.shared.calculateHealthScore(for: person)
                
                if let existing = weeklyData[weekStart] {
                    weeklyData[weekStart] = (existing.totalScore + healthScore, existing.count + 1)
                } else {
                    weeklyData[weekStart] = (healthScore, 1)
                }
            }
        }
        
        // Convert to data points and sort by date
        let dataPoints = weeklyData.map { (date, data) in
            HealthScoreDataPoint(
                weekStart: date,
                averageScore: data.totalScore / Double(data.count),
                relationshipCount: data.count
            )
        }.sorted { $0.weekStart < $1.weekStart }
        
        // Limit to last 25 weeks maximum, but only show weeks with actual data
        let maxWeeks = 25
        return Array(dataPoints.suffix(maxWeeks))
    }
    
    private func getInsightIcon(for type: PriorityInsightType) -> String {
        switch type {
        case .lowEngagement:
            return "exclamationmark.triangle.fill"
        case .overdueConversations:
            return "clock.badge.exclamationmark.fill"
        }
    }
    
    private func getInsightColor(for priority: Priority) -> Color {
        switch priority {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .green
        }
    }
    
    private func openLowHealthScoreWindow(metrics: [PersonMetrics]) {
        let lowHealthRelationships = metrics.filter { $0.healthScore < 0.3 }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        let hostingView = NSHostingView(rootView: LowHealthScoreDetailView(lowHealthRelationships: lowHealthRelationships).environment(\.managedObjectContext, viewContext))
        window.contentView = hostingView
        window.title = "Low Health Score Relationships"
        lowHealthWindowController = NSWindowController(window: window)
        lowHealthWindowController?.showWindow(nil)
    }
    
    private func openOverdueConversationsWindow(metrics: [PersonMetrics]) {
        let overdueRelationships = metrics.filter { metric in
            guard let lastDate = metric.lastConversationDate else { return true }
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return lastDate < thirtyDaysAgo
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        let hostingView = NSHostingView(rootView: OverdueConversationsDetailView(overdueRelationships: overdueRelationships).environment(\.managedObjectContext, viewContext))
        window.contentView = hostingView
        window.title = "Overdue Conversations"
        overdueWindowController = NSWindowController(window: window)
        overdueWindowController?.showWindow(nil)
    }
}

// MARK: - Enums and Structs

enum PriorityInsightType {
    case lowEngagement
    case overdueConversations
}

enum Priority {
    case high
    case medium
    case low
}

struct PriorityInsight {
    let title: String
    let description: String
    let type: PriorityInsightType
    let priority: Priority
}

// Preview
struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsView()
    }
}
