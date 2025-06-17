import SwiftUI
import CoreData
import UniformTypeIdentifiers
import EventKit
import Supabase

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("openaiApiKey") private var apiKey: String = ""
    @AppStorage("claudeApiKey") private var claudeApiKey: String = ""
    @AppStorage("openrouterApiKey") private var openrouterApiKey: String = ""
    @AppStorage("openrouterModel") private var openrouterModel: String = "meta-llama/llama-3.1-8b-instruct:free"
    @AppStorage("aiProvider") private var aiProvider: String = "apple"
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
    @AppStorage("customSummarizationPrompt") private var customSummarizationPrompt: String = """
You are an executive assistant creating comprehensive meeting minutes. Generate detailed, actionable meeting minutes that include:

**Meeting Overview:**
- Meeting purpose and context
- Key themes and overall tone
- Primary objectives discussed

**Discussion Details:**
- Main points raised by each participant
- Key decisions made and rationale
- Areas of agreement and disagreement
- Important insights or revelations
- Questions raised and answers provided

**Action Items & Follow-ups:**
- Specific tasks assigned with owners
- Deadlines and timelines mentioned
- Next steps and follow-up meetings
- Dependencies and blockers identified

**Outcomes & Conclusions:**
- Final decisions reached
- Issues resolved or escalated
- Commitments made by participants
- Success metrics or goals established

**Additional Notes:**
- Context for future reference
- Relationship dynamics observed
- Support needs identified
- Risk factors or concerns noted
- Strengths and positive developments

Format the output in clear, professional meeting minutes suitable for distribution and follow-up preparation.
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
    
    @StateObject private var properSync = ProperSyncManager.shared

    @State private var selectedTab = "general"
    @State private var refreshTrigger = false
    @State private var diagnosticsResult: String?
    @State private var isRunningDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                    if #available(iOS 18.1, macOS 15.1, *) {
                        Text("🍎 Apple Intelligence (On-Device)").tag("apple")
                    }
                    Text("OpenAI").tag("openai")
                    Text("Claude").tag("claude")
                    Text("OpenRouter (Free)").tag("openrouter")
                }
                .pickerStyle(.menu)
                
                // Provider benefits
                if aiProvider == "apple" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✅ Complete Privacy - Processing stays on device")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("✅ No API costs or internet required")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("✅ Fast response times")
                            .font(.caption)
                            .foregroundColor(.green)
                        if #unavailable(iOS 18.1, macOS 15.1) {
                            Text("⚠️ Requires iOS 18.1+ or macOS 15.1+")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            // API Key Section
            if aiProvider != "apple" {
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
                            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
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
                            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
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
                    } else if aiProvider == "openrouter" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SecureField("or-...", text: $openrouterApiKey)
                                    .textFieldStyle(.roundedBorder)
                                Button("Get Free Key") {
                                    if let url = URL(string: "https://openrouter.ai/keys") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            Text("OpenRouter provides free access to Llama 3.1 8B and other models. Vision analysis will fallback to OpenAI if configured.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("Model")
                                    .frame(width: 60, alignment: .leading)
                                Picker("Select Model", selection: $openrouterModel) {
                                    Text("Llama 3.1 8B (Free)").tag("meta-llama/llama-3.1-8b-instruct:free")
                                    Text("Llama 3.2 3B (Free)").tag("meta-llama/llama-3.2-3b-instruct:free")
                                    Text("Mistral 7B (Free)").tag("mistralai/mistral-7b-instruct:free")
                                    Text("Nous Hermes 2 Mixtral (Free)").tag("nousresearch/hermes-2-pro-mistral-7b:free")
                                    Text("Phi-3 Mini (Free)").tag("microsoft/phi-3-mini-128k-instruct:free")
                                    Text("Gemma 2 9B (Free)").tag("google/gemma-2-9b-it:free")
                                    Text("Qwen 2.5 7B (Free)").tag("qwen/qwen-2.5-7b-instruct:free")
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("Current: \(openrouterModel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
            
            // Summarization Prompt Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Summarization Prompt")
                    .font(.headline)
                Text("Customize the AI prompt used for generating meeting summaries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $customSummarizationPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: 400)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                HStack {
                    Button("Reset to Default") {
                        customSummarizationPrompt = """
You are an executive assistant creating comprehensive meeting minutes. Generate detailed, actionable meeting minutes that include:

**Meeting Overview:**
- Meeting purpose and context
- Key themes and overall tone
- Primary objectives discussed

**Discussion Details:**
- Main points raised by each participant
- Key decisions made and rationale
- Areas of agreement and disagreement
- Important insights or revelations
- Questions raised and answers provided

**Action Items & Follow-ups:**
- Specific tasks assigned with owners
- Deadlines and timelines mentioned
- Next steps and follow-up meetings
- Dependencies and blockers identified

**Outcomes & Conclusions:**
- Final decisions reached
- Issues resolved or escalated
- Commitments made by participants
- Success metrics or goals established

**Additional Notes:**
- Context for future reference
- Relationship dynamics observed
- Support needs identified
- Risk factors or concerns noted
- Strengths and positive developments

Format the output in clear, professional meeting minutes suitable for distribution and follow-up preparation.
"""
                    }
                    .buttonStyle(.link)
                    
                    Spacer()
                    
                    Text("\(customSummarizationPrompt.count) characters")
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
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                    
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
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                    
                    Button("Refresh Calendars") {
                        loadAvailableCalendars()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
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
                            .fill(properSync.isSyncing ? .blue : .green)
                            .frame(width: 8, height: 8)
                        Text(properSync.syncStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let lastSync = properSync.lastSyncDate {
                            Text("Last sync: \(lastSync, formatter: DateFormatter.timeOnly)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Progress Bar (when syncing)
                    if properSync.isSyncing {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView()
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                    }
                    
                    // Sync Button
                    Button(properSync.isSyncing ? "Syncing..." : "Sync Now") {
                        properSync.triggerSync()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                    .disabled(properSync.isSyncing)
                    
                    // Note: Deduplication is handled by proper sync now
                    Text("✨ Automatic deduplication is built into the new sync system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    // Data Recovery Button
                    Button("🚨 Trigger Full Sync") {
                        properSync.triggerSync()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                    .disabled(properSync.isSyncing)
                    .foregroundColor(.blue)
                    
                    // Status Display
                    if properSync.syncStatus != "Ready" && !properSync.isSyncing {
                        Text(properSync.syncStatus)
                            .font(.caption)
                            .foregroundColor(properSync.syncStatus.contains("failed") ? .red : .green)
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
            
            // Sync Diagnostics Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Sync Diagnostics")
                    .font(.headline)
                Text("Troubleshoot sync issues between devices")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(isRunningDiagnostics ? "Running..." : "Run Diagnostics") {
                    runSyncDiagnostics()
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(isRunningDiagnostics)
                
                Button("🔄 Fresh Start - Clear Local & Download from Cloud") {
                    Task {
                        await freshStartFromCloud()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.purple)
                
                Button("☢️ NUCLEAR RESET - Force Perfect Sync") {
                    Task {
                        await nuclearReset()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.red)
                
                Button("💥 TRUE NUCLEAR - Debug Version") {
                    Task {
                        await trueNuclearReset()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.black)
                
                Button("🔧 Reset Device Attribution") {
                    Task {
                        await resetDeviceAttribution()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.orange)
                
                Button("🔗 Fix Conversation Relationships") {
                    Task {
                        await fixConversationRelationships()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.blue)
                
                Button("🧹 Advanced Orphan Cleanup") {
                    Task {
                        await advancedOrphanCleanup()
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .foregroundColor(.purple)
                
                if let diagnosticsResult = diagnosticsResult {
                    ScrollView {
                        Text(diagnosticsResult)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
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
        case .fullAccess:
            return "Full calendar access granted"
        case .writeOnly:
            return "Write-only calendar access granted"
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
    
    private func runSyncDiagnostics() {
        guard !isRunningDiagnostics else { return }
        
        isRunningDiagnostics = true
        diagnosticsResult = "Running diagnostics..."
        
        Task {
            let results = await SyncDiagnostics.shared.runDiagnostics(context: viewContext)
            
            await MainActor.run {
                diagnosticsResult = results.joined(separator: "\n")
                isRunningDiagnostics = false
            }
        }
    }
    
    private func freshStartFromCloud() async {
        diagnosticsResult = "Starting fresh start from cloud..."
        
        do {
            // Step 1: Delete ALL local people and conversations
            diagnosticsResult = "🗑️ Clearing all local data..."
            
            // Delete all conversations first (due to relationships)
            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let allConversations = try viewContext.fetch(conversationRequest)
            for conversation in allConversations {
                viewContext.delete(conversation)
            }
            
            // Delete all people
            let peopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let allPeople = try viewContext.fetch(peopleRequest)
            for person in allPeople {
                viewContext.delete(person)
            }
            
            // Save the deletions
            try viewContext.save()
            diagnosticsResult = "✅ Local data cleared. Now downloading from cloud..."
            
            // Step 2: Download everything fresh from Supabase
            properSync.triggerSync()
            
            // Step 3: Save the downloaded data
            try viewContext.save()
            
            diagnosticsResult = "🎉 Fresh start completed! All data downloaded from cloud. Run diagnostics to verify."
            
        } catch {
            diagnosticsResult = "❌ Fresh start failed: \(error.localizedDescription)"
        }
    }
    
    private func nuclearReset() async {
        diagnosticsResult = "☢️ NUCLEAR RESET: Completely wiping local data and rebuilding from cloud..."
        
        do {
            let supabase = SupabaseConfig.shared.client
            
            // Step 1: Nuclear deletion of ALL Core Data
            diagnosticsResult = "🧹 Step 1/4: Completely wiping ALL local data..."
            
            // Delete ALL entities in the right order (relationships first)
            let conversationRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Conversation")
            let deleteConversationsRequest = NSBatchDeleteRequest(fetchRequest: conversationRequest)
            try viewContext.execute(deleteConversationsRequest)
            
            let peopleRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Person")
            let deletePeopleRequest = NSBatchDeleteRequest(fetchRequest: peopleRequest)
            try viewContext.execute(deletePeopleRequest)
            
            // Reset the context
            viewContext.reset()
            try viewContext.save()
            
            diagnosticsResult = "✅ Step 2/4: Downloading ONLY non-deleted people from cloud..."
            
            // Step 2: Download all people (no soft delete filtering)
            let remotePeople: [SupabasePerson] = try await supabase.database
                .from("people")
                .select()
                .execute()
                .value
            
            // Create people with proper identifiers
            for remotePerson in remotePeople {
                let person = Person(context: viewContext)
                person.identifier = UUID(uuidString: remotePerson.identifier) ?? UUID()
                person.name = remotePerson.name
                person.role = remotePerson.role
                person.notes = remotePerson.notes
                person.isDirectReport = remotePerson.isDirectReport ?? false
                person.timezone = remotePerson.timezone
                
                if let dateString = remotePerson.scheduledConversationDate {
                    person.scheduledConversationDate = ISO8601DateFormatter().date(from: dateString)
                }
                
                if let photoBase64 = remotePerson.photoBase64, !photoBase64.isEmpty {
                    person.photo = Data(base64Encoded: photoBase64)
                }
            }
            
            try viewContext.save()
            diagnosticsResult = "✅ Step 3/4: Downloading ONLY non-deleted conversations from cloud..."
            
            // Step 3: Download all conversations and rebuild relationships
            let remoteConversations: [SupabaseConversation] = try await supabase.database
                .from("conversations")
                .select()
                .execute()
                .value
            
            // Get all people for relationship building
            let allPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let allPeople = try viewContext.fetch(allPeopleRequest)
            var peopleMap: [String: Person] = [:]
            for person in allPeople {
                if let identifier = person.identifier?.uuidString {
                    peopleMap[identifier] = person
                }
            }
            
            // Create conversations with proper relationships
            for remoteConv in remoteConversations {
                let conversation = Conversation(context: viewContext)
                conversation.uuid = UUID(uuidString: remoteConv.uuid) ?? UUID()
                conversation.notes = remoteConv.notes
                conversation.summary = remoteConv.summary
                conversation.duration = Int32(remoteConv.duration ?? 0)
                conversation.engagementLevel = remoteConv.engagementLevel
                conversation.analysisVersion = remoteConv.analysisVersion
                conversation.qualityScore = remoteConv.qualityScore
                conversation.sentimentLabel = remoteConv.sentimentLabel
                conversation.sentimentScore = remoteConv.sentimentScore
                
                if let dateString = remoteConv.date {
                    conversation.date = ISO8601DateFormatter().date(from: dateString)
                }
                
                if let lastAnalyzedString = remoteConv.lastAnalyzed {
                    conversation.lastAnalyzed = ISO8601DateFormatter().date(from: lastAnalyzedString)
                }
                
                if let lastSentimentString = remoteConv.lastSentimentAnalysis {
                    conversation.lastSentimentAnalysis = ISO8601DateFormatter().date(from: lastSentimentString)
                }
                
                // Rebuild relationship
                if let personIdentifier = remoteConv.personIdentifier,
                   let person = peopleMap[personIdentifier] {
                    conversation.person = person
                }
            }
            
            try viewContext.save()
            diagnosticsResult = "✅ Step 4/4: Clearing device attributions for proper sync..."
            
            // Step 4: Clear all device attributions so sync works properly
            try await supabase.database
                .from("people")
                .update(["device_id": Optional<String>.none])
                .not("device_id", operator: .is, value: "null") // WHERE clause: only update non-null device_ids
                .execute()
            
            diagnosticsResult = "🎉 NUCLEAR RESET COMPLETE! All data rebuilt from cloud. Run diagnostics to verify."
            
        } catch {
            diagnosticsResult = "❌ Nuclear reset failed: \(error.localizedDescription)"
        }
    }
    
    private func resetDeviceAttribution() async {
        diagnosticsResult = "Resetting device attribution..."
        
        do {
            // Clear device_id for ALL people in Supabase, then let each device claim their own
            let supabase = SupabaseConfig.shared.client
            
            diagnosticsResult = "🧹 Clearing all device attributions in cloud..."
            
            // Update all people to have null device_id
            try await supabase.database
                .from("people")
                .update(["device_id": Optional<String>.none])
                .not("device_id", operator: .is, value: "null") // Only update non-null ones
                .execute()
            
            diagnosticsResult = "✅ Device attributions cleared. Now syncing to re-establish proper attribution..."
            
            // Now sync - this will re-attribute people to the devices that have them locally
            properSync.triggerSync()
            
            diagnosticsResult = "🎉 Device attribution reset completed! Run diagnostics to see the new attribution."
            
        } catch {
            diagnosticsResult = "❌ Device attribution reset failed: \(error.localizedDescription)"
        }
    }
    
    private func fixConversationRelationships() async {
        diagnosticsResult = "🔗 Analyzing conversation relationships..."
        
        do {
            let supabase = SupabaseConfig.shared.client
            
            // Get all remote conversations with their person identifiers
            let remoteConversations: [SupabaseConversation] = try await supabase.database
                .from("conversations")
                .select()
                .execute()
                .value
            
            // Get all local conversations and people
            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let localConversations = try viewContext.fetch(conversationRequest)
            
            let peopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let localPeople = try viewContext.fetch(peopleRequest)
            
            diagnosticsResult = "📊 Analysis: \(remoteConversations.count) remote, \(localConversations.count) local conversations, \(localPeople.count) people"
            
            // Create lookup maps
            var peopleMap: [String: Person] = [:]
            var localConvMap: [String: Conversation] = [:]
            
            for person in localPeople {
                if let identifier = person.identifier?.uuidString {
                    peopleMap[identifier] = person
                }
            }
            
            for conversation in localConversations {
                if let uuid = conversation.uuid?.uuidString {
                    localConvMap[uuid] = conversation
                }
            }
            
            var fixedCount = 0
            var missingPeople = 0
            var missingConversations = 0
            var alreadyLinked = 0
            
            // Analyze and fix relationships
            for remoteConv in remoteConversations {
                guard let personIdentifier = remoteConv.personIdentifier else { continue }
                
                // Find the local conversation by UUID
                guard let conversation = localConvMap[remoteConv.uuid] else {
                    missingConversations += 1
                    continue
                }
                
                // Find the person by identifier
                guard let person = peopleMap[personIdentifier] else {
                    missingPeople += 1
                    continue
                }
                
                // Check and fix the relationship
                if conversation.person != person {
                    conversation.person = person
                    fixedCount += 1
                    print("🔗 Fixed: \(remoteConv.uuid) -> \(person.name ?? "Unknown")")
                } else {
                    alreadyLinked += 1
                }
            }
            
            // Handle conversations that exist locally but not remotely (orphaned without remote reference)
            var orphanedLocalConversations = 0
            for conversation in localConversations {
                if conversation.person == nil {
                    // This conversation has no person relationship
                    let remoteExists = remoteConversations.contains { $0.uuid == conversation.uuid?.uuidString }
                    if !remoteExists {
                        orphanedLocalConversations += 1
                        print("⚠️ Orphaned local conversation: \(conversation.uuid?.uuidString ?? "unknown") with no remote reference")
                    }
                }
            }
            
            // Save the fixes
            if fixedCount > 0 {
                try viewContext.save()
            }
            
            // Detailed results
            var resultLines: [String] = []
            resultLines.append("🔗 RELATIONSHIP REPAIR RESULTS:")
            resultLines.append("   ✅ Fixed relationships: \(fixedCount)")
            resultLines.append("   ✅ Already linked: \(alreadyLinked)")
            resultLines.append("   ⚠️ Missing people: \(missingPeople)")
            resultLines.append("   ⚠️ Missing conversations: \(missingConversations)")
            resultLines.append("   ⚠️ Orphaned local conversations: \(orphanedLocalConversations)")
            
            if fixedCount > 0 {
                resultLines.append("")
                resultLines.append("🎉 Successfully fixed \(fixedCount) relationships!")
                resultLines.append("Run diagnostics again to verify the improvements.")
            } else if missingPeople > 0 || missingConversations > 0 {
                resultLines.append("")
                resultLines.append("⚠️ Some conversations couldn't be linked due to missing data.")
                resultLines.append("Consider running 'Fresh Start' to rebuild from cloud.")
            } else {
                resultLines.append("")
                resultLines.append("✅ All linkable relationships are already correct.")
            }
            
            diagnosticsResult = resultLines.joined(separator: "\n")
            
        } catch {
            diagnosticsResult = "❌ Failed to fix conversation relationships: \(error.localizedDescription)"
        }
    }
    
    private func advancedOrphanCleanup() async {
        diagnosticsResult = "🧹 Starting advanced orphan cleanup analysis..."
        
        do {
            let supabase = SupabaseConfig.shared.client
            
            // Get all remote conversations and people
            let remoteConversations: [SupabaseConversation] = try await supabase.database
                .from("conversations")
                .select()
                .execute()
                .value
            
            let remotePeople: [SupabasePerson] = try await supabase.database
                .from("people")
                .select()
                .execute()
                .value
            
            // Get all local data
            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let localConversations = try viewContext.fetch(conversationRequest)
            
            let peopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let localPeople = try viewContext.fetch(peopleRequest)
            
            // Create lookup maps
            let remoteConvUUIDs = Set(remoteConversations.map { $0.uuid })
            let remotePeopleIDs = Set(remotePeople.compactMap { $0.identifier })
            let localPeopleMap: [String: Person] = Dictionary(localPeople.compactMap { person in
                guard let id = person.identifier?.uuidString else { return nil }
                return (id, person)
            }, uniquingKeysWith: { first, _ in first })
            
            var cleanupResults: [String] = []
            var fixedConversations = 0
            var removedOrphans = 0
            
            cleanupResults.append("🔍 ADVANCED ORPHAN ANALYSIS:")
            cleanupResults.append("   Remote conversations: \(remoteConversations.count)")
            cleanupResults.append("   Remote people: \(remotePeople.count)")
            cleanupResults.append("   Local conversations: \(localConversations.count)")
            cleanupResults.append("   Local people: \(localPeople.count)")
            cleanupResults.append("")
            
            // Strategy 1: Fix conversations that exist remotely but are orphaned locally
            for remoteConv in remoteConversations {
                if let localConv = localConversations.first(where: { $0.uuid?.uuidString == remoteConv.uuid }),
                   localConv.person == nil,
                   let personId = remoteConv.personIdentifier,
                   let person = localPeopleMap[personId] {
                    
                    localConv.person = person
                    fixedConversations += 1
                    print("🔗 Strategy 1 - Fixed: \(remoteConv.uuid) -> \(person.name ?? "Unknown")")
                }
            }
            
            // Strategy 2: Identify truly orphaned local conversations
            var trulyOrphaned: [Conversation] = []
            for localConv in localConversations {
                if localConv.person == nil {
                    let hasRemoteReference = remoteConvUUIDs.contains(localConv.uuid?.uuidString ?? "")
                    if !hasRemoteReference {
                        trulyOrphaned.append(localConv)
                    }
                }
            }
            
            cleanupResults.append("📊 CLEANUP STRATEGIES:")
            cleanupResults.append("   Strategy 1 - Remote match fixes: \(fixedConversations)")
            cleanupResults.append("   Strategy 2 - Truly orphaned found: \(trulyOrphaned.count)")
            cleanupResults.append("")
            
            // Strategy 3: Try to match orphaned conversations by date/content similarity
            var matchedByHeuristics = 0
            for orphan in trulyOrphaned {
                // Try to find a person by matching conversation date with recent activity
                if let convDate = orphan.date {
                    let candidates = localPeople.filter { person in
                        // Look for people who had activity around the same time
                        if let lastContact = person.lastContactDate {
                            let timeDiff = abs(convDate.timeIntervalSince(lastContact))
                            return timeDiff < 86400 * 7 // Within 7 days
                        }
                        return false
                    }
                    
                    // If we found exactly one candidate, it's likely a match
                    if candidates.count == 1 {
                        orphan.person = candidates.first
                        matchedByHeuristics += 1
                        print("🎯 Strategy 3 - Heuristic match: \(orphan.uuid?.uuidString ?? "unknown") -> \(candidates.first?.name ?? "Unknown")")
                    }
                }
            }
            
            cleanupResults.append("   Strategy 3 - Heuristic matches: \(matchedByHeuristics)")
            cleanupResults.append("")
            
            // Save all fixes
            let totalFixed = fixedConversations + matchedByHeuristics
            if totalFixed > 0 {
                try viewContext.save()
                cleanupResults.append("✅ SUCCESSFULLY FIXED \(totalFixed) ORPHANED CONVERSATIONS!")
            } else {
                cleanupResults.append("ℹ️ No orphaned conversations could be automatically fixed.")
            }
            
            // Show remaining orphans
            let remainingOrphans = localConversations.filter { $0.person == nil }.count
            cleanupResults.append("")
            cleanupResults.append("📈 FINAL STATUS:")
            cleanupResults.append("   Remaining orphaned conversations: \(remainingOrphans)")
            
            if remainingOrphans > 0 {
                cleanupResults.append("")
                cleanupResults.append("💡 RECOMMENDATIONS:")
                cleanupResults.append("   • Run diagnostics to see current state")
                cleanupResults.append("   • Consider 'Fresh Start' if issues persist")
                cleanupResults.append("   • Manual review may be needed for complex cases")
            } else {
                cleanupResults.append("   🎉 ALL CONVERSATIONS NOW HAVE PROPER RELATIONSHIPS!")
            }
            
            diagnosticsResult = cleanupResults.joined(separator: "\n")
            
        } catch {
            diagnosticsResult = "❌ Advanced orphan cleanup failed: \(error.localizedDescription)"
        }
    }
    
    private func trueNuclearReset() async {
        var output: [String] = []
        output.append("💥 TRUE NUCLEAR RESET - Debug Mode")
        output.append(String(repeating: "=", count: 50))
        
        do {
            let supabase = SupabaseConfig.shared.client
            
            // STEP 1: Show exactly what's in the cloud BEFORE we do anything
            output.append("")
            output.append("🔍 STEP 1: CLOUD INVENTORY")
            
            let allRemotePeople: [SupabasePerson] = try await supabase.database
                .from("people")
                .select()
                .execute()
                .value
            
            let nonDeletedPeople = allRemotePeople.filter { !($0.isSoftDeleted ?? false) }
            let deletedPeople = allRemotePeople.filter { $0.isSoftDeleted ?? false }
            
            output.append("   Total people in cloud: \(allRemotePeople.count)")
            output.append("   Non-deleted: \(nonDeletedPeople.count)")
            output.append("   Deleted: \(deletedPeople.count)")
            
            // Show first few non-deleted people
            output.append("")
            output.append("📋 First 5 non-deleted people in cloud:")
            for (i, person) in nonDeletedPeople.prefix(5).enumerated() {
                output.append("   \(i+1). \(person.name ?? "Unknown") (ID: \(person.identifier))")
            }
            
            diagnosticsResult = output.joined(separator: "\n")
            
            // STEP 2: Wipe local completely
            output.append("")
            output.append("🧹 STEP 2: WIPING LOCAL DATA")
            
            let conversationRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Conversation")
            let deleteConversationsRequest = NSBatchDeleteRequest(fetchRequest: conversationRequest)
            try viewContext.execute(deleteConversationsRequest)
            
            let peopleRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Person")
            let deletePeopleRequest = NSBatchDeleteRequest(fetchRequest: peopleRequest)
            try viewContext.execute(deletePeopleRequest)
            
            viewContext.reset()
            try viewContext.save()
            
            output.append("   ✅ All local data deleted")
            diagnosticsResult = output.joined(separator: "\n")
            
            // STEP 3: Download exactly what we found in step 1
            output.append("")
            output.append("📥 STEP 3: DOWNLOADING NON-DELETED PEOPLE")
            output.append("   Creating \(nonDeletedPeople.count) people locally...")
            
            var createdCount = 0
            for remotePerson in nonDeletedPeople {
                let person = Person(context: viewContext)
                person.identifier = UUID(uuidString: remotePerson.identifier) ?? UUID()
                person.name = remotePerson.name
                person.role = remotePerson.role
                person.notes = remotePerson.notes
                person.isDirectReport = remotePerson.isDirectReport ?? false
                person.timezone = remotePerson.timezone
                
                if let dateString = remotePerson.scheduledConversationDate {
                    person.scheduledConversationDate = ISO8601DateFormatter().date(from: dateString)
                }
                
                if let photoBase64 = remotePerson.photoBase64, !photoBase64.isEmpty {
                    person.photo = Data(base64Encoded: photoBase64)
                }
                
                createdCount += 1
            }
            
            try viewContext.save()
            output.append("   ✅ Created \(createdCount) people locally")
            diagnosticsResult = output.joined(separator: "\n")
            
            // STEP 4: Download conversations
            output.append("")
            output.append("📥 STEP 4: DOWNLOADING CONVERSATIONS")
            
            let allRemoteConversations: [SupabaseConversation] = try await supabase.database
                .from("conversations")
                .select()
                .execute()
                .value
            
            let nonDeletedConversations = allRemoteConversations.filter { !($0.isSoftDeleted ?? false) }
            
            output.append("   Total conversations in cloud: \(allRemoteConversations.count)")
            output.append("   Non-deleted: \(nonDeletedConversations.count)")
            output.append("   Creating \(nonDeletedConversations.count) conversations locally...")
            
            // Get all people for relationship building
            let allLocalPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let allLocalPeople = try viewContext.fetch(allLocalPeopleRequest)
            var peopleMap: [String: Person] = [:]
            for person in allLocalPeople {
                if let identifier = person.identifier?.uuidString {
                    peopleMap[identifier] = person
                }
            }
            
            var conversationsCreated = 0
            var conversationsLinked = 0
            
            for remoteConv in nonDeletedConversations {
                let conversation = Conversation(context: viewContext)
                conversation.uuid = UUID(uuidString: remoteConv.uuid) ?? UUID()
                conversation.notes = remoteConv.notes
                conversation.summary = remoteConv.summary
                conversation.duration = Int32(remoteConv.duration ?? 0)
                
                if let dateString = remoteConv.date {
                    conversation.date = ISO8601DateFormatter().date(from: dateString)
                }
                
                // Link to person
                if let personIdentifier = remoteConv.personIdentifier,
                   let person = peopleMap[personIdentifier] {
                    conversation.person = person
                    conversationsLinked += 1
                }
                
                conversationsCreated += 1
            }
            
            try viewContext.save()
            
            output.append("   ✅ Created \(conversationsCreated) conversations")
            output.append("   ✅ Linked \(conversationsLinked) to people")
            
            // STEP 5: Final verification
            output.append("")
            output.append("🎯 STEP 5: FINAL VERIFICATION")
            
            let finalPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let finalPeopleCount = try viewContext.count(for: finalPeopleRequest)
            
            let finalConversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let finalConversationCount = try viewContext.count(for: finalConversationRequest)
            
            output.append("   Final local people: \(finalPeopleCount)")
            output.append("   Final local conversations: \(finalConversationCount)")
            output.append("")
            
            if finalPeopleCount == nonDeletedPeople.count {
                output.append("✅ SUCCESS: Local count matches cloud non-deleted count!")
            } else {
                output.append("❌ MISMATCH: Local (\(finalPeopleCount)) != Cloud non-deleted (\(nonDeletedPeople.count))")
            }
            
            output.append("")
            output.append("🎉 TRUE NUCLEAR RESET COMPLETE!")
            output.append("This device should now have EXACTLY \(nonDeletedPeople.count) people.")
            
            diagnosticsResult = output.joined(separator: "\n")
            
        } catch {
            output.append("")
            output.append("❌ TRUE NUCLEAR RESET FAILED: \(error.localizedDescription)")
            diagnosticsResult = output.joined(separator: "\n")
        }
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
