import Foundation
import CoreData

extension ActionItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ActionItem> {
        return NSFetchRequest<ActionItem>(entityName: "ActionItem")
    }

    @NSManaged public var assignee: String?
    @NSManaged public var completedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var dueDate: Date?
    @NSManaged public var identifier: UUID?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var isMyTask: Bool
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var notes: String?
    @NSManaged public var priority: String?
    @NSManaged public var reminderID: String?
    @NSManaged public var title: String?
    @NSManaged public var conversation: Conversation?
    @NSManaged public var person: Person?
}

extension ActionItem: Identifiable {
    public var id: UUID {
        identifier ?? UUID()
    }
}
