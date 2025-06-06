import Foundation

struct ConversationTitleFormatter {
    
    // Option 1: Date-based with topic summary
    static func dateBasedTitle(for conversation: Conversation) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let dateString = dateFormatter.string(from: conversation.date ?? Date())
        
        if let notes = conversation.notes, !notes.isEmpty {
            let topic = extractFirstTopic(from: notes)
            return "\(dateString) - \(topic)"
        }
        
        return dateString
    }
    
    // Option 2: Topic-focused with date
    static func topicFocusedTitle(for conversation: Conversation) -> String {
        if let notes = conversation.notes, !notes.isEmpty {
            let topic = extractFirstTopic(from: notes)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: conversation.date ?? Date())
            return "\(topic) (\(dateString))"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        return "Conversation on \(dateFormatter.string(from: conversation.date ?? Date()))"
    }
    
    // Option 3: Smart title based on content
    static func smartTitle(for conversation: Conversation) -> String {
        guard let notes = conversation.notes, !notes.isEmpty else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM d, yyyy"
            return dateFormatter.string(from: conversation.date ?? Date())
        }
        
        // Extract key topics or action items
        let keyPhrases = extractKeyPhrases(from: notes)
        
        if !keyPhrases.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: conversation.date ?? Date())
            return "\(keyPhrases.joined(separator: ", ")) • \(dateString)"
        }
        
        return extractFirstTopic(from: notes)
    }
    
    // Helper function to extract the first meaningful topic
    private static func extractFirstTopic(from notes: String) -> String {
        // Strip markdown
        var cleaned = notes
        cleaned = cleaned.replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\*{1,2}([^\*]+)\*{1,2}"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"_{1,2}([^_]+)_{1,2}"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[\s]*[-\*]\s+"#, with: "", options: [.regularExpression, .anchored])
        
        let lines = cleaned.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if let firstLine = lines.first {
            let maxLength = 50
            if firstLine.count > maxLength {
                return String(firstLine.prefix(maxLength)) + "..."
            }
            return String(firstLine)
        }
        
        return "Notes"
    }
    
    // Extract key phrases like action items, decisions, or important topics
    private static func extractKeyPhrases(from notes: String) -> [String] {
        var phrases: [String] = []
        
        // Look for action items
        if notes.lowercased().contains("action:") || notes.lowercased().contains("todo:") {
            phrases.append("Action Items")
        }
        
        // Look for decisions
        if notes.lowercased().contains("decided:") || notes.lowercased().contains("decision:") {
            phrases.append("Decisions")
        }
        
        // Look for follow-ups
        if notes.lowercased().contains("follow up") || notes.lowercased().contains("follow-up") {
            phrases.append("Follow-up")
        }
        
        // Look for key topics (you can expand this)
        if notes.lowercased().contains("project") {
            phrases.append("Project Update")
        }
        
        if notes.lowercased().contains("performance") || notes.lowercased().contains("review") {
            phrases.append("Performance")
        }
        
        if notes.lowercased().contains("goal") || notes.lowercased().contains("objective") {
            phrases.append("Goals")
        }
        
        return Array(phrases.prefix(2)) // Return max 2 key phrases
    }
}
