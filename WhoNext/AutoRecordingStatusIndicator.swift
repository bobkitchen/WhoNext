import SwiftUI
import AppKit

/// A floating status indicator that shows auto-recording monitoring state
/// Similar to how Quill shows its status in the corner
struct AutoRecordingStatusIndicator: View {
    @ObservedObject var recordingEngine = MeetingRecordingEngine.shared
    @State private var isHovered = false
    @State private var showDetails = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Status dot with animation
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 10)
                        .scaleEffect(isActive ? 2 : 1)
                        .opacity(isActive ? 0 : 0.5)
                        .animation(
                            isActive ? .easeInOut(duration: 2).repeatForever(autoreverses: false) : .default,
                            value: isActive
                        )
                )
            
            // Status text (only show when expanded or recording)
            if showDetails || recordingEngine.isRecording {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, showDetails ? 12 : 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(backgroundcolor)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
                showDetails = hovering || recordingEngine.isRecording
            }
        }
        .help(helpText)
    }
    
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
    
    private var backgroundcolor: Color {
        if isHovered {
            return Color(NSColor.controlBackgroundColor)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.9)
    }
    
    private var statusText: String {
        if recordingEngine.isRecording {
            if let meeting = recordingEngine.currentMeeting {
                return "Recording: \(meeting.calendarTitle ?? "Meeting")"
            }
            return "Recording..."
        } else if recordingEngine.isMonitoring {
            return "Monitoring"
        } else {
            return "Idle"
        }
    }
    
    private var helpText: String {
        if recordingEngine.isRecording {
            return "Currently recording a meeting. Click to view details."
        } else if recordingEngine.isMonitoring {
            return "Auto-monitoring for meetings. Will start recording automatically when a meeting is detected."
        } else {
            return "Auto-recording is idle. Click to start monitoring."
        }
    }
}

/// Window to host the floating indicator
class FloatingStatusWindow: NSPanel {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isFloatingPanel = true
        
        // Set content view
        // Wrap NSHostingView in a container to avoid Auto Layout constraint loops
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        let hostingView = NSHostingView(rootView: AutoRecordingStatusIndicator())
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)
        
        self.contentView = containerView
        
        // Position in top-right corner
        positionWindow()
    }
    
    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 120
        let windowHeight: CGFloat = 30
        let padding: CGFloat = 20
        
        // Position in top-right corner
        let x = screenFrame.maxX - windowWidth - padding
        let y = screenFrame.maxY - windowHeight - padding
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    /// Show the floating indicator
    static func showIndicator() {
        let window = FloatingStatusWindow()
        window.orderFront(nil)
        
        // Store reference to keep window alive
        FloatingStatusWindowController.shared.window = window
    }
    
    // Ensure the panel doesn't become key, allowing it to float without stealing focus
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

/// Controller to manage the floating window lifecycle
class FloatingStatusWindowController {
    static let shared = FloatingStatusWindowController()
    var window: FloatingStatusWindow?
    
    private init() {}
    
    func showIfNeeded() {
        if window == nil {
            FloatingStatusWindow.showIndicator()
        }
    }
    
    func hide() {
        window?.close()
        window = nil
    }
}