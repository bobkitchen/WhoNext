import Foundation
import CoreData

@objc(Conversation)
public class Conversation: NSManagedObject {
    @NSManaged public var date: Date?
    @NSManaged public var legacyId: Date?
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var notes: String?
    @NSManaged public var summary: String?
    @NSManaged public var uuid: UUID?
    @NSManaged public var person: Person?
}

extension Conversation: Identifiable {
    public var id: UUID {
        get {
            return uuid ?? UUID()
        }
        set {
            uuid = newValue
        }
    }
} 