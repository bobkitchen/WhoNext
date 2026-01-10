import Foundation
import CoreData

@objc(ActionItem)
public class ActionItem: NSManagedObject {

    // MARK: - Priority Enum

    enum Priority: String, CaseIterable {
        case high = "high"
        case medium = "medium"
        case low = "low"

        var displayName: String {
            switch self {
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            }
        }

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "blue"
            }
        }
    }

    // MARK: - Computed Properties

    var priorityEnum: Priority {
        get { Priority(rawValue: priority ?? "medium") ?? .medium }
        set { priority = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
    }

    var isDueSoon: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        let dayFromNow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return due <= dayFromNow && due >= Date()
    }

    var formattedDueDate: String? {
        guard let due = dueDate else { return nil }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(due) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInTomorrow(due) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: due)
    }

    /// Display name for the owner of this action item
    var ownerDisplayName: String {
        if isMyTask {
            return "Me"
        } else {
            return assignee ?? person?.name ?? "Them"
        }
    }

    // MARK: - Factory Methods

    /// Create a new action item
    static func create(
        in context: NSManagedObjectContext,
        title: String,
        dueDate: Date? = nil,
        priority: Priority = .medium,
        assignee: String? = nil,
        isMyTask: Bool = false,
        conversation: Conversation? = nil,
        person: Person? = nil
    ) -> ActionItem {
        let item = ActionItem(context: context)
        item.identifier = UUID()
        item.title = title
        item.dueDate = dueDate
        item.priorityEnum = priority
        item.assignee = assignee
        item.isMyTask = isMyTask
        item.isCompleted = false
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.conversation = conversation
        item.person = person
        return item
    }

    // MARK: - Actions

    /// Mark the action item as completed
    func markComplete() {
        isCompleted = true
        completedAt = Date()
        modifiedAt = Date()
    }

    /// Mark the action item as incomplete
    func markIncomplete() {
        isCompleted = false
        completedAt = nil
        modifiedAt = Date()
    }

    /// Toggle completion status
    func toggleCompletion() {
        if isCompleted {
            markIncomplete()
        } else {
            markComplete()
        }
    }

    // MARK: - Fetch Requests

    /// Fetch all incomplete action items, sorted by due date
    static func fetchIncomplete(in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "isCompleted == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.createdAt, ascending: false)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch incomplete action items: \(error)")
            return []
        }
    }

    /// Fetch action items for a specific person
    static func fetchForPerson(_ person: Person, in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "person == %@", person)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch action items for person: \(error)")
            return []
        }
    }

    /// Fetch action items for a specific conversation
    static func fetchForConversation(_ conversation: Conversation, in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "conversation == %@", conversation)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.createdAt, ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch action items for conversation: \(error)")
            return []
        }
    }

    /// Fetch overdue action items
    static func fetchOverdue(in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "isCompleted == NO AND dueDate < %@", Date() as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch overdue action items: \(error)")
            return []
        }
    }

    /// Fetch my action items (tasks I own)
    static func fetchMyTasks(in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "isMyTask == YES")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch my action items: \(error)")
            return []
        }
    }

    /// Fetch their action items (tasks others own)
    static func fetchTheirTasks(in context: NSManagedObjectContext) -> [ActionItem] {
        let request: NSFetchRequest<ActionItem> = ActionItem.fetchRequest()
        request.predicate = NSPredicate(format: "isMyTask == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ActionItem.isCompleted, ascending: true),
            NSSortDescriptor(keyPath: \ActionItem.dueDate, ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch their action items: \(error)")
            return []
        }
    }
}
