import SwiftUI
import AppKit

/// Floating window that displays live meeting recording status and transcription
class LiveMeetingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<LiveMeetingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = LiveMeetingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Live Meeting"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hostingController
        
        super.init(window: window)
        
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
        let yPos = screenFrame.maxY - windowFrame.height - 20
        
        window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
    
    func updateMeeting(_ meeting: LiveMeeting) {
        self.meeting = meeting
        if let hostingController = hostingController {
            hostingController.rootView = LiveMeetingView(meeting: meeting)
        }
    }
}

/// SwiftUI view for the live meeting window
struct LiveMeetingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var isExpanded: Bool = false
    @State private var showTranscript: Bool = true
    @State private var opacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .frame(width: 380, height: isExpanded ? 480 : 280)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .opacity(opacity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                opacity = hovering ? 1.0 : 0.85
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 16, height: 16)
                            .scaleEffect(meeting.isRecording ? 1.5 : 1.0)
                            .animation(
                                meeting.isRecording ?
                                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                                    .default,
                                value: meeting.isRecording
                            )
                    )
                
                Text("Recording")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Duration
            Text(meeting.formattedDuration)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Controls
            HStack(spacing: 8) {
                Button(action: toggleTranscript) {
                    Image(systemName: showTranscript ? "text.bubble" : "text.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle transcript")
                
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")
                
                Button(action: stopRecording) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop recording")
            }
        }
    }
    
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Meeting info
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                HStack {
                    Label("\(meeting.participantCount) participants", systemImage: "person.2")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if meeting.transcriptionProgress > 0 {
                        HStack(spacing: 4) {
                            ProgressView(value: meeting.transcriptionProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 60)
                            Text("\(Int(meeting.transcriptionProgress * 100))%")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Latest transcript
            if showTranscript && !meeting.transcript.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(meeting.transcript.suffix(5)) { segment in
                                TranscriptSegmentView(segment: segment)
                                    .id(segment.id)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: 120)
                    .onChange(of: meeting.transcript.count) { _ in
                        if let lastSegment = meeting.transcript.last {
                            withAnimation {
                                proxy.scrollTo(lastSegment.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Participants
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(meeting.identifiedParticipants) { participant in
                        ParticipantChip(participant: participant)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Full transcript
            if showTranscript {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(meeting.transcript) { segment in
                                TranscriptSegmentView(segment: segment, expanded: true)
                                    .id(segment.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: meeting.transcript.count) { _ in
                        if let lastSegment = meeting.transcript.last {
                            withAnimation {
                                proxy.scrollTo(lastSegment.id, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                // Audio visualization placeholder
                VStack {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Audio Recording")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    private func toggleTranscript() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showTranscript.toggle()
        }
    }
    
    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }
    
    private func stopRecording() {
        recordingEngine.manualStopRecording()
    }
}

/// View for a single transcript segment
struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    var expanded: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if expanded {
                Text(segment.formattedTimestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if let speaker = segment.speakerName {
                    Text(speaker)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                
                Text(segment.text)
                    .font(.system(size: expanded ? 13 : 12))
                    .foregroundColor(.primary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !segment.isFinalized && expanded {
                    Text("Processing...")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, expanded ? 0 : 4)
        .background(
            segment.isFinalized ?
                Color.clear :
                Color.orange.opacity(0.05)
        )
        .cornerRadius(4)
    }
}

/// Participant chip view
struct ParticipantChip: View {
    @ObservedObject var participant: IdentifiedParticipant
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(participant.isCurrentlySpeaking ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
                .animation(.easeInOut(duration: 0.2), value: participant.isCurrentlySpeaking)
            
            Text(participant.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            
            // Confidence indicator
            Circle()
                .fill(participant.confidenceLevel.color)
                .frame(width: 4, height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    Capsule()
                        .stroke(
                            participant.isCurrentlySpeaking ?
                                Color.green.opacity(0.5) :
                                Color(NSColor.separatorColor),
                            lineWidth: participant.isCurrentlySpeaking ? 2 : 1
                        )
                )
        )
        .scaleEffect(participant.isCurrentlySpeaking ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: participant.isCurrentlySpeaking)
    }
}

// MARK: - Live Meeting Window Manager

class LiveMeetingWindowManager {
    static let shared = LiveMeetingWindowManager()
    
    private var windowController: LiveMeetingWindowController?
    
    private init() {}
    
    func showWindow(for meeting: LiveMeeting) {
        if let windowController = windowController {
            windowController.updateMeeting(meeting)
            windowController.showWindow(nil)
        } else {
            windowController = LiveMeetingWindowController(meeting: meeting)
            windowController?.showWindow(nil)
        }
    }
    
    func hideWindow() {
        windowController?.close()
        windowController = nil
    }
    
    func updateMeeting(_ meeting: LiveMeeting) {
        windowController?.updateMeeting(meeting)
    }
}