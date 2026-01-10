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
        VStack(alignment: .leading, spacing: 32) {
            // Section 1: Week at a Glance (NEW)
            WeekAtGlanceView()
                .padding(.horizontal, 32)

            // Section 2: Relationship Health (Simplified)
            RelationshipHealthSummaryView(
                onViewDeclining: {
                    chatInput = "Tell me about my declining relationships and what I should do"
                    isChatFocused = true
                }
            )
            .padding(.horizontal, 32)

            // Section 3: Health Score Trends
            let allMetrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: self.viewContext)
            let metrics = allMetrics.filter { !$0.person.isCurrentUser }

            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Health Score Trends")
                        .font(.title2)
                        .fontWeight(.bold)

                    HealthScoreGraphView(healthScoreData: generateHealthScoreData(from: metrics))
                }
                .padding(.horizontal, 32)
            }

            // Section 4: Action Items Hub (NEW)
            ActionItemsHubView(
                onViewAll: {
                    // Navigate to action items or prompt AI
                    chatInput = "Show me all my pending action items"
                    isChatFocused = true
                }
            )
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
