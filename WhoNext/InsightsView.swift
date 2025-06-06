import SwiftUI
import AppKit
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
    
    // Track dismissed people for current session only
    @State private var dismissedPeopleIDs: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer().frame(height: 16) // Add space between toolbar and main content
            
            // Insights (Chat) Section and Statistics Cards
            HStack(alignment: .top, spacing: 24) {
                ChatView()
                    .frame(minWidth: 400, maxWidth: 500, minHeight: 0, maxHeight: .infinity)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .alignmentGuide(.top) { d in d[.top] } // Align top with cards
                
                VStack(spacing: 10) {
                    StatCardView(
                        imageName: "icon_flag",
                        title: "Cycle Progress",
                        value: cycleProgressText,
                        description: "Team members contacted"
                    )
                    StatCardView(
                        imageName: "icon_stopwatch",
                        title: "Weeks Remaining",
                        value: weeksRemainingText,
                        description: "At 2 per week"
                    )
                    StatCardView(
                        imageName: "icon_fire",
                        title: "Streak",
                        value: streakText,
                        description: "Weeks in a row"
                    )
                }
                .frame(width: 260)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .alignmentGuide(.top) { d in d[.top] }
            
            // Upcoming 1:1s as cards, limited to 2
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image("icon_calendar")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Upcoming 1:1s")
                }
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                if calendarService.upcomingMeetings.isEmpty {
                    Text("No upcoming 1:1s")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(Array(calendarService.upcomingMeetings.prefix(2))) { meeting in
                            let matchedPerson = matchPerson(for: meeting)
                            UpcomingMeetingCard(meeting: meeting, matchedPerson: matchedPerson, onSelect: {
                                if let person = matchedPerson {
                                    selectedPerson = person
                                    selectedPersonID = person.identifier
                                    selectedTab = .people
                                }
                            })
                        }
                    }
                }
            }
            
            // Follow-up Needed Section
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image("icon_bell")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Follow-up Needed")
                }
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                        ForEach(suggestedPeople, id: \.objectID) { person in
                            PersonCardView(
                                person: person,
                                isFollowUp: true,
                                onDismiss: {
                                    // Only hide the person from suggestions for this session
                                    // Do NOT create a conversation or update lastContactDate
                                    if let personID = person.identifier {
                                        dismissedPeopleIDs.insert(personID)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            Spacer()
        }
        .padding([.horizontal, .bottom], 24)
        .onAppear {
            calendarService.requestAccess { granted in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                }
            }
        }
    }
    
    private var suggestedPeople: [Person] {
        let filtered = people.filter { person in
            // Exclude people without names, direct reports, and dismissed people
            guard let name = person.name,
                  !person.isDirectReport,
                  let personID = person.identifier,
                  !dismissedPeopleIDs.contains(personID) else {
                return false
            }
            return true
        }
        // Sort by least recently contacted, then shuffle for randomness among those with the same lastContactDate
        let sorted = filtered.sorted {
            ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast)
        }
        // Take a larger pool (e.g., top 6 least-recently-contacted), then shuffle and pick 2
        let pool = Array(sorted.prefix(6)).shuffled()
        let result = Array(pool.prefix(2))
        return result
    }
    
    private func matchPerson(for meeting: UpcomingMeeting) -> Person? {
        let currentUser = people.first { person in
            guard let name = person.name else { return false }
            return name.lowercased().contains("bob kitchen")
        }
        guard let attendees = meeting.attendees else { return nil }
        let selfNames = [currentUser?.name?.lowercased(), "bk", "bob"]
        let otherAttendeeNames = attendees.filter { attendee in
            let attendeeLower = attendee.lowercased()
            return !selfNames.contains(where: { selfName in
                guard let selfName = selfName else { return false }
                return attendeeLower.contains(selfName)
            })
        }
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
            for person in people {
                guard let name = person.name else { continue }
                let (personFirst, personLast) = splitName(name)
                let lastNameMatches = !attendeeLast.isEmpty && attendeeLast == personLast
                let firstNameMatches = firstNamesMatch(attendeeFirst, personFirst)
                if lastNameMatches && firstNameMatches {
                    return person
                }
            }
        }
        return nil
    }
    
    private func openConversationWindow(for person: Person) {
        let newConversation = Conversation(context: viewContext)
        newConversation.date = Date()
        newConversation.person = person
        newConversation.uuid = UUID()
        
        person.scheduledConversationDate = nil
        print("[InsightsView][LOG] Saving context (manual)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
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

// MARK: - Statistic Card View
struct StatCardView: View {
    let imageName: String
    let title: String
    let value: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(imageName)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Statistic Computations
extension InsightsView {
    private var nonDirectReports: [Person] {
        people.filter { !$0.isDirectReport }
    }
    
    // 1. Cycle Progress
    private var cycleProgressText: String {
        "\(spokenToThisCycle.count) / \(nonDirectReports.count)"
    }
    
    // 2. Weeks Remaining
    private var weeksRemainingText: String {
        let remaining = max(nonDirectReports.count - spokenToThisCycle.count, 0)
        let perWeek = 2
        let weeks = Int(ceil(Double(remaining) / Double(perWeek)))
        return "\(weeks) week\(weeks == 1 ? "" : "s")"
    }
    
    // 3. Streak
    private var streakText: String {
        "\(longestStreak) week\(longestStreak == 1 ? "" : "s")"
    }
    
    // --- Cycle and Streak Logic ---
    // Find the set of people spoken to since the most recent time all were contacted
    private var spokenToThisCycle: [Person] {
        // For each person, get their most recent conversation date
        let lastDates = nonDirectReports.compactMap { person in
            (person, person.lastContactDate)
        }
        // Find the earliest of the most recent dates (cycle start)
        guard lastDates.count == nonDirectReports.count,
              let cycleStart = lastDates.map({ $0.1 ?? .distantPast }).min(),
              cycleStart > .distantPast else {
            // If not everyone has been spoken to, cycle started at earliest contact
            let earliest = lastDates.map { $0.1 ?? .distantPast }.min() ?? .distantPast
            return nonDirectReports.filter { ($0.lastContactDate ?? .distantPast) >= earliest && $0.lastContactDate != nil }
        }
        // Only those spoken to since cycleStart
        return nonDirectReports.filter { ($0.lastContactDate ?? .distantPast) >= cycleStart && $0.lastContactDate != nil }
    }
    
    // Calculate the longest streak of weeks meeting the 2-per-week goal
    private var longestStreak: Int {
        // Gather all conversation dates with non-direct reports
        let allDates = nonDirectReports.compactMap { $0.conversationsArray.map { $0.date }.compactMap { $0 } }.flatMap { $0 }
        guard !allDates.isEmpty else { return 0 }
        let sorted = allDates.sorted()
        // Group by week
        var streak = 0, maxStreak = 0, currentWeek: Date? = nil, countThisWeek = 0
        let calendar = Calendar.current
        for date in sorted {
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            if currentWeek == nil || calendar.component(.weekOfYear, from: currentWeek!) != weekOfYear || calendar.component(.yearForWeekOfYear, from: currentWeek!) != year {
                // New week
                if countThisWeek >= 2 { streak += 1 } else { streak = 0 }
                maxStreak = max(maxStreak, streak)
                currentWeek = date
                countThisWeek = 1
            } else {
                countThisWeek += 1
            }
        }
        // Check last week
        if countThisWeek >= 2 { streak += 1 } else { streak = 0 }
        maxStreak = max(maxStreak, streak)
        return maxStreak
    }
}

struct GlobalNewConversationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedPerson: Person?
    @State private var searchText: String = ""
    @State private var notes: String = ""
    @State private var showSuggestions: Bool = false
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    )
    private var people: FetchedResults<Person>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // To: field
            HStack {
                Text("To:")
                    .font(.headline)
                ZStack(alignment: .topLeading) {
                    TextField("Type a name...", text: $searchText, onEditingChanged: { editing in
                        showSuggestions = editing
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 240)
                    .onChange(of: searchText) { _ in showSuggestions = true }
                    .onSubmit {
                        if let match = people.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }) {
                            selectedPerson = match
                            searchText = match.name ?? ""
                            showSuggestions = false
                        }
                    }
                    .disabled(selectedPerson != nil)

                    if showSuggestions && !searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(people.filter { $0.name?.localizedCaseInsensitiveContains(searchText) == true }.prefix(5), id: \..objectID) { person in
                                Button(action: {
                                    selectedPerson = person
                                    searchText = person.name ?? ""
                                    showSuggestions = false
                                }) {
                                    HStack {
                                        Text(person.name ?? "Unknown")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color(.windowBackgroundColor))
                        .border(Color.gray.opacity(0.3))
                        .frame(maxWidth: 240)
                        .offset(y: 28)
                    }
                }
                if selectedPerson != nil {
                    Button(action: {
                        selectedPerson = nil
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Notes field
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes:")
                    .font(.headline)
                TextEditor(text: $notes)
                    .frame(height: 120)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
            }

            HStack {
                Spacer()
                Button("Save") {
                    saveConversation()
                }
                .disabled(selectedPerson == nil || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
    }

    private func saveConversation() {
        guard let person = selectedPerson else { return }
        let conversation = Conversation(context: viewContext)
        conversation.date = Date()
        conversation.person = person
        conversation.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.uuid = UUID()
        do {
            print("[InsightsView][LOG] Saving context (manual)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
            try viewContext.save()
        } catch {
            print("Failed to save conversation: \(error)")
        }
        // Reset fields and close window
        if let window = NSApp.keyWindow {
            window.close()
        }
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}

struct UpcomingMeetingCard: View {
    let meeting: UpcomingMeeting
    let matchedPerson: Person?
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar or icon (match PersonCardView)
                if let person = matchedPerson {
                    Circle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .overlay(Text(person.initials).foregroundColor(.white).font(.subheadline))
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let person = matchedPerson {
                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No match found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // Date info (match density of follow-up card)
            Text(meeting.startDate, style: .date)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(width: 300, height: 120)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        .onTapGesture { onSelect() }
    }
}
