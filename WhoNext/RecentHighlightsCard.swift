import SwiftUI
import CoreData

/// Card 3: This Week - Shows weekly engagement with inspiring framing
/// Celebrates progress and reinforces positive relationship building
struct RecentHighlightsCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var isHovered = false

    var onTap: (() -> Void)?

    private let calculator = ConversationMetricsCalculator.shared
    private let cardHeight: CGFloat = 160

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("THIS WEEK")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    Spacer()

                    Text(weekRangeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer().frame(height: 12)

                // Main inspiring headline
                Text(weekHeadline)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 8)

                // Supporting context
                Text(weekSubtext)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Spacer()

                // Activity indicators at bottom
                HStack(spacing: 12) {
                    if meetingsThisWeek > 0 {
                        activityBadge(icon: "bubble.left.and.bubble.right", count: meetingsThisWeek, label: "meetings")
                    }
                    if uniquePeopleThisWeek > 0 {
                        activityBadge(icon: "person.2", count: uniquePeopleThisWeek, label: "people")
                    }
                    if totalMinutesThisWeek > 30 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .medium))
                            Text(formatDuration(totalMinutesThisWeek))
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .frame(height: cardHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Coaching-focused Content

    private var weekHeadline: String {
        if meetingsThisWeek == 0 {
            return "Start your week strong"
        } else if meetingsThisWeek >= 5 && uniquePeopleThisWeek >= 3 {
            return "Great engagement!"
        } else if improvingCount > 0 {
            return "Relationships growing"
        } else if newConnectionsThisWeek > 0 {
            return "Expanding your network"
        } else if meetingsThisWeek >= 3 {
            return "Staying connected"
        } else if meetingsThisWeek > 0 {
            return "Building momentum"
        } else {
            return "Ready to connect"
        }
    }

    private var weekSubtext: String {
        if meetingsThisWeek == 0 {
            return "Schedule or record a meeting to track your relationship building"
        } else if newConnectionsThisWeek > 0 {
            return "\(newConnectionsThisWeek) new connection\(newConnectionsThisWeek == 1 ? "" : "s") this week - great for network growth"
        } else if improvingCount > 0 {
            return "\(improvingCount) relationship\(improvingCount == 1 ? "" : "s") showing positive momentum"
        } else if uniquePeopleThisWeek > 0 {
            return "Connected with \(uniquePeopleThisWeek) \(uniquePeopleThisWeek == 1 ? "person" : "people") - keep the rhythm going"
        } else {
            return "Your weekly relationship building summary"
        }
    }

    // MARK: - Helper Views

    private func activityBadge(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Computed Properties

    private var weekStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? Date()
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: endDate))"
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

    private var uniquePeopleThisWeek: Int {
        let uniquePeople = Set(conversationsThisWeek.compactMap { $0.value(forKey: "person") as? Person })
        return uniquePeople.count
    }

    /// People who had their first conversation this week
    private var newConnectionsThisWeek: Int {
        var count = 0
        for person in people where !person.isCurrentUser {
            guard let conversations = person.conversations?.allObjects as? [Conversation] else { continue }
            let sorted = conversations.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            if let firstDate = sorted.first?.date, firstDate >= weekStart {
                count += 1
            }
        }
        return count
    }

    private var relationshipMetrics: [PersonMetrics] {
        people.filter { !$0.isCurrentUser }.compactMap { calculator.calculateMetrics(for: $0) }
    }

    private var improvingCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "improving" }.count
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
    RecentHighlightsCard()
        .frame(width: 220)
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
