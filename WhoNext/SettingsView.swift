import SwiftUI
import CoreData
import UniformTypeIdentifiers
import CloudKit
import EventKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("openaiApiKey") private var apiKey: String = ""
    @AppStorage("dismissedPeople") private var dismissedPeopleData: Data = Data()
    @AppStorage("customPreMeetingPrompt") private var customPreMeetingPrompt: String = """
You are an executive assistant preparing a pre-meeting brief. Your job is to help the user engage with this person confidently by surfacing:
- Key personal details or preferences shared in past conversations
- Trends or changes in topics over time
- Any agreed tasks, deadlines, or follow-ups
- Recent wins, challenges, or important events
- Anything actionable or worth mentioning for the next meeting

Use the provided context to be specific and actionable. Highlight details that would help the user build rapport and recall important facts. If any information is missing, state so.

Pre-Meeting Brief:
"""
    @AppStorage("emailSubjectTemplate") private var emailSubjectTemplate: String = "1:1 - {name} + BK"
    @AppStorage("emailBodyTemplate") private var emailBodyTemplate: String = """
Hi {firstName},

I wanted to follow up on our conversation and see how things are going.

Would you have time for a quick chat this week?

Best regards
"""
    @State private var isValidatingKey = false
    @State private var isKeyValid = false
    @State private var keyError: String?
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var pastedPeopleText: String = ""
    @State private var showResetConfirmation = false
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarID: String = ""
    @AppStorage("selectedCalendarID") private var storedCalendarID: String = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    @StateObject private var syncStatus = CloudKitSyncStatus()

    @State private var selectedTab = "general"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .bold()
            
            // Tab selector with modern design
            HStack(spacing: 0) {
                TabButton(title: "General", icon: "gear", isSelected: selectedTab == "general") {
                    selectedTab = "general"
                }
                
                TabButton(title: "AI & Prompts", icon: "brain", isSelected: selectedTab == "ai") {
                    selectedTab = "ai"
                }
                
                TabButton(title: "Email Templates", icon: "envelope", isSelected: selectedTab == "email") {
                    selectedTab = "email"
                }
                
                TabButton(title: "Import & Export", icon: "square.and.arrow.down", isSelected: selectedTab == "import") {
                    selectedTab = "import"
                }
                
                TabButton(title: "Calendar", icon: "calendar", isSelected: selectedTab == "calendar") {
                    selectedTab = "calendar"
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case "general":
                        generalSettingsView
                    case "ai":
                        aiSettingsView
                    case "email":
                        emailSettingsView
                    case "import":
                        importExportView
                    case "calendar":
                        calendarSettingsView
                    default:
                        generalSettingsView
                    }
                }
                .padding(.trailing, 20)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Tab Button Component
    struct TabButton: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    
                    Text(title)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - General Settings
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // --- Sync Status ---
            VStack(alignment: .leading, spacing: 8) {
                Text("iCloud Sync Status")
                    .font(.headline)
                if syncStatus.isSyncing {
                    HStack {
                        ProgressView()
                        Text("Syncing with iCloud...")
                            .foregroundColor(.secondary)
                    }
                } else if let lastSync = syncStatus.lastSyncDate {
                    Text("Last successful sync: \(lastSync.formatted(date: .abbreviated, time: .standard))")
                        .foregroundColor(.green)
                } else {
                    Text("No sync has occurred yet.")
                        .foregroundColor(.secondary)
                }
                if let error = syncStatus.syncError {
                    Text("Sync Error: \(error)")
                        .foregroundColor(.red)
                }
                Button(action: {
                    syncStatus.isSyncing = true
                    syncStatus.manualSync()
                }) {
                    Label("Trigger Manual Sync", systemImage: "arrow.clockwise")
                }
                .disabled(syncStatus.isSyncing)
            }
            
            Divider()
            
            // Reset App Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Warning + Danger")
                    .font(.headline)
                    .foregroundColor(.red)
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Who You've Spoken To", systemImage: "arrow.counterclockwise")
                }
                .alert("Reset App", isPresented: $showResetConfirmation) {
                    Button("Reset", role: .destructive) { resetSpokenTo() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will reset all memory of who you've spoken to and who needs to be spoken to next. Conversation records and notes will NOT be deleted.")
                }
                Button(role: .destructive) {
                    deleteAllPeople()
                } label: {
                    Label("Delete All People", systemImage: "person.crop.circle.badge.xmark")
                }
                .help("Deletes all People records from both this device and iCloud. This cannot be undone!")
            }
        }
    }
    
    // MARK: - AI Settings
    private var aiSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.headline)
                HStack {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Validate") {
                        validateApiKey()
                    }
                    .disabled(isValidatingKey)
                }
                if isValidatingKey {
                    Text("Validating...")
                        .foregroundColor(.secondary)
                } else if isKeyValid {
                    Text("✓ Valid API Key")
                        .foregroundColor(.green)
                } else if let error = keyError {
                    Text("✗ \(error)")
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // Pre-Meeting Prompt Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Pre-Meeting Brief Prompt")
                    .font(.headline)
                Text("Customize the AI prompt used for generating pre-meeting briefs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customPreMeetingPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150, maxHeight: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                HStack {
                    Button("Reset to Default") {
                        customPreMeetingPrompt = """
You are an executive assistant preparing a pre-meeting brief. Your job is to help the user engage with this person confidently by surfacing:
- Key personal details or preferences shared in past conversations
- Trends or changes in topics over time
- Any agreed tasks, deadlines, or follow-ups
- Recent wins, challenges, or important events
- Anything actionable or worth mentioning for the next meeting

Use the provided context to be specific and actionable. Highlight details that would help the user build rapport and recall important facts. If any information is missing, state so.

Pre-Meeting Brief:
"""
                    }
                    .buttonStyle(.link)
                    
                    Spacer()
                    
                    Text("\(customPreMeetingPrompt.count) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Email Settings
    private var emailSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Email Template Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Templates")
                    .font(.headline)
                Text("Customize the email templates used for follow-up emails. Use {name} for full name and {firstName} for first name.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subject Template")
                            .font(.subheadline)
                        TextEditor(text: $emailSubjectTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body Template")
                            .font(.subheadline)
                        TextEditor(text: $emailBodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120, maxHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    Button("Reset to Defaults") {
                        emailSubjectTemplate = "1:1 - {name} + BK"
                        emailBodyTemplate = """
Hi {firstName},

I wanted to follow up on our conversation and see how things are going.

Would you have time for a quick chat this week?

Best regards
"""
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
    
    // MARK: - Import & Export
    private var importExportView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // CSV Import Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Team Members")
                    .font(.headline)
                Text("Import CSV file with columns: Name, Role, Direct Report (true/false), Timezone")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Button("Select CSV File") {
                        importError = nil
                        importSuccess = nil
                        importCSV()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let error = importError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    
                    if let success = importSuccess {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Calendar Settings
    private var calendarSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Calendar Integration Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar Integration")
                    .font(.headline)
                Text("Select which calendar to use for meeting scheduling and upcoming events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("Request Calendar Access") {
                        requestCalendarAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Refresh Calendars") {
                        loadAvailableCalendars()
                    }
                    .buttonStyle(.bordered)
                }
                
                // Calendar Selection
                if !availableCalendars.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Calendar:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Calendar", selection: $selectedCalendarID) {
                            Text("None Selected").tag("")
                            ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(Color(calendar.color))
                                        .frame(width: 12, height: 12)
                                    Text("\(calendar.title) (\(calendar.source.title))")
                                }
                                .tag(calendar.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedCalendarID) { newValue in
                            storedCalendarID = newValue
                            // Notify CalendarService to update
                            NotificationCenter.default.post(
                                name: Notification.Name("CalendarSelectionChanged"),
                                object: newValue
                            )
                        }
                    }
                }
                
                // Current Status
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    let authStatus = EKEventStore.authorizationStatus(for: .event)
                    HStack {
                        Circle()
                            .fill(authStatus == .authorized ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(calendarStatusText(authStatus))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            selectedCalendarID = storedCalendarID
            if EKEventStore.authorizationStatus(for: .event) == .authorized {
                loadAvailableCalendars()
            }
        }
    }
    
    private func requestCalendarAccess() {
        let eventStore = EKEventStore()
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        loadAvailableCalendars()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        loadAvailableCalendars()
                    }
                }
            }
        }
    }
    
    private func loadAvailableCalendars() {
        let eventStore = EKEventStore()
        availableCalendars = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }
    
    private func calendarStatusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Calendar access granted"
        case .denied:
            return "Calendar access denied"
        case .restricted:
            return "Calendar access restricted"
        case .notDetermined:
            return "Calendar access not requested"
        @unknown default:
            return "Unknown calendar status"
        }
    }
    
    private func validateApiKey() {
        guard !apiKey.isEmpty else {
            keyError = "API key cannot be empty"
            isKeyValid = false
            return
        }
        
        isValidatingKey = true
        isKeyValid = false
        keyError = nil
        
        // Simple validation request to OpenAI
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isValidatingKey = false
                
                if let error = error {
                    keyError = "Network error: \(error.localizedDescription)"
                    isKeyValid = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200:
                        isKeyValid = true
                        keyError = nil
                    case 401:
                        isKeyValid = false
                        keyError = "Invalid API key"
                    default:
                        isKeyValid = false
                        keyError = "Unexpected error (HTTP \(httpResponse.statusCode))"
                    }
                }
            }
        }.resume()
    }
    
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Move all Core Data operations to the main thread
            DispatchQueue.main.async {
                do {
                    print("Reading CSV from: \(url)")
                    let csvContent = try String(contentsOfFile: url.path, encoding: .utf8)
                    let rows = csvContent.components(separatedBy: .newlines)
                    
                    guard !rows.isEmpty else {
                        print("CSV file is empty")
                        importError = "CSV file is empty"
                        return
                    }
                    
                    print("Found \(rows.count) rows")
                    
                    // Parse headers
                    let headers = rows[0].components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    print("Headers: \(headers)")
                    
                    // Find required column indices
                    let nameIndex = headers.firstIndex(of: "name")
                    let roleIndex = headers.firstIndex(of: "role")
                    
                    guard let nameIdx = nameIndex else {
                        print("Name column not found")
                        importError = "Required 'Name' column not found in CSV"
                        return
                    }
                    
                    guard let roleIdx = roleIndex else {
                        print("Role column not found")
                        importError = "Required 'Role' column not found in CSV"
                        return
                    }
                    
                    // Find optional column indices
                    let directReportIndex = headers.firstIndex(of: "direct report")
                    let timezoneIndex = headers.firstIndex(of: "timezone")
                    
                    // Fetch existing people for duplicate checking
                    let fetchRequest = Person.fetchRequest()
                    let existingPeople = try viewContext.fetch(fetchRequest)
                    let existingNames = Set(existingPeople.compactMap { ($0 as? Person)?.name?.lowercased() })
                    
                    var importedCount = 0
                    var skippedCount = 0
                    
                    // Process each line
                    for row in rows.dropFirst() where !row.isEmpty {
                        let columns = row.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        
                        guard columns.count >= max(nameIdx, roleIdx) + 1 else {
                            print("Row has missing fields: \(columns)")
                            importError = "Row has missing required fields"
                            return
                        }
                        
                        let name = columns[nameIdx]
                        if existingNames.contains(name.lowercased()) {
                            print("Skipping duplicate: \(name)")
                            skippedCount += 1
                            continue
                        }
                        
                        print("Creating person: \(name)")
                        let newPerson = Person(context: viewContext)
                        newPerson.identifier = UUID()
                        newPerson.name = name
                        newPerson.role = columns[roleIdx]
                        
                        // Optional fields
                        if let drIdx = directReportIndex, columns.count > drIdx {
                            newPerson.isDirectReport = columns[drIdx].lowercased() == "true"
                        }
                        
                        if let tzIdx = timezoneIndex, columns.count > tzIdx {
                            newPerson.timezone = columns[tzIdx]
                        }
                        
                        importedCount += 1
                    }
                    
                    try viewContext.save()
                    // Force Core Data to refresh all managed objects after import
                    viewContext.refreshAllObjects()
                    print("[SettingsView][LOG] Saving context (import)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
                    print("Import complete: \(importedCount) imported, \(skippedCount) skipped")
                    
                    importError = nil
                    // Build success message
                    var successMsg = "✓ Imported \(importedCount) team member"
                    if importedCount != 1 { successMsg += "s" }
                    if skippedCount > 0 {
                        successMsg += " (skipped \(skippedCount) duplicate"
                        if skippedCount != 1 { successMsg += "s" }
                        successMsg += ")"
                    }
                    importSuccess = successMsg
                    
                    // Notify other views to refresh people after import
                    NotificationCenter.default.post(name: Notification.Name("PeopleDidImport"), object: nil)
                    
                } catch {
                    print("Import failed: \(error)")
                    importError = error.localizedDescription
                    importSuccess = nil
                }
            }
        }
    }
    
    private func resetSpokenTo() {
        // Clear all lastContactDate by removing all conversations' dates (but not deleting conversations or notes)
        for person in people {
            if let convs = person.conversations as? Set<Conversation> {
                for conversation in convs {
                    conversation.date = nil
                }
            }
        }
        try? viewContext.save()
        print("[SettingsView][LOG] Saving context (resetSpokenTo)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        
        // Clear dismissed people
        dismissedPeopleData = Data()
    }
    
    private func deleteAllPeople() {
        for person in people {
            viewContext.delete(person)
        }
        do {
            print("[SettingsView][LOG] Saving context (deleteAllPeople)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
            try viewContext.save()
            print("All people deleted.")
        } catch {
            print("Failed to delete all people: \(error)")
        }
    }
}
