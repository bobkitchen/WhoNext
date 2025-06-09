import SwiftUI
import CoreData
import UniformTypeIdentifiers
import EventKit
import Supabase

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("openaiApiKey") private var apiKey: String = ""
    @AppStorage("claudeApiKey") private var claudeApiKey: String = ""
    @AppStorage("aiProvider") private var aiProvider: String = "openai"
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
    @State private var isValidatingClaudeKey = false
    @State private var isClaudeKeyValid = false
    @State private var claudeKeyError: String?
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var pastedPeopleText: String = ""
    @State private var showResetConfirmation = false
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarID: String = ""
    @AppStorage("selectedCalendarID") private var storedCalendarID: String = ""
    @StateObject private var pdfProcessor = OrgChartProcessor()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)],
        predicate: nil,
        animation: .default
    ) private var conversations: FetchedResults<Conversation>
    
    @StateObject private var supabaseSync = SupabaseSyncManager.shared

    @State private var selectedTab = "general"
    @State private var refreshTrigger = false

    var body: some View {
        ScrollView {
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
                    
                    TabButton(title: "Calendar", icon: "calendar", isSelected: selectedTab == "calendar") {
                        selectedTab = "calendar"
                    }
                    
                    TabButton(title: "Import & Export", icon: "square.and.arrow.down", isSelected: selectedTab == "import") {
                        selectedTab = "import"
                    }
                    
                    TabButton(title: "Sync", icon: "arrow.triangle.2.circlepath.camera", isSelected: selectedTab == "sync") {
                        selectedTab = "sync"
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 10)
                
                // Content based on selected tab
                Group {
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
                    case "sync":
                        syncSettingsView
                    default:
                        generalSettingsView
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
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
            // AI Provider Section
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Provider")
                    .font(.headline)
                Picker("AI Provider", selection: $aiProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Claude").tag("claude")
                }
                .pickerStyle(.menu)
            }
            
            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.headline)
                if aiProvider == "openai" {
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
                } else if aiProvider == "claude" {
                    HStack {
                        SecureField("ck-...", text: $claudeApiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Validate") {
                            validateClaudeApiKey()
                        }
                        .disabled(isValidatingClaudeKey)
                    }
                    if isValidatingClaudeKey {
                        Text("Validating...")
                            .foregroundColor(.secondary)
                    } else if isClaudeKeyValid {
                        Text("✓ Valid API Key")
                            .foregroundColor(.green)
                    } else if let error = claudeKeyError {
                        Text("✗ \(error)")
                            .foregroundColor(.red)
                    }
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
                    .frame(minHeight: 200, maxHeight: 400)
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
                            .frame(minHeight: 120, maxHeight: 300)
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
            // Org Chart Import Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Org Chart")
                    .font(.headline)
                Text("Drop a file to automatically extract team member details using AI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                OrgChartDropZone(
                    isProcessing: pdfProcessor.isProcessing,
                    processingStatus: pdfProcessor.processingStatus
                ) { fileURL in
                    processOrgChartFile(fileURL)
                }
                .frame(height: 120)
                
                if let error = pdfProcessor.error {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                
                if let success = importSuccess {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                if let error = importError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // CSV Import Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Team Members (CSV)")
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
                        .onChange(of: selectedCalendarID) { oldValue, newValue in
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
    
    // MARK: - Sync Settings
    private var syncSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Supabase Sync Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Supabase Sync")
                    .font(.headline)
                Text("Real-time sync across all your devices")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Sync Status
                    HStack {
                        Circle()
                            .fill(supabaseSync.isSyncing ? .blue : (supabaseSync.error != nil ? .red : .green))
                            .frame(width: 8, height: 8)
                        Text(supabaseSync.syncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let lastSync = supabaseSync.lastSyncDate {
                            Text("Last sync: \(lastSync, formatter: DateFormatter.timeOnly)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Progress Bar (when syncing)
                    if supabaseSync.isSyncing {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: supabaseSync.syncProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                            if !supabaseSync.syncStep.isEmpty {
                                Text(supabaseSync.syncStep)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Sync Button
                    Button(supabaseSync.isSyncing ? "Syncing..." : "Sync Now") {
                        Task {
                            await supabaseSync.syncNow(context: viewContext)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(supabaseSync.isSyncing)
                    
                    // Deduplication Button
                    Button(supabaseSync.isSyncing ? "Deduplicating..." : "Remove Duplicates") {
                        Task {
                            do {
                                try await supabaseSync.deduplicateAllData(context: viewContext)
                                // Force refresh of the view to update conversation count
                                await MainActor.run {
                                    // Trigger a view refresh by updating the environment
                                    try? viewContext.save()
                                    refreshTrigger.toggle()
                                }
                            } catch {
                                print("Deduplication failed: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(supabaseSync.isSyncing)
                    .foregroundColor(.orange)
                    
                    // EMERGENCY: Data Recovery Button
                    Button("🚨 Check Supabase for Data") {
                        Task {
                            do {
                                // Force download everything from Supabase to restore local data
                                try await supabaseSync.downloadRemoteChanges(context: viewContext)
                                await MainActor.run {
                                    try? viewContext.save()
                                    refreshTrigger.toggle()
                                }
                                print("✅ Data recovery attempt completed")
                            } catch {
                                print("❌ Data recovery failed: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(supabaseSync.isSyncing)
                    .foregroundColor(.red)
                    
                    // Error Display
                    if let error = supabaseSync.error {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // Success Display (only show if not currently syncing)
                    if let success = supabaseSync.success, !supabaseSync.isSyncing {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Data Summary Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Data")
                    .font(.headline)
                Text("Current data in your local database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("People:")
                        Spacer()
                        Text("\(people.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Conversations:")
                        Spacer()
                        Text("\(conversations.count)")
                            .foregroundColor(.secondary)
                            .id(refreshTrigger) // Force refresh when trigger changes
                    }
                }
                .font(.caption)
                .padding(.vertical, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
    
    private func validateClaudeApiKey() {
        guard !claudeApiKey.isEmpty else {
            claudeKeyError = "API key cannot be empty"
            isClaudeKeyValid = false
            return
        }
        
        isValidatingClaudeKey = true
        isClaudeKeyValid = false
        claudeKeyError = nil
        
        // Simple validation request to Claude
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeApiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Simple test message
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 10,
            "messages": [
                [
                    "role": "user",
                    "content": "Hi"
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                self.isValidatingClaudeKey = false
                self.claudeKeyError = "Request encoding error: \(error.localizedDescription)"
                self.isClaudeKeyValid = false
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isValidatingClaudeKey = false
                
                if let error = error {
                    claudeKeyError = "Network error: \(error.localizedDescription)"
                    isClaudeKeyValid = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Claude API validation response: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Claude API response body: \(responseString)")
                    }
                    
                    switch httpResponse.statusCode {
                    case 200:
                        isClaudeKeyValid = true
                        claudeKeyError = nil
                    case 401:
                        isClaudeKeyValid = false
                        claudeKeyError = "Invalid API key - check your Claude API key"
                    case 400:
                        // Parse the error response for more details
                        if let data = data,
                           let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorResponse["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            claudeKeyError = "Bad request: \(message)"
                        } else {
                            claudeKeyError = "Bad request - check API key format"
                        }
                        isClaudeKeyValid = false
                    case 429:
                        isClaudeKeyValid = false
                        claudeKeyError = "Rate limit exceeded - try again later"
                    default:
                        isClaudeKeyValid = false
                        claudeKeyError = "API error (HTTP \(httpResponse.statusCode))"
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
                    
                    print("Import complete: \(importedCount) imported, \(skippedCount) skipped")
                    
                    do {
                        try viewContext.save()
                        print("Saving context (import)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
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
        do {
            try viewContext.save()
        } catch {
            print("Failed to reset spoken to dates: \(error)")
        }
        
        // Clear dismissed people
        dismissedPeopleData = Data()
    }
    
    private func deleteAllPeople() {
        for person in people {
            viewContext.delete(person)
        }
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete all people: \(error)")
        }
    }
    
    private func processOrgChartFile(_ fileURL: URL) {
        print("🔍 [DROP] File dropped: \(fileURL.lastPathComponent)")
        print("🔍 [DROP] File path: \(fileURL.path)")
        
        // Clear previous messages
        importSuccess = nil
        importError = nil
        
        pdfProcessor.processOrgChartFile(fileURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let csvContent):
                    // Process the CSV content using existing CSV import logic
                    self.processCSVContent(csvContent)
                case .failure(let error):
                    self.importError = "File processing failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func processCSVContent(_ csvContent: String) {
        print("🔍 [CSV] Starting CSV processing")
        print("🔍 [CSV] Raw CSV content:\n\(csvContent)")
        
        let lines = csvContent.components(separatedBy: .newlines)
        print("🔍 [CSV] Split into \(lines.count) lines")
        
        guard lines.count > 1 else {
            print("❌ [CSV] Not enough lines in CSV content")
            importError = "No data found in CSV content"
            return
        }
        
        // Fetch existing people for duplicate checking
        let fetchRequest = Person.fetchRequest()
        do {
            let existingPeople = try viewContext.fetch(fetchRequest)
            let existingNames = Set(existingPeople.compactMap { ($0 as? Person)?.name?.lowercased() })
            print("🔍 [CSV] Found \(existingNames.count) existing people: \(existingNames)")
            
            // Skip header line and process data
            let dataLines = Array(lines.dropFirst()).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            print("🔍 [CSV] Processing \(dataLines.count) data lines (after filtering empty lines)")
            
            var importedCount = 0
            var skippedCount = 0
            
            for (index, line) in dataLines.enumerated() {
                print("🔍 [CSV] Processing line \(index + 1): \(line)")
                
                let components = parseCSVLine(line)
                print("🔍 [CSV] Parsed components: \(components)")
                
                guard components.count >= 2 else {
                    print("⚠️ [CSV] Skipping line with insufficient components: \(components.count)")
                    continue
                }
                
                let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let role = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let isDirectReport = components.count > 2 ? components[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" : false
                let timezone = components.count > 4 ? components[4].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                
                print("🔍 [CSV] Extracted - Name: '\(name)', Role: '\(role)', DirectReport: \(isDirectReport), Timezone: '\(timezone)'")
                
                // Check for duplicates (case-insensitive)
                if existingNames.contains(name.lowercased()) {
                    print("⚠️ [CSV] Skipping duplicate: \(name)")
                    skippedCount += 1
                    continue
                }
                
                print("✅ [CSV] Creating new person: \(name)")
                let person = Person(context: viewContext)
                person.name = name
                person.role = role
                person.isDirectReport = isDirectReport
                person.timezone = timezone.isEmpty ? "UTC" : timezone
                importedCount += 1
            }
            
            print("🔍 [CSV] Import summary - Imported: \(importedCount), Skipped: \(skippedCount)")
            
            // Save context
            do {
                try viewContext.save()
                print("✅ [CSV] Context saved successfully")
                
                // Update success message
                var successMsg = "✓ Imported \(importedCount) team member"
                if importedCount != 1 { successMsg += "s" }
                successMsg += " from org chart"
                
                if skippedCount > 0 {
                    successMsg += " (skipped \(skippedCount) duplicate"
                    if skippedCount != 1 { successMsg += "s" }
                    successMsg += ")"
                }
                
                print("✅ [CSV] Success message: \(successMsg)")
                importSuccess = successMsg
                importError = nil
            } catch {
                print("❌ [CSV] Failed to save context: \(error)")
                importError = "Failed to save imported data: \(error.localizedDescription)"
                importSuccess = nil
            }
        } catch {
            print("❌ [CSV] Failed to fetch existing people: \(error)")
            importError = "Failed to check for duplicates: \(error.localizedDescription)"
        }
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var components = [String]()
        var currentComponent = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                components.append(currentComponent)
                currentComponent = ""
            } else {
                currentComponent.append(char)
            }
        }
        
        components.append(currentComponent)
        
        return components
    }
}

struct OrgChartDropZone: View {
    let isProcessing: Bool
    let processingStatus: String?
    let onDrop: (URL) -> Void
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay(
                VStack {
                    if let status = processingStatus {
                        Text(status)
                            .font(.headline)
                    } else {
                        VStack(spacing: 4) {
                            Text("Drop a file to import org chart")
                                .font(.headline)
                            Text("Supports: PDF, PowerPoint (.ppt/.pptx), Images (.jpg/.png)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if isProcessing {
                        ProgressView()
                    }
                }
            )
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                print("🔍 [DROP] onDrop triggered with \(providers.count) providers")
                if let provider = providers.first {
                    print("🔍 [DROP] Checking if provider can load URL...")
                    if provider.canLoadObject(ofClass: URL.self) {
                        print("🔍 [DROP] Provider can load URL, loading...")
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url = url {
                                print("🔍 [DROP] Successfully loaded URL: \(url)")
                                onDrop(url)
                            } else {
                                print("❌ [DROP] Failed to load URL")
                            }
                        }
                    } else {
                        print("❌ [DROP] Provider cannot load URL")
                    }
                } else {
                    print("❌ [DROP] No providers found")
                }
                return true
            }
    }
}

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
