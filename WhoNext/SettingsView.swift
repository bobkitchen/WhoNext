import SwiftUI
import CoreData
import CloudKit
import UniformTypeIdentifiers
import EventKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var userProfile = UserProfile.shared
    @ObservedObject private var recordingConfig = MeetingRecordingConfiguration.shared
    // Secure API key storage with @State bindings
    @State private var apiKey: String = ""
    @State private var claudeApiKey: String = ""
    @State private var openrouterApiKey: String = ""
    @State private var hasLoadedKeys = false
    @AppStorage("openrouterModel") private var openrouterModel: String = "google/gemma-2-9b-it:free"
    @AppStorage("aiProvider") private var aiProvider: String = "apple"
    @AppStorage("fallbackProvider") private var fallbackProvider: String = "openrouter"
    @AppStorage("dismissedPeople") private var dismissedPeopleData: Data = Data()
    @AppStorage("customPreMeetingPrompt") private var customPreMeetingPrompt: String = """
You are an executive assistant preparing a comprehensive pre-meeting intelligence brief. Analyze the conversation history and generate actionable insights to help the user engage confidently and build stronger relationships.

## Required Analysis Sections:

**🎯 MEETING FOCUS**
- Primary topics likely to be discussed based on recent patterns
- Key decisions or follow-ups pending from previous conversations
- Strategic priorities this person is currently focused on

**🔍 RELATIONSHIP INTELLIGENCE** 
- Communication style and preferences observed
- Working relationship trajectory and current dynamic
- Personal interests, motivations, or concerns mentioned
- Trust level and rapport-building opportunities

**⚡ ACTIONABLE INSIGHTS**
- Specific tasks, commitments, or deadlines to reference
- Wins, achievements, or positive developments to acknowledge  
- Challenges, concerns, or support needs to address
- Conversation starters that demonstrate you remember past discussions

**📈 PATTERNS & TRENDS**
- Evolution of topics or priorities over time
- Meeting frequency patterns and optimal timing
- Engagement levels and conversation quality trends
- Any recurring themes or persistent issues

**🎪 STRATEGIC RECOMMENDATIONS**
- Key talking points to strengthen the relationship
- Questions to ask that show engagement and care
- Potential challenges to navigate carefully
- Follow-up actions to propose or discuss

## Output Guidelines:
- Be specific with dates, quotes, and concrete details
- Prioritize recent conversations but reference historical context
- Include both professional and personal rapport-building elements
- Highlight gaps where information is missing or unclear
- Format with clear headers and bullet points for easy scanning

Generate a comprehensive brief that enables confident, relationship-building engagement:
"""
    @AppStorage("customSummarizationPrompt") private var customSummarizationPrompt: String = """
You are an executive assistant creating comprehensive meeting minutes. Generate detailed, actionable meeting minutes.

Format your response using markdown with ## for main sections and - for bullet points:

## Meeting Overview
- Meeting purpose and context
- Key themes and overall tone
- Primary objectives discussed

## Discussion Details
- Main points raised by each participant
- Key decisions made and rationale
- Areas of agreement and disagreement
- Important insights or revelations
- Questions raised and answers provided

## Action Items & Follow-ups
- Specific tasks assigned with owners
- Deadlines and timelines mentioned
- Next steps and follow-up meetings
- Dependencies and blockers identified

## Outcomes & Conclusions
- Final decisions reached
- Issues resolved or escalated
- Commitments made by participants
- Success metrics or goals established

## Additional Notes
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
    @State private var showModelWarning = false
    @State private var pendingFileURL: URL?
    @State private var showDeleteOrphanedConfirmation = false
    @State private var showAdvancedSyncOptions = false
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
    
    @State private var selectedTab = "profile"
    @State private var refreshTrigger = false
    @State private var diagnosticsResult: String?
    @State private var isRunningDiagnostics = false
    @State private var showSyncResetConfirmation = false
    @State private var showForceUploadConfirmation = false
    @State private var directReportTestResult: String?
    @State private var testPersonForSync: Person?
    @State private var showForceUploadOption = false
    @State private var showForceDownloadOption = false

    // API Balance checking
    @State private var isCheckingBalance = false
    @State private var openaiBalance: APIBalanceService.Balance?
    @State private var claudeBalance: APIBalanceService.Balance?
    @State private var openrouterBalance: APIBalanceService.Balance?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Tab selector with modern design - 5 tabs
                HStack(spacing: 0) {
                    TabButton(title: "My Profile", icon: "person.crop.circle.fill", isSelected: selectedTab == "profile") {
                        selectedTab = "profile"
                    }

                    TabButton(title: "AI", icon: "brain", isSelected: selectedTab == "ai") {
                        selectedTab = "ai"
                    }

                    TabButton(title: "Recording", icon: "waveform", isSelected: selectedTab == "recording") {
                        selectedTab = "recording"
                    }

                    TabButton(title: "Data & Sync", icon: "externaldrive.connected.to.line.below", isSelected: selectedTab == "data") {
                        selectedTab = "data"
                    }

                    TabButton(title: "Advanced", icon: "gearshape.2", isSelected: selectedTab == "advanced") {
                        selectedTab = "advanced"
                    }

                    Spacer()
                }
                .padding(.bottom, 10)

                // Content based on selected tab
                SwiftUI.Group {
                    switch selectedTab {
                    case "profile":
                        MyProfileSettingsView()
                    case "ai":
                        aiSettingsView
                    case "recording":
                        recordingSettingsView
                    case "data":
                        DataSyncSettingsView()
                            .environment(\.managedObjectContext, viewContext)
                    case "advanced":
                        AdvancedSettingsView()
                            .environment(\.managedObjectContext, viewContext)
                    default:
                        MyProfileSettingsView()
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !hasLoadedKeys {
                apiKey = SecureStorage.getAPIKey(for: .openai)
                claudeApiKey = SecureStorage.getAPIKey(for: .claude)
                openrouterApiKey = SecureStorage.getAPIKey(for: .openrouter)
                hasLoadedKeys = true
            }
        }
        .onChange(of: apiKey) { _, newValue in
            if hasLoadedKeys {
                if newValue.isEmpty {
                    SecureStorage.clearAPIKey(for: .openai)
                } else {
                    SecureStorage.setAPIKey(newValue, for: .openai)
                }
            }
        }
        .onChange(of: claudeApiKey) { _, newValue in
            if hasLoadedKeys {
                if newValue.isEmpty {
                    SecureStorage.clearAPIKey(for: .claude)
                } else {
                    SecureStorage.setAPIKey(newValue, for: .claude)
                }
            }
        }
        .onChange(of: openrouterApiKey) { _, newValue in
            if hasLoadedKeys {
                if newValue.isEmpty {
                    SecureStorage.clearAPIKey(for: .openrouter)
                } else {
                    SecureStorage.setAPIKey(newValue, for: .openrouter)
                }
            }
        }
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
    
    // MARK: - AI Settings
    private var aiSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // OpenRouter API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenRouter API Configuration")
                    .font(.headline)

                Text("API Key")
                    .font(.subheadline)
                HStack {
                    SecureField("or-...", text: $openrouterApiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Get Free Key") {
                        if let url = URL(string: "https://openrouter.ai/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text("OpenRouter provides access to premium models (GPT-5.2, Claude Sonnet 4.5), mid-tier options (GPT-4o Mini, Claude Haiku), and free models through one API key.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Select Model")
                    .font(.subheadline)
                Picker("Select Model", selection: $openrouterModel) {
                    // FREE MODELS
                    Text("🆓 Google Gemma 2 9B (FREE)").tag("google/gemma-2-9b-it:free")
                    Text("🆓 Llama 3.1 8B (FREE)").tag("meta-llama/llama-3.1-8b-instruct:free")

                    // BUDGET - OpenAI
                    Text("⚡ GPT-4o Mini ($0.15/$0.60)").tag("openai/gpt-4o-mini")
                    Text("⚡ GPT-4.1 Nano").tag("openai/gpt-4.1-nano")

                    // BUDGET - Claude
                    Text("🤖 Claude 4.5 Haiku").tag("anthropic/claude-4.5-haiku")

                    // PREMIUM - OpenAI
                    Text("💎 GPT-5 ($1.25/$10)").tag("openai/gpt-5")
                    Text("💎 GPT-5.2 ($1.75/$14)").tag("openai/gpt-5.2")

                    // PREMIUM - Claude
                    Text("⭐ Claude Sonnet 4.5 ($3/$15)").tag("anthropic/claude-sonnet-4.5")
                }
                .pickerStyle(.menu)
                Text("Current: \(openrouterModel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // OpenRouter Balance Display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OpenRouter Credits")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        Task {
                            await checkAPIBalance()
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isCheckingBalance {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isCheckingBalance ? "Checking..." : "Check Balance")
                        }
                    }
                    .buttonStyle(.link)
                    .disabled(isCheckingBalance)
                }

                // Display OpenRouter balance
                if let balance = openrouterBalance {
                    BalanceDisplayRow(balance: balance)
                } else {
                    Text("Click 'Check Balance' to view your API credits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Add Credits at openrouter.ai") {
                    if let url = URL(string: "https://openrouter.ai/credits") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Divider()

            // AI Prompts & Templates Section
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Prompts & Templates")
                    .font(.headline)

                Text("Customize the prompts used for AI-generated content. Click Customize to edit in a separate window.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 1) {
                    // Pre-Meeting Brief
                    PromptSettingsRow(
                        title: "Pre-Meeting Brief",
                        description: "AI prompt for generating pre-meeting intelligence briefs",
                        isCustomized: DefaultPrompts.isCustomized(customPreMeetingPrompt, type: .preMeetingBrief),
                        onCustomize: {
                            PromptEditorWindowController.shared.openPromptEditor(
                                type: .preMeetingBrief,
                                currentValue: customPreMeetingPrompt
                            ) { newValue, _ in
                                customPreMeetingPrompt = newValue
                            }
                        },
                        onReset: {
                            showResetPromptConfirmation = true
                            promptTypeToReset = .preMeetingBrief
                        }
                    )

                    Divider()
                        .padding(.horizontal)

                    // Summarization
                    PromptSettingsRow(
                        title: "Summarization",
                        description: "AI prompt for generating meeting summaries and minutes",
                        isCustomized: DefaultPrompts.isCustomized(customSummarizationPrompt, type: .summarization),
                        onCustomize: {
                            PromptEditorWindowController.shared.openPromptEditor(
                                type: .summarization,
                                currentValue: customSummarizationPrompt
                            ) { newValue, _ in
                                customSummarizationPrompt = newValue
                            }
                        },
                        onReset: {
                            showResetPromptConfirmation = true
                            promptTypeToReset = .summarization
                        }
                    )

                    Divider()
                        .padding(.horizontal)

                    // Email Templates
                    PromptSettingsRow(
                        title: "Email Templates",
                        description: "Templates for follow-up emails ({name}, {firstName})",
                        isCustomized: DefaultPrompts.isCustomized(emailSubjectTemplate, type: .emailSubject) ||
                                     DefaultPrompts.isCustomized(emailBodyTemplate, type: .emailBody),
                        onCustomize: {
                            PromptEditorWindowController.shared.openPromptEditor(
                                type: .email,
                                currentValue: emailBodyTemplate,
                                secondaryValue: emailSubjectTemplate
                            ) { newBody, newSubject in
                                emailBodyTemplate = newBody
                                if let subject = newSubject {
                                    emailSubjectTemplate = subject
                                }
                            }
                        },
                        onReset: {
                            // Email templates reset instantly (short content)
                            emailSubjectTemplate = DefaultPrompts.emailSubject
                            emailBodyTemplate = DefaultPrompts.emailBody
                        }
                    )
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .alert("Reset Prompt to Default?", isPresented: $showResetPromptConfirmation) {
                Button("Reset", role: .destructive) {
                    if let type = promptTypeToReset {
                        resetPromptToDefault(type)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will discard your customizations and restore the default prompt.")
            }
        }
    }

    @State private var showResetPromptConfirmation = false
    @State private var promptTypeToReset: DefaultPrompts.PromptType?

    private func resetPromptToDefault(_ type: DefaultPrompts.PromptType) {
        switch type {
        case .preMeetingBrief:
            customPreMeetingPrompt = DefaultPrompts.preMeetingBrief
        case .summarization:
            customSummarizationPrompt = DefaultPrompts.summarization
        case .emailSubject:
            emailSubjectTemplate = DefaultPrompts.emailSubject
        case .emailBody:
            emailBodyTemplate = DefaultPrompts.emailBody
        }
    }
}

// MARK: - Prompt Settings Row

struct PromptSettingsRow: View {
    let title: String
    let description: String
    let isCustomized: Bool
    let onCustomize: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            if isCustomized {
                Text("Customized")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text("Default")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            // Buttons
            HStack(spacing: 8) {
                if isCustomized {
                    Button("Reset") {
                        onReset()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Customize") {
                    onCustomize()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
    }
}

// MARK: - SettingsView Extension for Additional Views

extension SettingsView {
    // MARK: - Calendar Settings (Deprecated - moved to DataSyncSettingsView)
    var calendarSettingsView: some View {
        CalendarProviderSettings()
        /*
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
                            .fill(authStatus == .fullAccess ? .green : .red)
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
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                loadAvailableCalendars()
            }
        }
        */
    }

    // MARK: - Recording Settings
    var recordingSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Recording Triggers Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Recording Triggers")
                    .font(.headline)
                Text("Configure what triggers automatic meeting recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Two-Way Audio Detection", isOn: $recordingConfig.triggers.twoWayAudioEnabled)
                        .help("Automatically detect conversations based on audio patterns")
                    Toggle("Calendar Integration", isOn: $recordingConfig.triggers.calendarIntegrationEnabled)
                        .help("Start recording for scheduled calendar events")
                    Toggle("Meeting App Detection", isOn: $recordingConfig.triggers.meetingAppDetectionEnabled)
                        .help("Detect when meeting apps like Zoom are active")
                    Toggle("Keyword Detection", isOn: $recordingConfig.triggers.keywordDetectionEnabled)
                        .help("Trigger recording when specific keywords are mentioned")
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Auto-Recording Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Auto-Recording")
                    .font(.headline)
                Text("Control automatic recording behavior")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Auto-Recording", isOn: $recordingConfig.autoRecordingEnabled)
                        .help("Automatically start recording when meetings are detected")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Confidence Threshold")
                            Spacer()
                            Text("\(Int(recordingConfig.confidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $recordingConfig.confidenceThreshold, in: 0.3...1.0)
                            .disabled(!recordingConfig.autoRecordingEnabled)
                            .help("Higher values reduce false positives but may miss some meetings")
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Audio Quality Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Quality")
                    .font(.headline)
                Text("Configure recording quality settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sample Rate")
                        Spacer()
                        Picker("", selection: $recordingConfig.audioQuality.sampleRate) {
                            Text("16 kHz").tag(16000.0)
                            Text("44.1 kHz").tag(44100.0)
                            Text("48 kHz").tag(48000.0)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                    }
                    
                    HStack {
                        Text("Bit Rate")
                        Spacer()
                        Picker("", selection: $recordingConfig.audioQuality.bitRate) {
                            Text("64 kbps").tag(64000)
                            Text("128 kbps").tag(128000)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                    }
                    
                    Toggle("Enable Compression", isOn: $recordingConfig.audioQuality.compressionEnabled)
                        .help("Reduces file size but may slightly affect quality")
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Transcription Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcription")
                    .font(.headline)
                Text("Configure transcription preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use Local Transcription (Parakeet)", isOn: $recordingConfig.transcriptionSettings.useLocalTranscription)
                        .help("Process transcription locally for privacy")
                    Toggle("Whisper API Refinement", isOn: $recordingConfig.transcriptionSettings.whisperRefinementEnabled)
                        .help("Use OpenAI Whisper for higher accuracy")
                    Toggle("Speaker Diarization", isOn: $recordingConfig.transcriptionSettings.speakerDiarizationEnabled)
                        .help("Identify different speakers in the conversation")
                    
                    if recordingConfig.transcriptionSettings.speakerDiarizationEnabled {
                        DisclosureGroup("Advanced Speaker Settings") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Speaker Separation")
                                        .font(.caption)
                                    Spacer()
                                    Text(speakerSensitivityLabel(recordingConfig.transcriptionSettings.speakerSensitivity))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(speakerSensitivityColor(recordingConfig.transcriptionSettings.speakerSensitivity))
                                }

                                Slider(value: $recordingConfig.transcriptionSettings.speakerSensitivity,
                                       in: 0.60...0.80,
                                       step: 0.02)
                                    .help("Lower = stricter separation (better for similar voices). Default: 0.70")

                                HStack(spacing: 0) {
                                    Text("Strict (similar voices)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("Relaxed (different voices)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if abs(recordingConfig.transcriptionSettings.speakerSensitivity - 0.70) > 0.01 {
                                    Button("Reset to Optimal (0.70)") {
                                        recordingConfig.transcriptionSettings.speakerSensitivity = 0.70
                                    }
                                    .font(.caption)
                                    .buttonStyle(.link)
                                }

                                Text("Only adjust if speakers with similar voices aren't being separated correctly.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.top, 8)
                        }
                        .font(.caption)
                        .padding(.leading, 20)
                    }
                    
                    Toggle("Include Punctuation", isOn: $recordingConfig.transcriptionSettings.punctuationEnabled)
                        .help("Add punctuation to transcripts")
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Privacy Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy & Storage")
                    .font(.headline)
                Text("Control privacy and data retention")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Notify on Recording Start", isOn: $recordingConfig.privacySettings.notifyOnRecordingStart)
                        .help("Show notification when recording begins")
                    Toggle("Show Recording Indicator", isOn: $recordingConfig.privacySettings.showRecordingIndicator)
                        .help("Display visual indicator during recording")
                    Toggle("Pause in Private Browsing", isOn: $recordingConfig.privacySettings.pauseInPrivateBrowsing)
                        .help("Disable recording when private browsing is detected")
                    
                    HStack {
                        Text("Storage Retention")
                        Spacer()
                        Picker("", selection: $recordingConfig.storageRetentionDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("60 days").tag(60)
                            Text("90 days").tag(90)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 300)
                    }
                    .help("Automatically delete recordings after this period")
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Sync Settings
    private var syncSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // CloudKit Sync Status Section
            VStack(alignment: .leading, spacing: 12) {
                Text("iCloud Sync")
                    .font(.headline)

                HStack(spacing: 12) {
                    // CloudKit status indicator
                    HStack(spacing: 10) {
                        Circle()
                            .fill(cloudKitStatusColor)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(cloudKitStatusText)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Sync happens automatically via iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Refresh status button
                    Button("Refresh Status") {
                        checkCloudKitStatus()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                }

                // Show troubleshooting tip only when there's an issue
                if PersistenceController.iCloudStatus != .available {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(iCloudTroubleshootingTip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Local Data Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Data")
                    .font(.headline)

                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("People:")
                            .foregroundColor(.secondary)
                        Text("\(people.count)")
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Conversations:")
                            .foregroundColor(.secondary)
                        Text("\(conversations.count)")
                            .fontWeight(.medium)
                            .id(refreshTrigger)
                    }
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Advanced Options (hidden by default)
            VStack(alignment: .leading, spacing: 12) {
                // Toggle for advanced options
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvancedSyncOptions.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: showAdvancedSyncOptions ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .frame(width: 12)
                        Text("Advanced Options")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if showAdvancedSyncOptions {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Use these options only if sync isn't working correctly")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Diagnostics
                        Button(isRunningDiagnostics ? "Running..." : "Run Diagnostics") {
                            runSyncDiagnostics()
                        }
                        .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                        .disabled(isRunningDiagnostics)
                        .help("Check CloudKit sync health and identify issues")

                        // Initial setup option
                        Divider()
                            .padding(.vertical, 4)

                        Text("Initial Setup (use once)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Force Upload All Data") {
                            showForceUploadConfirmation = true
                        }
                        .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                        .help("Re-upload all local data to CloudKit - use only for initial setup")

                        // Diagnostics output
                        if let diagnosticsResult = diagnosticsResult {
                            ScrollView {
                                Text(diagnosticsResult)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .alert("Force Upload All Data", isPresented: $showForceUploadConfirmation) {
            Button("Upload", role: .destructive) {
                PersistenceController.shared.forceSyncAllExistingData()
                diagnosticsResult = "☁️ Force uploading all local data to CloudKit..."
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will re-upload ALL local data to CloudKit. Only use this for initial setup on a new device.\n\n⚠️ Warning: This can resurrect records that were deleted on other devices.")
        }
    }

    // MARK: - CloudKit Status Helpers

    private var cloudKitStatusColor: Color {
        switch PersistenceController.iCloudStatus {
        case .available:
            return .green
        case .noAccount:
            return .red
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var cloudKitStatusText: String {
        switch PersistenceController.iCloudStatus {
        case .available:
            if let lastChange = PersistenceController.lastRemoteChangeDate {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                return "Connected - Last change \(formatter.localizedString(for: lastChange, relativeTo: Date()))"
            }
            return "Connected"
        case .noAccount:
            return "Not Connected"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine, .temporarilyUnavailable:
            return "Connection Issue"
        @unknown default:
            return "Unknown Status"
        }
    }

    // MARK: - iCloud Status Helpers

    private var iCloudStatusColor: Color {
        switch PersistenceController.iCloudStatus {
        case .available:
            return .green
        case .noAccount:
            return .red
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var iCloudStatusText: String {
        switch PersistenceController.iCloudStatus {
        case .available:
            return "✅ iCloud Connected"
        case .noAccount:
            return "❌ No iCloud Account"
        case .restricted:
            return "⚠️ iCloud Restricted"
        case .couldNotDetermine:
            return "⚠️ Status Unknown"
        case .temporarilyUnavailable:
            return "⚠️ Temporarily Unavailable"
        @unknown default:
            return "⚠️ Unknown Status"
        }
    }

    private var iCloudTroubleshootingTip: String {
        switch PersistenceController.iCloudStatus {
        case .noAccount:
            return "Sign in to iCloud in System Settings → Apple Account to enable sync"
        case .restricted:
            return "iCloud access is restricted. Check parental controls or MDM settings"
        case .couldNotDetermine:
            return "Could not determine iCloud status. Try restarting the app"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Check your internet connection"
        default:
            return "Check System Settings → Apple Account for iCloud status"
        }
    }

    private func checkCloudKitStatus() {
        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                PersistenceController.iCloudStatus = status
                if let error = error {
                    print("☁️ [CloudKit] Status check error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Speaker Sensitivity Helpers

    private func speakerSensitivityLabel(_ value: Double) -> String {
        switch value {
        case ..<0.65:
            return "Very Strict"
        case 0.65..<0.68:
            return "Strict"
        case 0.68..<0.72:
            return "Optimal"
        case 0.72..<0.76:
            return "Relaxed"
        default:
            return "Very Relaxed"
        }
    }

    private func speakerSensitivityColor(_ value: Double) -> Color {
        switch value {
        case 0.68..<0.72:
            return .green  // Optimal range
        case 0.65..<0.75:
            return .blue   // Good range
        default:
            return .orange // Edge of safe range
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
            return "Calendar access granted (deprecated)"
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

    private func checkAPIBalance() async {
        isCheckingBalance = true
        openrouterBalance = await APIBalanceService.checkOpenRouterBalance(apiKey: openrouterApiKey)
        isCheckingBalance = false
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

        // Check if current model is GPT - if not, show warning
        let isGPTModel = openrouterModel.contains("gpt-") || openrouterModel.contains("openai/gpt")

        if !isGPTModel {
            // Store the file URL and show warning
            pendingFileURL = fileURL
            showModelWarning = true
            return
        }

        // Process directly if using GPT
        performOrgChartImport(fileURL)
    }

    private func performOrgChartImport(_ fileURL: URL) {
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

// MARK: - Balance Display Component
struct BalanceDisplayRow: View {
    let balance: APIBalanceService.Balance

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: balance.color == "green" ? "checkmark.circle.fill" :
                             balance.color == "orange" ? "exclamationmark.triangle.fill" :
                             balance.color == "red" ? "exclamationmark.circle.fill" :
                             "info.circle")
                .foregroundColor(balance.color == "green" ? .green :
                               balance.color == "orange" ? .orange :
                               balance.color == "red" ? .red : .secondary)

            Text(balance.displayText)
                .font(.body)
                .foregroundColor(balance.color == "green" ? .green :
                               balance.color == "orange" ? .orange :
                               balance.color == "red" ? .red : .secondary)
        }
        .padding(.vertical, 4)
    }
}

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
