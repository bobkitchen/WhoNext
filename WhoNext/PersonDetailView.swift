import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit

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

    @State private var preMeetingBrief: [UUID: String] = [:]
    @State private var fallbackIsGenerating = false
    @StateObject private var hybridAI = HybridAIService()
    @State private var preMeetingBriefWindowController: PreMeetingBriefWindowController?
    @State private var profileWindowController: ProfileWindowController?
    @State private var showLinkedInImport = false
    @State private var showAddActionItem = false
    @State private var actionItemsRefreshID = UUID()
    @State private var showingPhotoPopover = false

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
                actionItemsView
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationSaved"))) { _ in
            // Reload conversations when new ones are saved
            conversationManager.loadConversations(for: person)
        }
        .onDisappear {
            // Clean up any open windows when view disappears
            closePreMeetingBriefWindow()
            closeProfileWindow()
        }
        .sheet(isPresented: $showingPhotoPopover) {
            PersonPhotoPopover(person: person)
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 24) {
            // Enhanced Avatar with liquid glass styling - clickable when photo exists
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
                        .contentShape(Circle())
                        .onTapGesture {
                            showingPhotoPopover = true
                        }
                        .help("Click to see larger photo")
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
                    
                    if (person.value(forKey: "isDirectReport") as? Bool) == true {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                                .symbolRenderingMode(.hierarchical)
                            Text("Direct Report")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(.blue.opacity(0.1))
                                .overlay {
                                    Capsule()
                                        .stroke(.blue.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                    }

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

    // MARK: - LinkedIn Import Section

    @ViewBuilder
    private var linkedInImportView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Collapsible header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showLinkedInImport.toggle() } }) {
                HStack {
                    Image(systemName: showLinkedInImport ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)

                    Text("Import LinkedIn Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if person.notes?.isEmpty ?? true {
                        Text("No profile data")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable drop zone
            if showLinkedInImport {
                CompactLinkedInDropZone { markdown in
                    // Update person.notes with the extracted markdown
                    person.notes = markdown
                    person.modifiedAt = Date()

                    // Extract location and set timezone if not already set
                    if person.timezone?.isEmpty ?? true || person.timezone == "UTC" {
                        if let location = extractLocationFromMarkdown(markdown) {
                            let timezone = mapLocationToTimezone(location)
                            person.timezone = timezone
                            print("🌍 [PersonDetail] Set timezone to \(timezone) based on location: \(location)")
                        }
                    }

                    // Save changes
                    do {
                        try viewContext.save()
                        print("✅ [PersonDetail] LinkedIn profile data saved for \(person.name ?? "Unknown")")

                        // Collapse the import section after successful import
                        withAnimation {
                            showLinkedInImport = false
                        }
                    } catch {
                        print("❌ [PersonDetail] Failed to save LinkedIn data: \(error)")
                        ErrorManager.shared.handle(error, context: "Failed to save LinkedIn profile data")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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

                    Text("Import a LinkedIn PDF above or add notes manually via Edit")
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
                Text("(\(conversations.count) conversations)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if conversations.isEmpty {
                // Show placeholder when no conversations
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No conversation data yet")
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
        let sentiments = conversations.compactMap { conversation in
            conversation.value(forKey: "sentimentScore") as? Double
        }
        guard !sentiments.isEmpty else { return 0.0 }
        return sentiments.reduce(0, +) / Double(sentiments.count)
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
        if !conversations.isEmpty {
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

    // MARK: - Action Items Section

    private var personActionItems: [ActionItem] {
        ActionItem.fetchForPerson(person, in: viewContext)
    }

    private var pendingActionItems: [ActionItem] {
        personActionItems.filter { !$0.isCompleted }
    }

    @ViewBuilder
    private var actionItemsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Action Items")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    if !pendingActionItems.isEmpty {
                        Text("\(pendingActionItems.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Add button
                Button(action: { showAddActionItem = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if personActionItems.isEmpty {
                // Empty State
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No action items")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("Add action items or they'll appear here from meetings")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: { showAddActionItem = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12))
                            Text("Add Action Item")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Action Items List
                LazyVStack(spacing: 8) {
                    ForEach(personActionItems) { item in
                        PersonActionItemRow(item: item)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .id(actionItemsRefreshID)
        .sheet(isPresented: $showAddActionItem) {
            AddPersonActionItemView(person: person) {
                // Refresh the list after adding
                actionItemsRefreshID = UUID()
            }
            .environment(\.managedObjectContext, viewContext)
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
                    Text("Conversations")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
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
            
            if conversations.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 8) {
                        Text("No conversations yet")
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
                // Conversation List
                LazyVStack(spacing: 12) {
                    ForEach(conversations) { conversation in
                        ConversationRowView(conversation: conversation, conversationManager: conversationManager)
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

    // MARK: - Location & Timezone Helpers

    private func extractLocationFromMarkdown(_ markdown: String) -> String? {
        // Look for location line with 📍 emoji
        let lines = markdown.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("📍") {
                let location = trimmed.replacingOccurrences(of: "📍", with: "").trimmingCharacters(in: .whitespaces)
                if !location.isEmpty {
                    return location
                }
            }
        }
        return nil
    }

    private func mapLocationToTimezone(_ location: String) -> String {
        let lowercased = location.lowercased()

        // Country/region to timezone mapping
        let timezoneMap: [(keywords: [String], timezone: String)] = [
            // Africa
            (["kenya", "nairobi"], "Africa/Nairobi"),
            (["ethiopia", "addis"], "Africa/Addis_Ababa"),
            (["nigeria", "lagos"], "Africa/Lagos"),
            (["south africa", "johannesburg", "cape town"], "Africa/Johannesburg"),
            (["egypt", "cairo"], "Africa/Cairo"),
            (["morocco", "casablanca"], "Africa/Casablanca"),
            (["ghana", "accra"], "Africa/Accra"),
            (["tanzania", "dar es salaam"], "Africa/Dar_es_Salaam"),
            (["uganda", "kampala"], "Africa/Kampala"),
            (["rwanda", "kigali"], "Africa/Kigali"),
            (["senegal", "dakar"], "Africa/Dakar"),
            (["democratic republic of congo", "kinshasa", "drc"], "Africa/Kinshasa"),

            // Europe
            (["london", "uk", "united kingdom", "england", "britain"], "Europe/London"),
            (["paris", "france"], "Europe/Paris"),
            (["berlin", "germany"], "Europe/Berlin"),
            (["amsterdam", "netherlands"], "Europe/Amsterdam"),
            (["madrid", "spain"], "Europe/Madrid"),
            (["rome", "italy"], "Europe/Rome"),
            (["zurich", "switzerland", "geneva"], "Europe/Zurich"),
            (["stockholm", "sweden"], "Europe/Stockholm"),
            (["oslo", "norway"], "Europe/Oslo"),
            (["copenhagen", "denmark"], "Europe/Copenhagen"),
            (["dublin", "ireland"], "Europe/Dublin"),
            (["brussels", "belgium"], "Europe/Brussels"),
            (["vienna", "austria"], "Europe/Vienna"),
            (["warsaw", "poland"], "Europe/Warsaw"),
            (["prague", "czech"], "Europe/Prague"),

            // Americas
            (["new york", "nyc", "eastern"], "America/New_York"),
            (["los angeles", "la", "california", "pacific"], "America/Los_Angeles"),
            (["chicago", "central"], "America/Chicago"),
            (["denver", "mountain"], "America/Denver"),
            (["seattle", "washington"], "America/Los_Angeles"),
            (["san francisco", "sf", "bay area"], "America/Los_Angeles"),
            (["boston", "massachusetts"], "America/New_York"),
            (["miami", "florida"], "America/New_York"),
            (["atlanta", "georgia"], "America/New_York"),
            (["dallas", "texas", "houston", "austin"], "America/Chicago"),
            (["phoenix", "arizona"], "America/Phoenix"),
            (["toronto", "ontario", "canada"], "America/Toronto"),
            (["vancouver", "british columbia"], "America/Vancouver"),
            (["mexico city", "mexico"], "America/Mexico_City"),
            (["sao paulo", "brazil", "rio"], "America/Sao_Paulo"),
            (["buenos aires", "argentina"], "America/Argentina/Buenos_Aires"),
            (["bogota", "colombia"], "America/Bogota"),
            (["lima", "peru"], "America/Lima"),
            (["santiago", "chile"], "America/Santiago"),

            // Asia
            (["tokyo", "japan"], "Asia/Tokyo"),
            (["beijing", "china", "shanghai"], "Asia/Shanghai"),
            (["hong kong"], "Asia/Hong_Kong"),
            (["singapore"], "Asia/Singapore"),
            (["india", "mumbai", "delhi", "bangalore", "chennai"], "Asia/Kolkata"),
            (["dubai", "uae", "abu dhabi"], "Asia/Dubai"),
            (["seoul", "korea", "south korea"], "Asia/Seoul"),
            (["bangkok", "thailand"], "Asia/Bangkok"),
            (["jakarta", "indonesia"], "Asia/Jakarta"),
            (["manila", "philippines"], "Asia/Manila"),
            (["kuala lumpur", "malaysia"], "Asia/Kuala_Lumpur"),
            (["vietnam", "ho chi minh", "hanoi"], "Asia/Ho_Chi_Minh"),
            (["pakistan", "karachi", "lahore"], "Asia/Karachi"),
            (["bangladesh", "dhaka"], "Asia/Dhaka"),
            (["israel", "tel aviv", "jerusalem"], "Asia/Jerusalem"),
            (["turkey", "istanbul", "ankara"], "Europe/Istanbul"),
            (["saudi arabia", "riyadh"], "Asia/Riyadh"),
            (["jordan", "amman"], "Asia/Amman"),
            (["lebanon", "beirut"], "Asia/Beirut"),
            (["iraq", "baghdad"], "Asia/Baghdad"),
            (["iran", "tehran"], "Asia/Tehran"),
            (["afghanistan", "kabul"], "Asia/Kabul"),
            (["nepal", "kathmandu"], "Asia/Kathmandu"),
            (["sri lanka", "colombo"], "Asia/Colombo"),
            (["myanmar", "yangon"], "Asia/Yangon"),

            // Oceania
            (["sydney", "australia", "melbourne", "brisbane"], "Australia/Sydney"),
            (["perth", "western australia"], "Australia/Perth"),
            (["auckland", "new zealand", "wellington"], "Pacific/Auckland"),

            // US States
            (["washington dc", "dc", "virginia", "maryland"], "America/New_York"),
        ]

        for (keywords, timezone) in timezoneMap {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return timezone
                }
            }
        }

        // Default to UTC if no match found
        return "UTC"
    }
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
        // Open conversation in new window
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
        switch engagementLevel.lowercased() {
        case "high":
            return .green
        case "medium":
            return .orange
        case "low":
            return .red
        default:
            return .secondary
        }
    }
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

// MARK: - Person Action Item Row

struct PersonActionItemRow: View {
    @ObservedObject var item: ActionItem
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack(spacing: 12) {
            // Completion checkbox
            Button(action: toggleCompletion) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(item.isCompleted)
                    .foregroundColor(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Priority badge
                    PersonActionPriorityBadge(priority: item.priorityEnum)

                    // Due date
                    if let dueText = item.formattedDueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(dueText)
                        }
                        .font(.caption)
                        .foregroundColor(item.isOverdue ? .red : .secondary)
                    }

                    // From conversation
                    if let conversation = item.conversation, let date = conversation.date {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left")
                            Text(conversationDateFormatter.string(from: date))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Reminder indicator
            if item.reminderID != nil {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isOverdue ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button(item.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                toggleCompletion()
            }
            Divider()
            Button("Send to Reminders") {
                sendToReminders()
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        }
    }

    private func toggleCompletion() {
        withAnimation {
            item.toggleCompletion()
            try? viewContext.save()

            // Sync to Apple Reminders if linked
            if item.reminderID != nil {
                Task {
                    await RemindersIntegration.shared.updateReminderCompletion(for: item)
                }
            }
        }
    }

    private func sendToReminders() {
        Task {
            await RemindersIntegration.shared.createReminder(from: item)
        }
    }

    private func deleteItem() {
        withAnimation {
            viewContext.delete(item)
            try? viewContext.save()
        }
    }

    private var conversationDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}

// MARK: - Person Action Priority Badge

struct PersonActionPriorityBadge: View {
    let priority: ActionItem.Priority

    var body: some View {
        Text(priority.displayName)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch priority {
        case .high: return Color.red.opacity(0.2)
        case .medium: return Color.orange.opacity(0.2)
        case .low: return Color.blue.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

// MARK: - Add Person Action Item View

struct AddPersonActionItemView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil"),
        animation: .default
    )
    private var allPeople: FetchedResults<Person>

    let person: Person
    let onSave: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate = false
    @State private var priority: ActionItem.Priority = .medium
    @State private var ownerSelection: String = "them"
    @State private var customAssignee = ""
    @State private var sendToReminders = false
    @State private var showingSuggestions = false

    private var isMyTask: Bool {
        ownerSelection == "me"
    }

    private var assignee: String? {
        switch ownerSelection {
        case "me": return nil
        case "them": return person.name
        case "other": return customAssignee.isEmpty ? nil : customAssignee
        default: return nil
        }
    }

    /// People matching the search query, excluding the current person
    private var matchingPeople: [Person] {
        guard !customAssignee.isEmpty else { return [] }
        let query = customAssignee.lowercased()
        return allPeople.filter { p in
            p.identifier != person.identifier &&
            (p.name?.lowercased().contains(query) == true ||
             p.role?.lowercased().contains(query) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                Spacer()

                Text("New Action Item")
                    .font(.headline)

                Spacer()

                Button("Save") { saveItem() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What needs to be done?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Action item title...", text: $title)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                    }

                    // Owner picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who is responsible?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("Owner", selection: $ownerSelection) {
                            Text("Me").tag("me")
                            Text(person.name ?? "Them").tag("them")
                            Text("Other...").tag("other")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: ownerSelection) { _, newValue in
                            // Auto-enable reminders when "Me" is selected
                            if newValue == "me" {
                                sendToReminders = true
                            } else {
                                sendToReminders = false
                            }
                        }

                        // Custom assignee field when "Other" is selected
                        if ownerSelection == "other" {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Search contacts or enter name...", text: $customAssignee)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                                    .onChange(of: customAssignee) { _, _ in
                                        showingSuggestions = !customAssignee.isEmpty && !matchingPeople.isEmpty
                                    }

                                // Suggestions dropdown
                                if showingSuggestions && !matchingPeople.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(matchingPeople.prefix(5)) { suggestedPerson in
                                            Button(action: {
                                                customAssignee = suggestedPerson.name ?? ""
                                                showingSuggestions = false
                                            }) {
                                                HStack(spacing: 10) {
                                                    // Avatar
                                                    if let data = suggestedPerson.photo, let image = NSImage(data: data) {
                                                        Image(nsImage: image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 28, height: 28)
                                                            .clipShape(Circle())
                                                    } else {
                                                        Circle()
                                                            .fill(Color.accentColor.opacity(0.15))
                                                            .frame(width: 28, height: 28)
                                                            .overlay {
                                                                Text(suggestedPerson.initials)
                                                                    .font(.system(size: 10, weight: .medium))
                                                                    .foregroundColor(.accentColor)
                                                            }
                                                    }

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(suggestedPerson.name ?? "Unknown")
                                                            .font(.subheadline)
                                                            .fontWeight(.medium)
                                                            .foregroundColor(.primary)
                                                        if let role = suggestedPerson.role, !role.isEmpty {
                                                            Text(role)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }

                                                    Spacer()
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                                            if suggestedPerson.id != matchingPeople.prefix(5).last?.id {
                                                Divider()
                                                    .padding(.leading, 50)
                                            }
                                        }
                                    }
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                                }
                            }
                        }
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("Priority", selection: $priority) {
                            ForEach(ActionItem.Priority.allCases, id: \.self) { p in
                                HStack {
                                    Circle()
                                        .fill(priorityColor(p))
                                        .frame(width: 8, height: 8)
                                    Text(p.displayName)
                                }
                                .tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Due Date
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Set Due Date", isOn: $hasDueDate)
                            .font(.subheadline)

                        if hasDueDate {
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextEditor(text: $notes)
                            .font(.body)
                            .frame(minHeight: 60)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                    }

                    // Send to Reminders toggle
                    Toggle(isOn: $sendToReminders) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                            Text("Also create Apple Reminder")
                        }
                    }
                    .font(.subheadline)

                    // Context info
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text("Linked to: \(person.name ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .frame(width: 420, height: 560)
    }

    private func priorityColor(_ priority: ActionItem.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private func saveItem() {
        let item = ActionItem.create(
            in: viewContext,
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            assignee: assignee,
            isMyTask: isMyTask,
            conversation: nil,
            person: person
        )
        item.notes = notes.isEmpty ? nil : notes

        do {
            try viewContext.save()

            // Send to Reminders if requested
            if sendToReminders {
                Task {
                    await RemindersIntegration.shared.createReminder(from: item)
                }
            }

            onSave()
            dismiss()
        } catch {
            print("Failed to save action item: \(error)")
        }
    }
}
