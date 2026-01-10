import SwiftUI
import CoreData

/// Card 1: Your Momentum - Shows relationship trajectory and engagement quality
/// Focused on inspiring continued engagement, not just reporting status
struct RelationshipPulseCard: View {
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
                    Text("YOUR MOMENTUM")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: momentumIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(momentumColor)
                }

                Spacer().frame(height: 12)

                // Main insight - what's the story?
                Text(momentumHeadline)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 8)

                // Supporting context
                Text(momentumSubtext)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Spacer()

                // Trend indicators at bottom
                HStack(spacing: 16) {
                    if improvingCount > 0 {
                        trendBadge(icon: "arrow.up.right", count: improvingCount, color: .green)
                    }
                    if decliningCount > 0 {
                        trendBadge(icon: "arrow.down.right", count: decliningCount, color: .orange)
                    }
                    if overdueCount > 0 {
                        trendBadge(icon: "clock", count: overdueCount, color: .red)
                    }
                    if improvingCount == 0 && decliningCount == 0 && overdueCount == 0 {
                        Text("\(totalRelationships) relationships tracked")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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

    private var totalRelationships: Int {
        relationshipMetrics.count
    }

    private var improvingCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "improving" }.count
    }

    private var decliningCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "declining" }.count
    }

    private var overdueCount: Int {
        relationshipMetrics.filter { $0.isOverdue }.count
    }

    private var healthyPercentage: Double {
        guard !relationshipMetrics.isEmpty else { return 1.0 }
        let healthy = relationshipMetrics.filter { $0.healthScore >= 0.4 }.count
        return Double(healthy) / Double(relationshipMetrics.count)
    }

    // MARK: - Coaching-focused content

    private var momentumIcon: String {
        if improvingCount > decliningCount {
            return "chart.line.uptrend.xyaxis"
        } else if decliningCount > improvingCount {
            return "chart.line.downtrend.xyaxis"
        } else {
            return "chart.line.flattrend.xyaxis"
        }
    }

    private var momentumColor: Color {
        if improvingCount > decliningCount {
            return .green
        } else if decliningCount > 0 {
            return .orange
        } else {
            return .blue
        }
    }

    private var momentumHeadline: String {
        if totalRelationships == 0 {
            return "Start building connections"
        } else if improvingCount > 0 && decliningCount == 0 {
            return "Building strong momentum"
        } else if improvingCount > decliningCount {
            return "Positive trajectory"
        } else if decliningCount > 0 && overdueCount > 0 {
            return "Time to reconnect"
        } else if decliningCount > 0 {
            return "Some attention needed"
        } else if healthyPercentage >= 0.8 {
            return "Relationships thriving"
        } else {
            return "Steady engagement"
        }
    }

    private var momentumSubtext: String {
        if totalRelationships == 0 {
            return "Record meetings to track your relationship health"
        } else if improvingCount > 0 && decliningCount == 0 {
            return "\(improvingCount) relationship\(improvingCount == 1 ? " is" : "s are") strengthening - keep it up!"
        } else if overdueCount > 0 {
            return "\(overdueCount) conversation\(overdueCount == 1 ? "" : "s") overdue - consider reaching out"
        } else if decliningCount > 0 {
            return "Check in with \(decliningCount) relationship\(decliningCount == 1 ? "" : "s") showing decline"
        } else {
            return "Your engagement is consistent across \(totalRelationships) relationships"
        }
    }

    // MARK: - Helper Views

    private func trendBadge(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    RelationshipPulseCard()
        .frame(width: 220)
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
