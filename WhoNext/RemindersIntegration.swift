import Foundation
import EventKit
import CoreData
import SwiftUI

/// Handles integration with Apple Reminders
/// Allows creating reminders from action items and syncing completion status
@MainActor
class RemindersIntegration: ObservableObject {

    static let shared = RemindersIntegration()

    private let eventStore = EKEventStore()

    @Published var isAuthorized = false
    @Published var lastError: String?
    @Published var availableLists: [EKCalendar] = []

    /// Selected reminders list ID (empty = use default)
    @AppStorage("selectedRemindersListID") var selectedListID: String = ""

    /// Observer for EKEventStore changes
    private var notificationObserver: NSObjectProtocol?

    private init() {
        checkAuthorization()
    }

    // MARK: - Authorization

    /// Check current authorization status
    func checkAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        isAuthorized = (status == .fullAccess || status == .authorized)
        print("📋 Reminders authorization status: \(status.rawValue), isAuthorized: \(isAuthorized)")
    }

    /// Request access to reminders
    func requestAccess() async -> Bool {
        let currentStatus = EKEventStore.authorizationStatus(for: .reminder)
        print("📋 Current Reminders status before request: \(currentStatus.rawValue)")

        // If already denied, inform the user they need to go to Settings
        if currentStatus == .denied {
            await MainActor.run {
                lastError = "Reminders access was denied. Please enable it in System Settings > Privacy & Security > Reminders."
            }
            print("❌ Reminders access was previously denied - user must enable in System Settings")
            return false
        }

        do {
            print("📋 Requesting full access to Reminders...")
            let granted = try await eventStore.requestFullAccessToReminders()
            await MainActor.run {
                isAuthorized = granted
                if !granted {
                    lastError = "Reminders access was not granted. Please enable it in System Settings > Privacy & Security > Reminders."
                }
            }
            print("📋 Reminders access granted: \(granted)")
            return granted
        } catch {
            await MainActor.run {
                lastError = "Failed to request Reminders access: \(error.localizedDescription)"
            }
            print("❌ Failed to request Reminders access: \(error)")
            return false
        }
    }

    // MARK: - List Selection

    /// Fetch all available reminder lists
    func fetchAvailableLists() {
        guard isAuthorized else {
            availableLists = []
            return
        }
        let calendars = eventStore.calendars(for: .reminder)
        availableLists = calendars.sorted { $0.title < $1.title }
        print("📋 Found \(availableLists.count) reminder lists")
    }

    /// Get the target calendar for new reminders (selected or default)
    func getTargetCalendar() -> EKCalendar? {
        // Try to use selected calendar
        if !selectedListID.isEmpty,
           let calendar = eventStore.calendar(withIdentifier: selectedListID) {
            return calendar
        }
        // Fall back to default
        return eventStore.defaultCalendarForNewReminders()
    }

    /// Get the display name of the currently selected list
    var selectedListName: String {
        if selectedListID.isEmpty {
            return "Default List"
        }
        if let calendar = eventStore.calendar(withIdentifier: selectedListID) {
            return calendar.title
        }
        return "Default List"
    }

    // MARK: - Change Observer

    /// Start observing changes in the EKEventStore (to sync when Reminders app changes)
    func startObservingChanges() {
        guard notificationObserver == nil else { return }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleStoreChanged()
            }
        }
        print("📋 Started observing Reminders changes")
    }

    /// Stop observing changes
    func stopObservingChanges() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
            print("📋 Stopped observing Reminders changes")
        }
    }

    /// Handle changes in the event store
    private func handleStoreChanged() async {
        print("📋 EKEventStore changed - syncing reminders...")
        let context = PersistenceController.shared.container.viewContext
        await syncAllReminders(in: context)
    }

    // MARK: - Create Reminder

    /// Create an Apple Reminder from an ActionItem
    func createReminder(from actionItem: ActionItem) async -> Bool {
        print("📋 Creating reminder for: \(actionItem.title ?? "Untitled")")

        // Request access if not authorized
        if !isAuthorized {
            print("📋 Not authorized, requesting access...")
            let granted = await requestAccess()
            if !granted {
                print("❌ Reminders access not granted")
                return false
            }
        }

        // Get target reminders calendar (selected or default)
        guard let calendar = getTargetCalendar() else {
            lastError = "No reminders list found. Please ensure you have a Reminders list set up."
            print("❌ No reminders calendar found")
            return false
        }
        print("📋 Using reminders list: \(calendar.title)")

        // Create the reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = actionItem.title ?? "Untitled Action Item"
        reminder.calendar = calendar

        // Set due date if available
        if let dueDate = actionItem.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )

            // Add alarm 30 minutes before due date
            let alarm = EKAlarm(relativeOffset: -30 * 60) // 30 minutes before
            reminder.addAlarm(alarm)
        }

        // Set priority
        switch actionItem.priorityEnum {
        case .high:
            reminder.priority = 1
        case .medium:
            reminder.priority = 5
        case .low:
            reminder.priority = 9
        }

        // Add notes with context
        var notesText = actionItem.notes ?? ""
        if let conversation = actionItem.conversation {
            if let date = conversation.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                notesText += "\n\nFrom meeting on \(formatter.string(from: date))"
            }
            if let person = conversation.person {
                notesText += " with \(person.name ?? "Unknown")"
            }
        }
        reminder.notes = notesText.isEmpty ? nil : notesText

        // Save the reminder
        do {
            try eventStore.save(reminder, commit: true)

            // Store the reminder ID in the action item
            actionItem.reminderID = reminder.calendarItemIdentifier
            actionItem.modifiedAt = Date()

            // Save Core Data context
            if let context = actionItem.managedObjectContext {
                try context.save()
            }

            print("✅ Created reminder: \(reminder.title ?? "Untitled")")
            return true
        } catch {
            lastError = error.localizedDescription
            print("❌ Failed to create reminder: \(error)")
            return false
        }
    }

    // MARK: - Sync Status

    /// Sync completion status from Reminders back to ActionItem
    func syncReminderStatus(for actionItem: ActionItem) async {
        guard let reminderID = actionItem.reminderID else { return }

        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            // Reminder was deleted
            actionItem.reminderID = nil
            return
        }

        if reminder.isCompleted != actionItem.isCompleted {
            if reminder.isCompleted {
                actionItem.markComplete()
            } else {
                actionItem.markIncomplete()
            }

            if let context = actionItem.managedObjectContext {
                try? context.save()
            }
        }
    }

    /// Update reminder when action item is completed in app
    func updateReminderCompletion(for actionItem: ActionItem) async {
        guard let reminderID = actionItem.reminderID else { return }

        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return
        }

        reminder.isCompleted = actionItem.isCompleted
        if actionItem.isCompleted {
            reminder.completionDate = actionItem.completedAt ?? Date()
        }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            print("❌ Failed to update reminder: \(error)")
        }
    }

    // MARK: - Delete Reminder

    /// Delete the associated reminder when action item is deleted
    func deleteReminder(for actionItem: ActionItem) async {
        guard let reminderID = actionItem.reminderID else { return }

        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return
        }

        do {
            try eventStore.remove(reminder, commit: true)
            print("🗑️ Deleted reminder: \(reminder.title ?? "Untitled")")
        } catch {
            print("❌ Failed to delete reminder: \(error)")
        }
    }

    // MARK: - Batch Operations

    /// Create reminders for multiple action items
    func createReminders(from actionItems: [ActionItem]) async -> Int {
        var successCount = 0
        for item in actionItems {
            if await createReminder(from: item) {
                successCount += 1
            }
        }
        return successCount
    }

    /// Sync all action items with linked reminders
    func syncAllReminders(in context: NSManagedObjectContext) async {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "reminderID != nil")

        do {
            let items = try context.fetch(request)
            for item in items {
                await syncReminderStatus(for: item)
            }
            try context.save()
        } catch {
            print("❌ Failed to sync reminders: \(error)")
        }
    }
}
