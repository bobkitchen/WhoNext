import Foundation
import CoreData

/// Centralized service for generating intelligent chat context across all chat interfaces
class ChatContextService {
    
    // MARK: - Context Generation Strategy
    enum ContextStrategy {
        case minimal           // Simple greetings
        case basic            // General queries
        case comprehensive    // Work history and person queries
        case targeted         // Specific person or topic queries
    }
    
    // MARK: - Query Type Detection
    private struct QueryDetection {
        static let casualPhrases = [
            "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
            "how are you", "what's up", "thanks", "thank you", "bye", "goodbye",
            "help", "how can you help"
        ]
        
        static let workHistoryKeywords = [
            "work", "job", "employ", "career", "experience", "msf", "microsoft",
            "company", "role", "position", "background", "linkedin", "resume"
        ]
        
        static let personQueryKeywords = [
            "who", "person", "people", "team", "member", "colleague", "report",
            "manager", "employee", "staff", "name", "contact"
        ]
        
        static let relationshipKeywords = [
            "relationship", "meeting", "conversation", "talk", "chat", "connect",
            "1:1", "one on one", "follow up", "schedule", "catch up"
        ]
        
        static let analyticsKeywords = [
            "how many", "count", "total", "list", "show me", "find", "search",
            "trend", "pattern", "analysis", "report", "summary"
        ]
    }
    
    // MARK: - Main Context Generation
    static func generateContext(for message: String, people: [Person], provider: HybridAIProvider = .openAI) -> String {
        let strategy = determineContextStrategy(for: message)
        
        print("🔍 [ChatContext] Strategy: \(strategy) for message: \(String(message.prefix(50)))...")
        
        switch strategy {
        case .minimal:
            return generateMinimalContext()
        case .basic:
            return generateBasicContext(peopleCount: people.count)
        case .comprehensive:
            return generateComprehensiveContext(for: message, people: people, provider: provider)
        case .targeted:
            return generateTargetedContext(for: message, people: people, provider: provider)
        }
    }
    
    // MARK: - Context Strategy Determination
    private static func determineContextStrategy(for message: String) -> ContextStrategy {
        let lowercased = message.lowercased()
        
        // Check for casual/greeting messages first
        if QueryDetection.casualPhrases.contains(where: { lowercased.contains($0) }) && message.count < 50 {
            return .minimal
        }
        
        // Check for work history queries
        if QueryDetection.workHistoryKeywords.contains(where: { lowercased.contains($0) }) {
            return .comprehensive
        }
        
        // Check for person-specific queries
        if QueryDetection.personQueryKeywords.contains(where: { lowercased.contains($0) }) {
            return .comprehensive
        }
        
        // Check for relationship/meeting queries
        if QueryDetection.relationshipKeywords.contains(where: { lowercased.contains($0) }) {
            return .targeted
        }
        
        // Check for analytics/reporting queries
        if QueryDetection.analyticsKeywords.contains(where: { lowercased.contains($0) }) {
            return .targeted
        }
        
        // Default to basic context for general queries
        return .basic
    }
    
    // MARK: - Context Generation Methods
    
    private static func generateMinimalContext() -> String {
        return """
        You are a helpful AI assistant for a team management app called WhoNext.
        
        Be friendly and concise in your responses. If the user asks about specific people or work information, let them know you can help with team management, relationship tracking, and networking insights.
        """
    }
    
    private static func generateBasicContext(peopleCount: Int) -> String {
        return """
        You are an AI assistant for WhoNext, a team management and relationship tracking app.
        
        The user currently has \(peopleCount) team members in their database. You can help with:
        - Team management insights
        - Relationship and conversation tracking
        - Meeting preparation and follow-ups
        - Professional networking recommendations
        
        For specific questions about people or work history, provide helpful guidance based on available information.
        """
    }
    
    private static func generateComprehensiveContext(for message: String, people: [Person], provider: HybridAIProvider) -> String {
        let isWorkHistoryQuery = QueryDetection.workHistoryKeywords.contains { message.lowercased().contains($0) }
        
        var context = """
        You are an AI assistant for WhoNext, a team management and relationship tracking app.
        
        TEAM MEMBERS AND RELATIONSHIPS:
        
        """
        
        var includedPeople = 0
        var contextSize = context.count
        let maxContextSize = getMaxContextSize(for: provider)
        
        // Sort people by relevance for the query
        let sortedPeople = prioritizePeople(people, for: message, isWorkHistoryQuery: isWorkHistoryQuery)
        
        for person in sortedPeople {
            let personContext = generatePersonContext(person: person, includeFullHistory: isWorkHistoryQuery)
            
            // Check if adding this person would exceed context limits
            if contextSize + personContext.count > maxContextSize {
                print("🔍 [ChatContext] Context limit reached, included \(includedPeople) people")
                break
            }
            
            // Skip people without relevant information for work history queries
            if isWorkHistoryQuery && (person.notes?.isEmpty ?? true) {
                continue
            }
            
            context += personContext
            includedPeople += 1
            contextSize += personContext.count
        }
        
        context += "\nTOTAL TEAM MEMBERS INCLUDED: \(includedPeople) of \(people.count)\n"
        
        if includedPeople < people.count {
            context += "(Some team members excluded to optimize context for your query)\n"
        }
        
        return context
    }
    
    private static func generateTargetedContext(for message: String, people: [Person], provider: HybridAIProvider) -> String {
        var context = """
        You are an AI assistant for WhoNext, a team management and relationship tracking app.
        
        TARGETED ANALYSIS FOR YOUR QUERY:
        
        """
        
        let maxContextSize = getMaxContextSize(for: provider)
        let targetedPeople = findRelevantPeople(for: message, in: people)
        
        var contextSize = context.count
        var includedPeople = 0
        
        for person in targetedPeople {
            let personContext = generatePersonContext(person: person, includeFullHistory: true, focused: true)
            
            if contextSize + personContext.count > maxContextSize {
                break
            }
            
            context += personContext
            includedPeople += 1
            contextSize += personContext.count
        }
        
        // Add summary statistics
        context += generateTeamSummary(people: people)
        
        return context
    }
    
    // MARK: - Helper Methods
    
    private static func prioritizePeople(_ people: [Person], for message: String, isWorkHistoryQuery: Bool) -> [Person] {
        return people.sorted { person1, person2 in
            // Prioritize people mentioned by name in the query
            let name1Mentioned = person1.name?.lowercased().contains(where: { message.lowercased().contains($0.lowercased()) }) ?? false
            let name2Mentioned = person2.name?.lowercased().contains(where: { message.lowercased().contains($0.lowercased()) }) ?? false
            
            if name1Mentioned != name2Mentioned {
                return name1Mentioned
            }
            
            // For work history queries, prioritize people with background notes
            if isWorkHistoryQuery {
                let has1Notes = !(person1.notes?.isEmpty ?? true)
                let has2Notes = !(person2.notes?.isEmpty ?? true)
                if has1Notes != has2Notes {
                    return has1Notes
                }
            }
            
            // Prioritize direct reports
            if person1.isDirectReport != person2.isDirectReport {
                return person1.isDirectReport
            }
            
            // Prioritize people with recent conversations
            let conversations1 = person1.conversations as? Set<Conversation> ?? []
            let conversations2 = person2.conversations as? Set<Conversation> ?? []
            
            let recent1 = conversations1.filter { 
                guard let date = $0.date else { return false }
                return Date().timeIntervalSince(date) < 30 * 24 * 3600 // 30 days
            }.count
            
            let recent2 = conversations2.filter {
                guard let date = $0.date else { return false }
                return Date().timeIntervalSince(date) < 30 * 24 * 3600 // 30 days
            }.count
            
            return recent1 > recent2
        }
    }
    
    private static func findRelevantPeople(for message: String, in people: [Person]) -> [Person] {
        let lowercased = message.lowercased()
        
        return people.filter { person in
            // Check if person is mentioned by name
            if let name = person.name, lowercased.contains(name.lowercased()) {
                return true
            }
            
            // Check if person's role is mentioned
            if let role = person.role, lowercased.contains(role.lowercased()) {
                return true
            }
            
            // Check for direct report queries
            if lowercased.contains("direct report") && person.isDirectReport {
                return true
            }
            
            // Check background notes for keyword matches
            if let notes = person.notes {
                let keywords = ["microsoft", "msf", "manager", "engineer", "director", "senior", "lead"]
                for keyword in keywords {
                    if lowercased.contains(keyword) && notes.lowercased().contains(keyword) {
                        return true
                    }
                }
            }
            
            return false
        }
    }
    
    private static func generatePersonContext(person: Person, includeFullHistory: Bool = false, focused: Bool = false) -> String {
        let name = person.name ?? "Unknown"
        let role = person.role ?? "Unknown"
        let isDirectReport = person.isDirectReport
        let timezone = person.timezone ?? "Unknown"
        let conversations = person.conversations as? Set<Conversation> ?? []
        
        var context = """
        
        PERSON: \(name)
        Role: \(role)
        Direct Report: \(isDirectReport ? "Yes" : "No")
        Timezone: \(timezone)
        """
        
        // Add background notes if available
        if let notes = person.notes, !notes.isEmpty {
            context += "\nBackground: \(notes)"
        }
        
        // Add scheduled conversation info
        if let scheduledDate = person.scheduledConversationDate {
            context += "\nNext Scheduled: \(scheduledDate.formatted())"
        }
        
        context += "\nConversation History: \(conversations.count) total conversations"
        
        // Add conversation details
        if !conversations.isEmpty {
            let sortedConversations = conversations.sorted { 
                ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            
            let limit = includeFullHistory ? (focused ? 5 : 3) : 2
            let recentConversations = Array(sortedConversations.prefix(limit))
            
            context += "\n\nRecent Conversations:"
            for conversation in recentConversations {
                if let date = conversation.date {
                    let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                    let timeContext = daysSince == 0 ? "Today" : daysSince == 1 ? "Yesterday" : "\(daysSince) days ago"
                    
                    context += "\n- \(date.formatted(date: .abbreviated, time: .omitted)) (\(timeContext))"
                    
                    if let summary = conversation.summary, !summary.isEmpty {
                        context += "\n  Summary: \(summary)"
                    }
                    
                    if let notes = conversation.notes, !notes.isEmpty {
                        context += "\n  Notes: \(notes)"
                    }
                    
                    // Add engagement metrics if available
                    if !(conversation.sentimentLabel?.isEmpty ?? true) {
                        context += "\n  Sentiment: \(conversation.sentimentLabel ?? "Unknown")"
                    }
                }
            }
        }
        
        context += "\n" + String(repeating: "-", count: 40)
        
        return context
    }
    
    private static func generateTeamSummary(people: [Person]) -> String {
        let directReports = people.filter { $0.isDirectReport }.count
        let totalConversations = people.reduce(0) { sum, person in
            sum + ((person.conversations as? Set<Conversation>)?.count ?? 0)
        }
        
        return """
        
        TEAM SUMMARY:
        Total Team Members: \(people.count)
        Direct Reports: \(directReports)
        Total Conversations: \(totalConversations)
        """
    }
    
    private static func getMaxContextSize(for provider: HybridAIProvider) -> Int {
        switch provider {
        case .appleIntelligence:
            return 120000 // 30k tokens * 4 chars per token
        case .openAI:
            return 400000 // 100k tokens * 4 chars per token (gpt-4o has large context)
        case .openRouter:
            return 120000 // Conservative estimate for various models
        case .none:
            return 40000  // Fallback
        }
    }
}

// MARK: - Context Optimization Extensions
extension ChatContextService {
    
    /// Optimizes context based on provider capabilities and query requirements
    static func optimizeContextForProvider(_ context: String, provider: HybridAIProvider) -> String {
        let maxSize = getMaxContextSize(for: provider)
        
        if context.count <= maxSize {
            return context
        }
        
        print("🔍 [ChatContext] Context too large (\(context.count) chars), optimizing for \(provider)")
        
        // Intelligent truncation preserving structure
        let lines = context.components(separatedBy: .newlines)
        var optimizedLines: [String] = []
        var currentSize = 0
        
        // Always preserve header and instructions
        let headerEnd = lines.firstIndex { $0.contains("TEAM MEMBERS") || $0.contains("TARGETED ANALYSIS") } ?? 5
        for i in 0..<min(headerEnd + 1, lines.count) {
            optimizedLines.append(lines[i])
            currentSize += lines[i].count + 1
        }
        
        // Add as much person data as possible
        for i in (headerEnd + 1)..<lines.count {
            if currentSize + lines[i].count + 1 > maxSize {
                break
            }
            optimizedLines.append(lines[i])
            currentSize += lines[i].count + 1
        }
        
        var optimized = optimizedLines.joined(separator: "\n")
        optimized += "\n\n[Context optimized for \(provider) - some details may be truncated]"
        
        return optimized
    }
}