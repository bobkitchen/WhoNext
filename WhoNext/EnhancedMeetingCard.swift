import SwiftUI
import CoreData

struct EnhancedMeetingCard: View {
    let meeting: UpcomingMeeting
    @ObservedObject var recordingEngine: MeetingRecordingEngine
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    let isCurrentlyRecording: Bool
    
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showingBrief = false
    @State private var showingContextMenu = false
    @State private var showingAIBrief = true  // Toggle between AI Brief and Calendar Notes
    @State private var isRegenerating = false

    @ObservedObject private var briefManager = PreMeetingBriefManager.shared
    @Environment(\.managedObjectContext) private var viewContext

    /// Check if this is a 1:1 meeting
    private var isOneOnOne: Bool {
        (meeting.attendees?.count ?? 0) == 2
    }

    /// Get cached brief for this meeting
    private var cachedBrief: PreMeetingBriefManager.CachedBrief? {
        briefManager.getBrief(for: meeting.id)
    }

    /// Check if we have a valid AI brief
    private var hasValidBrief: Bool {
        guard let brief = cachedBrief else { return false }
        return !brief.briefContent.isEmpty
    }
    
    // Extract meeting stats
    private var meetingStats: (speakers: Int, duration: String, isRecorded: Bool) {
        // Check if this meeting has been recorded
        let isRecorded = false // Simplified for now
        
        // Format duration
        let minutes = Int(meeting.duration ?? 0) / 60
        let durationStr = minutes < 60 ? "\(minutes)m" : "\(minutes/60)h \(minutes%60)m"
        
        // Get speaker count (default to attendee count)
        let speakerCount = meeting.attendees?.count ?? 0
        
        return (speakerCount, durationStr, isRecorded)
    }
    
    // Helper to extract clean name from email
    private func extractName(from attendee: String) -> String {
        if attendee.contains("@") {
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            return String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        return attendee
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Card Content
            VStack(alignment: .leading, spacing: 12) {
                // Header Row
                HStack(alignment: .top) {
                    // Meeting Type & Status
                    HStack(spacing: 8) {
                        // Meeting type indicator
                        if (meeting.attendees?.count ?? 0) == 2 {
                            MeetingTypeBadge(type: .oneOnOne)
                        } else if (meeting.attendees?.count ?? 0) > 2 {
                            MeetingTypeBadge(type: .group)
                        }
                        
                        // Recording indicator
                        if isCurrentlyRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                    .modifier(GlowingPulse(color: .red))
                                Text("Recording")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        } else if meetingStats.isRecorded {
                            StatPill(icon: "checkmark.circle.fill", value: "Recorded", color: .green)
                        }
                    }
                    
                    Spacer()
                    
                    // Duration & Time
                    HStack(spacing: 8) {
                        DurationChip(duration: meeting.duration ?? 0)
                        
                        Text(meeting.startDate, style: .time)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Title
                Text(meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 1)
                
                // Participants
                HStack(spacing: 12) {
                    ParticipantAvatarStack(
                        participants: (meeting.attendees ?? []).map { extractName(from: $0) }
                    )
                    
                    if !(meeting.attendees?.isEmpty ?? true) {
                        Text((meeting.attendees ?? []).map { extractName(from: $0) }.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Quick Stats Row
                HStack(spacing: 8) {
                    StatPill(
                        icon: "person.2",
                        value: "\(meeting.attendees?.count ?? 0)",
                        color: .primaryBlue
                    )
                    
                    if let notes = meeting.notes, !notes.isEmpty {
                        StatPill(
                            icon: "note.text",
                            value: "Notes",
                            color: .orange
                        )
                    }
                    
                    if meeting.location?.contains("zoom.us") == true ||
                       meeting.location?.contains("meet.google") == true ||
                       meeting.location?.contains("teams.microsoft") == true {
                        StatPill(
                            icon: "video",
                            value: "Virtual",
                            color: .purple
                        )
                    }
                }
                
                // Hover Preview (AI Brief or Calendar Notes)
                if isHovered {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 4)

                        // Tab toggle for 1:1 meetings with briefs
                        if isOneOnOne {
                            meetingNotesTabToggle
                        } else {
                            // For group meetings, just show calendar notes
                            calendarNotesView
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(16)
            
            // Action Bar (appears on hover)
            if isHovered {
                HStack(spacing: 12) {
                    if !isCurrentlyRecording && !meetingStats.isRecorded {
                        Button(action: startRecording) {
                            Label("Record", systemImage: "record.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Button(action: { showingBrief = true }) {
                        Label("Brief", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    
                    if (meeting.attendees?.count ?? 0) == 2 {
                        Button(action: openPersonDetails) {
                            Label("View Person", systemImage: "person.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingContextMenu.toggle() }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.borderSubtle, lineWidth: 1)
        )
        .hoverEffect(scale: 1.02)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: copyMeetingDetails) {
                Label("Copy Details", systemImage: "doc.on.doc")
            }
            
            if meetingStats.isRecorded {
                Button(action: exportTranscript) {
                    Label("Export Transcript", systemImage: "square.and.arrow.up")
                }
            }
            
            Divider()
            
            Button(action: deleteMeeting) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingBrief) {
            PreMeetingBriefWindow(
                personName: meeting.title ?? "Meeting",
                briefContent: meeting.notes ?? "No meeting notes available",
                onClose: { showingBrief = false }
            )
        }
    }
    
    // MARK: - Actions
    
    private func startRecording() {
        // TODO: Implement manual recording start for specific meeting
        recordingEngine.manualStartRecording()
    }
    
    private func openPersonDetails() {
        // Find person from attendees
        if (meeting.attendees?.count ?? 0) == 2,
           let otherAttendee = meeting.attendees?.first(where: { !$0.contains("@yourcompany.com") }) {
            // Search for person in Core Data
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", extractName(from: otherAttendee))
            
            if let person = try? viewContext.fetch(request).first {
                selectedPerson = person
                selectedPersonID = person.identifier
                selectedTab = .people
            }
        }
    }
    
    private func copyMeetingDetails() {
        let details = """
        Meeting: \(meeting.title)
        Time: \(meeting.startDate.formatted())
        Duration: \(meetingStats.duration)
        Attendees: \((meeting.attendees ?? []).joined(separator: ", "))
        \(meeting.notes ?? "")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }
    
    private func exportTranscript() {
        // TODO: Implement transcript export
    }
    
    private func deleteMeeting() {
        // TODO: Implement meeting deletion
    }

    // MARK: - Notes Views

    /// Tab toggle between AI Brief and Calendar Notes for 1:1 meetings
    private var meetingNotesTabToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tab header with toggle and regenerate button
            HStack(spacing: 8) {
                // Tab toggle
                HStack(spacing: 0) {
                    tabButton(title: "AI Brief", isSelected: showingAIBrief) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAIBrief = true
                        }
                    }

                    tabButton(title: "Calendar Notes", isSelected: !showingAIBrief) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAIBrief = false
                        }
                    }
                }
                .background(Color(NSColor.separatorColor).opacity(0.3))
                .cornerRadius(6)

                Spacer()

                // Regenerate button (only for AI Brief tab)
                if showingAIBrief {
                    Button(action: regenerateBrief) {
                        if isRegenerating || briefManager.pendingMeetings.contains(meeting.id) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRegenerating || briefManager.pendingMeetings.contains(meeting.id))
                    .help("Regenerate brief")
                }
            }

            // Content based on selected tab
            if showingAIBrief {
                aiBriefView
            } else {
                calendarNotesView
            }
        }
    }

    /// Individual tab button
    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    /// AI Brief content view
    @ViewBuilder
    private var aiBriefView: some View {
        if let brief = cachedBrief, !brief.briefContent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                    Text("Brief for \(brief.personName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple)
                }

                Text(brief.briefContent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(5)

                if brief.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("Brief may be outdated")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.orange)
                }
            }
        } else if briefManager.pendingMeetings.contains(meeting.id) || briefManager.isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Generating brief...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        } else if cachedBrief != nil {
            // Brief exists but is empty - means no Person found
            VStack(alignment: .leading, spacing: 4) {
                Text("No Person record found for this meeting")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()

                Button(action: {
                    Task { @MainActor in
                        await briefManager.generateBriefForMeeting(meeting)
                    }
                }) {
                    Label("Generate Brief", systemImage: "sparkles")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            // No brief generated yet
            VStack(alignment: .leading, spacing: 4) {
                Text("AI brief not yet generated")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()

                Button(action: {
                    Task { @MainActor in
                        await briefManager.generateBriefForMeeting(meeting)
                    }
                }) {
                    Label("Generate Brief", systemImage: "sparkles")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Calendar notes view
    @ViewBuilder
    private var calendarNotesView: some View {
        if let notes = meeting.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("Calendar Notes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                }

                Text(notes)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(5)
            }
        } else {
            Text("No calendar notes available")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .italic()
        }
    }

    /// Regenerate brief action
    private func regenerateBrief() {
        isRegenerating = true
        Task { @MainActor in
            await briefManager.regenerateBrief(for: meeting)
            isRegenerating = false
        }
    }
}

// MARK: - Preview Provider
struct EnhancedMeetingCard_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedMeetingCard(
            meeting: UpcomingMeeting(
                id: "preview",
                title: "Weekly Sync with Team",
                startDate: Date(),
                calendarID: "primary",
                notes: "Discuss Q4 goals and project timeline",
                location: "https://zoom.us/j/123456789",
                attendees: ["john.doe@company.com", "jane.smith@company.com", "bob.wilson@company.com"],
                duration: 3600
            ),
            recordingEngine: MeetingRecordingEngine.shared,
            selectedPersonID: .constant(nil),
            selectedPerson: .constant(nil),
            selectedTab: .constant(.meetings),
            isCurrentlyRecording: false
        )
        .frame(width: 400)
        .padding()
    }
}