import SwiftUI
import AppKit

/// Compact, clean recording status window
class CompactRecordingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<CompactRecordingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = CompactRecordingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create a compact floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
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
        
        // Set minimum size
        panel.minSize = NSSize(width: 320, height: 400)
        
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

/// Clean, compact recording view
struct CompactRecordingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Quick stats bar
            statsBar
                .padding(.horizontal)
                .padding(.vertical, 10)
            
            Divider()
            
            // Tab view for content
            TabView(selection: $selectedTab) {
                transcriptTab
                    .tabItem {
                        Label("Transcript", systemImage: "text.bubble")
                    }
                    .tag(0)
                
                speakersTab
                    .tabItem {
                        Label("Speakers", systemImage: "person.2")
                    }
                    .tag(1)
                
                detailsTab
                    .tabItem {
                        Label("Details", systemImage: "info.circle")
                    }
                    .tag(2)
            }
            .padding(.top, 8)
        }
        .frame(minWidth: 320, minHeight: 400)
    }
    
    private var headerView: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: true),
                                value: meeting.isRecording
                            )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(meeting.isRecording ? "Recording" : "Paused")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(meeting.duration))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                
                // Stop button
                Button(action: { recordingEngine.manualStopRecording() }) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var statsBar: some View {
        HStack(spacing: 20) {
            // Word count
            HStack(spacing: 4) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("\(meeting.wordCount)")
                    .font(.system(size: 12, weight: .medium))
            }
            
            // Speaker count
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("\(meeting.participantCount)")
                    .font(.system(size: 12, weight: .medium))
            }
            
            // Confidence
            if meeting.averageConfidence > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(Int(meeting.averageConfidence * 100))%")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            
            Spacer()
            
            // File size
            Text(formatFileSize(meeting.currentFileSize))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private var transcriptTab: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if meeting.transcript.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text("Listening...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            if meeting.transcriptionProgress > 0 {
                                ProgressView(value: meeting.transcriptionProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 150)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(meeting.transcript) { segment in
                            HStack(alignment: .top, spacing: 8) {
                                // Speaker indicator
                                if let speaker = segment.speakerName {
                                    Text(String(speaker.prefix(2)).uppercased())
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(speakerColor(for: segment.speakerID)))
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 24, height: 24)
                                }
                                
                                // Transcript text
                                VStack(alignment: .leading, spacing: 2) {
                                    if let speaker = segment.speakerName {
                                        Text(speaker)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(segment.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(segment.isFinalized ? .primary : .secondary)
                                }
                                
                                Spacer()
                                
                                // Timestamp
                                Text(formatTimestamp(segment.timestamp))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .id(segment.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: meeting.transcript.count) { _ in
                if let last = meeting.transcript.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var speakersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if meeting.identifiedParticipants.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("No speakers identified yet")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(meeting.identifiedParticipants) { participant in
                        HStack {
                            // Avatar
                            Circle()
                                .fill(participant.color.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(participant.initials)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(participant.color)
                                )
                            
                            // Info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.name ?? "Unknown Speaker")
                                    .font(.system(size: 13, weight: .medium))
                                
                                HStack(spacing: 8) {
                                    Text("\(formatDuration(participant.speakingDuration)) speaking")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    if participant.isSpeaking {
                                        Label("Speaking", systemImage: "waveform")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Speaking percentage
                            if meeting.duration > 0 {
                                let percentage = Int((participant.speakingDuration / meeting.duration) * 100)
                                Text("\(percentage)%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var detailsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Recording details
                DetailSection(title: "Recording") {
                    DetailRow(label: "Duration", value: formatDuration(meeting.duration))
                    DetailRow(label: "File Size", value: formatFileSize(meeting.currentFileSize))
                    DetailRow(label: "Audio Quality", value: meeting.audioQuality.description)
                }
                
                // Transcription details
                DetailSection(title: "Transcription") {
                    DetailRow(label: "Total Words", value: "\(meeting.wordCount)")
                    DetailRow(label: "Segments", value: "\(meeting.transcript.count)")
                    if meeting.averageConfidence > 0 {
                        DetailRow(label: "Confidence", value: "\(Int(meeting.averageConfidence * 100))%")
                    }
                    if let language = meeting.detectedLanguage {
                        DetailRow(label: "Language", value: language)
                    }
                }
                
                // System status
                if meeting.cpuUsage > 0 || meeting.memoryUsage > 0 {
                    DetailSection(title: "System") {
                        if meeting.cpuUsage > 0 {
                            DetailRow(label: "CPU Usage", value: String(format: "%.1f%%", meeting.cpuUsage))
                        }
                        if meeting.memoryUsage > 0 {
                            DetailRow(label: "Memory", value: formatFileSize(meeting.memoryUsage))
                        }
                        DetailRow(label: "Buffer Health", value: meeting.bufferHealth.description)
                    }
                }
            }
            .padding()
        }
    }
    
    // Helper functions
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
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }
    
    private func speakerColor(for id: String?) -> Color {
        guard let id = id else { return .gray }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(id.hashValue) % colors.count
        return colors[index]
    }
}

// Supporting views
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

// BufferHealth description is already defined in LiveMeeting.swift