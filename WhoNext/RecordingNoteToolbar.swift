import SwiftUI

/// Formatting toolbar for notes in the recording window
/// Supports bold, italic, underline, lists, and highlighting
struct RecordingNoteToolbar: View {
    var onFormat: ((FormatAction) -> Void)?

    enum FormatAction {
        case bold
        case italic
        case underline
        case bulletList
        case numberedList
        case highlight
    }

    var body: some View {
        HStack(spacing: 4) {
            // Bold
            FormatButton(icon: "bold", label: "Bold", shortcut: "B") {
                onFormat?(.bold)
            }

            // Italic
            FormatButton(icon: "italic", label: "Italic", shortcut: "I") {
                onFormat?(.italic)
            }

            // Underline
            FormatButton(icon: "underline", label: "Underline", shortcut: "U") {
                onFormat?(.underline)
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            // Bullet list
            FormatButton(icon: "list.bullet", label: "Bullet List", shortcut: "L") {
                onFormat?(.bulletList)
            }

            // Numbered list
            FormatButton(icon: "list.number", label: "Numbered List", shortcut: "L") {
                onFormat?(.numberedList)
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            // Highlight
            FormatButton(icon: "highlighter", label: "Highlight", shortcut: "H") {
                onFormat?(.highlight)
            }

            Spacer()

            // Hint text
            Text("Tip: Use ACTION: to create action items")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

/// Individual format button with hover state
struct FormatButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

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
        .help("\(label) (\(shortcut))")
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    RecordingNoteToolbar { action in
        print("Format action: \(action)")
    }
    .padding()
}
