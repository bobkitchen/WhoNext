import SwiftUI
import CoreData

struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Person.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var people: FetchedResults<Person>
    
    @State private var selectedTimeframe: TimelineView.TimeFrame = .week
    @State private var allPersonMetrics: [PersonMetrics] = []
    @State private var aggregateStats: (averageDuration: Double, totalConversations: Int, averageHealthScore: Double) = (0, 0, 0)
    @State private var priorityInsights: [PriorityInsight] = []
    @State private var isLoadingSentiment = true
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Analytics")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Text("Insights into your conversation patterns and team engagement")
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
                    
                    if isLoadingSentiment {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing conversations...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else {
                        // Aggregate Statistics
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                            StatCardView(
                                title: "Avg Duration",
                                value: String(format: "%.1f min", aggregateStats.averageDuration),
                                icon: "clock.fill",
                                color: .blue
                            )
                            
                            StatCardView(
                                title: "Total Conversations",
                                value: "\(aggregateStats.totalConversations)",
                                icon: "bubble.left.and.bubble.right.fill",
                                color: .green
                            )
                            
                            StatCardView(
                                title: "Avg Health Score",
                                value: String(format: "%.1f", aggregateStats.averageHealthScore),
                                icon: "heart.fill",
                                color: .red
                            )
                        }
                        
                        // Priority Insights
                        if !priorityInsights.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Priority Insights")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                    ForEach(Array(priorityInsights.prefix(4)), id: \.title) { insight in
                                        HStack(spacing: 12) {
                                            Image(systemName: getInsightIcon(for: insight.type))
                                                .foregroundColor(getInsightColor(for: insight.priority))
                                                .font(.title3)
                                                .frame(width: 24, height: 24)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(insight.title)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Text(insight.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        // Relationship Health Overview
                        if !allPersonMetrics.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Relationship Health")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                                    ForEach(Array(allPersonMetrics.prefix(9)), id: \.person.objectID) { personMetrics in
                                        RelationshipHealthCardView(personMetrics: personMetrics)
                                    }
                                }
                                
                                if allPersonMetrics.count > 9 {
                                    Text("And \(allPersonMetrics.count - 9) more relationships...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                
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
                        appState.selectedTab = .people
                        appState.selectedPerson = person
                        appState.selectedPersonID = person.identifier
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
        .onAppear {
            loadSentimentInsights()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSentimentInsights() {
        isLoadingSentiment = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let metrics = ConversationMetricsCalculator.shared.calculateAllPersonMetrics(context: self.viewContext)
            let stats = self.computeAggregateStats(from: metrics)
            let insights = self.generatePriorityInsights(from: metrics)
            
            DispatchQueue.main.async {
                self.allPersonMetrics = metrics
                self.aggregateStats = stats
                self.priorityInsights = insights
                self.isLoadingSentiment = false
            }
        }
    }
    
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
}

// Preview
struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsView()
    }
}

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
