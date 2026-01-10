import SwiftUI
import CoreData

/// Main view for displaying and managing action items
struct ActionItemsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ActionItem.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var actionItems: FetchedResults<ActionItem>

    @State private var showingAddItem = false
    @State private var filterOption: FilterOption = .pending
    @State private var searchText = ""

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case myTasks = "My Tasks"
        case theirTasks = "Their Tasks"
        case pending = "Pending"
        case overdue = "Overdue"
        case completed = "Completed"
    }

    var filteredItems: [ActionItem] {
        var items = Array(actionItems)

        // Apply filter
        switch filterOption {
        case .all:
            break
        case .myTasks:
            items = items.filter { $0.isMyTask && !$0.isCompleted }
        case .theirTasks:
            items = items.filter { !$0.isMyTask && !$0.isCompleted }
        case .pending:
            items = items.filter { !$0.isCompleted }
        case .overdue:
            items = items.filter { $0.isOverdue }
        case .completed:
            items = items.filter { $0.isCompleted }
        }

        // Apply search
        if !searchText.isEmpty {
            items = items.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.assignee ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    var pendingCount: Int {
        actionItems.filter { !$0.isCompleted }.count
    }

    var overdueCount: Int {
        actionItems.filter { $0.isOverdue }.count
    }

    var myTasksCount: Int {
        actionItems.filter { $0.isMyTask && !$0.isCompleted }.count
    }

    var theirTasksCount: Int {
        actionItems.filter { !$0.isMyTask && !$0.isCompleted }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Filter tabs
            filterTabs

            // Content
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsList
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddActionItemView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Items")
                    .font(.title2)
                    .fontWeight(.bold)

                if pendingCount > 0 {
                    Text("\(pendingCount) pending\(overdueCount > 0 ? ", \(overdueCount) overdue" : "")")
                        .font(.caption)
                        .foregroundColor(overdueCount > 0 ? .red : .secondary)
                }
            }

            Spacer()

            Button(action: { showingAddItem = true }) {
                Label("Add Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        HStack(spacing: 12) {
            ForEach(FilterOption.allCases, id: \.self) { option in
                FilterTab(
                    title: option.rawValue,
                    isSelected: filterOption == option,
                    count: countForFilter(option)
                ) {
                    withAnimation { filterOption = option }
                }
            }

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func countForFilter(_ filter: FilterOption) -> Int {
        switch filter {
        case .all: return actionItems.count
        case .myTasks: return myTasksCount
        case .theirTasks: return theirTasksCount
        case .pending: return pendingCount
        case .overdue: return overdueCount
        case .completed: return actionItems.filter { $0.isCompleted }.count
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    ActionItemRow(item: item)
                        .contextMenu {
                            Button(item.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                                toggleCompletion(item)
                            }
                            Divider()
                            Button("Send to Reminders") {
                                sendToReminders(item)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteItem(item)
                            }
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(emptyStateTitle)
                .font(.headline)

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if filterOption == .pending || filterOption == .all {
                Button("Add Action Item") {
                    showingAddItem = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private var emptyStateTitle: String {
        switch filterOption {
        case .all: return "No Action Items"
        case .myTasks: return "No Tasks for You"
        case .theirTasks: return "No Tasks for Others"
        case .pending: return "All Caught Up!"
        case .overdue: return "No Overdue Items"
        case .completed: return "No Completed Items"
        }
    }

    private var emptyStateMessage: String {
        switch filterOption {
        case .all: return "Action items from your meetings will appear here"
        case .myTasks: return "You have no tasks assigned to yourself"
        case .theirTasks: return "No tasks are assigned to other people"
        case .pending: return "You have no pending action items"
        case .overdue: return "Great job staying on top of your tasks!"
        case .completed: return "Complete some items to see them here"
        }
    }

    // MARK: - Actions

    private func toggleCompletion(_ item: ActionItem) {
        withAnimation {
            item.toggleCompletion()
            try? viewContext.save()

            // Sync to Apple Reminders if linked
            if item.reminderID != nil {
                Task {
                    await RemindersIntegration.shared.updateReminderCompletion(for: item)
                }
            }
        }
    }

    private func deleteItem(_ item: ActionItem) {
        withAnimation {
            viewContext.delete(item)
            try? viewContext.save()
        }
    }

    private func sendToReminders(_ item: ActionItem) {
        Task {
            await RemindersIntegration.shared.createReminder(from: item)
        }
    }
}

// MARK: - Filter Tab

struct FilterTab: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Item Row

struct ActionItemRow: View {
    @ObservedObject var item: ActionItem
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack(spacing: 12) {
            // Completion checkbox
            Button(action: toggleCompletion) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Untitled")
                    .font(.headline)
                    .strikethrough(item.isCompleted)
                    .foregroundColor(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Priority badge
                    PriorityBadge(priority: item.priorityEnum)

                    // Owner badge
                    OwnerBadge(item: item)

                    // Due date
                    if let dueText = item.formattedDueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(dueText)
                        }
                        .font(.caption)
                        .foregroundColor(item.isOverdue ? .red : .secondary)
                    }

                    // Linked person
                    if let person = item.person {
                        HStack(spacing: 2) {
                            Image(systemName: "link")
                            Text(person.name ?? "Unknown")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            // Reminder indicator
            if item.reminderID != nil {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(item.isOverdue ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func toggleCompletion() {
        withAnimation {
            item.toggleCompletion()
            try? viewContext.save()

            // Sync to Apple Reminders if linked
            if item.reminderID != nil {
                Task {
                    await RemindersIntegration.shared.updateReminderCompletion(for: item)
                }
            }
        }
    }
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: ActionItem.Priority

    var body: some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch priority {
        case .high: return Color.red.opacity(0.2)
        case .medium: return Color.orange.opacity(0.2)
        case .low: return Color.blue.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

// MARK: - Owner Badge

struct OwnerBadge: View {
    let item: ActionItem

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: item.isMyTask ? "person.fill" : "person")
            Text(item.ownerDisplayName)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(item.isMyTask ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.15))
        .foregroundColor(item.isMyTask ? .blue : .secondary)
        .cornerRadius(4)
    }
}

// MARK: - Add Action Item View

struct AddActionItemView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil"),
        animation: .default
    )
    private var allPeople: FetchedResults<Person>

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var priority: ActionItem.Priority = .medium
    @State private var ownerSelection: String = "me"
    @State private var customAssignee = ""
    @State private var sendToReminders = true
    @State private var showingSuggestions = false

    /// People matching the search query
    private var matchingPeople: [Person] {
        guard !customAssignee.isEmpty else { return [] }
        let query = customAssignee.lowercased()
        return allPeople.filter { p in
            p.name?.lowercased().contains(query) == true ||
            p.role?.lowercased().contains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)

                Spacer()

                Text("New Action Item")
                    .font(.headline)

                Spacer()

                Button("Save") { saveItem() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section {
                    TextField("What needs to be done?", text: $title)
                        .font(.title3)
                }

                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        ForEach(ActionItem.Priority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }

                    Picker("Owner", selection: $ownerSelection) {
                        Text("Me").tag("me")
                        Text("Other...").tag("other")
                    }
                    .onChange(of: ownerSelection) { _, newValue in
                        sendToReminders = (newValue == "me")
                    }

                    if ownerSelection == "other" {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Search contacts or enter name...", text: $customAssignee)
                                .onChange(of: customAssignee) { _, _ in
                                    showingSuggestions = !customAssignee.isEmpty && !matchingPeople.isEmpty
                                }

                            // Suggestions dropdown
                            if showingSuggestions && !matchingPeople.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(matchingPeople.prefix(5)) { suggestedPerson in
                                        Button(action: {
                                            customAssignee = suggestedPerson.name ?? ""
                                            showingSuggestions = false
                                        }) {
                                            HStack(spacing: 10) {
                                                // Avatar
                                                if let data = suggestedPerson.photo, let image = NSImage(data: data) {
                                                    Image(nsImage: image)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 28, height: 28)
                                                        .clipShape(Circle())
                                                } else {
                                                    Circle()
                                                        .fill(Color.accentColor.opacity(0.15))
                                                        .frame(width: 28, height: 28)
                                                        .overlay {
                                                            Text(suggestedPerson.initials)
                                                                .font(.system(size: 10, weight: .medium))
                                                                .foregroundColor(.accentColor)
                                                        }
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(suggestedPerson.name ?? "Unknown")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.primary)
                                                    if let role = suggestedPerson.role, !role.isEmpty {
                                                        Text(role)
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                                        if suggestedPerson.id != matchingPeople.prefix(5).last?.id {
                                            Divider()
                                                .padding(.leading, 50)
                                        }
                                    }
                                }
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                    }

                    Toggle("Set Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due Date", selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ))
                    }

                    if ownerSelection == "me" {
                        Toggle("Also create Apple Reminder", isOn: $sendToReminders)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 580)
    }

    private func saveItem() {
        let isMyTask = (ownerSelection == "me")
        let assignee: String? = ownerSelection == "other" && !customAssignee.isEmpty ? customAssignee : nil

        let item = ActionItem.create(
            in: viewContext,
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            assignee: assignee,
            isMyTask: isMyTask
        )
        item.notes = notes.isEmpty ? nil : notes

        do {
            try viewContext.save()

            // Send to Apple Reminders if selected
            if isMyTask && sendToReminders {
                Task {
                    await RemindersIntegration.shared.createReminder(from: item)
                }
            }

            dismiss()
        } catch {
            print("Failed to save action item: \(error)")
        }
    }
}

#Preview {
    ActionItemsView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .frame(width: 600, height: 500)
}
