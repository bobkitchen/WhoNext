import SwiftUI
import CoreData

// MARK: - Inbox Entry Enum
enum InboxEntry: Identifiable {
    case conversation(Conversation)
    case groupMeeting(GroupMeeting)

    var id: UUID {
        switch self {
        case .conversation(let c): return c.uuid ?? UUID()
        case .groupMeeting(let g): return g.identifier ?? UUID()
        }
    }

    var date: Date {
        switch self {
        case .conversation(let c): return c.date ?? Date.distantPast
        case .groupMeeting(let g): return g.date ?? Date.distantPast
        }
    }

    var displayTitle: String {
        switch self {
        case .conversation(let c):
            let title = c.summary?.components(separatedBy: .newlines).first ?? ""
            return title.isEmpty ? "Untitled Conversation" : title
        case .groupMeeting(let g):
            return g.title?.isEmpty == false ? g.title! : "Untitled Meeting"
        }
    }

    var duration: Int32 {
        switch self {
        case .conversation(let c): return c.duration
        case .groupMeeting(let g): return g.duration
        }
    }

    var kindLabel: String {
        switch self {
        case .conversation: return "1:1"
        case .groupMeeting: return "Group"
        }
    }

    var kindIcon: String {
        switch self {
        case .conversation: return "person.2"
        case .groupMeeting: return "person.3"
        }
    }

    /// Name of the placeholder person this is currently assigned to (e.g. "Speaker 3"), or nil if truly orphaned
    var placeholderPersonName: String? {
        switch self {
        case .conversation(let c):
            guard let name = c.person?.name else { return nil }
            return Self.isSpeakerPlaceholder(name) ? name : nil
        case .groupMeeting:
            return nil
        }
    }

    var draggableItem: DraggableMeetingItem {
        switch self {
        case .conversation(let c):
            return DraggableMeetingItem(id: c.uuid ?? UUID(), kind: .conversation)
        case .groupMeeting(let g):
            return DraggableMeetingItem(id: g.identifier ?? UUID(), kind: .groupMeeting)
        }
    }

    /// Returns true if a person name looks like an auto-generated speaker placeholder
    static func isSpeakerPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let pattern = #"^Speaker(\s+\d+)?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Inbox Meeting Card
struct InboxMeetingCard: View {
    let entry: InboxEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var isHovered = false
    @State private var showingAssignPopover = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var allPeople: FetchedResults<Person>

    var body: some View {
        HStack(spacing: 14) {
            // Type icon
            ZStack {
                Circle()
                    .fill(kindColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: entry.kindIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(kindColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(entry.kindLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(kindColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(kindColor.opacity(0.15)))

                    Spacer()
                }

                HStack(spacing: 16) {
                    // Placeholder person label
                    if let speakerName = entry.placeholderPersonName {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 11))
                            Text(speakerName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.orange)
                    }

                    // Date
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(relativeDate)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)

                    // Duration
                    if entry.duration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.system(size: 11))
                            Text("\(entry.duration) min")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Assign button
            Button(action: { showingAssignPopover = true }) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Assign to person")
            .popover(isPresented: $showingAssignPopover, arrowEdge: .trailing) {
                AssignPersonPopover(
                    people: assignablePeople,
                    onAssign: { person in
                        assignToPerson(person)
                        showingAssignPopover = false
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(scale: 1.01)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
        .draggable(entry.draggableItem)
    }

    // MARK: - Computed

    private var assignablePeople: [Person] {
        allPeople.filter { !$0.isCurrentUser && !InboxEntry.isSpeakerPlaceholder($0.name ?? "") }
    }

    private var kindColor: Color {
        switch entry {
        case .conversation: return .blue
        case .groupMeeting: return .green
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.date, relativeTo: Date())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isSelected ?
                Color.accentColor.opacity(0.08) :
                (isHovered ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.4) :
                (isHovered ? Color(NSColor.separatorColor).opacity(0.3) : Color.clear),
                lineWidth: isSelected ? 1.5 : 1
            )
    }

    // MARK: - Assignment

    private func assignToPerson(_ person: Person) {
        let oldPerson: Person?
        switch entry {
        case .conversation(let conversation):
            oldPerson = conversation.person
            conversation.person = person
            conversation.modifiedAt = Date()
        case .groupMeeting(let meeting):
            oldPerson = nil
            meeting.addToAttendees(person)
            meeting.modifiedAt = Date()
        }
        try? viewContext.save()

        // Defer placeholder cleanup to a separate transaction so CloudKit sync
        // can finish processing the reassignment before we delete the Person.
        if let oldPerson, let name = oldPerson.name, InboxEntry.isSpeakerPlaceholder(name) {
            let objectID = oldPerson.objectID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak viewContext] in
                guard let context = viewContext else { return }
                guard let placeholder = try? context.existingObject(with: objectID) as? Person else { return }
                let remaining = (placeholder.conversations as? Set<Conversation>)?.count ?? 0
                if remaining == 0 {
                    context.delete(placeholder)
                    try? context.save()
                }
            }
        }
    }
}

// MARK: - Assign Person Popover
struct AssignPersonPopover: View {
    let people: [Person]
    let onAssign: (Person) -> Void

    @State private var searchText = ""

    private var filteredPeople: [Person] {
        if searchText.isEmpty { return people }
        let search = searchText.lowercased()
        return people.filter { ($0.name ?? "").lowercased().contains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Assign to...")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Search
            TextField("Search people...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // People list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredPeople, id: \.identifier) { person in
                        Button(action: { onAssign(person) }) {
                            HStack(spacing: 10) {
                                // Avatar
                                ZStack {
                                    Circle()
                                        .fill(avatarColor(for: person))
                                        .frame(width: 28, height: 28)
                                    Text(person.initials)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name ?? "Unnamed")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    if let role = person.role, !role.isEmpty {
                                        Text(role)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 260)
    }

    private func avatarColor(for person: Person) -> Color {
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink]
        let index = abs((person.name ?? "").hashValue) % colors.count
        return colors[index]
    }
}
