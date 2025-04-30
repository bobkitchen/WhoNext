import Foundation

struct PreMeetingBriefContextHelper {
    static func generateContext(for person: Person) -> String {
        var context = "Pre-Meeting Brief Context for: \(person.name ?? "Unknown")\n\n"
        let role = person.role ?? "Unknown"
        let isDirectReport = person.isDirectReport
        let timezone = person.timezone ?? "Unknown"
        let scheduledDate = person.scheduledConversationDate
        let conversations = person.conversations as? Set<Conversation> ?? []
        
        context += "Role: \(role)\n"
        context += "Direct Report: \(isDirectReport)\n"
        context += "Timezone: \(timezone)\n"
        if let scheduledDate = scheduledDate {
            context += "Next Scheduled Conversation: \(scheduledDate.formatted())\n"
        }
        context += "Number of Past Conversations: \(conversations.count)\n"
        
        if !conversations.isEmpty {
            context += "All Conversations:\n"
            let sortedConversations = conversations.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            for conversation in sortedConversations {
                if let date = conversation.date {
                    context += "- Date: \(date.formatted())\n"
                }
                if let summary = conversation.summary, !summary.isEmpty {
                    context += "  Summary: \(summary)\n"
                }
                if let notes = conversation.notes, !notes.isEmpty {
                    context += "  Notes: \(notes)\n"
                }
            }
            context += "\n"
        }
        return context
    }
}
