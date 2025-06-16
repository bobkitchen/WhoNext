import SwiftUI
import CoreData

struct StatisticsCardsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    var body: some View {
        VStack(spacing: 20) {
            EnhancedStatCardView(
                icon: "flag.fill",
                title: "Cycle Progress",
                value: cycleProgressText,
                subtitle: "Team members contacted",
                color: .blue,
                progress: Double(spokenToThisCycle.count) / Double(max(nonDirectReports.count, 1))
            )
            EnhancedStatCardView(
                icon: "heart.fill",
                title: "Health Alerts",
                value: "\(lowHealthRelationships.count)",
                subtitle: "Need attention",
                color: lowHealthRelationships.count > 0 ? .red : .green,
                progress: nil
            )
            EnhancedStatCardView(
                icon: "calendar.badge.clock",
                title: "This Week",
                value: "\(upcomingMeetingsThisWeek.count)",
                subtitle: "Scheduled meetings",
                color: .green,
                progress: nil
            )
        }
        .frame(width: 200)
    }
}

// MARK: - Computed Properties
extension StatisticsCardsView {
    private var nonDirectReports: [Person] {
        people.filter { !$0.isDirectReport }
    }
    
    private var cycleProgressText: String {
        "\(spokenToThisCycle.count) / \(nonDirectReports.count)"
    }
    
    private var spokenToThisCycle: [Person] {
        // For each person, get their most recent conversation date
        let lastDates = nonDirectReports.compactMap { person in
            (person, person.lastContactDate)
        }
        // Find the earliest of the most recent dates (cycle start)
        guard lastDates.count == nonDirectReports.count,
              let cycleStart = lastDates.map({ $0.1 ?? .distantPast }).min(),
              cycleStart > .distantPast else {
            // If not everyone has been spoken to, cycle started at earliest contact
            let earliest = lastDates.map { $0.1 ?? .distantPast }.min() ?? .distantPast
            return nonDirectReports.filter { ($0.lastContactDate ?? .distantPast) >= earliest && $0.lastContactDate != nil }
        }
        // Only those spoken to since cycleStart
        return nonDirectReports.filter { ($0.lastContactDate ?? .distantPast) >= cycleStart && $0.lastContactDate != nil }
    }
    
    private var lowHealthRelationships: [Person] {
        let calculator = ConversationMetricsCalculator()
        return people.compactMap { person in
            guard let metrics = calculator.calculateMetrics(for: person) else { return nil }
            return metrics.healthScore < 0.4 ? person : nil
        }
    }
    
    private var upcomingMeetingsThisWeek: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return CalendarService.shared.upcomingMeetings.filter { meeting in
            meeting.startDate >= now && meeting.startDate < endDate
        }
    }
}

#Preview {
    StatisticsCardsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}