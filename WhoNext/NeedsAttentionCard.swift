import SwiftUI
import CoreData

/// Card 2: Focus Next - Always shows who to prioritize, even when healthy
/// A coach never says "you're done" - always guides the next action
struct NeedsAttentionCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var isHovered = false

    var onTap: (() -> Void)?
    var onPersonTap: ((Person) -> Void)?

    private let calculator = ConversationMetricsCalculator.shared
    private let cardHeight: CGFloat = 160

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("FOCUS NEXT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    Spacer()

                    if urgentCount > 0 {
                        Text("\(urgentCount)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.orange))
                    }
                }

                Spacer().frame(height: 12)

                // Priority person to focus on
                if let priority = priorityPerson {
                    VStack(alignment: .leading, spacing: 8) {
                        // Main call to action
                        Text(priorityHeadline)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        // Priority person row
                        HStack(spacing: 10) {
                            Circle()
                                .fill(avatarColor(for: priority.person))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(initials(for: priority.person))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(priority.person.name ?? "Unknown")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)

                                Text(priorityReason(for: priority))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onPersonTap?(priority.person)
                        }
                    }
                } else {
                    // No relationships yet
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build your network")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Record your first meeting to start tracking relationships")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Additional context at bottom
                if additionalCount > 0 {
                    Text("+ \(additionalCount) more to review")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

    // MARK: - Computed Properties

    private var relationshipMetrics: [PersonMetrics] {
        people.filter { !$0.isCurrentUser }.compactMap { calculator.calculateMetrics(for: $0) }
    }

    /// People ranked by priority (urgent first, then by days since contact)
    private var prioritizedPeople: [PersonMetrics] {
        relationshipMetrics.sorted { a, b in
            // Urgent (declining or overdue) first
            let aUrgent = a.healthScore < 0.4 || a.isOverdue
            let bUrgent = b.healthScore < 0.4 || b.isOverdue
            if aUrgent != bUrgent { return aUrgent }

            // Then by days since contact (longest first)
            return a.daysSinceLastConversation > b.daysSinceLastConversation
        }
    }

    private var priorityPerson: PersonMetrics? {
        prioritizedPeople.first
    }

    private var urgentCount: Int {
        relationshipMetrics.filter { $0.healthScore < 0.4 || $0.isOverdue }.count
    }

    private var additionalCount: Int {
        max(0, prioritizedPeople.count - 1)
    }

    private var priorityHeadline: String {
        guard let priority = priorityPerson else { return "Build connections" }

        if priority.healthScore < 0.4 {
            return "Relationship needs care"
        } else if priority.isOverdue {
            return "Time to reconnect"
        } else if priority.daysSinceLastConversation > 14 {
            return "Check in soon"
        } else {
            return "Keep the momentum"
        }
    }

    private func priorityReason(for metrics: PersonMetrics) -> String {
        if metrics.isOverdue {
            return "\(metrics.daysSinceLastConversation) days since last contact"
        } else if metrics.healthScore < 0.4 {
            return "Engagement declining - reach out"
        } else if metrics.daysSinceLastConversation > 0 {
            return "Last met \(metrics.daysSinceLastConversation) days ago"
        } else {
            return "Connected recently"
        }
    }

    // MARK: - Helpers

    private func initials(for person: Person) -> String {
        guard let name = person.name else { return "?" }
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func avatarColor(for person: Person) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let hash = abs((person.name ?? "").hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Preview

#Preview {
    NeedsAttentionCard()
        .frame(width: 220)
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
