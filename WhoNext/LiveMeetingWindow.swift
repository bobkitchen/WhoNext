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
        
        // Create the window as NSPanel for floating behavior
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "Live Meeting"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false  // Stay visible when app is not active

        // CRITICAL: Disable window restoration to prevent bad positioning
        panel.isRestorable = false
        panel.setFrameAutosaveName("")

        let window = panel

        super.init(window: window)

        // Position window in top-right corner
        positionWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func positionWindow() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let padding: CGFloat = 20

        // Calculate position from top-right with padding
        let xPos = screenFrame.maxX - windowFrame.width - padding
        let yPos = screenFrame.maxY - windowFrame.height - padding

        // Ensure window stays fully on screen with safe boundaries
        let safeX = max(screenFrame.minX + padding, min(xPos, screenFrame.maxX - windowFrame.width - padding))
        let safeY = max(screenFrame.minY + padding, min(yPos, screenFrame.maxY - windowFrame.height - padding))

        window.setFrameOrigin(NSPoint(x: safeX, y: safeY))

        print("🟢 LiveMeetingWindow positioned at: \(safeX), \(safeY)")
        print("🟢 Screen bounds: \(screenFrame)")
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
                                TranscriptSegmentView(segment: segment, expanded: true)
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
    
    private var windowController: NSWindowController?
    private var currentWindowController: NSWindowController?
    
    private init() {}
    
    func showWindow(for meeting: LiveMeeting) {
        print("🪟 LiveMeetingWindowManager.showWindow called")
        print("🪟 Current thread: \(Thread.current)")
        print("🪟 Is main thread: \(Thread.isMainThread)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("🪟 On main thread, creating window")
            
            // Close existing window if any
            self.currentWindowController?.close()
            
            // Create refined recording window with improved UI
            print("🪟 Creating RefinedRecordingWindowController")
            let windowController = RefinedRecordingWindowController(meeting: meeting)
            self.currentWindowController = windowController
            
            print("🪟 Showing window")
            windowController.showWindow(nil)
            
            print("🪟 Window should be visible now")
        }
    }
    
    func hideWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.currentWindowController?.close()
            self?.currentWindowController = nil
        }
    }
    
    func updateMeeting(_ meeting: LiveMeeting) {
        // CompactRecordingWindowController doesn't have updateMeeting method
        // The meeting is observed directly via @ObservedObject
    }
}