import SwiftUI
import CoreData

struct GroupsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedGroup: Group?
    @State private var showingCreateGroup = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Group.name, ascending: true)],
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
                    GroupRow(group: group, isSelected: selectedGroup == group) {
                        selectedGroup = group
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .liquidGlassBackground(cornerRadius: 0, elevation: .low)
    }
}

// MARK: - Group Row Component
struct GroupRow: View {
    let group: Group
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    
    private var memberCount: Int {
        // Count unique participants from group meetings
        let meetings = group.meetings as? Set<GroupMeeting> ?? []
        let uniqueParticipants = Set(meetings.flatMap { meeting in
            // Parse participants from transcript or other fields
            return [] as [String] // Placeholder - would parse from meeting data
        })
        return uniqueParticipants.count
    }
    
    private var lastMeetingDate: Date? {
        let meetings = group.meetings as? Set<GroupMeeting> ?? []
        return meetings.map { $0.date ?? Date.distantPast }.max()
    }
    
    private var meetingCount: Int {
        (group.meetings as? Set<GroupMeeting>)?.count ?? 0
    }
    
    var body: some View {
        LiquidGlassListRow(
            isSelected: isSelected,
            action: action
        ) {
            HStack(spacing: 16) {
                // Group Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                
                // Group Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name ?? "Unnamed Group")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
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
                        // Show group meetings
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("View Meetings")
                    
                    // Add meeting button
                    Button(action: {
                        // Add new group meeting
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
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
        newGroup.createdAt = Date()
        
        // Note: We're not directly linking people to groups in the current model
        // This would require updating the Core Data model
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error creating group: \(error)")
        }
    }
}