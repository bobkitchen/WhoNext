import Foundation
import CoreData

extension GroupMeeting {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupMeeting> {
        return NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
    }
    
    @NSManaged public var audioFilePath: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var date: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var duration: Int32
    @NSManaged public var identifier: UUID?
    @NSManaged public var isAutoRecorded: Bool
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var keyTopics: NSObject?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var notes: String?
    @NSManaged public var qualityScore: Double
    @NSManaged public var scheduledDeletion: Date?
    @NSManaged public var sentimentScore: Double
    @NSManaged public var summary: String?
    @NSManaged public var title: String?
    @NSManaged public var transcript: String?
    @NSManaged public var transcriptData: Data?
    @NSManaged public var attendees: NSSet?
    @NSManaged public var group: Group?
}

// MARK: - Generated accessors for attendees
extension GroupMeeting {
    
    @objc(addAttendeesObject:)
    @NSManaged public func addToAttendees(_ value: Person)
    
    @objc(removeAttendeesObject:)
    @NSManaged public func removeFromAttendees(_ value: Person)
    
    @objc(addAttendees:)
    @NSManaged public func addToAttendees(_ values: NSSet)
    
    @objc(removeAttendees:)
    @NSManaged public func removeFromAttendees(_ values: NSSet)
}

extension GroupMeeting: Identifiable {
    public var id: UUID {
        identifier ?? UUID()
    }
}