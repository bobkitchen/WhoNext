import SwiftUI
import AppKit
import Combine

/// Enhanced floating window that displays comprehensive recording status and metrics
class EnhancedLiveMeetingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<EnhancedLiveMeetingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = EnhancedLiveMeetingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create the window with NSPanel for floating behavior
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Recording Status"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        
        // Set minimum and maximum sizes
        panel.minSize = NSSize(width: 380, height: 400)
        panel.maxSize = NSSize(width: 600, height: 900)
        
        super.init(window: panel)
        
        // Position window in top-right corner
        positionWindow()
        
        // Enable window edge snapping
        setupWindowSnapping()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        let xPos = screenFrame.maxX - windowFrame.width - 20
        let yPos = screenFrame.maxY - windowFrame.height - 20
        
        window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
    
    private func setupWindowSnapping() {
        // Add window delegate for edge snapping behavior
        window?.delegate = self
    }
    
    func updateMeeting(_ meeting: LiveMeeting) {
        self.meeting = meeting
        if let hostingController = hostingController {
            hostingController.rootView = EnhancedLiveMeetingView(meeting: meeting)
        }
    }
}

// MARK: - Window Delegate for Edge Snapping
extension EnhancedLiveMeetingWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window, let screen = window.screen else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let snapDistance: CGFloat = 15
        
        var newOrigin = windowFrame.origin
        
        // Snap to edges
        if abs(windowFrame.minX - screenFrame.minX) < snapDistance {
            newOrigin.x = screenFrame.minX
        } else if abs(windowFrame.maxX - screenFrame.maxX) < snapDistance {
            newOrigin.x = screenFrame.maxX - windowFrame.width
        }
        
        if abs(windowFrame.minY - screenFrame.minY) < snapDistance {
            newOrigin.y = screenFrame.minY
        } else if abs(windowFrame.maxY - screenFrame.maxY) < snapDistance {
            newOrigin.y = screenFrame.maxY - windowFrame.height
        }
        
        if newOrigin != windowFrame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }
}

/// Enhanced SwiftUI view for the live meeting window
struct EnhancedLiveMeetingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @StateObject private var audioCapture = SystemAudioCapture()
    
    // View state
    @State private var selectedTab: RecordingTab = .transcript
    @State private var isExpanded: Bool = false
    @State private var showAdvanced: Bool = false
    @State private var opacity: Double = 1.0
    @State private var quickNote: String = ""
    @State private var markers: [RecordingMarker] = []
    
    // Animation states
    @State private var recordingPulse: Bool = false
    
    enum RecordingTab: String, CaseIterable {
        case transcript = "Transcript"
        case speakers = "Speakers"
        case metrics = "Metrics"
        case notes = "Notes"
        
        var icon: String {
            switch self {
            case .transcript: return "text.bubble"
            case .speakers: return "person.2"
            case .metrics: return "chart.line.uptrend.xyaxis"
            case .notes: return "note.text"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with recording status
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Audio levels
            audioLevelsView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Tab selector
            tabSelector
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            Divider()
            
            // Main content area
            mainContent
                .frame(maxHeight: .infinity)
            
            Divider()
            
            // Footer with quick stats
            footerStats
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .frame(minWidth: 380, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .opacity(opacity)
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // Recording status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .scaleEffect(recordingPulse ? 1.5 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: true),
                                value: recordingPulse
                            )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording")
                        .font(.system(size: 14, weight: .semibold))
                    Text(meeting.displayTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Duration and controls
            VStack(alignment: .trailing, spacing: 4) {
                Text(meeting.formattedDuration)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Add marker button
                    Button(action: addMarker) {
                        Image(systemName: "flag")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Add Marker (⌘M)")
                    
                    // Pause/Resume button
                    Button(action: togglePause) {
                        Image(systemName: meeting.isRecording ? "pause.circle" : "play.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(meeting.isRecording ? "Pause" : "Resume")
                    
                    // Stop button
                    Button(action: stopRecording) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Recording")
                }
            }
        }
    }
    
    // MARK: - Audio Levels View
    private var audioLevelsView: some View {
        HStack(spacing: 16) {
            // Microphone level
            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                AudioLevelView(
                    level: audioCapture.microphoneLevel,
                    color: .blue,
                    label: "Mic"
                )
                .frame(width: 120, height: 16)
            }
            
            // System audio level
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                AudioLevelView(
                    level: audioCapture.systemAudioLevel,
                    color: .green,
                    label: "System"
                )
                .frame(width: 120, height: 16)
            }
            
            Spacer()
            
            // Audio quality indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(meeting.audioQuality.color)
                    .frame(width: 6, height: 6)
                Text(meeting.audioQuality.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(RecordingTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Advanced toggle
            Button(action: { showAdvanced.toggle() }) {
                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show advanced metrics")
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .transcript:
            transcriptView
        case .speakers:
            speakersView
        case .metrics:
            metricsView
        case .notes:
            notesView
        }
    }
    
    // MARK: - Transcript View
    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(meeting.transcript) { segment in
                        TranscriptSegmentView(segment: segment, expanded: true)
                            .id(segment.id)
                    }
                    
                    // Show typing indicator for volatile text
                    if meeting.transcriptionProgress > 0 && meeting.transcriptionProgress < 1 {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Processing...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(16)
            }
            .onChange(of: meeting.transcript.count) {
                if let lastSegment = meeting.transcript.last {
                    withAnimation {
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Speakers View
    private var speakersView: some View {
        VStack(spacing: 16) {
            // Active speakers grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                ForEach(meeting.identifiedParticipants) { participant in
                    SpeakerCardView(participant: participant)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Speaker statistics
            if !meeting.identifiedParticipants.isEmpty {
                Divider()
                
                SpeakerAnalyticsView(participants: meeting.identifiedParticipants)
                    .padding(16)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Metrics View
    private var metricsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Recording metrics
                MetricSection(title: "Recording") {
                    MetricRow(label: "Duration", value: meeting.formattedDuration)
                    MetricRow(label: "File Size", value: formatFileSize(meeting.currentFileSize))
                    MetricRow(label: "Bitrate", value: "32 kbps")
                    MetricRow(label: "Format", value: "AAC, 16kHz, Mono")
                }
                
                // Transcription metrics
                MetricSection(title: "Transcription") {
                    MetricRow(label: "Words", value: "\(meeting.wordCount)")
                    MetricRow(label: "Segments", value: "\(meeting.transcript.count)")
                    MetricRow(label: "Confidence", value: String(format: "%.1f%%", meeting.averageConfidence * 100))
                    MetricRow(label: "Language", value: meeting.detectedLanguage ?? "Auto")
                }
                
                // Speaker metrics
                if !meeting.identifiedParticipants.isEmpty {
                    MetricSection(title: "Speakers") {
                        MetricRow(label: "Participants", value: "\(meeting.participantCount)")
                        MetricRow(label: "Turn Changes", value: "\(meeting.speakerTurnCount)")
                        MetricRow(label: "Overlaps", value: "\(meeting.overlapCount)")
                    }
                }
                
                // System metrics (if advanced is enabled)
                if showAdvanced {
                    MetricSection(title: "System") {
                        MetricRow(label: "CPU Usage", value: String(format: "%.1f%%", meeting.cpuUsage))
                        MetricRow(label: "Memory", value: formatFileSize(meeting.memoryUsage))
                        MetricRow(label: "Buffer Health", value: meeting.bufferHealth.description)
                        MetricRow(label: "Dropped Frames", value: "\(meeting.droppedFrames)")
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Notes View
    private var notesView: some View {
        VStack(spacing: 12) {
            // Quick note input
            HStack {
                TextField("Add a note...", text: $quickNote)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNote()
                    }
                
                Button("Add") {
                    addNote()
                }
                .disabled(quickNote.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Divider()
            
            // Notes and markers list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(markers) { marker in
                        MarkerView(marker: marker)
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Footer Stats
    private var footerStats: some View {
        HStack(spacing: 20) {
            // Words count
            StatBadge(
                icon: "text.word.spacing",
                value: "\(meeting.wordCount)",
                label: "words"
            )
            
            // Speakers count
            StatBadge(
                icon: "person.2",
                value: "\(meeting.participantCount)",
                label: "speakers"
            )
            
            // File size
            StatBadge(
                icon: "internaldrive",
                value: formatFileSize(meeting.currentFileSize),
                label: "size"
            )
            
            Spacer()
            
            // Opacity slider
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Slider(value: $opacity, in: 0.5...1.0)
                    .frame(width: 80)
                
                Image(systemName: "sun.max")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func startAnimations() {
        recordingPulse = true
    }
    
    private func addMarker() {
        let marker = RecordingMarker(
            timestamp: meeting.duration,
            label: "Marker \(markers.count + 1)",
            type: .manual
        )
        markers.append(marker)
    }
    
    private func togglePause() {
        meeting.isRecording.toggle()
    }
    
    private func stopRecording() {
        recordingEngine.manualStopRecording()
    }
    
    private func addNote() {
        guard !quickNote.isEmpty else { return }
        
        let marker = RecordingMarker(
            timestamp: meeting.duration,
            label: quickNote,
            type: .note
        )
        markers.append(marker)
        quickNote = ""
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

struct AudioLevelView: View {
    let level: Float
    let color: Color
    let label: String
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
                
                // Level bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.1), value: level)
                
                // Peak indicator
                if level > 0.8 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(min(level, 1.0)))
                }
            }
        }
    }
}

struct SpeakerCardView: View {
    let participant: IdentifiedParticipant
    
    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(participant.color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Text(participant.initials)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(participant.color)
                
                // Speaking indicator
                if participant.isSpeaking {
                    Circle()
                        .stroke(participant.color, lineWidth: 2)
                        .frame(width: 54, height: 54)
                        .animation(
                            Animation.easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true),
                            value: participant.isSpeaking
                        )
                }
            }
            
            // Name
            Text(participant.name ?? "Speaker \(participant.id)")
                .font(.system(size: 11))
                .lineLimit(1)
            
            // Speaking time
            Text(formatDuration(participant.speakingDuration))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct MetricSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(6)
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MarkerView: View {
    let marker: RecordingMarker
    
    var body: some View {
        HStack {
            Image(systemName: marker.type.icon)
                .font(.system(size: 11))
                .foregroundColor(marker.type.color)
            
            Text(marker.label)
                .font(.system(size: 12))
            
            Spacer()
            
            Text(formatTimestamp(marker.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Supporting Models

struct RecordingMarker: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let label: String
    let type: MarkerType
    
    enum MarkerType {
        case manual
        case note
        case important
        
        var icon: String {
            switch self {
            case .manual: return "flag"
            case .note: return "note.text"
            case .important: return "exclamationmark.triangle"
            }
        }
        
        var color: Color {
            switch self {
            case .manual: return .blue
            case .note: return .green
            case .important: return .orange
            }
        }
    }
}


