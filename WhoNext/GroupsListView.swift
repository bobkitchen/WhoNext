import SwiftUI
import CoreData

struct GroupsListView: View {
    @Binding var selectedGroup: Group?
    var onGroupSelected: ((Group) -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingCreateGroup = false
    @State private var showingMeetingsSheet = false
    @State private var groupForMeetings: Group?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Group.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    ) private var groups: FetchedResults<Group>
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Add button
            LiquidGlassSectionHeader(
                "Groups",
                subtitle: "\(groups.count) groups",
                actionTitle: "Create Group",
                action: { showingCreateGroup = true }
            )
            
            // Groups List or Empty State
            if groups.isEmpty {
                emptyState
            } else {
                groupsList
            }
        }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView()
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.3.sequence")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
                .symbolEffect(.breathe.wholeSymbol)
            
            VStack(spacing: 8) {
                Text("No Groups Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("Create groups to organize team meetings and track group dynamics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: { showingCreateGroup = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Create Your First Group")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassBackground(cornerRadius: 0, elevation: .low)
    }
    
    private var groupsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(groups, id: \.identifier) { group in
                    GroupRow(
                        group: group,
                        isSelected: selectedGroup == group,
                        onSelect: {
                            selectedGroup = group
                            onGroupSelected?(group)
                        },
                        onViewMeetings: {
                            groupForMeetings = group
                            showingMeetingsSheet = true
                        },
                        onAddMeeting: {
                            // Select the group first, then the detail view will have an add meeting button
                            selectedGroup = group
                            onGroupSelected?(group)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .liquidGlassBackground(cornerRadius: 0, elevation: .low)
        .sheet(isPresented: $showingMeetingsSheet) {
            if let group = groupForMeetings {
                GroupMeetingsSheet(group: group)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
}

// MARK: - Group Meetings Sheet
struct GroupMeetingsSheet: View {
    let group: Group
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    private var meetings: [GroupMeeting] {
        group.sortedMeetings.filter { !$0.isSoftDeleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meetings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(group.name ?? "Group")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if meetings.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No meetings yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Meetings will appear here once recorded or added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(meetings) { meeting in
                            GroupMeetingRowView(meeting: meeting)
                                .environment(\.managedObjectContext, viewContext)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Group Row Component
struct GroupRow: View {
    let group: Group
    let isSelected: Bool
    let onSelect: () -> Void
    var onViewMeetings: (() -> Void)?
    var onAddMeeting: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    private var memberCount: Int {
        group.memberCount
    }

    private var lastMeetingDate: Date? {
        group.lastMeetingDate ?? group.mostRecentMeeting?.date
    }

    private var meetingCount: Int {
        group.meetingCount
    }

    private var groupColor: Color {
        switch group.type?.lowercased() {
        case "team": return .blue
        case "project": return .purple
        case "department": return .green
        case "external": return .orange
        default: return .accentColor
        }
    }

    private var groupIcon: String {
        switch group.type?.lowercased() {
        case "team": return "person.3.fill"
        case "project": return "folder.fill"
        case "department": return "building.2.fill"
        case "external": return "globe"
        default: return "person.3.fill"
        }
    }

    var body: some View {
        LiquidGlassListRow(
            isSelected: isSelected,
            action: onSelect
        ) {
            HStack(spacing: 16) {
                // Group Icon
                ZStack {
                    Circle()
                        .fill(groupColor.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: groupIcon)
                        .font(.system(size: 20))
                        .foregroundColor(groupColor)
                }

                // Group Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name ?? "Unnamed Group")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        // Member count
                        if memberCount > 0 {
                            Label("\(memberCount) members", systemImage: "person.2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Meeting count
                        Label("\(meetingCount) meetings", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Last meeting
                        if let lastMeeting = lastMeetingDate {
                            Label(relativeDate(lastMeeting), systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Quick Actions
                HStack(spacing: 8) {
                    // View meetings button
                    Button(action: {
                        onViewMeetings?()
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View Meetings")

                    // Add meeting button
                    Button(action: {
                        onAddMeeting?()
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add Meeting")
                }
                .opacity(isSelected ? 1 : 0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Create Group View
struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var groupName = ""
    @State private var description = ""
    @State private var selectedPeople: Set<Person> = []
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Group")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Group Information") {
                    TextField("Group Name", text: $groupName)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Members (Optional)") {
                    Text("Select people who are typically in this group's meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(people, id: \.identifier) { person in
                                HStack {
                                    Image(systemName: selectedPeople.contains(person) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedPeople.contains(person) ? .accentColor : .secondary)
                                    
                                    Text(person.name ?? "Unknown")
                                    
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedPeople.contains(person) {
                                        selectedPeople.remove(person)
                                    } else {
                                        selectedPeople.insert(person)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Create Group") {
                    createGroup()
                }
                .keyboardShortcut(.return)
                .disabled(groupName.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
    
    private func createGroup() {
        let newGroup = Group(context: viewContext)
        newGroup.identifier = UUID()
        newGroup.name = groupName
        newGroup.groupDescription = description
        newGroup.createdAt = Date()
        newGroup.modifiedAt = Date()

        // Add selected people as members
        for person in selectedPeople {
            newGroup.addMember(person)
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error creating group: \(error)")
        }
    }
}