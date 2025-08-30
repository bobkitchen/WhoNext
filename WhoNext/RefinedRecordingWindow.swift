import SwiftUI
import AppKit

/// Refined recording window with improved UI/UX
class RefinedRecordingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<RefinedRecordingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = RefinedRecordingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create a floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        
        // Set size constraints
        panel.minSize = NSSize(width: 380, height: 480)
        panel.maxSize = NSSize(width: 520, height: 720)
        
        super.init(window: panel)
        
        // Position window
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

/// Refined recording view with improved design
struct RefinedRecordingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var speakerColors: [String: Color] = [:]
    @State private var speakerNumbers: [String: Int] = [:]
    @State private var nextSpeakerNumber = 1
    
    // Design constants
    private let spacing: CGFloat = 8
    private let cornerRadius: CGFloat = 8
    private let cardBackground = Color(NSColor.controlBackgroundColor).opacity(0.5)
    
    var body: some View {
        VStack(spacing: 0) {
            // Refined header
            refinedHeader
                .padding(spacing * 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            
            // Main content with cards
            VStack(spacing: spacing) {
                // Transcript card
                transcriptCard
                    .frame(maxHeight: .infinity)
                
                // Dashboard cards
                dashboardCards
                    .frame(height: 100)
            }
            .padding(spacing)
            
            // Simplified status bar
            statusBar
                .padding(.horizontal, spacing * 2)
                .padding(.vertical, spacing)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Refined Header
    private var refinedHeader: some View {
        HStack {
            // Combined status and title
            HStack(spacing: 8) {
                // Recording indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            .scaleEffect(2)
                            .opacity(0)
                            .animation(
                                Animation.easeOut(duration: 2)
                                    .repeatForever(autoreverses: false),
                                value: meeting.isRecording
                            )
                    )
                
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Recording")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration and controls
            HStack(spacing: 12) {
                Text(formatDuration(meeting.duration))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                
                Button(action: { recordingEngine.manualStopRecording() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Transcript Card
    private var transcriptCard: some View {
        VStack(spacing: 0) {
            // Card content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if meeting.transcript.isEmpty {
                            emptyTranscriptState
                        } else {
                            transcriptContent
                        }
                    }
                }
                .onChange(of: meeting.transcript.count) { _ in
                    if let last = meeting.transcript.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 36))
                .foregroundColor(Color.secondary.opacity(0.3))
            
            Text("Listening...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Transcript will appear here")
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
    
    private var transcriptContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(meeting.transcript.suffix(15).enumerated()), id: \.element.id) { index, segment in
                let showTimestamp = shouldShowTimestamp(for: index, segment: segment)
                let speakerInfo = getSpeakerInfo(for: segment)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Show timestamp if needed
                    if showTimestamp {
                        Text(formatTimestamp(segment.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.secondary.opacity(0.5))
                            .padding(.top, 8)
                    }
                    
                    // Segment with speaker
                    HStack(alignment: .top, spacing: 10) {
                        // Speaker avatar
                        ZStack {
                            Circle()
                                .fill(speakerInfo.color.opacity(0.15))
                                .frame(width: 24, height: 24)
                            
                            Text(speakerInfo.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(speakerInfo.color)
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speakerInfo.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(speakerInfo.color)
                            
                            Text(segment.text)
                                .font(.system(size: 14))
                                .foregroundColor(segment.isFinalized ? .primary : Color.primary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .id(segment.id)
                }
                
                // Add separator between different speakers
                if index < meeting.transcript.suffix(15).count - 1 {
                    let nextSegment = meeting.transcript.suffix(15)[index + 1]
                    if segment.speakerID != nextSegment.speakerID {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            
            // Processing indicator
            if meeting.transcriptionProgress > 0 && meeting.transcriptionProgress < 1 {
                processingIndicator
                    .padding(.vertical, 12)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var processingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: meeting.transcriptionProgress
                    )
            }
        }
        .padding(.leading, 46)
    }
    
    // MARK: - Dashboard Cards
    private var dashboardCards: some View {
        HStack(spacing: spacing) {
            // Speakers card
            speakersCard
                .frame(maxWidth: .infinity)
            
            // Stats card
            statsCard
                .frame(maxWidth: .infinity)
        }
    }
    
    private var speakersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE SPEAKERS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            
            if meeting.identifiedParticipants.isEmpty {
                HStack {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 14))
                        .foregroundColor(Color.secondary.opacity(0.4))
                    
                    Text("Awaiting first speaker...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(meeting.identifiedParticipants.prefix(2)) { participant in
                        CompactSpeakerRow(
                            participant: participant,
                            totalDuration: meeting.duration
                        )
                    }
                    
                    if meeting.identifiedParticipants.count > 2 {
                        Text("+\(meeting.identifiedParticipants.count - 2) more speakers")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEETING STATS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    StatItem(
                        value: "\(meeting.wordCount)",
                        label: "words",
                        icon: "text.word.spacing"
                    )
                    
                    StatItem(
                        value: "\(Int(meeting.averageConfidence * 100))%",
                        label: "confidence",
                        icon: "checkmark.circle"
                    )
                }
                
                HStack(spacing: 16) {
                    StatItem(
                        value: formatFileSize(meeting.currentFileSize),
                        label: "size",
                        icon: "doc"
                    )
                    
                    StatItem(
                        value: meeting.detectedLanguage ?? "Auto",
                        label: "language",
                        icon: "globe"
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack(spacing: 12) {
            // Quality indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(meeting.bufferHealth.color)
                    .frame(width: 5, height: 5)
                Text(meeting.bufferHealth.description + " quality")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Speaking status
            if let activeSpeaker = meeting.identifiedParticipants.first(where: { $0.isSpeaking }) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text("\(activeSpeaker.name ?? "Someone") speaking")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No one speaking")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func shouldShowTimestamp(for index: Int, segment: TranscriptSegment) -> Bool {
        // Show timestamp for first segment
        if index == 0 { return true }
        
        let segments = meeting.transcript.suffix(15)
        let previousSegment = segments[index - 1]
        
        // Show if speaker changed
        if segment.speakerID != previousSegment.speakerID { return true }
        
        // Show if 30+ seconds elapsed
        if segment.timestamp - previousSegment.timestamp > 30 { return true }
        
        return false
    }
    
    private func getSpeakerInfo(for segment: TranscriptSegment) -> (name: String, label: String, color: Color) {
        if let speakerName = segment.speakerName, !speakerName.isEmpty {
            // Named speaker
            let initials = speakerName.split(separator: " ")
                .compactMap { $0.first }
                .prefix(2)
                .map { String($0) }
                .joined()
                .uppercased()
            
            let color = getColorForSpeaker(speakerName)
            return (speakerName, initials.isEmpty ? "?" : initials, color)
        } else if let speakerID = segment.speakerID {
            // Unnamed speaker with ID
            if speakerNumbers[speakerID] == nil {
                speakerNumbers[speakerID] = nextSpeakerNumber
                nextSpeakerNumber += 1
            }
            
            let number = speakerNumbers[speakerID] ?? 1
            let color = getColorForSpeaker(speakerID)
            return ("Speaker \(number)", "\(number)", color)
        } else {
            // Completely unknown
            return ("Speaker", "?", .gray)
        }
    }
    
    private func getColorForSpeaker(_ identifier: String) -> Color {
        if let color = speakerColors[identifier] {
            return color
        }
        
        let colors: [Color] = [
            .blue, .green, .orange, .purple, 
            .pink, .cyan, .indigo, .mint
        ]
        let color = colors[speakerColors.count % colors.count]
        speakerColors[identifier] = color
        return color
    }
    
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
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.0fKB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Supporting Views

struct CompactSpeakerRow: View {
    let participant: IdentifiedParticipant
    let totalDuration: TimeInterval
    
    private var percentage: Double {
        guard totalDuration > 0 else { return 0 }
        return min(participant.speakingDuration / totalDuration, 1.0)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Active indicator
            Circle()
                .fill(participant.isSpeaking ? Color.green : Color.clear)
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(participant.isSpeaking ? Color.green : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            
            // Name
            Text(participant.name ?? "Unknown")
                .font(.system(size: 11, weight: participant.isSpeaking ? .medium : .regular))
                .lineLimit(1)
            
            Spacer()
            
            // Time bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(participant.color.opacity(0.5))
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                }
            }
            .frame(width: 60, height: 8)
            
            // Percentage
            Text("\(Int(percentage * 100))%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}