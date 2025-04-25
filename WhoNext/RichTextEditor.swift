import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var isEditable: Bool = true
    var onAction: ((RichTextEditor.Action) -> Void)? = nil
    @Binding var isFocused: Bool

    enum Action {
        case bold, italic, underline, font, size, markdownImport, markdownExport
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesFindPanel = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.delegate = context.coordinator
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView // Save reference

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.attributedString() != text {
            textView.textStorage?.setAttributedString(text)
        }
        textView.isEditable = isEditable
        // Focus if requested
        if isFocused, let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.attributedString()
        }
    }
}

struct RichTextToolbar: View {
    let onAction: (RichTextEditor.Action) -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { onAction(.bold) }) {
                Image(systemName: "bold")
            }.help("Bold")
            Button(action: { onAction(.italic) }) {
                Image(systemName: "italic")
            }.help("Italic")
            Button(action: { onAction(.underline) }) {
                Image(systemName: "underline")
            }.help("Underline")
            Divider().frame(height: 20)
            Button(action: { onAction(.font) }) {
                Image(systemName: "textformat")
            }.help("Font")
            Button(action: { onAction(.size) }) {
                Image(systemName: "textformat.size")
            }.help("Font Size")
            Divider().frame(height: 20)
            Button(action: { onAction(.markdownImport) }) {
                Image(systemName: "arrow.down.doc")
            }.help("Import Markdown")
            Button(action: { onAction(.markdownExport) }) {
                Image(systemName: "arrow.up.doc")
            }.help("Export Markdown")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
