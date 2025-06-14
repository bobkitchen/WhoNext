import SwiftUI
import AppKit
import CoreData
import Combine

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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 16) // Add space between toolbar and main content
                
                // Insights (Chat) Section and Statistics Cards
                HStack(alignment: .top, spacing: 24) {
                    ChatView()
                        .frame(minWidth: 400, maxHeight: 480)
                        .liquidGlassCard(
                            cornerRadius: 20,
                            elevation: .medium,
                            padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                            isInteractive: true
                        )
                        .alignmentGuide(.top) { d in d[.top] } // Align top with cards
                    
                    VStack(spacing: 20) {
                        EnhancedStatCardView(
                            icon: "flag.fill",
                            title: "Cycle Progress",
                            value: cycleProgressText,
                            subtitle: "Team members contacted",
                            color: .blue,
                            progress: Double(spokenToThisCycle.count) / Double(max(nonDirectReports.count, 1))
                        )
                        EnhancedStatCardView(
                            icon: "heart.fill",
                            title: "Health Alerts",
                            value: "\(lowHealthRelationships.count)",
                            subtitle: "Need attention",
                            color: lowHealthRelationships.count > 0 ? .red : .green,
                            progress: nil
                        )
                        EnhancedStatCardView(
                            icon: "calendar.badge.clock",
                            title: "This Week",
                            value: "\(upcomingMeetingsThisWeek.count)",
                            subtitle: "Scheduled meetings",
                            color: .green,
                            progress: nil
                        )
                    }
                    .frame(width: 200)
                }
                
                // Upcoming 1:1s Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        
                        Text("Upcoming 1:1s")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("(\(upcomingMeetingsThisWeek.count))")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .fill(.secondary.opacity(0.1))
                            }
                        
                        Spacer()
                    }
                    .liquidGlassSectionHeader()
                    
                    if upcomingMeetingsThisWeek.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                            
                            Text("No upcoming meetings")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text("Your calendar is clear for this week")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .liquidGlassCard(
                            cornerRadius: 16,
                            elevation: .low,
                            padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                            isInteractive: false
                        )
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(upcomingMeetingsThisWeek, id: \.id) { meeting in
                                UpcomingMeetingCard(
                                    meeting: meeting,
                                    matchedPerson: people.first { person in
                                        meeting.attendees?.contains { attendee in
                                            attendee.lowercased().contains(person.name?.lowercased() ?? "")
                                        } ?? false
                                    }
                                ) {
                                    if let matchedPerson = people.first(where: { person in
                                        meeting.attendees?.contains { attendee in
                                            attendee.lowercased().contains(person.name?.lowercased() ?? "")
                                        } ?? false
                                    }) {
                                        selectedPerson = matchedPerson
                                        selectedPersonID = matchedPerson.identifier
                                        selectedTab = .people
                                    }
                                }
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
                        
                        if !suggestedPeople.isEmpty {
                            Text("(\(min(suggestedPeople.count, 2)))")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    
                    if suggestedPeople.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green.opacity(0.5))
                                Text("No follow-ups needed")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(Array(suggestedPeople.prefix(2))) { person in
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
                
                Spacer().frame(height: 24) // Bottom padding
            }
            .padding([.horizontal, .bottom], 24)
        }
        .onAppear {
            calendarService.requestAccess { granted, error in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                } else {
                    // Handle access denied or error
                    if let error = error {
                        print("Calendar access error: \(error)")
                    }
                }
            }
        }
    }
    
    private var upcomingMeetingsThisWeek: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= now && meeting.startDate < endDate
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
    
    private var lowHealthRelationships: [Person] {
        let calculator = ConversationMetricsCalculator()
        return people.compactMap { person in
            guard let metrics = calculator.calculateMetrics(for: person) else { return nil }
            return metrics.healthScore < 0.4 ? person : nil
        }
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
                    .onChange(of: searchText) { oldValue, newValue in showSuggestions = true }
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
    @State private var isHovered = false
    @State private var showEmailInstructions = false
    @State private var showPermissionAlert = false
    
    // Calculate days since last contact
    var daysSinceContact: String? {
        guard let lastDate = person.lastContactDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        if days == 0 {
            return "today"
        } else if days == 1 {
            return "yesterday"
        } else {
            return "\(days) days ago"
        }
    }
    
    // Generate email draft
    func openEmailDraft() {
        // Get email templates from settings
        @AppStorage("emailSubjectTemplate") var subjectTemplate = "1:1 - {name} + BK"
        @AppStorage("emailBodyTemplate") var bodyTemplate = """
Hi {firstName},

I wanted to follow up on our conversation and see how things are going.

Would you have time for a quick chat this week?

Best regards
"""
        
        let firstName = person.name?.components(separatedBy: " ").first ?? "there"
        let fullName = person.name ?? "Meeting"
        
        // Replace placeholders in templates
        let subject = subjectTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        let body = bodyTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        print("Email button clicked - trying to open Outlook")
        
        // Launch Outlook and use keyboard automation
        launchOutlookAndAutomate(subject: subject, body: body)
    }
    
    private func launchOutlookAndAutomate(subject: String, body: String) {
        let outlookBundleID = "com.microsoft.Outlook"
        let workspace = NSWorkspace.shared
        
        guard let outlookURL = workspace.urlForApplication(withBundleIdentifier: outlookBundleID) else {
            print("Outlook not found")
            return
        }
        
        workspace.openApplication(at: outlookURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if let error = error {
                print("Error opening Outlook: \(error)")
                return
            }
            
            print("Successfully opened Outlook, waiting for it to be ready...")
            
            // Wait for Outlook to be ready, then automate
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.waitForOutlookAndExecute(subject: subject, body: body)
            }
        }
    }
    
    private func waitForOutlookAndExecute(subject: String, body: String, attempt: Int = 1) {
        print("🔍 Checking if Outlook is ready (attempt \(attempt)/5)...")
        
        // Check if Outlook is running using NSWorkspace
        let runningApps = NSWorkspace.shared.runningApplications
        let outlookRunning = runningApps.contains { app in
            app.bundleIdentifier == "com.microsoft.Outlook" && app.isActive
        }
        
        if outlookRunning {
            print("✅ Outlook is running and active - proceeding with AppleScript")
            executeAppleScript(emailAddress: "\(person.name?.components(separatedBy: " ").first?.lowercased() ?? "").\(person.name?.components(separatedBy: " ").last?.lowercased() ?? "")@rescue.org", subject: subject, body: body)
        } else if attempt < 5 {
            print("⏳ Outlook not ready yet, waiting 2 seconds... (attempt \(attempt)/5)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.waitForOutlookAndExecute(subject: subject, body: body, attempt: attempt + 1)
            }
        } else {
            print("❌ Outlook failed to become ready after 5 attempts - falling back to clipboard")
            fallbackToClipboard(subject: subject, body: body)
        }
    }
    
    private func executeAppleScript(emailAddress: String, subject: String, body: String) {
        print("🍎 Using AppleScript automation for Outlook")
        
        // Check if we have accessibility permissions for System Events
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("❌ Accessibility permissions required for System Events - falling back to clipboard")
            fallbackToClipboard(subject: subject, body: body)
            return
        }
        
        let appleScript = """
        tell application "System Events"
            tell process "Microsoft Outlook"
                -- Bring Outlook to front
                set frontmost to true
                delay 2
                
                -- Send Cmd+N to create new email
                key code 45 using command down
                delay 3
                
                -- Type email address (cursor should be in To field)
                keystroke "\(emailAddress)"
                delay 1
                
                -- Tab to subject field
                key code 48
                delay 0.5
                
                -- Type subject
                keystroke "\(subject)"
                delay 0.5
                
                -- Tab to body field
                key code 48
                delay 0.5
                
                -- Type body
                keystroke "\(body)"
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("❌ AppleScript error: \(error)")
                print("🔄 Falling back to clipboard method")
                fallbackToClipboard(subject: subject, body: body)
            } else {
                print("✅ AppleScript email creation successful")
            }
        } else {
            print("❌ Failed to create AppleScript")
            fallbackToClipboard(subject: subject, body: body)
        }
    }
    
    private func fallbackToClipboard(subject: String, body: String) {
        let emailContent = "Subject: \(subject)\n\n\(body)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emailContent, forType: .string)
        
        // Open Outlook
        let outlookBundleID = "com.microsoft.Outlook"
        let workspace = NSWorkspace.shared
        
        if let outlookURL = workspace.urlForApplication(withBundleIdentifier: outlookBundleID) {
            workspace.openApplication(at: outlookURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showEmailInstructions = true
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with avatar and name
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(person.initials)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let role = person.role {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isFollowUp, let dismiss = onDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss follow-up")
                }
            }
            
            Divider()
                .opacity(0.5)
            
            // Contact info and actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let daysAgo = daysSinceContact {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Contacted \(daysAgo)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("Never contacted")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    if let scheduled = person.scheduledConversationDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Meeting scheduled")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Email button
                Button(action: openEmailDraft) {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                        Text("Email")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(isHovered ? 0.8 : 0.1))
                    .foregroundColor(isHovered ? .white : .blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(
                    color: isHovered ? .black.opacity(0.1) : .black.opacity(0.05),
                    radius: isHovered ? 12 : 8,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isHovered ? Color.orange.opacity(0.3) : Color.gray.opacity(0.1),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .alert(isPresented: $showEmailInstructions) {
            Alert(
                title: Text("Email Ready"),
                message: Text("Press Cmd+N to create a new email, then paste (Cmd+V) the pre-filled content."),
                dismissButton: .default(Text("Got it"))
            )
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text("To automatically create emails, grant accessibility access in System Settings > Privacy & Security > Accessibility. Or continue with manual email creation."),
                primaryButton: .default(Text("Open Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                },
                secondaryButton: .default(Text("Use Manual Method")) {
                    let firstName = person.name?.components(separatedBy: " ").first ?? "there"
                    let subject = "Follow up - \(person.name ?? "Meeting")"
                    let body = """
                    Hi \(firstName),
                    
                    I wanted to follow up on our conversation and see how things are going.
                    
                    Would you have time for a quick chat this week?
                    
                    Best regards
                    """
                    fallbackToClipboard(subject: subject, body: body)
                }
            )
        }
    }
}

struct UpcomingMeetingCard: View {
    let meeting: UpcomingMeeting
    let matchedPerson: Person?
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    // Calculate time until meeting
    var timeUntilMeeting: String {
        let now = Date()
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: meeting.startDate)
        
        if let days = components.day, days > 0 {
            return "in \(days) day\(days == 1 ? "" : "s")"
        } else if let hours = components.hour, hours > 0 {
            return "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else if let minutes = components.minute, minutes > 0 {
            return "in \(minutes) min"
        } else {
            return "starting soon"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // Enhanced Avatar with liquid glass styling
                ZStack(alignment: .bottomTrailing) {
                    if let person = matchedPerson {
                        if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                                }
                        } else {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                }
                                .overlay {
                                    Text(person.initials)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                }
                        }
                    } else {
                        Circle()
                            .fill(.secondary.opacity(0.1))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle()
                                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
                            }
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    
                    // Enhanced calendar indicator
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle()
                                .stroke(.background, lineWidth: 2)
                        }
                        .shadow(color: .green.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let person = matchedPerson {
                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("External meeting")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Enhanced time and date info
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)
                    
                    Text(timeUntilMeeting)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(.orange.opacity(0.1))
                        .overlay {
                            Capsule()
                                .stroke(.orange.opacity(0.2), lineWidth: 0.5)
                        }
                }
                
                Spacer()
                
                Text(meeting.startDate, style: .time)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(.secondary.opacity(0.08))
                    }
            }
        }
        .liquidGlassCard(
            cornerRadius: 16,
            elevation: isHovered ? .high : .medium,
            padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
            isInteractive: true
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.liquidGlass, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture { 
            onSelect() 
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meeting: \(meeting.title)")
        .accessibilityHint("Tap to view person details. \(timeUntilMeeting)")
    }
}
