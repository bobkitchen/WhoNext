import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit

// MARK: - PersonTimelineEntry

enum PersonTimelineEntry: Identifiable {
    case conversation(Conversation)
    case groupMeeting(GroupMeeting)

    var id: UUID {
        switch self {
        case .conversation(let c): return c.uuid ?? UUID()
        case .groupMeeting(let g): return g.identifier ?? UUID()
        }
    }

    var date: Date? {
        switch self {
        case .conversation(let c): return c.date
        case .groupMeeting(let g): return g.date
        }
    }
}

struct PersonDetailView: View {
    @ObservedObject var person: Person
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var appStateManager: AppStateManager

    private var conversationManager: ConversationStateManager {
        return appStateManager.conversationManager
    }

    private var conversations: [Conversation] {
        // Try to get from conversation manager first
        let managerConversations = conversationManager.getConversations(for: person)
        if !managerConversations.isEmpty {
            return managerConversations
        }

        // Fallback to direct Core Data access if manager is empty
        return (person.conversations?.allObjects as? [Conversation] ?? [])
            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }

    private var timelineItems: [PersonTimelineEntry] {
        let conversationItems = conversations.map { PersonTimelineEntry.conversation($0) }
        let groupItems = person.groupMeetingsArray.map { PersonTimelineEntry.groupMeeting($0) }
        return (conversationItems + groupItems)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    @State private var preMeetingBrief: [UUID: String] = [:]
    @State private var fallbackIsGenerating = false
    @ObservedObject private var hybridAI = HybridAIService.shared
    @State private var preMeetingBriefWindowController: PreMeetingBriefWindowController?
    @State private var profileWindowController: ProfileWindowController?

    // LinkedIn Enrichment
    enum LinkedInEnrichState {
        case idle
        case searching
        case selecting([LinkedInCandidate])
        case enriching(String) // URL being enriched
        case success
        case error(String)
    }
    @State private var enrichState: LinkedInEnrichState = .idle
    @State private var showCandidatePicker = false

    init(person: Person) {
        self.person = person
    }
    
    private var isGenerating: Bool {
        return appStateManager.isGeneratingContent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                linkedInImportView
                notesView
                sentimentAnalyticsView
                preMeetingBriefView
                conversationsView
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .errorAlert(ErrorManager.shared)
        .onAppear {
            // Load conversations for this person when view appears
            conversationManager.loadConversations(for: person)
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationSaved)) { _ in
            // Reload conversations when new ones are saved
            conversationManager.loadConversations(for: person)
        }
        .onReceive(NotificationCenter.default.publisher(for: .groupMeetingSaved)) { _ in
            // Trigger refresh when group meeting saved (person.groupMeetings updates via Core Data)
            conversationManager.loadConversations(for: person)
        }
        .onDisappear {
            // Clean up any open windows when view disappears
            closePreMeetingBriefWindow()
            closeProfileWindow()
        }
    }
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 24) {
            // Enhanced Avatar with liquid glass styling
            ZStack {
                if let data = person.photo, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.primary.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        }
                        .overlay {
                            Text(person.initials)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                        }
                        .shadow(color: Color.accentColor.opacity(0.2), radius: 4, x: 0, y: 2)
                }
            }
            
            // Person Info with enhanced typography
            VStack(alignment: .leading, spacing: 8) {
                Text(person.name ?? "Unnamed")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let timezone = person.timezone, !timezone.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                            Text(timezone)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(.secondary.opacity(0.1))
                        }
                    }
                    
                    CategoryBadge(category: person.category)

                    // Voice Recognition Status
                    if person.voiceSampleCount > 0 {
                        let confidence = Int(person.voiceConfidence * 100)
                        let badgeColor: Color = person.voiceConfidence >= 0.8 ? .green : (person.voiceConfidence >= 0.5 ? .orange : .red)
                        let icon = person.voiceConfidence >= 0.8 ? "waveform.circle.fill" : "waveform.circle"

                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(badgeColor)
                                .symbolRenderingMode(.hierarchical)
                            Text("Voice: \(confidence)%")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(badgeColor)
                            Text("(\(person.voiceSampleCount) samples)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(badgeColor.opacity(0.1))
                                .overlay {
                                    Capsule()
                                        .stroke(badgeColor.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                        .help(person.voiceConfidence >= 0.8 ? "High confidence voice recognition" : "Needs more voice samples for reliable recognition")
                    }
                }
            }
            
            Spacer()
            
            // Action button - Edit only (LinkedIn import moved to dedicated section)
            Button(action: openEditWindow) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                    Text("Edit")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
        }
        .liquidGlassCard(
            cornerRadius: 16,
            elevation: .medium,
            padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
            isInteractive: false
        )
    }

    // MARK: - LinkedIn Enrichment Section

    @ViewBuilder
    private var linkedInImportView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enrich button
            switch enrichState {
            case .idle:
                if person.linkedinUrl != nil {
                    Button(action: { reEnrich() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                            Text("Re-enrich from LinkedIn")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                } else {
                    Button(action: { startEnrichment() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14))
                            Text("Enrich from LinkedIn")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

            case .searching:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching for \(person.name ?? "person") on LinkedIn...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

            case .selecting:
                // Handled by sheet
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Select a profile...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

            case .enriching:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enriching profile...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

            case .success:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text("Profile enriched successfully")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

            case .error(let message):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    Button("Try Again") { enrichState = .idle }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .sheet(isPresented: $showCandidatePicker) {
            if case .selecting(let candidates) = enrichState {
                LinkedInCandidatePickerView(
                    candidates: candidates,
                    personName: person.name ?? "Unknown",
                    onSelect: { candidate in
                        showCandidatePicker = false
                        enrichFromCandidate(candidate)
                    },
                    onCancel: {
                        showCandidatePicker = false
                        enrichState = .idle
                    }
                )
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var notesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text("Profile Notes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()

                // Pop-out button
                Button(action: openProfileWindow) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.accentColor)
                        .help("Open profile in new window")
                }
                .buttonStyle(.plain)
            }

            if let notes = person.notes, !notes.isEmpty {
                ScrollView {
                    ProfileContentView(content: notes)
                }
                .frame(maxHeight: 200)
            } else {
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No profile information")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("Use 'Enrich from LinkedIn' above or add notes via Edit")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var sentimentAnalyticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Conversation Analytics")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("(\(timelineItems.count) meetings)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if timelineItems.isEmpty {
                // Show placeholder when no meetings
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No meeting data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Start a conversation to see analytics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                // Analytics Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    // Health Score Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundColor(healthScoreColor)
                            Text("Health Score")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(String(format: "%.1f", relationshipHealthScore))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(healthScoreColor)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Average Sentiment Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "face.smiling.fill")
                                .font(.system(size: 12))
                                .foregroundColor(averageSentimentColor)
                            Text("Avg Sentiment")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(averageSentimentLabel)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(averageSentimentColor)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Total Conversations Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            Text("Conversations")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(conversations.count)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Detailed Analytics
                ConversationDurationView(person: person)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    private var relationshipHealthScore: Double {
        guard let metrics = ConversationMetricsCalculator.shared.calculateMetrics(for: person) else {
            return 0.0
        }
        return metrics.healthScore
    }
    
    private var healthScoreColor: Color {
        let score = relationshipHealthScore
        if score >= 0.7 { return .green }
        else if score >= 0.4 { return .orange }
        else { return .red }
    }
    
    private var averageSentiment: Double {
        let conversationSentiments = conversations.compactMap { conversation in
            conversation.value(forKey: "sentimentScore") as? Double
        }
        let groupSentiments = person.groupMeetingsArray.map { $0.sentimentScore }
        let allSentiments = conversationSentiments + groupSentiments
        guard !allSentiments.isEmpty else { return 0.0 }
        return allSentiments.reduce(0, +) / Double(allSentiments.count)
    }
    
    private var averageSentimentLabel: String {
        let sentiment = averageSentiment
        if sentiment >= 0.6 { return "Positive" }
        else if sentiment >= 0.4 { return "Neutral" }
        else if sentiment >= 0.2 { return "Mixed" }
        else { return "Negative" }
    }
    
    private var averageSentimentColor: Color {
        let sentiment = averageSentiment
        if sentiment >= 0.6 { return .green }
        else if sentiment >= 0.4 { return .blue }
        else if sentiment >= 0.2 { return .orange }
        else { return .red }
    }
    
    @ViewBuilder
    private var preMeetingBriefView: some View {
        if !timelineItems.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Pre-Meeting Brief")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let brief = preMeetingBrief[person.identifier ?? UUID()], !brief.isEmpty {
                        HStack(spacing: 8) {
                            // Pop Out button
                            Button(action: {
                                openPreMeetingBriefWindow(brief)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                    Text("Pop Out")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Copy button
                            Button(action: {
                                copyToClipboard(brief)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 10))
                                    Text("Copy")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Button(action: isGenerating ? {} : generatePreMeetingBrief) {
                            HStack(spacing: 4) {
                                if isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                }
                                Text(isGenerating ? "Generating..." : "Generate")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isGenerating)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var conversationsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Meeting History")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("(\(timelineItems.count))")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: openNewConversationWindow) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("New")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if timelineItems.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))

                    VStack(spacing: 8) {
                        Text("No meetings yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Start your first conversation to begin building insights")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: openNewConversationWindow) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                            Text("Add First Conversation")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Unified Timeline List
                LazyVStack(spacing: 12) {
                    ForEach(timelineItems) { item in
                        switch item {
                        case .conversation(let conversation):
                            ConversationRowView(conversation: conversation, conversationManager: conversationManager)
                        case .groupMeeting(let meeting):
                            GroupMeetingTimelineRow(meeting: meeting)
                        }
                    }
                }
            }
        }
    }
    
    private func openEditWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit \(person.name ?? "Person")"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PersonEditView(
                person: person,
                onSave: { window.close() },
                onCancel: { window.close() }
            )
            .environment(\.managedObjectContext, viewContext)
        )
        let delegate = ConversationWindowDelegate()
        window.delegate = delegate
        objc_setAssociatedObject(window, &ConversationWindowDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.makeKeyAndOrderFront(nil)
    }
    
    private func openNewConversationWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Conversation with \(person.name ?? "Person")"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: NewConversationWindowView(
                preselectedPerson: person,
                onSave: { window.close() },
                onCancel: { window.close() }
            )
            .environment(\.managedObjectContext, viewContext)
        )
        let delegate = ConversationWindowDelegate()
        window.delegate = delegate
        objc_setAssociatedObject(window, &ConversationWindowDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.makeKeyAndOrderFront(nil)
    }
    
    private func openPreMeetingBriefWindow(_ briefContent: String) {
        // Close existing window if open
        closePreMeetingBriefWindow()
        
        let windowController = PreMeetingBriefWindowController(
            personName: person.name ?? "Unknown",
            briefContent: briefContent
        ) { [self] in
            // This closure is called when the window is closed
            preMeetingBriefWindowController = nil
        }
        
        preMeetingBriefWindowController = windowController
        windowController.showWindow(nil)
    }
    
    private func closePreMeetingBriefWindow() {
        preMeetingBriefWindowController?.close()
        preMeetingBriefWindowController = nil
    }
    
    private func openProfileWindow() {
        // Close existing window if open
        closeProfileWindow()

        let profileContent = person.notes ?? "No profile information available."
        
        let windowController = ProfileWindowController(
            personName: person.name ?? "Unknown",
            profileContent: profileContent
        ) { [self] in
            // This closure is called when the window is closed
            profileWindowController = nil
        }
        
        profileWindowController = windowController
        windowController.showWindow(nil)
    }
    
    private func closeProfileWindow() {
        profileWindowController?.close()
        profileWindowController = nil
    }
    
    private func generatePreMeetingBrief() {
        appStateManager.setGeneratingContent(true)
        preMeetingBrief[person.identifier ?? UUID()] = nil
        
        hybridAI.generateBrief(for: person) { result in
            DispatchQueue.main.async {
                self.appStateManager.setGeneratingContent(false)
                switch result {
                case .success(let brief):
                    self.preMeetingBrief[self.person.identifier ?? UUID()] = brief
                case .failure(let error):
                    ErrorManager.shared.handle(error, context: "Failed to generate pre-meeting brief")
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - LinkedIn Enrichment

    private func startEnrichment() {
        guard ApifyLinkedInService.shared.hasToken else {
            enrichState = .error("Apify API token not configured. Set it in Settings → LinkedIn Enrichment.")
            return
        }

        enrichState = .searching
        let name = person.name ?? ""
        let company = person.company

        Task {
            do {
                let candidates = try await ApifyLinkedInService.shared.searchLinkedInProfiles(name: name, company: company)
                await MainActor.run {
                    if candidates.isEmpty {
                        enrichState = .error("No LinkedIn profiles found for \"\(name)\". Check the name and company.")
                    } else if candidates.count == 1 {
                        enrichFromCandidate(candidates[0])
                    } else {
                        enrichState = .selecting(candidates)
                        showCandidatePicker = true
                    }
                }
            } catch {
                await MainActor.run {
                    enrichState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func reEnrich() {
        guard let url = person.linkedinUrl else { return }
        guard ApifyLinkedInService.shared.hasToken else {
            enrichState = .error("Apify API token not configured. Set it in Settings → LinkedIn Enrichment.")
            return
        }

        enrichState = .enriching(url)
        let token = SecureStorage.getAPIKey(for: .apify)

        Task {
            do {
                let profile = try await ApifyLinkedInService.shared.enrichProfile(url: url, token: token)
                let photoData: Data?
                if let photoUrl = profile.profilePicture {
                    photoData = try? await ApifyLinkedInService.shared.downloadPhoto(from: photoUrl)
                } else {
                    photoData = nil
                }

                await MainActor.run {
                    ApifyLinkedInService.shared.applyProfile(profile, to: person, linkedinUrl: url, photoData: photoData)
                    try? viewContext.save()
                    enrichState = .success
                    Task { try? await Task.sleep(for: .seconds(3)); enrichState = .idle }
                }
            } catch {
                await MainActor.run {
                    enrichState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func enrichFromCandidate(_ candidate: LinkedInCandidate) {
        enrichState = .enriching(candidate.url)
        let token = SecureStorage.getAPIKey(for: .apify)

        Task {
            do {
                let profile = try await ApifyLinkedInService.shared.enrichProfile(url: candidate.url, token: token)
                let photoData: Data?
                if let photoUrl = profile.profilePicture {
                    photoData = try? await ApifyLinkedInService.shared.downloadPhoto(from: photoUrl)
                } else {
                    photoData = nil
                }

                await MainActor.run {
                    ApifyLinkedInService.shared.applyProfile(profile, to: person, linkedinUrl: candidate.url, photoData: photoData)
                    try? viewContext.save()
                    enrichState = .success
                    Task { try? await Task.sleep(for: .seconds(3)); enrichState = .idle }
                }
            } catch {
                await MainActor.run {
                    enrichState = .error(error.localizedDescription)
                }
            }
        }
    }

    // mapLocationToTimezone moved to Utilities/TimezoneMapper.swift
}

struct ConversationRowView: View {
    let conversation: Conversation
    let conversationManager: ConversationStateManager
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dateIndicator
            conversationContent
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            openConversationWindow()
        }
        .contextMenu {
            Button(action: openConversationWindow) {
                Label("Open in Window", systemImage: "macwindow")
            }
            
            Divider()
            
            Button(action: deleteConversation) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var dateIndicator: some View {
        VStack(spacing: 4) {
            if let date = conversation.date {
                Text(dayFormatter.string(from: date))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(monthFormatter.string(from: date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 50)
        .padding(.vertical, 4)
    }
    
    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            durationAndEngagementInfo
            summaryOrNotes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var headerRow: some View {
        HStack {
            Text(conversationTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
            
            // Sentiment indicator
            if conversation.value(forKey: "lastSentimentAnalysis") != nil {
                sentimentIndicator
            }
            
            if let date = conversation.date {
                Text(timeFormatter.string(from: date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var durationAndEngagementInfo: some View {
        let duration = conversation.value(forKey: "duration") as? Int16 ?? 0
        if duration > 0 || conversation.value(forKey: "lastSentimentAnalysis") != nil {
            HStack(spacing: 12) {
                if duration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(duration)m")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let engagementLevel = conversation.value(forKey: "engagementLevel") as? String {
                    HStack(spacing: 4) {
                        Image(systemName: engagementIcon(engagementLevel))
                            .font(.system(size: 10))
                            .foregroundColor(engagementColor(engagementLevel))
                        Text(engagementLevel.capitalized)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var summaryOrNotes: some View {
        if let summary = conversation.summary, !summary.isEmpty {
            Text(summary)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
        } else if let notes = conversation.notes, !notes.isEmpty {
            Text(notes)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
    }
    
    private var conversationTitle: String {
        if let summary = conversation.summary, !summary.isEmpty {
            // Extract first line as title
            let firstLine = summary.components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty ? "Conversation" : firstLine
        } else if let notes = conversation.notes, !notes.isEmpty {
            let firstLine = notes.components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty ? "Conversation" : firstLine
        }
        return "Conversation"
    }
    
    private var sentimentIndicator: some View {
        Circle()
            .fill(sentimentColor)
            .frame(width: 8, height: 8)
    }
    
    private var sentimentColor: Color {
        let score = conversation.value(forKey: "sentimentScore") as? Double ?? 0.0
        if score > 0.3 {
            return .green
        } else if score < -0.3 {
            return .red
        } else {
            return .orange
        }
    }
    
    private func openConversationWindow() {
        // Open conversation in new window.
        // IMPORTANT: We use isReleasedWhenClosed = false and manage lifecycle
        // via NSWindowDelegate. Setting isReleasedWhenClosed = true caused
        // EXC_BAD_ACCESS crashes because when the window deallocs, the
        // NSHostingView's SwiftUI content (holding Core Data managed object
        // references) is torn down simultaneously. If CloudKit is mid-merge
        // at that moment, the managed object deallocation conflicts with the
        // merge transaction ("entangle context after pre-commit").
        //
        // Fix: nil out contentView in windowWillClose (releasing SwiftUI content
        // and its managed object refs) BEFORE the window itself deallocs.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Conversation - \(conversationTitle)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: conversation, conversationManager: conversationManager)
                .environment(\.managedObjectContext, viewContext)
        )
        let delegate = ConversationWindowDelegate()
        window.delegate = delegate
        // Store delegate as associated object so it lives as long as the window
        objc_setAssociatedObject(window, &ConversationWindowDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.makeKeyAndOrderFront(nil)
    }
    
    private func deleteConversation() {
        // Delete locally - CloudKit sync handles propagation automatically
        viewContext.delete(conversation)
        try? viewContext.save()
    }
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func engagementIcon(_ engagementLevel: String) -> String {
        switch engagementLevel.lowercased() {
        case "high":
            return "flame.fill"
        case "medium":
            return "circle.fill"
        case "low":
            return "circle"
        default:
            return "circle"
        }
    }
    
    private func engagementColor(_ engagementLevel: String) -> Color {
        SentimentColors.engagement(engagementLevel)
    }
}

// MARK: - GroupMeetingTimelineRow

struct GroupMeetingTimelineRow: View {
    let meeting: GroupMeeting

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Date indicator
            VStack(spacing: 4) {
                if let date = meeting.date {
                    Text(dayFormatter.string(from: date))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    Text(monthFormatter.string(from: date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }
            .frame(width: 50)
            .padding(.vertical, 4)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Purple group badge
                    if let groupName = meeting.group?.name {
                        HStack(spacing: 4) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 9))
                            Text("Group: \(groupName)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    if let date = meeting.date {
                        Text(timeFormatter.string(from: date))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                // Attendee count and duration
                HStack(spacing: 12) {
                    if meeting.attendeeCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("\(meeting.attendeeCount) attendees")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    if meeting.duration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(meeting.formattedDuration)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }

                // Summary preview
                if let summary = meeting.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - PreMeetingBriefWindowController
class PreMeetingBriefWindowController: NSWindowController {
    private let onClose: () -> Void
    
    init(personName: String, briefContent: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.title = "Pre-Meeting Brief - \(personName)"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        window.contentView = NSHostingView(
            rootView: PreMeetingBriefWindow(
                personName: personName,
                briefContent: briefContent,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func close() {
        super.close()
        onClose()
    }
}

// MARK: - NSWindowDelegate
extension PreMeetingBriefWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - ProfileWindowController
class ProfileWindowController: NSWindowController {
    private let onClose: () -> Void
    
    init(personName: String, profileContent: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.title = "Profile - \(personName)"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        window.contentView = NSHostingView(
            rootView: ProfileWindow(
                personName: personName,
                profileContent: profileContent,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func close() {
        super.close()
        onClose()
    }
}

// MARK: - NSWindowDelegate for ProfileWindowController
extension ProfileWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - ProfileContentView
struct ProfileContentView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(processContent(), id: \.self) { section in
                processSection(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func processContent() -> [String] {
        // Split content into sections while preserving structure
        content.components(separatedBy: "\n\n")
    }
    
    @ViewBuilder
    private func processSection(_ section: String) -> some View {
        let lines = section.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                if line.hasPrefix("###") {
                    // Subheading - process inline formatting
                    let cleanedText = line.replacingOccurrences(of: "### ", with: "")
                    Text(processInlineFormatting(cleanedText))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                } else if line.hasPrefix("##") {
                    // Main heading - process inline formatting
                    let cleanedText = line.replacingOccurrences(of: "## ", with: "")
                    Text(processInlineFormatting(cleanedText))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.top, 8)
                } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("•") ||
                         line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                    // Bullet point - process inline formatting
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        let bulletText = line.replacingOccurrences(of: "•", with: "")
                                .replacingOccurrences(of: "-", with: "")
                                .trimmingCharacters(in: .whitespaces)

                        Text(processInlineFormatting(bulletText))
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, line.hasPrefix("    ") ? 20 : 0)
                } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Regular text
                    Text(processInlineFormatting(line))
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, line.hasPrefix("    ") ? 32 : 0)
                }
            }
        }
    }
    
    private func processInlineFormatting(_ text: String) -> AttributedString {
        var processedText = text
        var result = AttributedString()
        
        // Replace **text** with bold formatting
        let boldPattern = "\\*\\*([^*]+)\\*\\*"
        
        do {
            let regex = try NSRegularExpression(pattern: boldPattern, options: [])
            let nsString = processedText as NSString
            let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var lastEndIndex = 0
            
            for match in matches {
                // Add text before the bold part
                let beforeRange = NSRange(location: lastEndIndex, length: match.range.location - lastEndIndex)
                if let beforeText = nsString.substring(with: beforeRange) as String?, !beforeText.isEmpty {
                    result.append(AttributedString(beforeText))
                }
                
                // Add the bold text
                if let boldRange = Range(match.range(at: 1), in: processedText) {
                    var boldText = AttributedString(String(processedText[boldRange]))
                    boldText.font = .system(size: 14, weight: .semibold)
                    result.append(boldText)
                }
                
                lastEndIndex = match.range.location + match.range.length
            }
            
            // Add any remaining text after the last match
            if lastEndIndex < nsString.length {
                let remainingText = nsString.substring(from: lastEndIndex)
                result.append(AttributedString(remainingText))
            }
            
            // If no matches found, just return the original text
            if matches.isEmpty {
                result = AttributedString(text)
            }
            
        } catch {
            // If regex fails, return the text as-is
            result = AttributedString(text)
        }
        
        return result
    }
}

// MARK: - ProfileWindow View
struct ProfileWindow: View {
    let personName: String
    let profileContent: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                Text("\(personName) - Full Profile")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                if !profileContent.isEmpty && !profileContent.starts(with: "No profile") {
                    ProfileContentView(content: profileContent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No profile information available")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("To add profile information:")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("1. Print LinkedIn profile to PDF from your browser", systemImage: "1.circle")
                            Label("2. Drop the PDF onto the 'Import LinkedIn Profile' section", systemImage: "2.circle")
                            Label("3. Or click 'Edit' to add notes manually", systemImage: "3.circle")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    .padding(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Footer with copy button
            HStack {
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profileContent, forType: .string)
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .disabled(profileContent.isEmpty || profileContent.starts(with: "No profile"))
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Conversation Window Delegate

/// Manages conversation window lifecycle to prevent Core Data crashes.
/// When the window closes, we nil out contentView first to release the SwiftUI
/// view hierarchy (and its managed object references) before the window deallocs.
/// This prevents EXC_BAD_ACCESS when CloudKit is mid-merge during window close.
class ConversationWindowDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) static var associatedKey: UInt8 = 0

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Release the SwiftUI hosting view (and its managed object refs) before
        // the window itself is deallocated. This breaks the retain cycle between
        // the window and the Core Data objects, preventing crashes when CloudKit
        // merges happen during deallocation.
        window.contentView = nil
    }

    func windowDidClose(_ notification: Notification) {
        // Remove the associated delegate reference so ARC can clean up
        if let window = notification.object as? NSWindow {
            objc_setAssociatedObject(window, &ConversationWindowDelegate.associatedKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
