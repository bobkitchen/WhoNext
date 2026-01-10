import SwiftUI
import AppKit

// MARK: - Active Text View Tracker
/// Tracks the currently active/focused notes text view for formatting operations
/// This solves the problem of toolbar buttons stealing focus from the text view
class ActiveNotesTextViewTracker {
    static let shared = ActiveNotesTextViewTracker()

    /// The most recently focused notes text view
    weak var activeTextView: NSTextView?

    /// The selected range at the time focus was lost (for restoring)
    var lastSelectedRange: NSRange = NSRange(location: 0, length: 0)

    private init() {}

    /// Call this when a notes text view becomes active
    func setActive(_ textView: NSTextView) {
        activeTextView = textView
        lastSelectedRange = textView.selectedRange()
        print("📝 NotesTracker: Text view registered, selection: \(lastSelectedRange)")
    }

    /// Call this to save the selection before focus is lost
    func saveSelection() {
        if let textView = activeTextView {
            lastSelectedRange = textView.selectedRange()
            print("📝 NotesTracker: Saved selection before focus loss: \(lastSelectedRange)")
        }
    }

    /// Update the selection (called when selection changes while active)
    func updateSelection(_ range: NSRange) {
        lastSelectedRange = range
    }

    /// Apply formatting to the active text view
    func applyBold() {
        print("📝 NotesTracker: applyBold called")
        applyFontTrait(.boldFontMask)
    }

    func applyItalic() {
        print("📝 NotesTracker: applyItalic called")
        applyFontTrait(.italicFontMask)
    }

    func applyUnderline() {
        print("📝 NotesTracker: applyUnderline called, activeTextView: \(activeTextView != nil), selection: \(lastSelectedRange)")
        guard let textView = activeTextView,
              let textStorage = textView.textStorage else {
            print("📝 NotesTracker: No active text view!")
            return
        }

        let selectedRange = lastSelectedRange
        guard selectedRange.length > 0 else {
            print("📝 NotesTracker: No text selected (selection length is 0)")
            return
        }
        guard selectedRange.location + selectedRange.length <= textStorage.length else {
            print("📝 NotesTracker: Selection out of bounds")
            return
        }

        textStorage.beginEditing()

        var hasUnderline = false
        textStorage.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 {
                hasUnderline = true
            }
        }

        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: selectedRange)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
        }

        textStorage.endEditing()
        print("📝 NotesTracker: Underline applied successfully")

        // Restore focus and selection
        restoreFocus()
    }

    func applyHighlight() {
        print("📝 NotesTracker: applyHighlight called")
        guard let textView = activeTextView,
              let textStorage = textView.textStorage else {
            print("📝 NotesTracker: No active text view!")
            return
        }

        let selectedRange = lastSelectedRange
        guard selectedRange.length > 0 else {
            print("📝 NotesTracker: No text selected (selection length is 0)")
            return
        }
        guard selectedRange.location + selectedRange.length <= textStorage.length else {
            print("📝 NotesTracker: Selection out of bounds")
            return
        }

        textStorage.beginEditing()

        var hasHighlight = false
        textStorage.enumerateAttribute(.backgroundColor, in: selectedRange, options: []) { value, _, _ in
            if value != nil {
                hasHighlight = true
            }
        }

        if hasHighlight {
            textStorage.removeAttribute(.backgroundColor, range: selectedRange)
        } else {
            textStorage.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.4), range: selectedRange)
        }

        textStorage.endEditing()
        print("📝 NotesTracker: Highlight applied successfully")

        restoreFocus()
    }

    func insertBulletList() {
        print("📝 NotesTracker: insertBulletList called")
        guard let textView = activeTextView else {
            print("📝 NotesTracker: No active text view!")
            return
        }
        restoreFocus()
        textView.insertText("• ", replacementRange: NSRange(location: lastSelectedRange.location, length: 0))
    }

    func insertNumberedList() {
        print("📝 NotesTracker: insertNumberedList called")
        guard let textView = activeTextView else {
            print("📝 NotesTracker: No active text view!")
            return
        }
        restoreFocus()
        textView.insertText("1. ", replacementRange: NSRange(location: lastSelectedRange.location, length: 0))
    }

    private func applyFontTrait(_ trait: NSFontTraitMask) {
        let traitName = trait == .boldFontMask ? "Bold" : "Italic"
        print("📝 NotesTracker: applyFontTrait(\(traitName)) called, activeTextView: \(activeTextView != nil), selection: \(lastSelectedRange)")

        guard let textView = activeTextView,
              let textStorage = textView.textStorage else {
            print("📝 NotesTracker: No active text view!")
            return
        }

        let selectedRange = lastSelectedRange
        guard selectedRange.length > 0 else {
            print("📝 NotesTracker: No text selected (selection length is 0)")
            return
        }
        guard selectedRange.location + selectedRange.length <= textStorage.length else {
            print("📝 NotesTracker: Selection out of bounds (range: \(selectedRange), text length: \(textStorage.length))")
            return
        }

        textStorage.beginEditing()

        textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
            guard let currentFont = value as? NSFont else {
                print("📝 NotesTracker: No font attribute found at range \(range)")
                return
            }

            let descriptor = currentFont.fontDescriptor
            let hasTrait = trait == .boldFontMask
                ? descriptor.symbolicTraits.contains(.bold)
                : descriptor.symbolicTraits.contains(.italic)

            let newFont: NSFont
            if hasTrait {
                newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: trait)
            } else {
                newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
            }
            textStorage.addAttribute(.font, value: newFont, range: range)
            print("📝 NotesTracker: Applied \(traitName) to range \(range)")
        }

        textStorage.endEditing()

        restoreFocus()
    }

    private func restoreFocus() {
        guard let textView = activeTextView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(lastSelectedRange)
        print("📝 NotesTracker: Restored focus and selection to \(lastSelectedRange)")
    }
}

// MARK: - Rich Text Editor

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var isEditable: Bool = true
    var onAction: ((RichTextEditor.Action) -> Void)? = nil
    @Binding var isFocused: Bool

    enum Action {
        case bold, italic, underline, font, size, markdownImport, markdownExport
        case bulletList, numberedList, highlight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NotesTextView()
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

        // Enable spell checking and autocorrect
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isGrammarCheckingEnabled = true

        // Additional settings for better autocorrect
        textView.isAutomaticTextCompletionEnabled = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.smartInsertDeleteEnabled = true

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

    // MARK: - Public Formatting Methods

    /// Apply formatting action to the text view
    func applyAction(_ action: Action, coordinator: Coordinator) {
        coordinator.applyFormatting(action)
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

        // MARK: - Formatting Methods

        func applyFormatting(_ action: RichTextEditor.Action) {
            guard let textView = textView else { return }

            switch action {
            case .bold:
                applyBold()
            case .italic:
                applyItalic()
            case .underline:
                applyUnderline()
            case .highlight:
                applyHighlight()
            case .bulletList:
                insertBulletList()
            case .numberedList:
                insertNumberedList()
            default:
                break
            }

            // Update binding after formatting
            parent.text = textView.attributedString()
        }

        private func applyBold() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            textStorage.beginEditing()

            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                guard let currentFont = value as? NSFont else { return }

                let newFont: NSFont
                if currentFont.fontDescriptor.symbolicTraits.contains(.bold) {
                    // Remove bold
                    newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .boldFontMask)
                } else {
                    // Add bold
                    newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: range)
            }

            textStorage.endEditing()
        }

        private func applyItalic() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            textStorage.beginEditing()

            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                guard let currentFont = value as? NSFont else { return }

                let newFont: NSFont
                if currentFont.fontDescriptor.symbolicTraits.contains(.italic) {
                    // Remove italic
                    newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
                } else {
                    // Add italic
                    newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                }
                textStorage.addAttribute(.font, value: newFont, range: range)
            }

            textStorage.endEditing()
        }

        private func applyUnderline() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            textStorage.beginEditing()

            // Check if underline is already applied
            var hasUnderline = false
            textStorage.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    hasUnderline = true
                }
            }

            if hasUnderline {
                textStorage.removeAttribute(.underlineStyle, range: selectedRange)
            } else {
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }

            textStorage.endEditing()
        }

        private func applyHighlight() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            textStorage.beginEditing()

            // Check if highlight is already applied
            var hasHighlight = false
            textStorage.enumerateAttribute(.backgroundColor, in: selectedRange, options: []) { value, _, _ in
                if value != nil {
                    hasHighlight = true
                }
            }

            if hasHighlight {
                textStorage.removeAttribute(.backgroundColor, range: selectedRange)
            } else {
                textStorage.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.4), range: selectedRange)
            }

            textStorage.endEditing()
        }

        private func insertBulletList() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange()
            let insertLocation = selectedRange.location

            // Insert bullet point at cursor or start of selection
            let bulletText = "• "
            textView.insertText(bulletText, replacementRange: NSRange(location: insertLocation, length: 0))
        }

        private func insertNumberedList() {
            guard let textView = textView else { return }

            let selectedRange = textView.selectedRange()
            let insertLocation = selectedRange.location

            // Insert numbered item at cursor
            let numberText = "1. "
            textView.insertText(numberText, replacementRange: NSRange(location: insertLocation, length: 0))
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

// MARK: - Notes Text View
/// Custom NSTextView subclass that registers itself with ActiveNotesTextViewTracker
/// This allows toolbar buttons to find the text view even when they steal focus
class NotesTextView: NSTextView {

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        print("📝 NotesTextView: becomeFirstResponder called, result: \(result)")
        if result {
            // Register as the active notes text view
            ActiveNotesTextViewTracker.shared.setActive(self)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        print("📝 NotesTextView: resignFirstResponder called")
        // Save selection before losing focus
        ActiveNotesTextViewTracker.shared.saveSelection()
        return super.resignFirstResponder()
    }

    // Override mouseDown to ensure we're tracking when user clicks in text view
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Ensure we're registered and selection is up to date
        if self.window?.firstResponder === self {
            ActiveNotesTextViewTracker.shared.setActive(self)
        }
    }

    // Track selection changes via NSTextViewDelegate method
    override func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        let result = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        // Update tracker when selection changes
        if self === ActiveNotesTextViewTracker.shared.activeTextView {
            ActiveNotesTextViewTracker.shared.updateSelection(result)
        }
        return result
    }

    // Track selection changes to keep the tracker updated
    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        if self === ActiveNotesTextViewTracker.shared.activeTextView {
            ActiveNotesTextViewTracker.shared.updateSelection(charRange)
        }
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag && self === ActiveNotesTextViewTracker.shared.activeTextView {
            ActiveNotesTextViewTracker.shared.updateSelection(charRange)
        }
    }
}
