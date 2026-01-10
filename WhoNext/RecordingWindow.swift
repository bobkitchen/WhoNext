import SwiftUI
import AppKit
import CoreData

// MARK: - Recording Window Manager

/// Singleton manager for the recording window
class RecordingWindowManager {
    static let shared = RecordingWindowManager()

    private var windowController: RecordingWindowController?

    private init() {}

    /// Show the recording window
    func show() {
        if windowController == nil {
            windowController = RecordingWindowController()
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    /// Hide the recording window
    func hide() {
        windowController?.close()
    }

    /// Check if window is visible
    var isVisible: Bool {
        windowController?.window?.isVisible ?? false
    }
}

// MARK: - Recording Window Controller

/// NSWindowController for the recording window - uses standard NSWindow (not floating panel)
class RecordingWindowController: NSWindowController, NSWindowDelegate {

    private var hostingController: NSHostingController<AnyView>?

    // UserDefaults keys for window position persistence
    private let windowFrameKey = "RecordingWindowFrame"

    init() {
        // Create the SwiftUI view with Core Data context
        let context = PersistenceController.shared.container.viewContext
        let contentView = AnyView(
            RecordingWindowView()
                .environment(\.managedObjectContext, context)
        )
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        // Get saved frame or use default position
        let defaultFrame = Self.defaultWindowFrame()
        let savedFrame = Self.loadSavedFrame() ?? defaultFrame

        // Create standard window (NOT NSPanel, NOT floating)
        let window = NSWindow(
            contentRect: savedFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        window.title = "Recording"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible

        // Standard window level (can go behind other windows)
        window.level = .normal

        super.init(window: window)

        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Position Persistence

    private static func defaultWindowFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: 700, height: 600)
        }

        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 700
        let windowHeight: CGFloat = 600
        let padding: CGFloat = 50

        // Position in top-right area by default
        let x = screenFrame.maxX - windowWidth - padding
        let y = screenFrame.maxY - windowHeight - padding

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }

    private static func loadSavedFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: "RecordingWindowFrame") else {
            return nil
        }
        return NSRectFromString(frameString)
    }

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        let frameString = NSStringFromRect(frame)
        UserDefaults.standard.set(frameString, forKey: windowFrameKey)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()

        // Confirm stop recording if still recording
        let recordingEngine = MeetingRecordingEngine.shared
        if recordingEngine.isRecording {
            let alert = NSAlert()
            alert.messageText = "Stop Recording?"
            alert.informativeText = "Closing this window will stop the current recording."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Stop Recording")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                recordingEngine.manualStopRecording()
            } else {
                // Prevent close - reopen window
                DispatchQueue.main.async {
                    RecordingWindowManager.shared.show()
                }
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }
}

// MARK: - Recording Window View

/// Main SwiftUI view for the recording window
struct RecordingWindowView: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var isNotesFocused = false

    // Binding to sync notes with LiveMeeting
    private var userNotesBinding: Binding<NSAttributedString> {
        Binding(
            get: { recordingEngine.currentMeeting?.userNotes ?? NSAttributedString() },
            set: { newValue in
                recordingEngine.currentMeeting?.userNotes = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with recording status
            recordingHeader

            Divider()

            // Main content area
            HSplitView {
                // Left: Transcript
                transcriptSection
                    .frame(minWidth: 300)

                // Right: Participants + Audio Quality
                participantsSidebar
                    .frame(width: 200)
            }

            Divider()

            // Bottom: Notes section
            notesSection
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Header

    private var recordingHeader: some View {
        HStack(spacing: 12) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.6)
                    )

                Text("Recording")
                    .font(.headline)
                    .foregroundColor(.red)
            }

            // Meeting title
            if let meeting = recordingEngine.currentMeeting {
                Text(meeting.displayTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(formattedDuration)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            // Stop button
            Button(action: {
                recordingEngine.manualStopRecording()
                RecordingWindowManager.shared.hide()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                    Text("Stop")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE TRANSCRIPT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let meeting = recordingEngine.currentMeeting {
                            ForEach(Array(meeting.transcript.suffix(30).enumerated()), id: \.offset) { index, segment in
                                TranscriptSegmentRow(segment: segment)
                                    .id(index)
                            }
                        }

                        // Anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .onChange(of: recordingEngine.currentMeeting?.transcript.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Participants Sidebar

    private var participantsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Participants section
            VStack(alignment: .leading, spacing: 8) {
                Text("PARTICIPANTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if let meeting = recordingEngine.currentMeeting {
                    ForEach(meeting.identifiedParticipants, id: \.speakerID) { participant in
                        ParticipantRow(participant: participant)
                    }
                } else {
                    Text("No participants detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Audio quality indicator
            VStack(alignment: .leading, spacing: 4) {
                Text("AUDIO QUALITY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        Rectangle()
                            .fill(i < 4 ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 20, height: 8)
                            .cornerRadius(2)
                    }
                }

                Text("Excellent")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.secondary)
                Text("MY NOTES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Your notes will enhance the AI summary")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Rich text editor - syncs with LiveMeeting.userNotes
            RichTextEditor(
                text: userNotesBinding,
                isEditable: true,
                onAction: nil,
                isFocused: $isNotesFocused
            )
            .frame(minHeight: 120, maxHeight: 200)

            // Formatting toolbar - uses responder chain for standard actions
            NotesFormattingToolbar()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let duration = recordingEngine.recordingDuration
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Notes Formatting Toolbar

/// Formatting toolbar that uses ActiveNotesTextViewTracker for reliable formatting
/// This approach maintains the text view reference even when toolbar buttons steal focus
struct NotesFormattingToolbar: View {
    @State private var isHoveredBold = false
    @State private var isHoveredItalic = false
    @State private var isHoveredUnderline = false
    @State private var isHoveredBullet = false
    @State private var isHoveredNumber = false
    @State private var isHoveredHighlight = false

    private let tracker = ActiveNotesTextViewTracker.shared

    var body: some View {
        HStack(spacing: 4) {
            // Bold - Cmd+B
            ToolbarFormatButton(icon: "bold", label: "Bold", shortcut: "⌘B", isHovered: $isHoveredBold) {
                tracker.applyBold()
            }

            // Italic - Cmd+I
            ToolbarFormatButton(icon: "italic", label: "Italic", shortcut: "⌘I", isHovered: $isHoveredItalic) {
                tracker.applyItalic()
            }

            // Underline - Cmd+U
            ToolbarFormatButton(icon: "underline", label: "Underline", shortcut: "⌘U", isHovered: $isHoveredUnderline) {
                tracker.applyUnderline()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            // Bullet list
            ToolbarFormatButton(icon: "list.bullet", label: "Bullet List", shortcut: "", isHovered: $isHoveredBullet) {
                tracker.insertBulletList()
            }

            // Numbered list
            ToolbarFormatButton(icon: "list.number", label: "Numbered List", shortcut: "", isHovered: $isHoveredNumber) {
                tracker.insertNumberedList()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            // Highlight
            ToolbarFormatButton(icon: "highlighter", label: "Highlight", shortcut: "⌘⇧H", isHovered: $isHoveredHighlight) {
                tracker.applyHighlight()
            }

            Spacer()

            // Hint text
            Text("Tip: Use ACTION: to create action items")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// Individual toolbar button with hover state
struct ToolbarFormatButton: View {
    let icon: String
    let label: String
    let shortcut: String
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(shortcut.isEmpty ? label : "\(label) (\(shortcut))")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Supporting Views

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let speaker = segment.speakerName {
                Text(speaker)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            Text(segment.text)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

struct ParticipantRow: View {
    let participant: IdentifiedParticipant

    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 28, height: 28)
                .overlay(
                    Text(initials)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(participant.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if participant.isCurrentUser {
                    Text("(You)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Speaking indicator
            if participant.isSpeaking {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var initials: String {
        let name = participant.displayName
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(participant.speakerID.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Preview

#Preview {
    RecordingWindowView()
        .frame(width: 700, height: 600)
}
