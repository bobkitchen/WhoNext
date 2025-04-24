import SwiftUI
import CoreData

struct InsightsView: View {
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    // Calendar integration
    @StateObject private var calendarService = CalendarService.shared
    
    @AppStorage("dismissedPeople") private var dismissedPeopleData: Data = Data()
    @State private var dismissedPeople: [UUID: Date] = [:]
    
    private var suggestedPeople: [Person] {
        let calendar = Calendar.current
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        
        // Get all non-direct reports, sorted alphabetically
        let nonDirectReports = people
            .filter { person in
                guard let name = person.name, !name.isEmpty else { return false }
                guard !person.isDirectReport else { return false }
                
                // Check if person was dismissed within the last month
                if let id = person.identifier,
                   let dismissedDate = dismissedPeople[id],
                   dismissedDate > oneMonthAgo {
                    return false
                }
                
                return true
            }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        
        // Sort by last contact date, putting people we haven't met with first
        return nonDirectReports
            .sorted { 
                let date1 = $0.lastContactDate ?? .distantPast
                let date2 = $1.lastContactDate ?? .distantPast
                return date1 < date2
            }
            .prefix(2)
            .map { $0 }
    }
    
    private var comingUpTomorrow: [Person] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return people.filter {
            guard let scheduled = $0.scheduledConversationDate else { return false }
            return calendar.isDate(scheduled, inSameDayAs: tomorrow)
        }
    }
    
    @State private var showingCalendar: Person? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Upcoming 1:1 Meetings
            VStack(alignment: .leading, spacing: 16) {
                Text("Upcoming 1:1s")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                if calendarService.upcomingMeetings.isEmpty {
                    Text("No upcoming 1:1s")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendarService.upcomingMeetings) { meeting in
                        let matchedPerson = matchPerson(for: meeting)
                        Button(action: {
                            if let person = matchedPerson {
                                selectedPerson = person
                                selectedPersonID = person.identifier
                                selectedTab = .people // Switch to people tab for navigation
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(meeting.title)
                                        .font(.system(size: 15, weight: .medium))
                                    if let person = matchedPerson {
                                        Text(person.name ?? "")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(meeting.startDate, style: .date)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(matchedPerson == nil)
                        .opacity(matchedPerson == nil ? 0.5 : 1.0)
                        .help(matchedPerson == nil ? "No matching person found" : "Go to person detail")
                        .padding(.vertical, 4)
                    }
                }
            }
            .cardStyle()
            
            // Chat Interface
            ChatView()
                .frame(height: 300)
                .cardStyle()
            
            // Suggested People Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Follow-up Needed")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if suggestedPeople.isEmpty {
                    Text("No follow-ups needed")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .cardStyle()
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(suggestedPeople) { person in
                            PersonCardView(
                                person: person,
                                isFollowUp: true,
                                onDismiss: {
                                    if let id = person.identifier {
                                        dismissedPeople[id] = Date()
                                        if let encoded = try? JSONEncoder().encode(dismissedPeople) {
                                            dismissedPeopleData = encoded
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            // Coming Up Tomorrow Section
            if !comingUpTomorrow.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Coming Up Tomorrow")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(comingUpTomorrow) { person in
                            PersonCardView(
                                person: person,
                                isFollowUp: false,
                                onDismiss: nil
                            )
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(24)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let decoded = try? JSONDecoder().decode([UUID: Date].self, from: dismissedPeopleData) {
                dismissedPeople = decoded
            }
            calendarService.requestAccess { granted in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                }
            }
        }
    }
    
    private func matchPerson(for meeting: UpcomingMeeting) -> Person? {
        let currentUser = people.first { person in
            guard let name = person.name else { return false }
            return name.lowercased().contains("bob kitchen")
        }
        guard let attendees = meeting.attendees else { print("No attendees for meeting: \(meeting.title)"); return nil }
        let selfNames = [currentUser?.name?.lowercased(), "bk", "bob"]
        print("Meeting: \(meeting.title)")
        print("Attendees: \(attendees)")
        print("Self names: \(selfNames)")
        print("People list: \(people.compactMap { $0.name })")
        let otherAttendeeNames = attendees.filter { attendee in
            let attendeeLower = attendee.lowercased()
            return !selfNames.contains(where: { selfName in
                guard let selfName = selfName else { return false }
                return attendeeLower.contains(selfName)
            })
        }
        print("Other attendee names: \(otherAttendeeNames)")
        let nicknameMap: [String: String] = [
            "kathryn": "kate", "kate": "kathryn",
            "robert": "bob", "bob": "robert",
            "william": "bill", "bill": "william",
        ]
        func firstNamesMatch(_ a: String, _ b: String) -> Bool {
            if a == b { return true }
            if a.hasPrefix(b) || b.hasPrefix(a) { return true }
            if let nickA = nicknameMap[a], nickA == b { return true }
            if let nickB = nicknameMap[b], nickB == a { return true }
            return false
        }
        func splitName(_ name: String) -> (first: String, last: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let parts = trimmed.split(separator: " ").map { String($0) }
            if parts.count >= 2 {
                let first = parts[0]
                let last = parts[1...].joined(separator: " ")
                return (first, last)
            } else if parts.count == 1 {
                return (parts[0], "")
            } else {
                return ("", "")
            }
        }
        for attendee in otherAttendeeNames {
            let (attendeeFirst, attendeeLast) = splitName(attendee)
            print("Attendee split: first=\(attendeeFirst), last=\(attendeeLast)")
            for person in people {
                guard let name = person.name else { continue }
                let (personFirst, personLast) = splitName(name)
                print("  Person split: first=\(personFirst), last=\(personLast) [\(name)]")
                let lastNameMatches = !attendeeLast.isEmpty && attendeeLast == personLast
                let firstNameMatches = firstNamesMatch(attendeeFirst, personFirst)
                print("    Last names match? \(lastNameMatches), First names match? \(firstNameMatches)")
                if lastNameMatches && firstNameMatches {
                    print("Matched attendee: \(attendee) to person: \(name)")
                    return person
                }
            }
        }
        print("No match found for meeting: \(meeting.title)")
        return nil
    }
    
    private func openConversationWindow(for person: Person) {
        let newConversation = Conversation(context: viewContext)
        newConversation.date = Date()
        newConversation.person = person
        newConversation.uuid = UUID()
        
        person.scheduledConversationDate = nil
        try? viewContext.save()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ConversationDetailView.formattedWindowTitle(for: newConversation, person: person)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: newConversation, isInitiallyEditing: true)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
}

struct PersonCardView: View {
    let person: Person
    let isFollowUp: Bool
    let onDismiss: (() -> Void)?
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with avatar and name
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .overlay(Text(person.initials).foregroundColor(.white).font(.subheadline))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name ?? "Unknown")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let role = person.role {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isFollowUp, let dismiss = onDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Contact info
            if let lastDate = person.lastContactDate {
                Text("Last contacted on \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                Text("Never contacted")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            if let scheduled = person.scheduledConversationDate {
                Text("Meeting scheduled for \(scheduled.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .frame(width: 300, height: 120)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}
