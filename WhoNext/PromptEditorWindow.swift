import SwiftUI
import AppKit

/// Window controller for prompt editing windows
/// Uses NSWindowDelegate to properly manage window lifecycle and prevent crashes
final class PromptEditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var currentSaveHandler: ((String, String?) -> Void)?
    private var hostingController: NSHostingController<AnyView>?

    static let shared = PromptEditorWindowController()

    private override init() {
        super.init()
    }

    func openPromptEditor(
        type: PromptEditorType,
        currentValue: String,
        secondaryValue: String? = nil,
        onSave: @escaping (String, String?) -> Void
    ) {
        // Close existing window if any
        closeCurrentWindow()

        // Store the save handler
        currentSaveHandler = onSave

        // Create the editor view with simple callbacks that just notify us
        let editorView = PromptEditorView(
            type: type,
            initialValue: currentValue,
            initialSecondaryValue: secondaryValue,
            onSave: { [weak self] primary, secondary in
                self?.handleSave(primary: primary, secondary: secondary)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )

        hostingController = NSHostingController(rootView: AnyView(editorView))

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Important: Keep the window alive until we explicitly close it
        newWindow.isReleasedWhenClosed = false
        newWindow.title = type.windowTitle
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.setFrameAutosaveName("PromptEditor-\(type.rawValue)")
        newWindow.minSize = NSSize(width: 500, height: 400)

        // Set delegate to handle window close events
        newWindow.delegate = self

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    private func handleSave(primary: String, secondary: String?) {
        // Call the save handler first
        currentSaveHandler?(primary, secondary)
        // Then close the window
        closeCurrentWindow()
    }

    private func handleCancel() {
        closeCurrentWindow()
    }

    private func closeCurrentWindow() {
        guard let window = window else { return }

        // Remove delegate first to prevent any callbacks during close
        window.delegate = nil

        // Order out (hide) the window
        window.orderOut(nil)

        // Clear references
        self.window = nil
        self.hostingController = nil
        self.currentSaveHandler = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // User clicked the X button - clean up properly
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }

        // Remove delegate to prevent any further callbacks
        closingWindow.delegate = nil

        // Clear our references
        self.window = nil
        self.hostingController = nil
        self.currentSaveHandler = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Allow the window to close
        return true
    }
}

/// Types of prompts that can be edited
enum PromptEditorType: String {
    case preMeetingBrief = "preMeetingBrief"
    case summarization = "summarization"
    case email = "email"

    var windowTitle: String {
        switch self {
        case .preMeetingBrief:
            return "Edit Pre-Meeting Brief Prompt"
        case .summarization:
            return "Edit Summarization Prompt"
        case .email:
            return "Edit Email Template"
        }
    }

    var description: String {
        switch self {
        case .preMeetingBrief:
            return "This prompt is used when generating pre-meeting intelligence briefs. It guides the AI on what information to extract and how to present it."
        case .summarization:
            return "This prompt is used when summarizing meeting transcripts. It tells the AI what sections to include and how to format the output."
        case .email:
            return "This template is used for generating follow-up emails. Use {name} for full name and {firstName} for first name."
        }
    }

    var hasSecondaryField: Bool {
        self == .email
    }

    var primaryLabel: String {
        switch self {
        case .preMeetingBrief, .summarization:
            return "Prompt"
        case .email:
            return "Email Body"
        }
    }

    var secondaryLabel: String? {
        switch self {
        case .email:
            return "Email Subject"
        default:
            return nil
        }
    }
}

/// The editor view shown in the prompt editing window
struct PromptEditorView: View {
    let type: PromptEditorType
    @State private var primaryText: String
    @State private var secondaryText: String
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var hasChanges = false

    init(
        type: PromptEditorType,
        initialValue: String,
        initialSecondaryValue: String?,
        onSave: @escaping (String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.type = type
        self._primaryText = State(initialValue: initialValue)
        self._secondaryText = State(initialValue: initialSecondaryValue ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with description
            VStack(alignment: .leading, spacing: 8) {
                Text(type.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Editor content
            VStack(alignment: .leading, spacing: 16) {
                // Secondary field (email subject) - shown first if exists
                if type.hasSecondaryField, let label = type.secondaryLabel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label)
                            .font(.headline)

                        TextField("Subject", text: $secondaryText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: secondaryText) { _, _ in
                                hasChanges = true
                            }
                    }
                }

                // Primary field (prompt or email body)
                VStack(alignment: .leading, spacing: 6) {
                    Text(type.primaryLabel)
                        .font(.headline)

                    TextEditor(text: $primaryText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: primaryText) { _, _ in
                            hasChanges = true
                        }
                }
            }
            .padding()

            Divider()

            // Footer with buttons
            HStack {
                Button("Restore Default") {
                    restoreDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    onSave(primaryText, type.hasSecondaryField ? secondaryText : nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func restoreDefaults() {
        switch type {
        case .preMeetingBrief:
            primaryText = DefaultPrompts.preMeetingBrief
        case .summarization:
            primaryText = DefaultPrompts.summarization
        case .email:
            primaryText = DefaultPrompts.emailBody
            secondaryText = DefaultPrompts.emailSubject
        }
        hasChanges = true
    }
}

#Preview {
    PromptEditorView(
        type: .preMeetingBrief,
        initialValue: DefaultPrompts.preMeetingBrief,
        initialSecondaryValue: nil,
        onSave: { _, _ in },
        onCancel: { }
    )
    .frame(width: 700, height: 600)
}
