import SwiftUI

struct MarkdownView: View {
    let markdown: String
    
    var body: some View {
        // Parse and render markdown manually
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdownLines(markdown), id: \.self) { line in
                renderLine(line)
            }
        }
        .textSelection(.enabled)
    }
    
    private func parseMarkdownLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }
    
    @ViewBuilder
    private func renderLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty {
            Text(" ") // Empty line for spacing
                .font(.body)
        } else if trimmed.hasPrefix("# ") {
            Text(trimmed.dropFirst(2))
                .font(.title)
                .fontWeight(.bold)
        } else if trimmed.hasPrefix("## ") {
            Text(trimmed.dropFirst(3))
                .font(.title2)
                .fontWeight(.semibold)
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.dropFirst(4))
                .font(.title3)
                .fontWeight(.medium)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)
                renderFormattedText(String(trimmed.dropFirst(2)))
            }
        } else if let numberMatch = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            HStack(alignment: .top, spacing: 8) {
                Text(trimmed[numberMatch].trimmingCharacters(in: .whitespaces))
                    .font(.body)
                renderFormattedText(String(trimmed[numberMatch.upperBound...]))
            }
        } else {
            renderFormattedText(trimmed)
        }
    }
    
    private func renderFormattedText(_ text: String) -> Text {
        var result = Text("")
        var currentText = ""
        var isBold = false
        var isItalic = false
        var isCode = false
        
        var index = text.startIndex
        
        while index < text.endIndex {
            let remaining = String(text[index...])
            
            // Check for code blocks
            if remaining.hasPrefix("`") {
                if !currentText.isEmpty {
                    result = result + formatText(currentText, bold: isBold, italic: isItalic, code: isCode)
                    currentText = ""
                }
                isCode.toggle()
                index = text.index(after: index)
                continue
            }
            
            // Check for bold
            if remaining.hasPrefix("**") || remaining.hasPrefix("__") {
                if !currentText.isEmpty {
                    result = result + formatText(currentText, bold: isBold, italic: isItalic, code: isCode)
                    currentText = ""
                }
                isBold.toggle()
                index = text.index(index, offsetBy: 2)
                continue
            }
            
            // Check for italic
            if remaining.hasPrefix("*") || remaining.hasPrefix("_") {
                // Make sure it's not part of bold
                if index > text.startIndex {
                    let prevIndex = text.index(before: index)
                    if text[prevIndex] == "*" || text[prevIndex] == "_" {
                        currentText.append(text[index])
                        index = text.index(after: index)
                        continue
                    }
                }
                
                if !currentText.isEmpty {
                    result = result + formatText(currentText, bold: isBold, italic: isItalic, code: isCode)
                    currentText = ""
                }
                isItalic.toggle()
                index = text.index(after: index)
                continue
            }
            
            currentText.append(text[index])
            index = text.index(after: index)
        }
        
        if !currentText.isEmpty {
            result = result + formatText(currentText, bold: isBold, italic: isItalic, code: isCode)
        }
        
        return result
    }
    
    private func formatText(_ text: String, bold: Bool, italic: Bool, code: Bool) -> Text {
        var formatted = Text(text)
        
        if code {
            formatted = formatted
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.blue)
        } else {
            if bold {
                formatted = formatted.fontWeight(.bold)
            }
            if italic {
                formatted = formatted.italic()
            }
        }
        
        return formatted
    }
}

struct MarkdownView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            MarkdownView(markdown: """
            # Heading 1
            ## Heading 2
            ### Heading 3
            
            This is **bold text** and this is *italic text*.
            
            You can also use __bold__ and _italic_ with underscores.
            
            - List item 1
            - List item 2 with **bold**
            * List item 3 with *italic*
            
            1. Numbered item
            2. Another numbered item
            
            Here is some `inline code` in the text.
            
            Mixed formatting: **bold and *italic* together**
            """)
            .padding()
        }
    }
}
