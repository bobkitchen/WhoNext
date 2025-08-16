import Foundation
import CoreData

extension Group {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Group> {
        return NSFetchRequest<Group>(entityName: "Group")
    }
    
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var groupDescription: String?
    @NSManaged public var identifier: UUID?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var lastMeetingDate: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var name: String?
    @NSManaged public var nextMeetingDate: Date?
    @NSManaged public var type: String?
    @NSManaged public var meetings: NSSet?
    @NSManaged public var members: NSSet?
}

// MARK: - Generated accessors for meetings
extension Group {
    
    @objc(addMeetingsObject:)
    @NSManaged public func addToMeetings(_ value: GroupMeeting)
    
    @objc(removeMeetingsObject:)
    @NSManaged public func removeFromMeetings(_ value: GroupMeeting)
    
    @objc(addMeetings:)
    @NSManaged public func addToMeetings(_ values: NSSet)
    
    @objc(removeMeetings:)
    @NSManaged public func removeFromMeetings(_ values: NSSet)
}

// MARK: - Generated accessors for members
extension Group {
    
    @objc(addMembersObject:)
    @NSManaged public func addToMembers(_ value: Person)
    
    @objc(removeMembersObject:)
    @NSManaged public func removeFromMembers(_ value: Person)
    
    @objc(addMembers:)
    @NSManaged public func addToMembers(_ values: NSSet)
    
    @objc(removeMembers:)
    @NSManaged public func removeFromMembers(_ values: NSSet)
}

extension Group: Identifiable {
    public var id: UUID {
        identifier ?? UUID()
    }
}