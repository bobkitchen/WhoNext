import SwiftUI

struct MarkdownText: View {
    let markdown: String
    
    var body: some View {
        if let attributedString = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            Text(attributedString)
                .textSelection(.enabled)
        } else {
            // Fallback to basic markdown rendering
            Text(markdown)
                .textSelection(.enabled)
        }
    }
}

// Alternative implementation using LocalizedStringKey
struct MarkdownTextAlternative: View {
    let markdown: String
    
    var body: some View {
        Text(LocalizedStringKey(markdown))
            .textSelection(.enabled)
    }
}

// Preview helper
struct MarkdownText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Using AttributedString:")
                .font(.headline)
            MarkdownText(markdown: """
            # Heading
            
            This is **bold** and this is *italic*.
            
            - List item 1
            - List item 2
            
            [Link to Apple](https://apple.com)
            
            `inline code`
            """)
            
            Divider()
            
            Text("Using LocalizedStringKey:")
                .font(.headline)
            MarkdownTextAlternative(markdown: """
            # Heading
            
            This is **bold** and this is *italic*.
            
            - List item 1
            - List item 2
            
            [Link to Apple](https://apple.com)
            
            `inline code`
            """)
        }
        .padding()
    }
}
