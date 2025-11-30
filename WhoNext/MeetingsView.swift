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
    
    // Collapsible Section States
    @AppStorage("isTodayExpanded") private var isTodayExpanded = true
    @AppStorage("isThisWeekExpanded") private var isThisWeekExpanded = true
    
    // Chat Window Management
    @State private var chatWindow: PopoutChatWindow?
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified Header
            MeetingsHeaderView(
                selectedFilter: $selectedFilter,
                todaysCount: todaysMeetings.count,
                thisWeeksCount: thisWeeksMeetings.count,
                onJoinMeeting: {
                    // Logic to join next meeting
                    if let nextMeeting = todaysMeetings.first(where: { $0.startDate > Date() }) ?? todaysMeetings.first {
                        if let location = nextMeeting.location,
                           let url = extractMeetingURL(from: location) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            )
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    // Statistics Dashboard
                    StatisticsCardsView()
                        .padding(.bottom, 8)
                        .smoothTransition()

                    // Today's Meetings Section
                    todaysMeetingsSection
                        .smoothTransition()
                    
                    // This Week's Meetings Section
                    thisWeeksMeetingsSection
                        .smoothTransition()
                    
                    // Follow-up Needed Section
                    FollowUpNeededView()
                        .smoothTransition()
                    
                    Spacer().frame(height: 24)
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: openChatWindow) {
                    Label("Chat Insights", systemImage: "bubble.left.and.bubble.right")
                }
                .help("Open AI Chat Insights")
            }
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
    
    // MARK: - Today's Meetings
    private var todaysMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isTodayExpanded.toggle() } }) {
                HStack {
                    SectionHeaderView(
                        icon: "calendar.badge.clock",
                        title: "Today's Meetings",
                        count: todaysMeetings.count
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isTodayExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isTodayExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if todaysMeetings.isEmpty {
                        EmptyStateCard(
                            icon: "calendar.badge.clock",
                            title: "No meetings today",
                            subtitle: "Enjoy your focus time!"
                        )
                    } else {
                        MasonryGrid(todaysMeetings) { meeting in
                                EnhancedMeetingCard(
                                    meeting: meeting,
                                    recordingEngine: recordingEngine,
                                    selectedPersonID: $selectedPersonID,
                                    selectedPerson: $selectedPerson,
                                    selectedTab: $selectedTab,
                                    isCurrentlyRecording: recordingEngine.currentMeeting?.calendarTitle == meeting.title
                                )
                        }
                    }
                }
                .padding(.leading, 16) // Indent content slightly
            }
        }
    }
    
    // MARK: - This Week's Meetings
    private var thisWeeksMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isThisWeekExpanded.toggle() } }) {
                HStack {
                    SectionHeaderView(
                        icon: "calendar",
                        title: "This Week",
                        count: thisWeeksMeetings.count
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isThisWeekExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isThisWeekExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if thisWeeksMeetings.isEmpty {
                        EmptyStateCard(
                            icon: "calendar",
                            title: "No upcoming meetings",
                            subtitle: "Your calendar is clear for the week"
                        )
                    } else {
                        MasonryGrid(thisWeeksMeetings.prefix(6)) { meeting in
                                EnhancedMeetingCard(
                                    meeting: meeting,
                                    recordingEngine: recordingEngine,
                                    selectedPersonID: $selectedPersonID,
                                    selectedPerson: $selectedPerson,
                                    selectedTab: $selectedTab,
                                    isCurrentlyRecording: false
                                )
                        }
                    }
                }
                .padding(.leading, 16) // Indent content slightly
            }
        }
    }
    
    private func openChatWindow() {
        if chatWindow == nil {
            chatWindow = PopoutChatWindow(context: viewContext)
        }
        chatWindow?.makeKeyAndOrderFront(nil)
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
    
    private func extractMeetingURL(from location: String) -> URL? {
        // Try to extract URL from location string
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: location, range: NSRange(location.startIndex..., in: location))
        return matches?.first?.url
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

// MARK: - Masonry Grid Helper
struct MasonryGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content
    
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column
            LazyVStack(spacing: 16) {
                ForEach(Array(data.enumerated()).filter { $0.offset % 2 == 0 }.map { $0.element }) { item in
                    content(item)
                }
            }
            
            // Right Column
            LazyVStack(spacing: 16) {
                ForEach(Array(data.enumerated()).filter { $0.offset % 2 != 0 }.map { $0.element }) { item in
                    content(item)
                }
            }
        }
    }
}

