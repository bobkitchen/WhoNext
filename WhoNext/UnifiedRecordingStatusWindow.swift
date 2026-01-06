import SwiftUI
import AppKit

/// Unified floating window that smoothly transitions between monitoring and recording states
/// Compact by default, user can expand to see full details
class UnifiedRecordingStatusWindowController: NSWindowController {

    private var hostingController: NSHostingController<UnifiedRecordingStatusView>?
    private var currentState: WindowState = .monitoring

    enum WindowState {
        case monitoring
        case recording
    }

    init() {
        // Create the SwiftUI view
        let contentView = UnifiedRecordingStatusView()
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        // Get screen dimensions for positioning
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 80
        let padding: CGFloat = 20

        // Calculate top-right position
        let xPos = screenFrame.maxX - windowWidth - padding
        let yPos = screenFrame.maxY - windowHeight - padding

        // Create window at the correct position from the start
        let panel = NSPanel(
            contentRect: NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        // Configure panel properties
        panel.title = "Recording Monitor"
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.styleMask.insert(.fullSizeContentView)
        panel.minSize = NSSize(width: 320, height: 80)
        panel.maxSize = NSSize(width: 480, height: 800)
        panel.setFrameAutosaveName("")

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Position window immediately (no delay) - call before showing window
    func positionWindowNow() {
        guard let window = window else { return }

        // Prefer the window's current screen, fallback to main screen
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20

        // Use the actual window frame size after it's been set
        let windowFrame = window.frame
        let windowWidth = windowFrame.width
        let windowHeight = windowFrame.height

        // Calculate position from top-right corner
        let x = screenFrame.maxX - windowWidth - padding
        let y = screenFrame.maxY - windowHeight - padding

        // Ensure window stays fully on screen with safe boundaries
        let safeX = max(screenFrame.minX + padding, min(x, screenFrame.maxX - windowWidth - padding))
        let safeY = max(screenFrame.minY + padding, min(y, screenFrame.maxY - windowHeight - padding))

        let newOrigin = NSPoint(x: safeX, y: safeY)
        window.setFrameOrigin(newOrigin)

        print("🪟 Window positioned at: \(newOrigin)")
        print("🪟 Screen frame: \(screenFrame)")
        print("🪟 Window size: \(windowWidth) x \(windowHeight)")
    }

    /// Transition between monitoring and recording states
    func transitionToState(_ newState: WindowState, animated: Bool = true) {
        guard currentState != newState else { return }
        currentState = newState

        // The view will handle the visual transition
        // Window size changes are handled by the view's frame changes
    }

    /// Expand the window to show full details
    func expand(to size: NSSize, animated: Bool = true) {
        guard let window = window, let screen = window.screen else { return }

        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20

        // Calculate new position from top-right corner
        let x = screenFrame.maxX - size.width - padding
        let y = screenFrame.maxY - size.height - padding

        // Ensure window stays fully on screen with safe boundaries
        let safeX = max(screenFrame.minX + padding, min(x, screenFrame.maxX - size.width - padding))
        let safeY = max(screenFrame.minY + padding, min(y, screenFrame.maxY - size.height - padding))

        // Create new frame with safe origin
        let newFrame = NSRect(x: safeX, y: safeY, width: size.width, height: size.height)

        print("🪟 Expanding window to: \(newFrame), screen: \(screenFrame)")

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            })
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    /// Collapse the window to compact size
    func collapse(animated: Bool = true) {
        expand(to: NSSize(width: 320, height: 80), animated: animated)
    }
}

/// Unified view that shows monitoring or recording state
struct UnifiedRecordingStatusView: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var isExpanded = false
    @State private var speakerNames: [String: String] = [:]
    @State private var speakerNamingModes: [String: NamingMode] = [:]
    @State private var editingSpeaker: String? = nil
    @State private var editingName: String = ""
    @State private var editingPerson: Person? = nil
    @State private var editingNamingMode: NamingMode = .unnamed
    @State private var unnamedSpeakers: Set<String> = []

    var body: some View {
        ZStack {
            if isExpanded {
                expandedView
                    .frame(width: 480, height: 640)
            } else {
                compactView
                    .frame(width: 320, height: 80)
            }
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .onChange(of: isExpanded) { _, newValue in
            updateWindowSize(expanded: newValue)
        }
    }

    // MARK: - Compact View

    private var compactView: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 70) // Space for window controls
            // Status indicator with pulsing animation
            ZStack {
                // Outer glow
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .blur(radius: 4)

                // Pulsing ring
                Circle()
                    .stroke(statusColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(isActive ? 1.3 : 1.0)
                    .opacity(isActive ? 0 : 0.6)
                    .animation(
                        isActive ? .easeOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                        value: isActive
                    )

                // Main dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [statusColor.opacity(0.9), statusColor],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor, radius: 3, x: 0, y: 0)
            }

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

                if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                    Text(meeting.displayTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Duration (if recording)
            if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                Text(formatDuration(meeting.duration))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
            }

            // Expand/Collapse button
            Button(action: { toggleExpanded() }) {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand to see details")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header
            expandedHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.15).opacity(0.9))

            Divider()
                .background(Color.white.opacity(0.1))

            if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                // Recording content
                recordingContent(meeting: meeting)
            } else {
                // Monitoring content
                monitoringContent
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Footer
            expandedFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(white: 0.12).opacity(0.9))
        }
    }

    private var expandedHeader: some View {
        HStack {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .fill(statusColor.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .scaleEffect(isActive ? 1.5 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: isActive
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))

                    if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                        Text(meeting.displayTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Duration and controls
            if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
                HStack(spacing: 12) {
                    Text(formatDuration(meeting.duration))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.95))

                    Button(action: { recordingEngine.manualStopRecording() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 28, height: 28)

                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Collapse button
            Button(action: { toggleExpanded() }) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Collapse")
        }
    }

    private func recordingContent(meeting: LiveMeeting) -> some View {
        VStack(spacing: 0) {
            // Transcript - fills available space
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if meeting.transcript.isEmpty {
                            emptyTranscriptState
                        } else {
                            ForEach(Array(meeting.transcript.suffix(15))) { segment in
                                transcriptSegmentView(segment: segment)
                                    .id(segment.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.10).opacity(0.5))
                .onChange(of: meeting.transcript.count) { _, _ in
                    if let last = meeting.transcript.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Stats cards
            HStack(spacing: 8) {
                statsCard(meeting: meeting)
                speakersCard(meeting: meeting)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var monitoringContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.6))
                .symbolEffect(.pulse)

            Text("Auto-monitoring for meetings")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            Text("Recording will start automatically when a meeting is detected")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 36))
                .foregroundColor(Color.white.opacity(0.3))

            Text("Listening...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Text("Transcript will appear here")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func transcriptSegmentView(segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Speaker avatar
            Circle()
                .fill(getSpeakerColor(for: segment).opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(getSpeakerInitials(for: segment))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(getSpeakerColor(for: segment))
                )

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(getSpeakerName(for: segment))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(getSpeakerColor(for: segment))

                Text(segment.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(segment.isFinalized ? 0.95 : 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func statsCard(meeting: LiveMeeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 12) {
                StatItem(
                    value: "\(meeting.wordCount)",
                    label: "words",
                    icon: "text.word.spacing"
                )

                StatItem(
                    value: formatFileSize(meeting.currentFileSize),
                    label: "size",
                    icon: "doc"
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.10).opacity(0.5))
        .cornerRadius(8)
    }

    private func speakersCard(meeting: LiveMeeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPEAKERS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            if meeting.identifiedParticipants.isEmpty {
                HStack {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.4))

                    Text("Awaiting speakers...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(meeting.identifiedParticipants.prefix(2)) { participant in
                        HStack {
                            Circle()
                                .fill(participant.isSpeaking ? Color.green : Color.clear)
                                .frame(width: 4, height: 4)

                            Text(participant.name ?? "Speaker \(participant.speakerID)")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)

                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.10).opacity(0.5))
        .cornerRadius(8)
    }

    private var expandedFooter: some View {
        HStack {
            // Quality indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(recordingEngine.isRecording ?
                          (recordingEngine.currentMeeting?.bufferHealth.color ?? .gray) :
                          .green)
                    .frame(width: 5, height: 5)

                Text(recordingEngine.isRecording ?
                     (recordingEngine.currentMeeting?.bufferHealth.description ?? "Good") + " quality" :
                     "System ready")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var isActive: Bool {
        recordingEngine.isMonitoring || recordingEngine.isRecording
    }

    private var statusColor: Color {
        if recordingEngine.isRecording {
            return .red
        } else if recordingEngine.isMonitoring {
            return .green
        } else {
            return .gray
        }
    }

    private var statusTitle: String {
        if recordingEngine.isRecording {
            return "Recording"
        } else if recordingEngine.isMonitoring {
            return "Monitoring"
        } else {
            return "Idle"
        }
    }


    // MARK: - Helper Methods

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }

    private func updateWindowSize(expanded: Bool) {
        guard let windowController = NSApp.windows.compactMap({
            $0.windowController as? UnifiedRecordingStatusWindowController
        }).first else { return }

        if expanded {
            windowController.expand(to: NSSize(width: 480, height: 640), animated: true)
        } else {
            windowController.collapse(animated: true)
        }
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

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.0fKB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        }
    }

    private func getSpeakerName(for segment: TranscriptSegment) -> String {
        if let speakerID = segment.speakerID, let customName = speakerNames[speakerID] {
            return customName
        } else if let speakerName = segment.speakerName, !speakerName.isEmpty {
            return speakerName
        } else if let speakerID = segment.speakerID {
            return "Speaker \(speakerID)"
        }
        return "Unknown"
    }

    private func getSpeakerInitials(for segment: TranscriptSegment) -> String {
        let name = getSpeakerName(for: segment)
        let initials = name.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0) }
            .joined()
            .uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private func getSpeakerColor(for segment: TranscriptSegment) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        let identifier = segment.speakerID ?? segment.speakerName ?? "unknown"
        let hash = abs(identifier.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Singleton Manager

class UnifiedRecordingStatusWindowManager {
    static let shared = UnifiedRecordingStatusWindowManager()
    private var windowController: UnifiedRecordingStatusWindowController?

    private init() {}

    func showIfNeeded() {
        print("🔴🔴🔴 UNIFIED WINDOW MANAGER: showIfNeeded() called 🔴🔴🔴")
        if windowController == nil {
            print("🔴🔴🔴 Creating NEW window controller 🔴🔴🔴")
            windowController = UnifiedRecordingStatusWindowController()
            windowController?.showWindow(nil)

            // CRITICAL: Force position AFTER showing to override macOS auto-positioning
            DispatchQueue.main.async { [weak self] in
                self?.windowController?.positionWindowNow()
                // Force it again after a tiny delay to ensure it sticks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.windowController?.positionWindowNow()
                }
            }
        } else {
            print("🔴🔴🔴 Window already exists, bringing to front 🔴🔴🔴")
            windowController?.window?.orderFront(nil)
            // Reposition when bringing back
            DispatchQueue.main.async { [weak self] in
                self?.windowController?.positionWindowNow()
            }
        }
    }

    func hide() {
        // Prevent saving window frame on close
        if let window = windowController?.window {
            window.setFrameAutosaveName("")
        }
        windowController?.close()
        windowController = nil
    }

    func transitionToRecording() {
        windowController?.transitionToState(.recording, animated: true)
    }

    func transitionToMonitoring() {
        windowController?.transitionToState(.monitoring, animated: true)
    }

    func toggle() {
        if windowController == nil {
            showIfNeeded()
        } else {
            hide()
        }
    }

    var isVisible: Bool {
        return windowController?.window?.isVisible ?? false
    }
}

// VisualEffectBlur is already defined in EnhancedFloatingRecordingPrompt.swift
