import SwiftUI
import CoreData

/// Week at a Glance - Summary widget for the top of Insights page
/// Shows meetings, action items, decisions, and relationship trends for the current week
struct WeekAtGlanceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    private let calculator = ConversationMetricsCalculator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with date range
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Week at a Glance")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(weekRangeText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Week navigation could go here in future
            }

            // Main stats grid
            HStack(spacing: 24) {
                // Meetings
                statItem(
                    value: "\(meetingsThisWeek)",
                    label: "meetings",
                    icon: "calendar",
                    color: .blue
                )

                Divider()
                    .frame(height: 40)

                // Action Items
                statItem(
                    value: "\(actionItemsCreated)",
                    label: "actions created",
                    icon: "checkmark.circle",
                    color: .green,
                    secondaryValue: actionItemsResolved > 0 ? "\(actionItemsResolved) resolved" : nil
                )

                Divider()
                    .frame(height: 40)

                // Time in conversations
                statItem(
                    value: formatDuration(totalMinutesThisWeek),
                    label: "in conversations",
                    icon: "clock",
                    color: .orange
                )

                Divider()
                    .frame(height: 40)

                // Relationship trends
                relationshipTrendsItem
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Helper Views

    private func statItem(
        value: String,
        label: String,
        icon: String,
        color: Color,
        secondaryValue: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let secondary = secondaryValue {
                    Text(secondary)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var relationshipTrendsItem: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.circle")
                .font(.title2)
                .foregroundColor(.pink)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    trendPill(count: improvingCount, icon: "arrow.up.right", color: .green, label: "improving")
                    trendPill(count: decliningCount, icon: "arrow.down.right", color: .orange, label: "declining")
                }

                if needAttentionCount > 0 {
                    Text("\(needAttentionCount) need attention")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func trendPill(count: Int, icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundColor(color)
        .help("\(count) \(label)")
    }

    // MARK: - Computed Properties

    private var weekStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? Date()
    }

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    private var conversationsThisWeek: [Conversation] {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.predicate = NSPredicate(format: "date >= %@", weekStart as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch conversations: \(error)")
            return []
        }
    }

    private var meetingsThisWeek: Int {
        conversationsThisWeek.count
    }

    private var totalMinutesThisWeek: Int {
        conversationsThisWeek.reduce(0) { sum, conv in
            sum + Int(conv.value(forKey: "duration") as? Int32 ?? 0)
        }
    }

    private var actionItemsThisWeek: [ActionItem] {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "createdAt >= %@", weekStart as NSDate)

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch action items: \(error)")
            return []
        }
    }

    private var actionItemsCreated: Int {
        actionItemsThisWeek.count
    }

    private var actionItemsResolved: Int {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "completedAt >= %@", weekStart as NSDate)

        do {
            return try viewContext.fetch(request).count
        } catch {
            return 0
        }
    }

    private var relationshipMetrics: [PersonMetrics] {
        people.filter { !$0.isCurrentUser }.compactMap { calculator.calculateMetrics(for: $0) }
    }

    private var improvingCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "improving" }.count
    }

    private var decliningCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "declining" }.count
    }

    private var needAttentionCount: Int {
        relationshipMetrics.filter { $0.healthScore < 0.4 }.count
    }

    // MARK: - Helpers

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WeekAtGlanceView()
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
