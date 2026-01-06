import Foundation

struct PreMeetingBriefContextHelper {
    static func generateContext(for person: Person) -> String {
        var context = "=== PRE-MEETING INTELLIGENCE BRIEF ===\n"
        context += "Person: \(person.name ?? "Unknown")\n\n"
        
        // Core Profile Information
        context += "## PERSON PROFILE\n"
        let role = person.role ?? "Unknown"
        let isDirectReport = person.isDirectReport
        let timezone = person.timezone ?? "Unknown"
        let scheduledDate = person.scheduledConversationDate
        let conversations = person.conversations as? Set<Conversation> ?? []
        
        context += "Role: \(role)\n"
        context += "Direct Report: \(isDirectReport ? "Yes" : "No")\n"
        context += "Timezone: \(timezone)\n"
        if let scheduledDate = scheduledDate {
            context += "Next Scheduled Conversation: \(scheduledDate.formatted())\n"
        }
        context += "Total Conversation History: \(conversations.count) conversations\n\n"
        
        // Enhanced conversation analysis
        if !conversations.isEmpty {
            let sortedConversations = conversations.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            
            // Recent conversation activity
            context += "## CONVERSATION TIMELINE & PATTERNS\n"
            let now = Date()
            let recent = sortedConversations.filter { 
                guard let date = $0.date else { return false }
                return now.timeIntervalSince(date) < 30 * 24 * 3600 // Last 30 days
            }
            let older = sortedConversations.filter {
                guard let date = $0.date else { return false }
                return now.timeIntervalSince(date) >= 30 * 24 * 3600
            }
            
            context += "Recent Conversations (Last 30 days): \(recent.count)\n"
            context += "Historical Conversations (Older): \(older.count)\n"
            
            // Meeting frequency analysis
            if conversations.count >= 2 {
                let dates = sortedConversations.compactMap { $0.date }.sorted(by: >)
                if dates.count >= 2 {
                    let daysBetween = Calendar.current.dateComponents([.day], from: dates.last!, to: dates.first!).day ?? 0
                    let averageFrequency = daysBetween / max(1, dates.count - 1)
                    context += "Average Meeting Frequency: Every \(averageFrequency) days\n"
                }
            }
            
            // Last meeting context
            if let lastConversation = sortedConversations.first,
               let lastDate = lastConversation.date {
                let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: now).day ?? 0
                context += "Last Meeting: \(daysSince) days ago (\(lastDate.formatted()))\n"
            }
            context += "\n"
            
            // Detailed conversation history - OPTIMIZED: Limit to 10 most recent
            context += "## DETAILED CONVERSATION HISTORY\n"
            context += "(Most recent 10 conversations - ordered by most recent first)\n\n"

            // Limit to 10 conversations for performance
            let limitedConversations = sortedConversations.prefix(10)

            for (index, conversation) in limitedConversations.enumerated() {
                let isRecent = index < 5 // First 5 get full detail
                let prefix = isRecent ? "🔥 RECENT" : "📋 HISTORICAL"

                if let date = conversation.date {
                    let daysSince = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
                    let timeContext = daysSince == 0 ? "Today" : daysSince == 1 ? "Yesterday" : "\(daysSince) days ago"
                    context += "\(prefix) - \(date.formatted(date: .abbreviated, time: .omitted)) (\(timeContext))\n"
                }

                if isRecent {
                    // Full detail for recent 5 conversations
                    if let summary = conversation.summary, !summary.isEmpty {
                        context += "SUMMARY: \(summary)\n"
                    }

                    if let notes = conversation.notes, !notes.isEmpty {
                        context += "NOTES: \(notes)\n"
                    }

                    if let sentiment = conversation.sentimentLabel, !sentiment.isEmpty {
                        context += "SENTIMENT: \(sentiment)"
                        if conversation.sentimentScore > 0 {
                            context += " (\(Int(conversation.sentimentScore))%)"
                        }
                        context += "\n"
                    }

                    if let topics = conversation.keyTopics, !topics.isEmpty {
                        context += "KEY TOPICS: \(topics.joined(separator: ", "))\n"
                    }
                } else {
                    // Summary only for older conversations (6-10)
                    if let summary = conversation.summary, !summary.isEmpty {
                        // Truncate summary to first 200 chars for older conversations
                        let truncated = summary.count > 200 ? String(summary.prefix(200)) + "..." : summary
                        context += "SUMMARY: \(truncated)\n"
                    }

                    if let topics = conversation.keyTopics, !topics.isEmpty {
                        context += "TOPICS: \(topics.prefix(3).joined(separator: ", "))\n"
                    }
                }

                context += "\n" + String(repeating: "-", count: 50) + "\n\n"
            }

            // Add summary for conversations beyond the 10 shown
            if sortedConversations.count > 10 {
                context += "📊 ADDITIONAL HISTORICAL DATA\n"
                context += "Total older conversations: \(sortedConversations.count - 10)\n"
                context += "(Not shown to optimize brief generation speed)\n\n"
            }
            
            // Intelligence analysis section
            context += "## INTELLIGENCE ANALYSIS PRIORITIES\n"
            context += "Focus your analysis on:\n"
            context += "1. RECENT PATTERNS: What themes emerge from the last 2-3 conversations?\n"
            context += "2. RELATIONSHIP TRAJECTORY: How has the working relationship evolved?\n"
            context += "3. PENDING ITEMS: Any unresolved tasks, commitments, or follow-ups?\n"
            context += "4. COMMUNICATION STYLE: How does this person prefer to communicate?\n"
            context += "5. CURRENT PRIORITIES: What are their main focus areas right now?\n"
            context += "6. SUPPORT NEEDS: Where might they need help or guidance?\n"
            context += "7. RAPPORT BUILDERS: What personal or professional interests can you reference?\n"
            context += "8. POTENTIAL CONCERNS: Any red flags or issues that need addressing?\n\n"
        } else {
            context += "## NO CONVERSATION HISTORY\n"
            context += "This appears to be a first meeting or no previous conversations are recorded.\n"
            context += "Focus on:\n"
            context += "- Introduction and relationship building\n"
            context += "- Understanding their role and current priorities\n"
            context += "- Establishing communication preferences\n"
            context += "- Setting expectations for future interactions\n\n"
        }
        
        return context
    }
}
