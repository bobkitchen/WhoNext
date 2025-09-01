import SwiftUI
import AppKit

/// Glanceable recording window that shows all information at once
class GlanceableRecordingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<GlanceableRecordingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = GlanceableRecordingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create a floating panel with optimal size for glanceability
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Recording"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        
        // Set size constraints
        panel.minSize = NSSize(width: 360, height: 450)
        panel.maxSize = NSSize(width: 500, height: 700)
        
        super.init(window: panel)
        
        // Position window in top-right corner
        positionWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        let xPos = screenFrame.maxX - windowFrame.width - 20
        let yPos = screenFrame.maxY - windowFrame.height - 40
        
        window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
}

/// Glanceable recording view with all information visible at once
struct GlanceableRecordingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var hoveredSpeaker: String? = nil
    @State private var opacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with recording status
            headerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main transcript area
            transcriptSection
                .frame(maxHeight: .infinity)
            
            Divider()
            
            // Speakers and metrics dashboard
            dashboardSection
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Status bar
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .frame(minWidth: 360, minHeight: 450)
        .opacity(opacity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                opacity = hovering ? 1.0 : 0.92
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            // Recording indicator and title
            HStack(spacing: 10) {
                // Pulsing recording indicator
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        .scaleEffect(meeting.isRecording ? 2.0 : 1.0)
                        .opacity(meeting.isRecording ? 0.0 : 0.5)
                        .animation(
                            meeting.isRecording ?
                            Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false) :
                            .default,
                            value: meeting.isRecording
                        )
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    Text("Recording")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Duration and stop button
            HStack(spacing: 12) {
                Text(formatDuration(meeting.duration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                
                Button(action: { recordingEngine.manualStopRecording() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop Recording")
            }
        }
    }
    
    // MARK: - Transcript Section
    private var transcriptSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if meeting.transcript.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "mic.circle")
                                .font(.system(size: 48))
                                .foregroundColor(Color.secondary.opacity(0.3))
                            
                            VStack(spacing: 4) {
                                Text("Listening...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text("Transcript will appear here")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.secondary.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // Show recent transcript segments with fade effect
                        ForEach(Array(meeting.transcript.suffix(10).enumerated()), id: \.element.id) { index, segment in
                            let isRecent = index >= meeting.transcript.suffix(10).count - 4
                            
                            HStack(alignment: .top, spacing: 10) {
                                // Speaker avatar
                                SpeakerAvatar(
                                    name: segment.speakerName,
                                    id: segment.speakerID,
                                    size: 28
                                )
                                
                                // Transcript content
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(segment.speakerName ?? "Unknown")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(formatTimestamp(segment.timestamp))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(Color.secondary.opacity(0.5))
                                    }
                                    
                                    Text(segment.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(segment.isFinalized ? .primary : Color.primary.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .opacity(isRecent ? 1.0 : 0.6)
                            .id(segment.id)
                        }
                        
                        // Typing indicator when processing
                        if meeting.transcriptionProgress > 0 && meeting.transcriptionProgress < 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(Color.secondary.opacity(0.4))
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(1.2)
                                        .animation(
                                            Animation.easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(index) * 0.2),
                                            value: meeting.transcriptionProgress
                                        )
                                }
                            }
                            .padding(.leading, 54)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .onChange(of: meeting.transcript.count) { _ in
                if let last = meeting.transcript.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor).opacity(0.95),
                    Color(NSColor.windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Dashboard Section
    private var dashboardSection: some View {
        HStack(spacing: 16) {
            // Speakers panel
            VStack(alignment: .leading, spacing: 8) {
                Text("SPEAKERS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if meeting.identifiedParticipants.isEmpty {
                    Text("No speakers yet")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 4) {
                        ForEach(meeting.identifiedParticipants.prefix(3)) { participant in
                            SpeakerBar(
                                participant: participant,
                                totalDuration: meeting.duration,
                                isHovered: hoveredSpeaker == participant.id.uuidString
                            )
                            .onHover { hovering in
                                hoveredSpeaker = hovering ? participant.id.uuidString : nil
                            }
                        }
                        
                        if meeting.identifiedParticipants.count > 3 {
                            Text("+\(meeting.identifiedParticipants.count - 3) more")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 60)
            
            // Metrics panel
            VStack(alignment: .leading, spacing: 8) {
                Text("METRICS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    MetricDisplay(
                        value: "\(meeting.wordCount)",
                        label: "words",
                        icon: "text.word.spacing"
                    )
                    
                    if meeting.averageConfidence > 0 {
                        MetricDisplay(
                            value: "\(Int(meeting.averageConfidence * 100))%",
                            label: "conf",
                            icon: "checkmark.circle"
                        )
                    }
                    
                    MetricDisplay(
                        value: formatFileSize(meeting.currentFileSize),
                        label: "size",
                        icon: "internaldrive"
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack(spacing: 16) {
            // Audio quality
            HStack(spacing: 4) {
                Circle()
                    .fill(meeting.bufferHealth.color)
                    .frame(width: 6, height: 6)
                
                Text(meeting.bufferHealth.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Language
            if let language = meeting.detectedLanguage {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                    Text(language)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Active speakers count
            if meeting.identifiedParticipants.contains(where: { $0.isSpeaking }) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    
                    let speakingCount = meeting.identifiedParticipants.filter { $0.isSpeaking }.count
                    Text("\(speakingCount) speaking")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No one speaking")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
    }
    
    // MARK: - Helper Functions
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Supporting Views

struct SpeakerAvatar: View {
    let name: String?
    let id: String?
    let size: CGFloat
    
    private var initials: String {
        guard let name = name else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    private var color: Color {
        guard let id = id else { return .gray }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo]
        let index = abs(id.hashValue) % colors.count
        return colors[index]
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

struct SpeakerBar: View {
    let participant: IdentifiedParticipant
    let totalDuration: TimeInterval
    let isHovered: Bool
    
    private var percentage: Double {
        guard totalDuration > 0 else { return 0 }
        return min(participant.speakingDuration / totalDuration, 1.0)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Speaking indicator
            Circle()
                .fill(participant.isSpeaking ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(participant.isSpeaking ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Name
            Text(participant.name ?? "Unknown")
                .font(.system(size: 11, weight: participant.isSpeaking ? .medium : .regular))
                .foregroundColor(participant.isSpeaking ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            
            // Time bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(participant.color.opacity(0.6))
                        .frame(width: geometry.size.width * CGFloat(percentage))
                        .animation(.easeInOut(duration: 0.3), value: percentage)
                }
            }
            .frame(height: 14)
            
            // Time and percentage
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 10, weight: .medium))
                
                Text(formatSpeakingTime(participant.speakingDuration))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
    }
    
    private func formatSpeakingTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct MetricDisplay: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.secondary.opacity(0.7))
        }
    }
}