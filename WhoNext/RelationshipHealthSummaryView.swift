import SwiftUI
import CoreData

/// Simplified Relationship Health display for Insights page
/// Groups relationships by type with progress bars showing health percentage
struct RelationshipHealthSummaryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    var onViewDeclining: (() -> Void)?

    private let calculator = ConversationMetricsCalculator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relationship Health")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                // Direct Reports
                healthRow(
                    type: .directReport,
                    count: directReportCount,
                    healthyCount: healthyDirectReports,
                    color: .blue
                )

                // Skip Levels
                healthRow(
                    type: .skipLevel,
                    count: skipLevelCount,
                    healthyCount: healthySkipLevels,
                    color: .purple
                )

                // Other Relationships
                healthRow(
                    type: .other,
                    count: otherCount,
                    healthyCount: healthyOthers,
                    color: .green
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )

            // Declining relationships alert
            if decliningCount > 0 {
                Button(action: { onViewDeclining?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("\(decliningCount) relationship\(decliningCount == 1 ? "" : "s") declining")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("View details")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helper Views

    private func healthRow(type: RelationshipType, count: Int, healthyCount: Int, color: Color) -> some View {
        let percentage = count > 0 ? Double(healthyCount) / Double(count) : 0

        return HStack(spacing: 16) {
            // Type indicator
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Type name and count
            VStack(alignment: .leading, spacing: 2) {
                Text(type.description)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(count) people")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(healthColor(for: percentage))
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 8)

            // Percentage
            Text("\(Int(percentage * 100))% healthy")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private func healthColor(for percentage: Double) -> Color {
        if percentage >= 0.7 {
            return .green
        } else if percentage >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    // MARK: - Computed Properties

    private var relationshipMetrics: [PersonMetrics] {
        people.filter { !$0.isCurrentUser }.compactMap { calculator.calculateMetrics(for: $0) }
    }

    // Direct Reports
    private var directReportMetrics: [PersonMetrics] {
        relationshipMetrics.filter { $0.relationshipType == .directReport }
    }

    private var directReportCount: Int {
        directReportMetrics.count
    }

    private var healthyDirectReports: Int {
        directReportMetrics.filter { $0.healthScore >= 0.4 }.count
    }

    // Skip Levels
    private var skipLevelMetrics: [PersonMetrics] {
        relationshipMetrics.filter { $0.relationshipType == .skipLevel }
    }

    private var skipLevelCount: Int {
        skipLevelMetrics.count
    }

    private var healthySkipLevels: Int {
        skipLevelMetrics.filter { $0.healthScore >= 0.4 }.count
    }

    // Others
    private var otherMetrics: [PersonMetrics] {
        relationshipMetrics.filter { $0.relationshipType == .other }
    }

    private var otherCount: Int {
        otherMetrics.count
    }

    private var healthyOthers: Int {
        otherMetrics.filter { $0.healthScore >= 0.4 }.count
    }

    // Declining
    private var decliningCount: Int {
        relationshipMetrics.filter { $0.trendDirection == "declining" }.count
    }
}

// MARK: - Preview

#Preview {
    RelationshipHealthSummaryView()
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
