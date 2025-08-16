import SwiftUI

struct PreMeetingBriefWindow: View {
    let personName: String
    let briefContent: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pre-Meeting Brief")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(personName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Copy button
                    Button(action: {
                        copyToClipboard(briefContent)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12))
                            Text("Copy")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
            
            // Brief content with improved markdown rendering
            ScrollView {
                ProfileContentView(content: briefContent)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // Simplified markdown processing
    private func processMarkdownContent(_ content: String) -> [String] {
        return content.components(separatedBy: .newlines)
    }
    
    @ViewBuilder
    private func renderLine(_ line: String, index: Int) -> some View {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        if trimmedLine.hasPrefix("##") {
            // Header with ##
            let headerText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            Text(headerText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 8)
        } else if trimmedLine.hasPrefix("**") && trimmedLine.hasSuffix("**") && trimmedLine.count > 4 {
            // Header with **text**
            let headerText = String(trimmedLine.dropFirst(2).dropLast(2))
            Text(headerText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 8)
        } else if trimmedLine.hasPrefix("*") && !trimmedLine.hasPrefix("**") {
            // Bullet point
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
                
                renderInlineMarkdown(String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        } else if !trimmedLine.isEmpty {
            // Regular text
            renderInlineMarkdown(line)
                .font(.system(size: 14))
                .lineSpacing(2)
                .textSelection(.enabled)
        } else {
            // Empty line
            Text(" ")
                .font(.system(size: 4))
        }
    }
    
    // Simple inline markdown rendering using Text with manual parsing
    private func renderInlineMarkdown(_ text: String) -> Text {
        // Simple approach: split on ** and alternate between normal and bold
        let parts = text.components(separatedBy: "**")
        
        // Use reduce to build the text properly
        return parts.enumerated().reduce(Text("")) { result, element in
            let (index, part) = element
            let partText = index % 2 == 0 ? Text(part) : Text(part).fontWeight(.bold)
            return result + partText
        }
    }
}

#Preview {
    PreMeetingBriefWindow(
        personName: "John Doe",
        briefContent: """
        **Meeting Overview:**
        This is a sample pre-meeting brief with detailed information about the upcoming conversation.
        
        **Key Points:**
        * Previous conversation highlights
        * Action items from last meeting
        * Current project status
        
        **Discussion Topics:**
        * Project timeline review
        * Budget considerations
        * Next steps planning
        """,
        onClose: {}
    )
}
