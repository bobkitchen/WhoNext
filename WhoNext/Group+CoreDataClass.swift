import Foundation
import CoreData

@objc(Group)
public class Group: NSManagedObject, @unchecked Sendable {
    
    // MARK: - Computed Properties
    
    /// Returns the number of meetings for this group
    var meetingCount: Int {
        meetings?.count ?? 0
    }
    
    /// Returns the number of members in this group
    var memberCount: Int {
        members?.count ?? 0
    }
    
    /// Returns all meetings sorted by date (newest first)
    var sortedMeetings: [GroupMeeting] {
        let meetingsSet = meetings as? Set<GroupMeeting> ?? []
        return meetingsSet.sorted { meeting1, meeting2 in
            guard let date1 = meeting1.date, let date2 = meeting2.date else { return false }
            return date1 > date2
        }
    }
    
    /// Returns all members sorted by name
    var sortedMembers: [Person] {
        let membersSet = members as? Set<Person> ?? []
        return membersSet.sorted { person1, person2 in
            (person1.name ?? "") < (person2.name ?? "")
        }
    }
    
    /// Returns the most recent meeting
    var mostRecentMeeting: GroupMeeting? {
        sortedMeetings.first
    }
    
    /// Checks if a meeting is scheduled within the next 24 hours
    var hasUpcomingMeeting: Bool {
        guard let nextMeetingDate = nextMeetingDate else { return false }
        let now = Date()
        let twentyFourHoursFromNow = now.addingTimeInterval(24 * 60 * 60)
        return nextMeetingDate >= now && nextMeetingDate <= twentyFourHoursFromNow
    }
    
    // MARK: - Helper Methods
    
    /// Adds a member to the group
    func addMember(_ person: Person) {
        let currentMembers = mutableSetValue(forKey: "members")
        currentMembers.add(person)
    }
    
    /// Removes a member from the group
    func removeMember(_ person: Person) {
        let currentMembers = mutableSetValue(forKey: "members")
        currentMembers.remove(person)
    }
    
    /// Adds a meeting to the group
    func addMeeting(_ meeting: GroupMeeting) {
        let currentMeetings = mutableSetValue(forKey: "meetings")
        currentMeetings.add(meeting)
        
        // Update last meeting date
        if let meetingDate = meeting.date {
            if lastMeetingDate == nil || meetingDate > lastMeetingDate! {
                lastMeetingDate = meetingDate
            }
        }
    }
    
    /// Creates a new meeting for this group
    func createMeeting(context: NSManagedObjectContext) -> GroupMeeting {
        let meeting = GroupMeeting(context: context)
        meeting.identifier = UUID()
        meeting.createdAt = Date()
        meeting.group = self
        meeting.date = Date()
        
        // Add current members as attendees
        if let members = members as? Set<Person> {
            meeting.attendees = NSSet(set: members)
        }
        
        addMeeting(meeting)
        return meeting
    }
    
    // MARK: - Soft Delete
    
    /// Marks the group as soft deleted
    func softDelete() {
        isSoftDeleted = true
        deletedAt = Date()
        
        // Also soft delete all meetings
        if let meetings = meetings as? Set<GroupMeeting> {
            for meeting in meetings {
                meeting.softDelete()
            }
        }
    }
    
    /// Restores a soft deleted group
    func restore() {
        isSoftDeleted = false
        deletedAt = nil
        
        // Also restore all meetings
        if let meetings = meetings as? Set<GroupMeeting> {
            for meeting in meetings {
                meeting.restore()
            }
        }
    }
}