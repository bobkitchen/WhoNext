import SwiftUI
import CoreData
import AppKit

struct AnalyticsDashboardView: View {
    @Binding var chatInput: String
    @FocusState.Binding var isChatFocused: Bool
    
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
        VStack(alignment: .leading, spacing: 40) {
            // Sentiment Analysis Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Relationship Health")
                    .font(.title2)
                    .fontWeight(.bold)

                let allMetrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: self.viewContext)
                // Filter out current user from analytics
                let metrics = allMetrics.filter { !$0.person.isCurrentUser }
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
                            chatInput = "Tell me about my low health relationships and what I should do"
                            isChatFocused = true
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
                            chatInput = "Who haven't I talked to recently and when should I reach out?"
                            isChatFocused = true
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
                // Filter out current user from timeline
                let timelinePeople = people.filter { !$0.isCurrentUser }
                TimelineView(people: Array(timelinePeople), timeframe: selectedTimeframe) { person in
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

                // Filter out current user from heat map
                let heatMapPeople = people.filter { !$0.isCurrentUser }
                ActivityHeatMapView(people: Array(heatMapPeople))
                    .padding(.horizontal, 32)
            }
            
            Spacer(minLength: 40)
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
}

#Preview {
    struct PreviewWrapper: View {
        @State private var chatInput = ""
        @FocusState private var isChatFocused: Bool

        var body: some View {
            let context = PersistenceController.shared.container.viewContext
            AnalyticsDashboardView(
                chatInput: $chatInput,
                isChatFocused: $isChatFocused
            )
            .environment(\.managedObjectContext, context)
            .environmentObject(AppStateManager(viewContext: context))
        }
    }

    return PreviewWrapper()
}
