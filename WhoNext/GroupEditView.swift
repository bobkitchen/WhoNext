import SwiftUI
import CoreData

struct GroupEditView: View {
    @ObservedObject var group: Group
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var name: String = ""
    @State private var groupDescription: String = ""
    @State private var type: String = ""

    private let groupTypes = ["Team", "Project", "Department", "External", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Group")
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
                    TextField("Group Name", text: $name)

                    Picker("Type", selection: $type) {
                        Text("Select Type").tag("")
                        ForEach(groupTypes, id: \.self) { groupType in
                            Text(groupType).tag(groupType)
                        }
                    }

                    TextField("Description (optional)", text: $groupDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Members") {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.secondary)
                        Text("\(group.memberCount) members")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Manage members from the group detail view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Statistics") {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text("\(group.meetingCount) meetings")
                    }

                    if let lastMeeting = group.lastMeetingDate {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("Last meeting: \(lastMeeting, formatter: dateFormatter)")
                        }
                    }

                    if let createdAt = group.createdAt {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundColor(.secondary)
                            Text("Created: \(createdAt, formatter: dateFormatter)")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button(role: .destructive, action: deleteGroup) {
                    Label("Delete Group", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .onAppear {
            name = group.name ?? ""
            groupDescription = group.groupDescription ?? ""
            type = group.type ?? ""
        }
    }

    private func saveChanges() {
        group.name = name
        group.groupDescription = groupDescription
        group.type = type
        group.modifiedAt = Date()

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving group: \(error)")
        }
    }

    private func deleteGroup() {
        group.softDelete()

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error deleting group: \(error)")
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Add Member to Group View
struct AddMemberToGroupView: View {
    let group: Group
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var searchText = ""
    @State private var selectedPeople: Set<Person> = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var allPeople: FetchedResults<Person>

    private var availablePeople: [Person] {
        let existingMembers = group.members as? Set<Person> ?? []
        return allPeople.filter { person in
            // Exclude existing members and current user
            !existingMembers.contains(person) && !person.isCurrentUser
        }.filter { person in
            // Apply search filter
            if searchText.isEmpty { return true }
            let name = person.name?.lowercased() ?? ""
            let role = person.role?.lowercased() ?? ""
            let search = searchText.lowercased()
            return name.contains(search) || role.contains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Members to \(group.name ?? "Group")")
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

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search people...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            // People List
            if availablePeople.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "person.crop.circle.badge.checkmark" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "All contacts are already members" : "No matching contacts found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availablePeople, id: \.identifier) { person in
                            PersonSelectionRow(
                                person: person,
                                isSelected: selectedPeople.contains(person)
                            ) {
                                if selectedPeople.contains(person) {
                                    selectedPeople.remove(person)
                                } else {
                                    selectedPeople.insert(person)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Actions
            HStack {
                Text("\(selectedPeople.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Add Members") {
                    addMembers()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(selectedPeople.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }

    private func addMembers() {
        for person in selectedPeople {
            group.addMember(person)
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error adding members: \(error)")
        }
    }
}

// MARK: - Person Selection Row
struct PersonSelectionRow: View {
    let person: Person
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                // Avatar
                ZStack {
                    if let data = person.photo, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(person.initials)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Group Meeting View
struct CreateGroupMeetingView: View {
    let group: Group
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title = ""
    @State private var date = Date()
    @State private var duration: Int = 30
    @State private var notes = ""
    @State private var selectedAttendees: Set<Person> = []

    private var members: [Person] {
        group.sortedMembers
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Meeting for \(group.name ?? "Group")")
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
                Section("Meeting Details") {
                    TextField("Meeting Title (optional)", text: $title)

                    DatePicker("Date & Time", selection: $date)

                    Picker("Duration", selection: $duration) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("1 hour").tag(60)
                        Text("1.5 hours").tag(90)
                        Text("2 hours").tag(120)
                    }
                }

                Section("Attendees") {
                    if members.isEmpty {
                        Text("No members in this group. Add members first to track attendees.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(members, id: \.identifier) { person in
                            HStack {
                                Image(systemName: selectedAttendees.contains(person) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedAttendees.contains(person) ? .accentColor : .secondary)

                                Text(person.name ?? "Unknown")

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedAttendees.contains(person) {
                                    selectedAttendees.remove(person)
                                } else {
                                    selectedAttendees.insert(person)
                                }
                            }
                        }

                        Button("Select All") {
                            selectedAttendees = Set(members)
                        }
                        .font(.caption)
                    }
                }

                Section("Notes") {
                    TextField("Meeting notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
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

                Button("Create Meeting") {
                    createMeeting()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            // Pre-select all members by default
            selectedAttendees = Set(members)
        }
    }

    private func createMeeting() {
        let meeting = GroupMeeting(context: viewContext)
        meeting.identifier = UUID()
        meeting.createdAt = Date()
        meeting.date = date
        meeting.duration = Int32(duration * 60) // Convert to seconds
        meeting.group = group
        meeting.notes = notes.isEmpty ? nil : notes

        // Set title or generate one
        if title.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            meeting.title = "\(group.name ?? "Group") - \(dateFormatter.string(from: date))"
        } else {
            meeting.title = title
        }

        // Add attendees
        for person in selectedAttendees {
            meeting.addAttendee(person)
        }

        // Update group's last meeting date
        group.lastMeetingDate = date
        group.addMeeting(meeting)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error creating meeting: \(error)")
        }
    }
}
