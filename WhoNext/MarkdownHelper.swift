import Foundation
import AppKit
import Down

struct MarkdownHelper {
    static func attributedString(from markdown: String) -> NSAttributedString {
        if let downAttributed = try? Down(markdownString: markdown).toAttributedString() {
            return downAttributed
        }
        return NSAttributedString(string: markdown)
    }

    static func markdownString(from attributedString: NSAttributedString) -> String {
        let range = NSRange(location: 0, length: attributedString.length)
        if let data = try? attributedString.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
           let html = String(data: data, encoding: .utf8) {
            return html
        }
        return attributedString.string
    }
}
