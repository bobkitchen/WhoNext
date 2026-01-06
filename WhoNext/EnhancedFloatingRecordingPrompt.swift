//
//  EnhancedFloatingRecordingPrompt.swift
//  WhoNext
//
//  Created on 1/1/26.
//

import SwiftUI
import AppKit

/// Native macOS visual effect blur for HUD-style windows
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Represents a detected meeting that needs user action
struct DetectedMeeting: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let source: MeetingSource
    let detectedAt: Date
    let confidence: Float
    let participants: [String]?

    enum MeetingSource {
        case calendar
        case microphoneActivity
        case meetingApp
    }

    var sourceIcon: String {
        switch source {
        case .calendar: return "calendar"
        case .microphoneActivity: return "mic.fill"
        case .meetingApp: return "video.fill"
        }
    }

    var sourceLabel: String {
        switch source {
        case .calendar: return "Calendar"
        case .microphoneActivity: return "Mic Activity"
        case .meetingApp: return "Meeting App"
        }
    }
}

/// Enhanced floating window with modern design and user prompts
struct EnhancedFloatingRecordingPrompt: View {
    @ObservedObject var recordingEngine = MeetingRecordingEngine.shared
    @ObservedObject var audioCapture: SystemAudioCapture

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var detectedMeeting: DetectedMeeting?
    @State private var showPermissionWarning = false

    var body: some View {
        VStack(spacing: 0) {
            // Main status bar (always visible)
            statusBar

            // Expandable content (when hovered or has prompt)
            if isExpanded || detectedMeeting != nil {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)

                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            ZStack {
                // Single smooth dark background with accent
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.10).opacity(0.95),
                                Color(white: 0.08).opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(statusColor.opacity(0.08))
                            .blendMode(.plusLighter)
                    )

                // Subtle border
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: statusColor.opacity(0.25), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
                if hovering {
                    isExpanded = true
                } else if detectedMeeting == nil {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            // Vibrant status indicator with glow
            ZStack {
                // Outer glow ring
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

            // Vibrant status text
            Text(statusTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

            Spacer()

            // Glowing action button
            Button(action: handleQuickAction) {
                Image(systemName: quickActionIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(quickActionHelpText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusIndicator: some View {
        ZStack {
            // Pulsing background
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 32, height: 32)
                .scaleEffect(isActive ? 1.2 : 1.0)
                .opacity(isActive ? 0.5 : 0.8)
                .animation(
                    isActive ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default,
                    value: isActive
                )

            // Main dot
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            // Recording icon overlay
            if recordingEngine.isRecording {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
            }
        }
    }

    private var quickActionButton: some View {
        Button(action: handleQuickAction) {
            Image(systemName: quickActionIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(quickActionColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(quickActionHelpText)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 12) {
            Divider()

            // Meeting detection prompt
            if let meeting = detectedMeeting {
                meetingPrompt(for: meeting)
            } else {
                // Stats and info when expanded
                statsView
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func meetingPrompt(for meeting: DetectedMeeting) -> some View {
        VStack(spacing: 12) {
            // Meeting info
            HStack(spacing: 10) {
                Image(systemName: meeting.sourceIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Label(meeting.sourceLabel, systemImage: meeting.sourceIcon)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text("\(Int(meeting.confidence * 100))% confident")
                            .font(.system(size: 10))
                            .foregroundColor(meeting.confidence > 0.8 ? .green : .orange)
                    }
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { dismissMeetingPrompt() }) {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                Button(action: { startRecordingForDetectedMeeting(meeting) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 12))
                        Text("Start Recording")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
    }

    private var statsView: some View {
        VStack(alignment: .leading, spacing: 9) {
            if recordingEngine.isMonitoring {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.green.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .green.opacity(0.4), radius: 2, x: 0, y: 0)

                    Text("Monitoring")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            if audioCapture.captureMode == .microphoneOnly {
                HStack(spacing: 7) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 2, x: 0, y: 0)

                    Text("Mic only")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            if let nextMeeting = upcomingMeetingInfo {
                HStack(spacing: 7) {
                    Image(systemName: "clock.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 2, x: 0, y: 0)

                    Text(nextMeeting)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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

    private var quickActionIcon: String {
        if recordingEngine.isRecording {
            return "stop.circle"
        } else if detectedMeeting != nil {
            return "xmark.circle"
        } else {
            return recordingEngine.isMonitoring ? "pause.circle" : "play.circle"
        }
    }

    private var quickActionColor: Color {
        if recordingEngine.isRecording {
            return .red
        }
        return .accentColor
    }

    private var quickActionHelpText: String {
        if recordingEngine.isRecording {
            return "Stop recording"
        } else if detectedMeeting != nil {
            return "Dismiss prompt"
        } else {
            return recordingEngine.isMonitoring ? "Pause monitoring" : "Start monitoring"
        }
    }

    private var upcomingMeetingInfo: String? {
        // Get next meeting from calendar
        guard let service = CalendarService.shared.upcomingMeetings.first else { return nil }

        let timeInterval = service.startDate.timeIntervalSinceNow
        if timeInterval > 0 && timeInterval < 3600 { // Within next hour
            let minutes = Int(timeInterval / 60)
            return "Next meeting in \(minutes)m"
        }
        return nil
    }

    // MARK: - Actions

    private func handleQuickAction() {
        if recordingEngine.isRecording {
            recordingEngine.stopRecording()
        } else if detectedMeeting != nil {
            dismissMeetingPrompt()
        } else {
            if recordingEngine.isMonitoring {
                recordingEngine.stopMonitoring()
            } else {
                recordingEngine.startMonitoring()
            }
        }
    }

    private func startRecordingForDetectedMeeting(_ meeting: DetectedMeeting) {
        recordingEngine.manualStartRecording()
        withAnimation {
            detectedMeeting = nil
        }
    }

    private func dismissMeetingPrompt() {
        withAnimation {
            detectedMeeting = nil
        }
    }

    // MARK: - Public Methods

    func showMeetingPrompt(_ meeting: DetectedMeeting) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            detectedMeeting = meeting
            isExpanded = true
        }
    }
}

/// Enhanced floating window controller
class EnhancedFloatingWindow: NSPanel {
    private var hostingView: NSHostingView<EnhancedFloatingRecordingPrompt>?

    init(audioCapture: SystemAudioCapture) {
        print("🪟 EnhancedFloatingWindow.init() called")
        let contentView = EnhancedFloatingRecordingPrompt(audioCapture: audioCapture)
        let hosting = NSHostingView(rootView: contentView)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 48),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow, .resizable],
            backing: .buffered,
            defer: false
        )

        self.hostingView = hosting

        // Configure window for modern floating HUD
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isFloatingPanel = true
        self.hasShadow = false // SwiftUI handles shadows
        self.animationBehavior = .utilityWindow

        // Set content
        self.contentView = hosting

        // Ensure the window itself respects the corner radius
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.cornerCurve = .continuous
        self.contentView?.layer?.masksToBounds = true

        // Position window
        positionWindow()
        print("🪟 EnhancedFloatingWindow positioned at: \(self.frame)")
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 340
        let windowHeight: CGFloat = 120
        let padding: CGFloat = 20

        // Position in top-right corner
        let x = screenFrame.maxX - windowWidth - padding
        let y = screenFrame.maxY - windowHeight - padding

        self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    func showMeetingPrompt(_ meeting: DetectedMeeting) {
        hostingView?.rootView.showMeetingPrompt(meeting)

        // Expand window height to accommodate prompt
        var frame = self.frame
        frame.size.height = 220
        self.setFrame(frame, display: true, animate: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Enhanced controller with meeting prompt support
class EnhancedFloatingWindowController {
    static let shared = EnhancedFloatingWindowController()
    private var window: EnhancedFloatingWindow?

    private init() {}

    func showIfNeeded(audioCapture: SystemAudioCapture) {
        print("🪟 EnhancedFloatingWindowController.showIfNeeded() called, window exists: \(window != nil)")
        if window == nil {
            print("🪟 Creating new EnhancedFloatingWindow...")
            window = EnhancedFloatingWindow(audioCapture: audioCapture)
            print("🪟 Calling orderFront...")
            window?.orderFront(nil)
            print("🪟 Window is visible: \(window?.isVisible ?? false), level: \(window?.level.rawValue ?? 0)")
        } else {
            print("🪟 Window already exists, bringing to front...")
            window?.orderFront(nil)
        }
    }

    func showMeetingPrompt(_ meeting: DetectedMeeting) {
        window?.showMeetingPrompt(meeting)
        window?.orderFront(nil)
    }

    func hide() {
        window?.close()
        window = nil
    }
}
