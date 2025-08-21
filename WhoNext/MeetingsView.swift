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
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Recording Status Bar
                recordingStatusBar
                
                // Today's Meetings Section
                todaysMeetingsSection
                
                // This Week's Meetings Section
                thisWeeksMeetingsSection
                
                // Statistics and Chat Section
                HStack(alignment: .top, spacing: 24) {
                    StatisticsCardsView()
                    ChatSectionView()
                }
                
                // Follow-up Needed Section
                FollowUpNeededView()
                
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
                
                // Monitor/Stop Button
                if recordingEngine.isMonitoring {
                    Button(action: { recordingEngine.stopMonitoring() }) {
                        Label("Stop Monitoring", systemImage: "stop.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: { recordingEngine.startMonitoring() }) {
                        Label("Start Monitoring", systemImage: "play.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
        
        return calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= startOfDay && meeting.startDate < endOfDay
        }
    }
    
    private var thisWeeksMeetings: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= startOfTomorrow && meeting.startDate < endDate
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
                
                // Attendees
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attendees.prefix(5), id: \.self) { attendee in
                                Text(attendee)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(10)
                            }
                            if attendees.count > 5 {
                                Text("+\(attendees.count - 5)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                        PreMeetingBriefView(meeting: meeting)
                            .frame(width: 400, height: 500)
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
        formatter.timeStyle = .short
        return formatter.string(from: meeting.startDate)
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
    @Environment(\.managedObjectContext) private var viewContext
    @State private var personNotes: [(Person, String?)] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pre-Meeting Brief")
                .font(.headline)
            
            Text(meeting.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Divider()
            
            if !personNotes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(personNotes, id: \.0.identifier) { person, notes in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(person.name ?? "Unknown")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                if let notes = notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                } else {
                                    Text("No recent notes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No participant information available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            loadParticipantNotes()
        }
    }
    
    private func loadParticipantNotes() {
        guard let attendees = meeting.attendees else { return }
        
        let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
        
        do {
            let allPeople = try viewContext.fetch(fetchRequest)
            
            personNotes = attendees.compactMap { attendeeName in
                if let person = allPeople.first(where: { 
                    $0.name?.localizedCaseInsensitiveContains(attendeeName) == true 
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