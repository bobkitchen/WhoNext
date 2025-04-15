import Foundation
import CoreData

@objc(Person)
public class Person: NSManagedObject {
    @NSManaged public var identifier: UUID?
    @NSManaged public var isDirectReport: Bool
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var photo: Data?
    @NSManaged public var role: String?
    @NSManaged public var scheduledConversationDate: Date?
    @NSManaged public var timezone: String?
    @NSManaged public var conversations: NSSet?
}

// MARK: - Computed Properties
extension Person {
    public var wrappedName: String {
        name ?? "Unknown"
    }
    
    public var wrappedRole: String {
        role ?? "Unknown"
    }
    
    public var wrappedTimezone: String {
        timezone ?? "Unknown"
    }
    
    public var conversationsArray: [Conversation] {
        let set = conversations as? Set<Conversation> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    public var lastContactDate: Date? {
        conversationsArray.first?.date
    }
    
    public var initials: String {
        let components = (name ?? "").split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined()
    }
}

extension Person: Identifiable {
    public var id: UUID {
        get {
            return identifier ?? UUID()
        }
        set {
            identifier = newValue
        }
    }
} 