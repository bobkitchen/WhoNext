import Foundation
import CoreData
import SwiftUI

/// Manages the assignment of meetings to individuals, groups, or mixed audiences
class MeetingAssignmentManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MeetingAssignmentManager()
    
    // MARK: - Published Properties
    @Published var assignmentRules: [AssignmentRule] = []
    @Published var recentAssignments: [RecentAssignment] = []
    
    // MARK: - Private Properties
    private let context = PersistenceController.shared.container.viewContext
    private let assignmentThreshold = 4 // Max attendees for individual assignment
    
    // MARK: - Initialization
    
    private init() {
        loadAssignmentRules()
        loadRecentAssignments()
    }
    
    // MARK: - Assignment Logic
    
    /// Determine assignment for a meeting based on attendees
    func determineAssignment(for meeting: LiveMeeting) -> MeetingAssignment {
        let attendeeCount = meeting.identifiedParticipants.count
        
        // Check for matching rule
        if let rule = findMatchingRule(for: meeting) {
            return applyRule(rule, to: meeting)
        }
        
        // Default logic based on attendee count
        switch attendeeCount {
        case 0:
            return MeetingAssignment(
                type: .unassigned,
                primaryAssignee: nil,
                secondaryAssignees: [],
                reason: "No attendees identified"
            )
            
        case 1:
            // Self-meeting or note
            return MeetingAssignment(
                type: .individual,
                primaryAssignee: .person(meeting.identifiedParticipants[0]),
                secondaryAssignees: [],
                reason: "Single person meeting/note"
            )
            
        case 2:
            // One-on-one meeting
            return MeetingAssignment(
                type: .individual,
                primaryAssignee: nil, // Will be determined by both participants
                secondaryAssignees: meeting.identifiedParticipants,
                reason: "One-on-one meeting"
            )
            
        case 3...assignmentThreshold:
            // Small group - assign to all individuals
            return MeetingAssignment(
                type: .mixed,
                primaryAssignee: nil,
                secondaryAssignees: meeting.identifiedParticipants,
                reason: "Small group meeting (\(attendeeCount) attendees)"
            )
            
        default:
            // Large group - create or find group
            return assignToGroup(meeting: meeting)
        }
    }
    
    /// Assign meeting to Core Data entities
    func assignMeeting(
        _ groupMeeting: GroupMeeting,
        assignment: MeetingAssignment,
        transcript: String,
        summary: String?
    ) {
        switch assignment.type {
        case .individual:
            assignToIndividuals(
                meeting: groupMeeting,
                assignment: assignment,
                transcript: transcript,
                summary: summary
            )
            
        case .group:
            assignToGroup(
                meeting: groupMeeting,
                assignment: assignment,
                transcript: transcript,
                summary: summary
            )
            
        case .mixed:
            assignToMixed(
                meeting: groupMeeting,
                assignment: assignment,
                transcript: transcript,
                summary: summary
            )
            
        case .unassigned:
            // Store as orphaned meeting for later assignment
            groupMeeting.setValue("unassigned", forKey: "assignmentType")
        }
        
        // Save assignment history
        saveAssignmentHistory(meeting: groupMeeting, assignment: assignment)
        
        // Save context
        do {
            try context.save()
            print("✅ Meeting assigned successfully")
        } catch {
            print("❌ Failed to save assignment: \(error)")
        }
    }
    
    // MARK: - Private Assignment Methods
    
    private func assignToIndividuals(
        meeting: GroupMeeting,
        assignment: MeetingAssignment,
        transcript: String,
        summary: String?
    ) {
        // For one-on-one meetings, create conversation for both participants
        for participant in assignment.secondaryAssignees {
            if let person = findOrCreatePerson(from: participant) {
                // Create conversation record
                let conversation = Conversation(context: context)
                conversation.uuid = UUID()
                conversation.date = meeting.date
                conversation.duration = meeting.duration
                conversation.person = person
                conversation.notes = transcript
                conversation.summary = summary
                
                // Link to group meeting
                meeting.addToAttendees(person)
                
                // Note: lastContactDate is computed from conversations
                // No need to update it manually
            }
        }
        
        meeting.setValue("individual", forKey: "assignmentType")
    }
    
    private func assignToGroup(
        meeting: GroupMeeting,
        assignment: MeetingAssignment,
        transcript: String,
        summary: String?
    ) {
        // Find or create group
        let group: Group
        
        if case .group(let existingGroup) = assignment.primaryAssignee {
            group = existingGroup as? Group ?? createGroup(for: meeting)
        } else {
            group = createGroup(for: meeting)
        }
        
        // Assign meeting to group
        meeting.group = group
        meeting.setValue("group", forKey: "assignmentType")
        
        // Add attendees
        for participant in assignment.secondaryAssignees {
            if let person = findOrCreatePerson(from: participant) {
                meeting.addToAttendees(person)
                group.addToMembers(person)
            }
        }
        
        // Update group metadata
        group.lastMeetingDate = meeting.date
    }
    
    private func assignToMixed(
        meeting: GroupMeeting,
        assignment: MeetingAssignment,
        transcript: String,
        summary: String?
    ) {
        // Create both individual conversations and group assignment
        
        // First, handle group aspect
        let group = createGroup(for: meeting)
        meeting.group = group
        
        // Then create individual conversations for key participants
        for participant in assignment.secondaryAssignees {
            if let person = findOrCreatePerson(from: participant) {
                // Add to meeting attendees
                meeting.addToAttendees(person)
                group.addToMembers(person)
                
                // Create lightweight conversation reference
                let conversation = Conversation(context: context)
                conversation.uuid = UUID()
                conversation.date = meeting.date
                conversation.duration = meeting.duration
                conversation.person = person
                conversation.summary = "Group meeting: \(meeting.displayTitle)"
                conversation.notes = "[See group meeting for full transcript]"
                
                // Note: lastContactDate is computed from conversations
                // No need to update it manually
            }
        }
        
        meeting.setValue("mixed", forKey: "assignmentType")
    }
    
    private func assignToGroup(meeting: LiveMeeting) -> MeetingAssignment {
        // Try to identify existing group based on attendees
        if let existingGroup = findExistingGroup(attendees: meeting.identifiedParticipants) {
            return MeetingAssignment(
                type: .group,
                primaryAssignee: .group(existingGroup),
                secondaryAssignees: meeting.identifiedParticipants,
                reason: "Matched existing group: \(existingGroup.name ?? "Unnamed")"
            )
        }
        
        // Create new group
        return MeetingAssignment(
            type: .group,
            primaryAssignee: nil, // Will create new group
            secondaryAssignees: meeting.identifiedParticipants,
            reason: "Large meeting (\(meeting.identifiedParticipants.count) attendees) - new group"
        )
    }
    
    // MARK: - Entity Management
    
    private func findOrCreatePerson(from participant: IdentifiedParticipant) -> Person? {
        guard let name = participant.name else { return nil }
        
        // Try to find existing person
        let fetchRequest: NSFetchRequest<Person> = Person.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        
        if let existingPerson = try? context.fetch(fetchRequest).first {
            return existingPerson
        }
        
        // Create new person
        let person = Person(context: context)
        person.identifier = UUID()
        person.name = name
        person.createdAt = Date()
        
        return person
    }
    
    private func createGroup(for meeting: GroupMeeting) -> Group {
        let group = Group(context: context)
        group.identifier = UUID()
        group.name = meeting.title ?? "Meeting Group \(Date().formatted())"
        group.createdAt = Date()
        group.type = determineGroupType(attendeeCount: meeting.attendeeCount)
        
        return group
    }
    
    private func createGroup(for meeting: LiveMeeting) -> Group {
        let group = Group(context: context)
        group.identifier = UUID()
        group.name = meeting.calendarTitle ?? "Meeting Group \(Date().formatted())"
        group.createdAt = Date()
        group.type = determineGroupType(attendeeCount: meeting.identifiedParticipants.count)
        
        return group
    }
    
    private func findExistingGroup(attendees: [IdentifiedParticipant]) -> Group? {
        let attendeeNames = attendees.compactMap { $0.name }
        guard !attendeeNames.isEmpty else { return nil }
        
        // Find groups with similar member composition
        let fetchRequest: NSFetchRequest<Group> = Group.fetchRequest()
        
        do {
            let groups = try context.fetch(fetchRequest)
            
            // Find best matching group (>70% member overlap)
            for group in groups {
                let groupMembers = (group.members as? Set<Person> ?? []).compactMap { $0.name }
                let overlap = Set(attendeeNames).intersection(Set(groupMembers))
                
                let overlapRatio = Double(overlap.count) / Double(max(attendeeNames.count, groupMembers.count))
                if overlapRatio > 0.7 {
                    return group
                }
            }
        } catch {
            print("Failed to find existing groups: \(error)")
        }
        
        return nil
    }
    
    private func determineGroupType(attendeeCount: Int) -> String {
        switch attendeeCount {
        case 0...2:
            return "one-on-one"
        case 3...5:
            return "small-team"
        case 6...15:
            return "team"
        default:
            return "all-hands"
        }
    }
    
    // MARK: - Assignment Rules
    
    private func findMatchingRule(for meeting: LiveMeeting) -> AssignmentRule? {
        for rule in assignmentRules {
            if rule.matches(meeting) {
                return rule
            }
        }
        return nil
    }
    
    private func applyRule(_ rule: AssignmentRule, to meeting: LiveMeeting) -> MeetingAssignment {
        // Apply custom rule logic
        return MeetingAssignment(
            type: rule.assignmentType,
            primaryAssignee: rule.primaryAssignee,
            secondaryAssignees: meeting.identifiedParticipants,
            reason: "Applied rule: \(rule.name)"
        )
    }
    
    func addAssignmentRule(_ rule: AssignmentRule) {
        assignmentRules.append(rule)
        saveAssignmentRules()
    }
    
    private func loadAssignmentRules() {
        if let data = UserDefaults.standard.data(forKey: "MeetingAssignmentRules"),
           let decoded = try? JSONDecoder().decode([AssignmentRule].self, from: data) {
            assignmentRules = decoded
        }
    }
    
    private func saveAssignmentRules() {
        if let encoded = try? JSONEncoder().encode(assignmentRules) {
            UserDefaults.standard.set(encoded, forKey: "MeetingAssignmentRules")
        }
    }
    
    // MARK: - Assignment History
    
    private func saveAssignmentHistory(meeting: GroupMeeting, assignment: MeetingAssignment) {
        let recent = RecentAssignment(
            meetingId: meeting.identifier ?? UUID(),
            meetingTitle: meeting.displayTitle,
            assignmentType: assignment.type,
            assignedTo: assignment.displayName,
            date: Date(),
            reason: assignment.reason
        )
        
        recentAssignments.insert(recent, at: 0)
        
        // Keep only last 50
        if recentAssignments.count > 50 {
            recentAssignments = Array(recentAssignments.prefix(50))
        }
        
        saveRecentAssignments()
    }
    
    private func loadRecentAssignments() {
        if let data = UserDefaults.standard.data(forKey: "RecentMeetingAssignments"),
           let decoded = try? JSONDecoder().decode([RecentAssignment].self, from: data) {
            recentAssignments = decoded
        }
    }
    
    private func saveRecentAssignments() {
        if let encoded = try? JSONEncoder().encode(recentAssignments) {
            UserDefaults.standard.set(encoded, forKey: "RecentMeetingAssignments")
        }
    }
}

// MARK: - Supporting Types

struct MeetingAssignment {
    let type: AssignmentType
    let primaryAssignee: AssigneeType?
    let secondaryAssignees: [IdentifiedParticipant]
    let reason: String
    
    var displayName: String {
        switch type {
        case .individual:
            if secondaryAssignees.count == 2 {
                let names = secondaryAssignees.compactMap { $0.name }
                return names.joined(separator: " & ")
            } else {
                return secondaryAssignees.first?.name ?? "Unknown"
            }
        case .group:
            if case .group(let group) = primaryAssignee,
               let groupEntity = group as? Group {
                return groupEntity.name ?? "Unnamed Group"
            }
            return "Group"
        case .mixed:
            return "Mixed (Group + Individuals)"
        case .unassigned:
            return "Unassigned"
        }
    }
}

enum AssignmentType: String, Codable {
    case individual
    case group
    case mixed
    case unassigned
}

enum AssigneeType {
    case person(IdentifiedParticipant)
    case group(NSManagedObject)
}

struct AssignmentRule: Identifiable, Codable {
    let id = UUID()
    let name: String
    let condition: AssignmentCondition
    let assignmentType: AssignmentType
    let targetGroup: String? // Group name if assigning to specific group
    
    func matches(_ meeting: LiveMeeting) -> Bool {
        switch condition {
        case .titleContains(let text):
            return meeting.calendarTitle?.contains(text) ?? false
            
        case .attendeeCountRange(let range):
            return range.contains(meeting.identifiedParticipants.count)
            
        case .hasAttendee(let name):
            return meeting.identifiedParticipants.contains { $0.name == name }
            
        case .recurring:
            // Check if this is a recurring meeting
            return meeting.calendarTitle?.contains("recurring") ?? false
        }
    }
    
    var primaryAssignee: AssigneeType? {
        // Would need to fetch actual group entity
        return nil
    }
}

enum AssignmentCondition: Codable {
    case titleContains(String)
    case attendeeCountRange(ClosedRange<Int>)
    case hasAttendee(String)
    case recurring
}

struct RecentAssignment: Identifiable, Codable {
    let id = UUID()
    let meetingId: UUID
    let meetingTitle: String
    let assignmentType: AssignmentType
    let assignedTo: String
    let date: Date
    let reason: String
}

// MARK: - Assignment Configuration View

struct AssignmentConfigurationView: View {
    @StateObject private var manager = MeetingAssignmentManager.shared
    @State private var showAddRule = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Meeting Assignment Rules")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { showAddRule = true }) {
                    Label("Add Rule", systemImage: "plus")
                }
            }
            
            // Current rules
            if manager.assignmentRules.isEmpty {
                Text("No custom rules configured")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.assignmentRules) { rule in
                            AssignmentRuleRow(rule: rule)
                        }
                    }
                }
            }
            
            Divider()
            
            // Recent assignments
            Text("Recent Assignments")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(manager.recentAssignments.prefix(10)) { assignment in
                        RecentAssignmentRow(assignment: assignment)
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showAddRule) {
            AddAssignmentRuleView { rule in
                manager.addAssignmentRule(rule)
            }
        }
    }
}

struct AssignmentRuleRow: View {
    let rule: AssignmentRule
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(rule.name)
                    .fontWeight(.medium)
                
                Text(conditionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Label(rule.assignmentType.rawValue.capitalized, systemImage: iconForType(rule.assignmentType))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var conditionDescription: String {
        switch rule.condition {
        case .titleContains(let text):
            return "Title contains: \(text)"
        case .attendeeCountRange(let range):
            return "Attendees: \(range.lowerBound)-\(range.upperBound)"
        case .hasAttendee(let name):
            return "Has attendee: \(name)"
        case .recurring:
            return "Recurring meetings"
        }
    }
    
    private func iconForType(_ type: AssignmentType) -> String {
        switch type {
        case .individual: return "person"
        case .group: return "person.3"
        case .mixed: return "person.2.square.stack"
        case .unassigned: return "questionmark.circle"
        }
    }
}

struct RecentAssignmentRow: View {
    let assignment: RecentAssignment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(assignment.meetingTitle)
                    .font(.caption)
                    .lineLimit(1)
                
                Text("→ \(assignment.assignedTo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(assignment.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

struct AddAssignmentRuleView: View {
    let onSave: (AssignmentRule) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var ruleName = ""
    @State private var conditionType = "title"
    @State private var conditionValue = ""
    @State private var assignmentType: AssignmentType = .group
    @State private var targetGroup = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Assignment Rule")
                .font(.headline)
            
            TextField("Rule Name", text: $ruleName)
            
            // Condition configuration
            Picker("Condition", selection: $conditionType) {
                Text("Title Contains").tag("title")
                Text("Attendee Count").tag("count")
                Text("Has Attendee").tag("attendee")
                Text("Recurring").tag("recurring")
            }
            
            TextField("Value", text: $conditionValue)
                .disabled(conditionType == "recurring")
            
            // Assignment configuration
            Picker("Assign To", selection: $assignmentType) {
                Text("Individual").tag(AssignmentType.individual)
                Text("Group").tag(AssignmentType.group)
                Text("Mixed").tag(AssignmentType.mixed)
            }
            
            if assignmentType == .group {
                TextField("Target Group Name", text: $targetGroup)
            }
            
            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    // Create and save rule
                    let condition: AssignmentCondition
                    switch conditionType {
                    case "title":
                        condition = .titleContains(conditionValue)
                    case "count":
                        let maxCount = Int(conditionValue) ?? 10
                        let range = 0...maxCount
                        condition = .attendeeCountRange(range)
                    case "attendee":
                        condition = .hasAttendee(conditionValue)
                    default:
                        condition = .recurring
                    }
                    
                    let rule = AssignmentRule(
                        name: ruleName,
                        condition: condition,
                        assignmentType: assignmentType,
                        targetGroup: targetGroup.isEmpty ? nil : targetGroup
                    )
                    
                    onSave(rule)
                    dismiss()
                }
                .disabled(ruleName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}