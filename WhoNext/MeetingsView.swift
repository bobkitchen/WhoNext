import SwiftUI
import AppKit
import CoreData
import Combine

struct MeetingsView: View {
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @ObservedObject private var config = MeetingRecordingConfiguration.shared
    @ObservedObject private var calendarService = CalendarService.shared
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    @State private var showingRecordingSettings = false
    
    // MARK: - Phase 4: UI Overhaul - Meeting Filters
    enum MeetingFilter: String, CaseIterable {
        case all = "All"
        case oneOnOne = "1:1s"
        case group = "Groups"
        
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .oneOnOne: return "person.2"
            case .group: return "person.3"
            }
        }
    }
    
    @State private var selectedFilter: MeetingFilter = .all
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Recording Status Bar
                recordingStatusBar
                
                // Meeting Type Filter (Phase 4)
                meetingFilterTabs
                    .smoothTransition()
                
                // Today's Meetings Section
                todaysMeetingsSection
                    .smoothTransition()
                
                // This Week's Meetings Section
                thisWeeksMeetingsSection
                    .smoothTransition()
                
                // Statistics and Chat Section
                HStack(alignment: .top, spacing: 24) {
                    StatisticsCardsView()
                        .hoverEffect(scale: 1.01)
                    ChatSectionView()
                        .hoverEffect(scale: 1.01)
                }
                .smoothTransition()
                
                // Follow-up Needed Section
                FollowUpNeededView()
                    .smoothTransition()
                
                Spacer().frame(height: 24)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .onAppear {
            // Request calendar access and fetch meetings
            calendarService.requestAccess { granted, error in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                }
            }
        }
    }
    
    // MARK: - Recording Status Bar
    private var recordingStatusBar: some View {
        HStack {
            // Recording Status
            HStack(spacing: 12) {
                Circle()
                    .fill(recordingStatusColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                
                Text(recordingStatusText)
                    .font(.system(size: 13, weight: .medium))
                
                if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(formatDuration(meeting.duration))
                        .font(.system(size: 13))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(20)
            
            Spacer()
            
            // Monitoring Status Indicator
            if recordingEngine.isMonitoring {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 8)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: recordingEngine.isMonitoring)
                        )
                    Text("Auto-Monitoring Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Quick Controls
            HStack(spacing: 8) {
                // Manual Record/Stop Button
                if recordingEngine.isRecording {
                    Button(action: { 
                        recordingEngine.stopRecording()
                    }) {
                        Label("Stop Recording", systemImage: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                } else {
                    Button(action: { 
                        // Start manual recording
                        recordingEngine.startManualRecording()
                    }) {
                        Label("Record", systemImage: "record.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                }
                
                Divider()
                    .frame(height: 20)
                
                // Auto-Record Toggle
                Toggle(isOn: $config.autoRecordingEnabled) {
                    Label("Auto-Record", systemImage: "record.circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: config.autoRecordingEnabled) { newValue in
                    if newValue && !recordingEngine.isMonitoring {
                        recordingEngine.startMonitoring()
                    } else if !newValue && recordingEngine.isMonitoring {
                        recordingEngine.stopMonitoring()
                    }
                }
                
                // Monitor Status Button (shows current state)
                if recordingEngine.isMonitoring {
                    Button(action: { recordingEngine.stopMonitoring() }) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Stop monitoring for meetings")
                } else {
                    Button(action: { recordingEngine.startMonitoring() }) {
                        Image(systemName: "eye")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Start monitoring for meetings")
                }
                
                // Settings Button
                Button(action: { showingRecordingSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingRecordingSettings) {
                    recordingSettingsPopover
                }
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Today's Meetings
    private var todaysMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(
                icon: "calendar.badge.clock",
                title: "Today's Meetings",
                count: todaysMeetings.count
            )
            
            if todaysMeetings.isEmpty {
                EmptyStateCard(
                    icon: "calendar.badge.clock",
                    title: "No meetings today",
                    subtitle: "Enjoy your focus time!"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(todaysMeetings, id: \.id) { meeting in
                        MeetingCard(
                            meeting: meeting,
                            recordingEngine: recordingEngine,
                            selectedPersonID: $selectedPersonID,
                            selectedPerson: $selectedPerson,
                            selectedTab: $selectedTab,
                            isCurrentlyRecording: recordingEngine.currentMeeting?.calendarTitle == meeting.title
                        )
                        .hoverEffect()
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
            }
        }
    }
    
    // MARK: - This Week's Meetings
    private var thisWeeksMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(
                icon: "calendar",
                title: "This Week",
                count: thisWeeksMeetings.count
            )
            
            if thisWeeksMeetings.isEmpty {
                EmptyStateCard(
                    icon: "calendar",
                    title: "No upcoming meetings",
                    subtitle: "Your calendar is clear for the week"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(thisWeeksMeetings.prefix(6), id: \.id) { meeting in
                        MeetingCard(
                            meeting: meeting,
                            recordingEngine: recordingEngine,
                            selectedPersonID: $selectedPersonID,
                            selectedPerson: $selectedPerson,
                            selectedTab: $selectedTab,
                            isCurrentlyRecording: false
                        )
                        .hoverEffect()
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
            }
        }
    }
    
    // MARK: - Recording Settings Popover
    private var recordingSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Settings")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                // Confidence Threshold
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confidence Threshold")
                        .font(.subheadline)
                    HStack {
                        Slider(value: .constant(0.7), in: 0...1) // Placeholder - config properties need to be added
                        Text("70%")
                            .monospacedDigit()
                            .frame(width: 45)
                    }
                }
                
                // Minimum Duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum Duration")
                        .font(.subheadline)
                    HStack {
                        Slider(value: .constant(30), in: 30...300, step: 30) // Placeholder
                        Text("30s")
                            .monospacedDigit()
                            .frame(width: 45)
                    }
                }
                
                // Audio Quality
                Toggle("High Quality Audio", isOn: .constant(true))
                    .font(.subheadline)
            }
            
            Divider()
            
            Button("Open Full Settings") {
                // Open settings window to Recording tab
                // Open settings window - would need proper app delegate reference
                showingRecordingSettings = false
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(width: 300)
    }
    
    // MARK: - Computed Properties
    private var todaysMeetings: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        
        let meetings = calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= startOfDay && meeting.startDate < endOfDay
        }
        
        return filterMeetings(meetings)
    }
    
    private var thisWeeksMeetings: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        let meetings = calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= startOfTomorrow && meeting.startDate < endDate
        }
        
        return filterMeetings(meetings)
    }
    
    // Filter meetings based on selected filter type
    private func filterMeetings(_ meetings: [UpcomingMeeting]) -> [UpcomingMeeting] {
        switch selectedFilter {
        case .all:
            return meetings
        case .oneOnOne:
            // Filter for meetings with 2 or fewer attendees (likely 1:1s)
            return meetings.filter { meeting in
                let attendeeCount = meeting.attendees?.count ?? 0
                return attendeeCount <= 2
            }
        case .group:
            // Filter for meetings with more than 2 attendees (group meetings)
            return meetings.filter { meeting in
                let attendeeCount = meeting.attendees?.count ?? 0
                return attendeeCount > 2
            }
        }
    }
    
    private var recordingStatusColor: Color {
        switch recordingEngine.recordingState {
        case .idle:
            return .gray
        case .monitoring:
            return .green
        case .conversationDetected:
            return .orange
        case .recording:
            return .red
        case .processing:
            return .purple
        case .error:
            return .red
        }
    }
    
    private var recordingStatusText: String {
        switch recordingEngine.recordingState {
        case .idle:
            return "Idle"
        case .monitoring:
            return "Monitoring"
        case .conversationDetected:
            return "Conversation Detected"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Phase 4: Meeting Filter UI
    
    private var meetingFilterTabs: some View {
        HStack(spacing: 12) {
            ForEach(MeetingFilter.allCases, id: \.self) { filter in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedFilter = filter
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 12))
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .medium))
                    }
                    .foregroundColor(selectedFilter == filter ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        selectedFilter == filter ?
                        Color.accentColor :
                        Color(NSColor.controlBackgroundColor)
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Meeting count badge
            if let currentMeeting = recordingEngine.currentMeeting {
                HStack(spacing: 4) {
                    Image(systemName: currentMeeting.meetingType.icon)
                        .font(.system(size: 11))
                    Text(currentMeeting.meetingType.displayName)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(currentMeeting.meetingType.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(currentMeeting.meetingType.color.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Enhanced Recording Status with Meeting Type
    
    private var enhancedRecordingStatus: some View {
        HStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(recordingEngine.isRecording ? Color.red : Color.green.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                
                Text(recordingEngine.isRecording ? "Recording" : "Ready")
                    .font(.system(size: 13, weight: .medium))
            }
            
            // Meeting type and speaker count
            if let meeting = recordingEngine.currentMeeting {
                Divider()
                    .frame(height: 16)
                
                HStack(spacing: 12) {
                    // Meeting type badge
                    Label(meeting.meetingType.displayName, systemImage: meeting.meetingType.icon)
                        .font(.system(size: 12))
                        .foregroundColor(meeting.meetingType.color)
                    
                    // Speaker count
                    if meeting.detectedSpeakerCount > 0 {
                        Label("\(meeting.detectedSpeakerCount) speakers", systemImage: "person.wave.2")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Confidence indicator
                    if meeting.speakerDetectionConfidence > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("\(Int(meeting.speakerDetectionConfidence * 100))%")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(meeting.speakerDetectionConfidence > 0.8 ? .green : .orange)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Meeting Card Component
struct MeetingCard: View {
    let meeting: UpcomingMeeting
    @ObservedObject var recordingEngine: MeetingRecordingEngine
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    let isCurrentlyRecording: Bool
    
    @State private var isExpanded = false
    @State private var showingBrief = false
    
    // Helper function to extract name from email or return original string
    private func extractName(from attendee: String) -> String {
        // If it's an email address, extract the name part
        if attendee.contains("@") {
            // Take the part before @ and clean it up
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            let name = String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            
            // Capitalize each word
            return name.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        // If it's already a name, return as is
        return attendee
    }
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Label(timeString, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let location = meeting.location, !location.isEmpty {
                                Label(location, systemImage: "location")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Recording indicator
                    if isCurrentlyRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Attendees (excluding current user)
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    let filteredAttendees = attendees.filter { !UserProfile.shared.isCurrentUser($0) }
                    if !filteredAttendees.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filteredAttendees.prefix(5), id: \.self) { attendee in
                                    Text(extractName(from: attendee))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(10)
                                        .help(attendee) // Show full email on hover
                                }
                                if filteredAttendees.count > 5 {
                                    Text("+\(filteredAttendees.count - 5)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Actions
                HStack(spacing: 8) {
                    // Pre-meeting brief
                    Button(action: { showingBrief.toggle() }) {
                        Label("Brief", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $showingBrief) {
                        PreMeetingBriefView(meeting: meeting, showingPopover: $showingBrief)
                            .frame(width: 600, height: 700)
                    }
                    
                    // Join meeting (if URL available)
                    if let location = meeting.location,
                       location.contains("zoom") || location.contains("teams") || location.contains("meet") {
                        Button(action: { 
                            if let url = extractMeetingURL(from: location) {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("Join", systemImage: "video")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Spacer()
                    
                    // Recording control
                    if isCurrentlyRecording {
                        Button(action: { recordingEngine.manualStopRecording() }) {
                            Label("Stop", systemImage: "stop.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    } else if isMeetingActive {
                        Button(action: { recordingEngine.manualStartRecording() }) {
                            Label("Record", systemImage: "record.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
            }
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        
        // Check if the meeting is today
        let calendar = Calendar.current
        if calendar.isDateInToday(meeting.startDate) {
            // For today, just show the time
            formatter.timeStyle = .short
            return formatter.string(from: meeting.startDate)
        } else {
            // For other days, show day and time
            formatter.dateFormat = "EEE" // Short day format (Mon, Tue, etc.)
            let dayString = formatter.string(from: meeting.startDate)
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let timeString = formatter.string(from: meeting.startDate)
            return "\(dayString) • \(timeString)"
        }
    }
    
    private var isMeetingActive: Bool {
        let now = Date()
        let endTime = meeting.startDate.addingTimeInterval(3600) // Assume 1 hour
        return meeting.startDate <= now && now <= endTime
    }
    
    private func extractMeetingURL(from location: String) -> URL? {
        // Try to extract URL from location string
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: location, range: NSRange(location.startIndex..., in: location))
        return matches?.first?.url
    }
}

// MARK: - Pre-Meeting Brief View
struct PreMeetingBriefView: View {
    let meeting: UpcomingMeeting
    @Binding var showingPopover: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @State private var personNotes: [(Person, String?)] = []
    @State private var showingWindow = false
    @State private var groupMeetingNotes: [String] = []
    @State private var aiBriefContent: String? = nil
    @State private var isGeneratingBrief = false
    @State private var briefGenerationError: String? = nil
    @State private var showRawNotes = false
    
    enum MeetingType {
        case oneOnOne
        case group
    }
    
    // Determine meeting type based on attendee count
    private var meetingType: MeetingType {
        let filteredAttendees = (meeting.attendees ?? []).filter { !UserProfile.shared.isCurrentUser($0) }
        return filteredAttendees.count <= 1 ? .oneOnOne : .group
    }
    
    // Helper function to extract name from email or return original string
    private func extractName(from attendee: String) -> String {
        // If it's an email address, extract the name part
        if attendee.contains("@") {
            // Take the part before @ and clean it up
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            let name = String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            
            // Capitalize each word
            return name.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        // If it's already a name, return as is
        return attendee
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with pop-out button and meeting type indicator
            HStack {
                HStack(spacing: 8) {
                    Text("Pre-Meeting Brief")
                        .font(.headline)
                    
                    // Meeting type badge
                    Text(meetingType == .oneOnOne ? "1:1" : "Group")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(meetingType == .oneOnOne ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(meetingType == .oneOnOne ? .blue : .green)
                        .cornerRadius(4)
                    
                    // AI indicator
                    if aiBriefContent != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("AI")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Generate/Refresh AI Brief button
                if !isGeneratingBrief {
                    Button(action: {
                        generateAIBrief()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: aiBriefContent != nil ? "arrow.clockwise" : "sparkles")
                                .font(.system(size: 12))
                            Text(aiBriefContent != nil ? "Refresh" : "Generate AI Brief")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                // Toggle view button
                if aiBriefContent != nil {
                    Button(action: {
                        showRawNotes.toggle()
                    }) {
                        Image(systemName: showRawNotes ? "doc.text" : "sparkles.rectangle.stack")
                            .foregroundColor(.secondary)
                            .help(showRawNotes ? "Show AI Brief" : "Show Raw Notes")
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    openInWindow()
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.secondary)
                        .help("Open in separate window")
                }
                .buttonStyle(.plain)
            }
            
            Text(meeting.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Divider()
            
            // Show AI Brief if available and not showing raw notes
            if let aiBrief = aiBriefContent, !showRawNotes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Parse and render AI-generated markdown
                        ForEach(formatAIBriefIntoSections(aiBrief), id: \.self) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                // Check if this is a header (starts with ## or is in bold **)
                                if section.hasPrefix("##") {
                                    let headerText = section.replacingOccurrences(of: "##", with: "").trimmingCharacters(in: .whitespaces)
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.accentColor)
                                        Text(headerText)
                                            .font(.system(.headline, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.top, 8)
                                } else if section.hasPrefix("**") && section.hasSuffix("**") {
                                    // Bold text
                                    Text(section.replacingOccurrences(of: "**", with: ""))
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                } else if section.contains("•") || section.contains("-") || section.hasPrefix("*") {
                                    // Bullet points
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(section.components(separatedBy: .newlines).filter { !$0.isEmpty }, id: \.self) { line in
                                            HStack(alignment: .top, spacing: 10) {
                                                let cleanLine = line.trimmingCharacters(in: .whitespaces)
                                                if cleanLine.hasPrefix("•") || cleanLine.hasPrefix("-") || cleanLine.hasPrefix("*") {
                                                    Circle()
                                                        .fill(Color.accentColor.opacity(0.3))
                                                        .frame(width: 6, height: 6)
                                                        .offset(y: 8)
                                                    Text(cleanLine.dropFirst().trimmingCharacters(in: .whitespaces))
                                                        .font(.system(.body))
                                                        .foregroundColor(.primary.opacity(0.9))
                                                        .fixedSize(horizontal: false, vertical: true)
                                                } else if let firstChar = cleanLine.first, firstChar.isNumber {
                                                    // Numbered list
                                                    Text(cleanLine)
                                                        .font(.system(.body))
                                                        .foregroundColor(.primary.opacity(0.9))
                                                        .fixedSize(horizontal: false, vertical: true)
                                                } else {
                                                    Text(line)
                                                        .font(.system(.body))
                                                        .foregroundColor(.primary.opacity(0.9))
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.accentColor.opacity(0.05))
                                    .cornerRadius(8)
                                } else {
                                    // Regular paragraph
                                    Text(section)
                                        .font(.system(.body))
                                        .foregroundColor(.primary.opacity(0.85))
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)
                }
            } else if briefGenerationError != nil {
                // Show error state
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(briefGenerationError!)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        generateAIBrief()
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if aiBriefContent == nil || showRawNotes {
                // Show raw notes (existing content)
                // Show meeting agenda from calendar if available
            if meetingType == .group, let notes = meeting.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meeting Agenda")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(formatAgendaItems(notes), id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(item)
                                        .font(.system(.body, design: .default))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            // Show content based on meeting type
            if meetingType == .oneOnOne {
                // For 1:1 meetings, show person notes with better formatting
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    let filteredAttendees = attendees.filter { !UserProfile.shared.isCurrentUser($0) }
                    if !filteredAttendees.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                Text("Recent Notes")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            .padding(.bottom, 4)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                if !personNotes.isEmpty {
                                // Show people with notes
                                ForEach(personNotes, id: \.0.identifier) { person, notes in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "person.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.accentColor)
                                            Text(person.name ?? "Unknown")
                                                .font(.system(.body, design: .rounded))
                                                .fontWeight(.semibold)
                                        }
                                        
                                        if let notes = notes, !notes.isEmpty {
                                            // Format and display notes with modern card-based design
                                            VStack(alignment: .leading, spacing: 16) {
                                                ForEach(formatNotesIntoSections(notes), id: \.self) { section in
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        // Check if section looks like a header
                                                        if section.hasPrefix("#") || (section.uppercased() == section && section.count < 50 && section.count > 2) || section.hasSuffix(":") {
                                                            HStack(spacing: 6) {
                                                                Image(systemName: "chevron.right.circle.fill")
                                                                    .font(.system(size: 12))
                                                                    .foregroundColor(.accentColor)
                                                                Text(section.replacingOccurrences(of: "#", with: "")
                                                                    .replacingOccurrences(of: ":", with: "")
                                                                    .trimmingCharacters(in: .whitespaces))
                                                                    .font(.system(.subheadline, design: .rounded))
                                                                    .fontWeight(.semibold)
                                                                    .foregroundColor(.primary)
                                                            }
                                                            .padding(.bottom, 4)
                                                        } else if section.contains("•") || section.contains("-") || section.contains("*") {
                                                            // Bullet points with better spacing
                                                            VStack(alignment: .leading, spacing: 10) {
                                                                ForEach(section.components(separatedBy: .newlines).filter { !$0.isEmpty }, id: \.self) { line in
                                                                    HStack(alignment: .top, spacing: 10) {
                                                                        let cleanLine = line.trimmingCharacters(in: .whitespaces)
                                                                        if cleanLine.first == "•" || cleanLine.first == "-" || cleanLine.first == "*" {
                                                                            Circle()
                                                                                .fill(Color.accentColor.opacity(0.3))
                                                                                .frame(width: 6, height: 6)
                                                                                .offset(y: 6)
                                                                            Text(cleanLine.dropFirst()
                                                                                .trimmingCharacters(in: .whitespaces))
                                                                                .font(.system(.body, design: .default))
                                                                                .foregroundColor(.primary.opacity(0.9))
                                                                                .fixedSize(horizontal: false, vertical: true)
                                                                                .lineSpacing(2)
                                                                        } else if let firstChar = cleanLine.first, firstChar.isNumber {
                                                                            // Numbered list
                                                                            let numberEnd = cleanLine.firstIndex(where: { !$0.isNumber && $0 != "." && $0 != ")" }) ?? cleanLine.endIndex
                                                                            let number = String(cleanLine[..<numberEnd])
                                                                            let content = String(cleanLine[numberEnd...]).trimmingCharacters(in: .whitespaces)
                                                                            
                                                                            HStack(alignment: .top, spacing: 8) {
                                                                                Text(number)
                                                                                    .font(.system(.caption, design: .monospaced))
                                                                                    .foregroundColor(.accentColor)
                                                                                    .frame(minWidth: 20, alignment: .trailing)
                                                                                Text(content)
                                                                                    .font(.system(.body, design: .default))
                                                                                    .foregroundColor(.primary.opacity(0.9))
                                                                                    .fixedSize(horizontal: false, vertical: true)
                                                                                    .lineSpacing(2)
                                                                            }
                                                                        } else {
                                                                            Text(line)
                                                                                .font(.system(.body, design: .default))
                                                                                .foregroundColor(.primary.opacity(0.9))
                                                                                .fixedSize(horizontal: false, vertical: true)
                                                                                .lineSpacing(2)
                                                                        }
                                                                    }
                                                                    .padding(.horizontal, 8)
                                                                }
                                                            }
                                                            .padding(.vertical, 6)
                                                            .padding(.horizontal, 8)
                                                            .background(Color.accentColor.opacity(0.05))
                                                            .cornerRadius(6)
                                                        } else {
                                                            // Regular paragraph text
                                                            Text(section)
                                                                .font(.system(.body, design: .default))
                                                                .foregroundColor(.primary.opacity(0.85))
                                                                .lineSpacing(4)
                                                                .fixedSize(horizontal: false, vertical: true)
                                                                .padding(.horizontal, 8)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.leading, 16)
                                        } else {
                                            HStack(spacing: 8) {
                                                Image(systemName: "note.text")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary.opacity(0.5))
                                                Text("No recent notes available")
                                                    .font(.system(.body, design: .default))
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.leading, 16)
                                        }
                                    }
                                    .padding(16)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                                    .cornerRadius(10)
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                            }
                            
                            // Show remaining attendees without Person records
                            let matchedNames = personNotes.compactMap { person, _ in person.name }
                            let unmatchedAttendees = filteredAttendees.filter { attendee in
                                let extractedName = extractName(from: attendee)
                                return !matchedNames.contains(where: { name in
                                    name.localizedCaseInsensitiveContains(extractedName) ||
                                    extractedName.localizedCaseInsensitiveContains(name)
                                })
                            }
                            
                            if !unmatchedAttendees.isEmpty {
                                ForEach(unmatchedAttendees, id: \.self) { attendee in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Image(systemName: "person.crop.circle.badge.questionmark")
                                                .font(.system(size: 20))
                                                .foregroundColor(.secondary.opacity(0.7))
                                            Text(extractName(from: attendee))
                                                .font(.system(.body, design: .rounded))
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                        }
                                        HStack(spacing: 8) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary.opacity(0.5))
                                            Text("No profile created yet")
                                                .font(.system(.caption, design: .default))
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                        .padding(.leading, 28)
                                    }
                                    .padding(16)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.05), lineWidth: 1)
                                    )
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                }
                    } // Close filtered attendees if
                } // Close attendees if
            } else if meetingType == .group {
                // For group meetings, show different content
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    let filteredAttendees = attendees.filter { !UserProfile.shared.isCurrentUser($0) }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Show attendee list
                        Text("Participants (\(filteredAttendees.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            ForEach(Array(filteredAttendees.prefix(5)), id: \.self) { attendee in
                                Text(extractName(from: attendee))
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                            }
                            if filteredAttendees.count > 5 {
                                Text("+\(filteredAttendees.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Show group meeting history if available
                        if !groupMeetingNotes.isEmpty {
                            Divider()
                            
                            Text("Previous Group Meetings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(groupMeetingNotes, id: \.self) { note in
                                        Text(note)
                                            .font(.system(.body, design: .default))
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                            .padding()
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No attendees listed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            } // Close the if/else for AI content vs raw notes
        }
        .padding()
        .onAppear {
            loadParticipantNotes()
        }
    }
    
    private func loadParticipantNotes() {
        guard let attendees = meeting.attendees else { return }
        
        // For group meetings, try to find matching group meetings instead of individual notes
        if meetingType == .group {
            loadGroupMeetingNotes()
        } else {
            // For 1:1 meetings, load individual conversation notes
            let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
            
            do {
                let allPeople = try viewContext.fetch(fetchRequest)
                
                personNotes = attendees.compactMap { attendee in
                    // Skip current user
                    if UserProfile.shared.isCurrentUser(attendee) {
                        return nil
                    }
                    
                    // Extract name from email if needed
                    let extractedName = extractName(from: attendee)
                    
                    // Try to find a matching person by name
                    if let person = allPeople.first(where: { person in
                        // Check if person's name matches the extracted name
                        if let personName = person.name {
                            // Exact match
                            if personName.localizedCaseInsensitiveCompare(extractedName) == .orderedSame {
                                return true
                            }
                            // Check if the person's name contains all parts of the extracted name
                            let extractedParts = extractedName.split(separator: " ").map { String($0).lowercased() }
                            let personParts = personName.split(separator: " ").map { String($0).lowercased() }
                            if extractedParts.allSatisfy({ part in
                                personParts.contains(part)
                            }) {
                                return true
                            }
                        }
                        
                        return false
                    }) {
                        // Get most recent conversation notes
                        let recentNotes = (person.conversations as? Set<Conversation>)?
                            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
                            .first?.notes
                        
                        return (person, recentNotes)
                    }
                    return nil
                }
            } catch {
                print("Error fetching participant notes: \(error)")
            }
        }
    }
    
    private func loadGroupMeetingNotes() {
        let fetchRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GroupMeeting.date, ascending: false)]
        fetchRequest.fetchLimit = 3 // Get last 3 group meetings
        
        do {
            let recentMeetings = try viewContext.fetch(fetchRequest)
            
            // Filter for meetings with similar attendee sets
            let filteredAttendees = (meeting.attendees ?? []).filter { !UserProfile.shared.isCurrentUser($0) }
            let attendeeSet = Set(filteredAttendees.map { extractName(from: $0).lowercased() })
            
            groupMeetingNotes = recentMeetings.compactMap { groupMeeting in
                // Check if this group meeting has a similar attendee set
                if let meetingAttendees = groupMeeting.attendees as? Set<Person> {
                    let meetingAttendeeNames = Set(meetingAttendees.compactMap { $0.name?.lowercased() })
                    
                    // If there's significant overlap, include this meeting's notes
                    let intersection = attendeeSet.intersection(meetingAttendeeNames)
                    if intersection.count >= min(2, attendeeSet.count - 1) { // At least 2 or most attendees match
                        if let summary = groupMeeting.summary {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .medium
                            let dateString = groupMeeting.date.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                            return "**\(dateString)**: \(summary)"
                        }
                    }
                }
                return nil
            }
        } catch {
            print("Error fetching group meeting notes: \(error)")
        }
    }
    
    // Helper function to format notes into readable sections
    private func formatNotesIntoSections(_ notes: String) -> [String] {
        var formattedSections: [String] = []
        
        // First, try to identify clear sections (headers, bullet points, paragraphs)
        let lines = notes.components(separatedBy: .newlines)
        var currentSection = ""
        var isInList = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this is a header (all caps, or starts with #, or ends with :)
            let isHeader = (trimmed.uppercased() == trimmed && trimmed.count < 50 && trimmed.count > 2) ||
                          trimmed.hasPrefix("#") ||
                          (trimmed.hasSuffix(":") && trimmed.count < 50)
            
            // Check if this is a bullet point
            let isBullet = trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ||
                          (trimmed.first?.isNumber ?? false && (trimmed.contains(".") || trimmed.contains(")")))
            
            if isHeader && !currentSection.isEmpty {
                // Save current section and start new one with header
                formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                currentSection = trimmed
                isInList = false
            } else if isBullet {
                if !isInList && !currentSection.isEmpty {
                    // Save current section and start a list
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = trimmed
                } else {
                    // Continue adding to list
                    currentSection += "\n" + trimmed
                }
                isInList = true
            } else if trimmed.isEmpty {
                // Empty line - potential section break
                if !currentSection.isEmpty {
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = ""
                    isInList = false
                }
            } else {
                // Regular text
                if isInList && !currentSection.isEmpty {
                    // End the list and start new section
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = trimmed
                    isInList = false
                } else {
                    // Add to current section
                    if !currentSection.isEmpty {
                        currentSection += " "
                    }
                    currentSection += trimmed
                }
            }
        }
        
        // Add any remaining content
        if !currentSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // If no sections were created, split by sentences for readability
        if formattedSections.isEmpty || (formattedSections.count == 1 && formattedSections[0].count > 300) {
            let text = formattedSections.first ?? notes
            let sentences = text.replacingOccurrences(of: ". ", with: ".\n").components(separatedBy: "\n")
            var newSections: [String] = []
            var currentParagraph = ""
            
            for (index, sentence) in sentences.enumerated() {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if !currentParagraph.isEmpty {
                        currentParagraph += " "
                    }
                    currentParagraph += trimmed
                    if !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?") {
                        currentParagraph += "."
                    }
                    
                    // Create new paragraph every 2-3 sentences or at natural breaks
                    if (index + 1) % 3 == 0 || trimmed.hasSuffix(":") || index == sentences.count - 1 {
                        newSections.append(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentParagraph = ""
                    }
                }
            }
            
            if !currentParagraph.isEmpty {
                newSections.append(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            return newSections.isEmpty ? [notes] : newSections
        }
        
        return formattedSections
    }
    
    // Helper function to format agenda items from calendar notes
    private func formatAgendaItems(_ notes: String) -> [String] {
        // Look for common agenda patterns
        let lines = notes.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        var agendaItems: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip common headers
            if trimmed.lowercased().contains("agenda") || trimmed.lowercased().contains("topics") {
                continue
            }
            
            // Remove common bullet points and numbering
            var cleanedLine = trimmed
            if cleanedLine.hasPrefix("•") || cleanedLine.hasPrefix("-") || cleanedLine.hasPrefix("*") {
                cleanedLine = String(cleanedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if let firstChar = cleanedLine.first, firstChar.isNumber {
                // Remove numbered lists (1. 2. etc)
                if let dotIndex = cleanedLine.firstIndex(of: ".") {
                    cleanedLine = String(cleanedLine[cleanedLine.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            if !cleanedLine.isEmpty {
                agendaItems.append(cleanedLine)
            }
        }
        
        // If no structured items found, just split by sentences
        if agendaItems.isEmpty {
            return notes.components(separatedBy: ". ").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        return agendaItems
    }
    
    // Format AI-generated brief into sections for display
    private func formatAIBriefIntoSections(_ brief: String) -> [String] {
        var sections: [String] = []
        let lines = brief.components(separatedBy: .newlines)
        var currentSection = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.isEmpty {
                // Empty line - save current section if not empty
                if !currentSection.isEmpty {
                    sections.append(currentSection)
                    currentSection = ""
                }
            } else if trimmed.hasPrefix("##") || trimmed.hasPrefix("#") {
                // Header - save previous section and start new one
                if !currentSection.isEmpty {
                    sections.append(currentSection)
                }
                sections.append(trimmed)
                currentSection = ""
            } else if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count < 100 {
                // Bold header line
                if !currentSection.isEmpty {
                    sections.append(currentSection)
                }
                sections.append(trimmed)
                currentSection = ""
            } else {
                // Add to current section
                if !currentSection.isEmpty {
                    currentSection += "\n"
                }
                currentSection += trimmed
            }
        }
        
        // Add any remaining content
        if !currentSection.isEmpty {
            sections.append(currentSection)
        }
        
        return sections.filter { !$0.isEmpty }
    }
    
    // Generate AI brief for the meeting
    private func generateAIBrief() {
        guard !isGeneratingBrief else { return }
        
        isGeneratingBrief = true
        briefGenerationError = nil
        
        // For 1:1 meetings, use the person-specific AI service
        if meetingType == .oneOnOne && !personNotes.isEmpty,
           let (person, _) = personNotes.first {
            
            PreMeetingBriefService.generateBrief(for: person, apiKey: AIService.shared.apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let brief):
                        self.aiBriefContent = brief
                        self.isGeneratingBrief = false
                    case .failure(let error):
                        self.briefGenerationError = "Failed to generate AI brief: \(error.localizedDescription)"
                        self.isGeneratingBrief = false
                    }
                }
            }
        } else {
            // For group meetings or when no person is found, generate a generic brief
            generateGenericAIBrief()
        }
    }
    
    // Generate generic AI brief for group meetings or unknown attendees
    private func generateGenericAIBrief() {
        var context = "=== PRE-MEETING BRIEF ===\n"
        context += "Meeting: \(meeting.title)\n"
        context += "Type: \(meetingType == .group ? "Group Meeting" : "1:1 Meeting")\n"
        
        if let attendees = meeting.attendees {
            context += "Attendees: \(attendees.joined(separator: ", "))\n"
        }
        
        if let notes = meeting.notes, !notes.isEmpty {
            context += "\nMeeting Agenda/Notes:\n\(notes)\n"
        }
        
        // Add group meeting history if available
        if !groupMeetingNotes.isEmpty {
            context += "\nPrevious Group Meeting Summaries:\n"
            for note in groupMeetingNotes {
                context += "- \(note)\n"
            }
        }
        
        // Add raw person notes if available
        if !personNotes.isEmpty {
            context += "\nParticipant Notes:\n"
            for (person, notes) in personNotes {
                if let notes = notes {
                    context += "\n\(person.name ?? "Unknown"):\n\(notes)\n"
                }
            }
        }
        
        let prompt = """
        Generate a comprehensive pre-meeting brief based on the context provided. Focus on:
        1. Key discussion topics and agenda items
        2. Action items and follow-ups from previous meetings
        3. Strategic recommendations for this meeting
        4. Important context about participants (if available)
        
        Format the output with clear sections using markdown headers (##) and bullet points.
        Be concise but thorough. Highlight the most important information.
        """
        
        Task {
            do {
                let response = try await AIService.shared.sendMessage(prompt, context: context)
                DispatchQueue.main.async {
                    self.aiBriefContent = response
                    self.isGeneratingBrief = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.briefGenerationError = "Failed to generate AI brief: \(error.localizedDescription)"
                    self.isGeneratingBrief = false
                }
            }
        }
    }
    
    private func openInWindow() {
        // Create a new window for the pre-meeting brief
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Pre-Meeting Brief: \(meeting.title)"
        window.center()
        
        // Create a SwiftUI view for the window content
        let contentView = VStack(alignment: .leading, spacing: 16) {
            Text("Pre-Meeting Brief")
                .font(.headline)
            
            Text(meeting.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Divider()
            
            // Reuse the same content as the popover
            PreMeetingBriefWindowContent(meeting: meeting)
                .environment(\.managedObjectContext, viewContext)
        }
        .padding()
        
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Close the popover
        showingPopover = false
    }
}

// MARK: - Pre-Meeting Brief Window Content
struct PreMeetingBriefWindowContent: View {
    let meeting: UpcomingMeeting
    @Environment(\.managedObjectContext) private var viewContext
    @State private var personNotes: [(Person, String?)] = []
    @State private var groupMeetingNotes: [String] = []
    
    enum MeetingType {
        case oneOnOne
        case group
    }
    
    // Determine meeting type based on attendee count
    private var meetingType: MeetingType {
        let filteredAttendees = (meeting.attendees ?? []).filter { !UserProfile.shared.isCurrentUser($0) }
        return filteredAttendees.count <= 1 ? .oneOnOne : .group
    }
    
    // Helper function to extract name from email or return original string
    private func extractName(from attendee: String) -> String {
        // If it's an email address, extract the name part
        if attendee.contains("@") {
            // Take the part before @ and clean it up
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            let name = String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            
            // Capitalize each word
            return name.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        // If it's already a name, return as is
        return attendee
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Show attendees section (excluding current user)
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    let filteredAttendees = attendees.filter { !UserProfile.shared.isCurrentUser($0) }
                    if !filteredAttendees.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Attendees")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                if !personNotes.isEmpty {
                                    // Show people with notes
                                    ForEach(personNotes, id: \.0.identifier) { person, notes in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "person.circle.fill")
                                                    .foregroundColor(.accentColor)
                                                Text(person.name ?? "Unknown")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            
                                            if let notes = notes, !notes.isEmpty {
                                                // Format notes with proper spacing and readability
                                                VStack(alignment: .leading, spacing: 8) {
                                                    ForEach(formatNotesIntoSections(notes), id: \.self) { section in
                                                        if let attributedString = try? AttributedString(markdown: section) {
                                                            Text(attributedString)
                                                                .font(.system(.body, design: .default))
                                                                .foregroundColor(.primary)
                                                                .lineSpacing(4)
                                                                .textSelection(.enabled)
                                                        } else {
                                                            Text(section)
                                                                .font(.system(.body, design: .default))
                                                                .foregroundColor(.primary)
                                                                .lineSpacing(4)
                                                                .textSelection(.enabled)
                                                        }
                                                    }
                                                }
                                                .padding(.leading, 24)
                                            } else {
                                                Text("No recent notes")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                                    .padding(.leading, 24)
                                            }
                                        }
                                        .padding()
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                    }
                                }
                                
                                // Show remaining attendees without Person records
                                let matchedNames = personNotes.compactMap { person, _ in person.name }
                                let unmatchedAttendees = filteredAttendees.filter { attendee in
                                    let extractedName = extractName(from: attendee)
                                    return !matchedNames.contains(where: { name in
                                        name.localizedCaseInsensitiveContains(extractedName) ||
                                        extractedName.localizedCaseInsensitiveContains(name)
                                    })
                                }
                                
                                if !unmatchedAttendees.isEmpty {
                                    ForEach(unmatchedAttendees, id: \.self) { attendee in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "person.circle")
                                                    .foregroundColor(.secondary)
                                                Text(extractName(from: attendee))
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                            }
                                            Text("No profile found")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .italic()
                                                .padding(.leading, 24)
                                        }
                                        .padding()
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "person.3")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No attendees listed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            loadParticipantNotes()
        }
    }
    
    private func loadParticipantNotes() {
        guard let attendees = meeting.attendees else { return }
        
        // For group meetings, try to find matching group meetings instead of individual notes
        if meetingType == .group {
            loadGroupMeetingNotes()
        } else {
            // For 1:1 meetings, load individual conversation notes
            let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
            
            do {
                let allPeople = try viewContext.fetch(fetchRequest)
                
                personNotes = attendees.compactMap { attendee in
                    // Skip current user
                    if UserProfile.shared.isCurrentUser(attendee) {
                        return nil
                    }
                    
                    // Extract name from email if needed
                    let extractedName = extractName(from: attendee)
                    
                    // Try to find a matching person by name
                    if let person = allPeople.first(where: { person in
                        // Check if person's name matches the extracted name
                        if let personName = person.name {
                            // Exact match
                            if personName.localizedCaseInsensitiveCompare(extractedName) == .orderedSame {
                                return true
                            }
                            // Check if the person's name contains all parts of the extracted name
                            let extractedParts = extractedName.split(separator: " ").map { String($0).lowercased() }
                            let personParts = personName.split(separator: " ").map { String($0).lowercased() }
                            if extractedParts.allSatisfy({ part in
                                personParts.contains(part)
                            }) {
                                return true
                            }
                        }
                        
                        return false
                    }) {
                        // Get most recent conversation notes
                        let recentNotes = (person.conversations as? Set<Conversation>)?
                            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
                            .first?.notes
                        
                        return (person, recentNotes)
                    }
                    return nil
                }
            } catch {
                print("Error fetching participant notes: \(error)")
            }
        }
    }
    
    private func loadGroupMeetingNotes() {
        let fetchRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GroupMeeting.date, ascending: false)]
        fetchRequest.fetchLimit = 3 // Get last 3 group meetings
        
        do {
            let recentMeetings = try viewContext.fetch(fetchRequest)
            
            // Filter for meetings with similar attendee sets
            let filteredAttendees = (meeting.attendees ?? []).filter { !UserProfile.shared.isCurrentUser($0) }
            let attendeeSet = Set(filteredAttendees.map { extractName(from: $0).lowercased() })
            
            groupMeetingNotes = recentMeetings.compactMap { groupMeeting in
                // Check if this group meeting has a similar attendee set
                if let meetingAttendees = groupMeeting.attendees as? Set<Person> {
                    let meetingAttendeeNames = Set(meetingAttendees.compactMap { $0.name?.lowercased() })
                    
                    // If there's significant overlap, include this meeting's notes
                    let intersection = attendeeSet.intersection(meetingAttendeeNames)
                    if intersection.count >= min(2, attendeeSet.count - 1) { // At least 2 or most attendees match
                        if let summary = groupMeeting.summary {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .medium
                            let dateString = groupMeeting.date.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                            return "**\(dateString)**: \(summary)"
                        }
                    }
                }
                return nil
            }
        } catch {
            print("Error fetching group meeting notes: \(error)")
        }
    }
    
    // Helper function to format notes into readable sections
    private func formatNotesIntoSections(_ notes: String) -> [String] {
        var formattedSections: [String] = []
        
        // First, try to identify clear sections (headers, bullet points, paragraphs)
        let lines = notes.components(separatedBy: .newlines)
        var currentSection = ""
        var isInList = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this is a header (all caps, or starts with #, or ends with :)
            let isHeader = (trimmed.uppercased() == trimmed && trimmed.count < 50 && trimmed.count > 2) ||
                          trimmed.hasPrefix("#") ||
                          (trimmed.hasSuffix(":") && trimmed.count < 50)
            
            // Check if this is a bullet point
            let isBullet = trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ||
                          (trimmed.first?.isNumber ?? false && (trimmed.contains(".") || trimmed.contains(")")))
            
            if isHeader && !currentSection.isEmpty {
                // Save current section and start new one with header
                formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                currentSection = trimmed
                isInList = false
            } else if isBullet {
                if !isInList && !currentSection.isEmpty {
                    // Save current section and start a list
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = trimmed
                } else {
                    // Continue adding to list
                    currentSection += "\n" + trimmed
                }
                isInList = true
            } else if trimmed.isEmpty {
                // Empty line - potential section break
                if !currentSection.isEmpty {
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = ""
                    isInList = false
                }
            } else {
                // Regular text
                if isInList && !currentSection.isEmpty {
                    // End the list and start new section
                    formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSection = trimmed
                    isInList = false
                } else {
                    // Add to current section
                    if !currentSection.isEmpty {
                        currentSection += " "
                    }
                    currentSection += trimmed
                }
            }
        }
        
        // Add any remaining content
        if !currentSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formattedSections.append(currentSection.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // If no sections were created, split by sentences for readability
        if formattedSections.isEmpty || (formattedSections.count == 1 && formattedSections[0].count > 300) {
            let text = formattedSections.first ?? notes
            let sentences = text.replacingOccurrences(of: ". ", with: ".\n").components(separatedBy: "\n")
            var newSections: [String] = []
            var currentParagraph = ""
            
            for (index, sentence) in sentences.enumerated() {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if !currentParagraph.isEmpty {
                        currentParagraph += " "
                    }
                    currentParagraph += trimmed
                    if !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?") {
                        currentParagraph += "."
                    }
                    
                    // Create new paragraph every 2-3 sentences or at natural breaks
                    if (index + 1) % 3 == 0 || trimmed.hasSuffix(":") || index == sentences.count - 1 {
                        newSections.append(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines))
                        currentParagraph = ""
                    }
                }
            }
            
            if !currentParagraph.isEmpty {
                newSections.append(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            return newSections.isEmpty ? [notes] : newSections
        }
        
        return formattedSections
    }
    
    // Helper function to format agenda items from calendar notes
    private func formatAgendaItems(_ notes: String) -> [String] {
        // Look for common agenda patterns
        let lines = notes.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        var agendaItems: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip common headers
            if trimmed.lowercased().contains("agenda") || trimmed.lowercased().contains("topics") {
                continue
            }
            
            // Remove common bullet points and numbering
            var cleanedLine = trimmed
            if cleanedLine.hasPrefix("•") || cleanedLine.hasPrefix("-") || cleanedLine.hasPrefix("*") {
                cleanedLine = String(cleanedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if let firstChar = cleanedLine.first, firstChar.isNumber {
                // Remove numbered lists (1. 2. etc)
                if let dotIndex = cleanedLine.firstIndex(of: ".") {
                    cleanedLine = String(cleanedLine[cleanedLine.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            if !cleanedLine.isEmpty {
                agendaItems.append(cleanedLine)
            }
        }
        
        // If no structured items found, just split by sentences
        if agendaItems.isEmpty {
            return notes.components(separatedBy: ". ").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        return agendaItems
    }
}