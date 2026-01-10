import SwiftUI
import CoreData

/// Action Items Hub for Insights page
/// Shows action items divided by ownership: Your Commitments vs Waiting on Others
struct ActionItemsHubView: View {
    @Environment(\.managedObjectContext) private var viewContext

    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Action Items")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if totalItems > 0 {
                    Button(action: { onViewAll?() }) {
                        Text("View All")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if totalItems == 0 {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("All caught up!")
                            .font(.headline)
                        Text("No pending action items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Your Commitments
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill")
                                .foregroundColor(.orange)
                            Text("YOUR COMMITMENTS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("(\(myTasksCount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if myTasks.isEmpty {
                            Text("No pending commitments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(myTasks.prefix(4), id: \.objectID) { item in
                                actionItemRow(item: item)
                            }

                            if myTasksCount > 4 {
                                Text("+ \(myTasksCount - 4) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )

                    // Waiting on Others
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            Text("WAITING ON OTHERS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("(\(theirTasksCount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if theirTasks.isEmpty {
                            Text("Nothing pending from others")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(theirTasks.prefix(4), id: \.objectID) { item in
                                actionItemRow(item: item)
                            }

                            if theirTasksCount > 4 {
                                Text("+ \(theirTasksCount - 4) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
        }
    }

    // MARK: - Helper Views

    private func actionItemRow(item: ActionItem) -> some View {
        HStack(spacing: 8) {
            // Overdue indicator
            if isOverdue(item) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Untitled")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let person = item.person {
                        Text(person.name ?? "Unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let dueDate = item.dueDate {
                        Text("Due \(formatDueDate(dueDate))")
                            .font(.caption2)
                            .foregroundColor(isOverdue(item) ? .red : .secondary)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var myTasks: [ActionItem] {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "isMyTask == YES AND isCompleted == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]
        request.fetchLimit = 10

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch my tasks: \(error)")
            return []
        }
    }

    private var myTasksCount: Int {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "isMyTask == YES AND isCompleted == NO")

        do {
            return try viewContext.count(for: request)
        } catch {
            return 0
        }
    }

    private var theirTasks: [ActionItem] {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "isMyTask == NO AND isCompleted == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]
        request.fetchLimit = 10

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch their tasks: \(error)")
            return []
        }
    }

    private var theirTasksCount: Int {
        let request = NSFetchRequest<ActionItem>(entityName: "ActionItem")
        request.predicate = NSPredicate(format: "isMyTask == NO AND isCompleted == NO")

        do {
            return try viewContext.count(for: request)
        } catch {
            return 0
        }
    }

    private var totalItems: Int {
        myTasksCount + theirTasksCount
    }

    // MARK: - Helpers

    private func isOverdue(_ item: ActionItem) -> Bool {
        guard let dueDate = item.dueDate else { return false }
        return dueDate < Date() && !item.isCompleted
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else if calendar.isDateInTomorrow(date) {
            return "tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    ActionItemsHubView()
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
