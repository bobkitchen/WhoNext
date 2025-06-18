import Foundation

class PreMeetingBriefService {
    static func generateBrief(for person: Person, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Use the same context logic as the main chatbot, filtered for this person
        let context = PreMeetingBriefContextHelper.generateContext(for: person)
        
        // Get the custom prompt from AppStorage
        let customPrompt = UserDefaults.standard.string(forKey: "customPreMeetingPrompt") ?? """
You are an executive assistant preparing a comprehensive pre-meeting intelligence brief. Analyze the conversation history and generate actionable insights to help the user engage confidently and build stronger relationships.

## Required Analysis Sections:

**🎯 MEETING FOCUS**
- Primary topics likely to be discussed based on recent patterns
- Key decisions or follow-ups pending from previous conversations
- Strategic priorities this person is currently focused on

**🔍 RELATIONSHIP INTELLIGENCE** 
- Communication style and preferences observed
- Working relationship trajectory and current dynamic
- Personal interests, motivations, or concerns mentioned
- Trust level and rapport-building opportunities

**⚡ ACTIONABLE INSIGHTS**
- Specific tasks, commitments, or deadlines to reference
- Wins, achievements, or positive developments to acknowledge  
- Challenges, concerns, or support needs to address
- Conversation starters that demonstrate you remember past discussions

**📈 PATTERNS & TRENDS**
- Evolution of topics or priorities over time
- Meeting frequency patterns and optimal timing
- Engagement levels and conversation quality trends
- Any recurring themes or persistent issues

**🎪 STRATEGIC RECOMMENDATIONS**
- Key talking points to strengthen the relationship
- Questions to ask that show engagement and care
- Potential challenges to navigate carefully
- Follow-up actions to propose or discuss

## Output Guidelines:
- Be specific with dates, quotes, and concrete details
- Prioritize recent conversations but reference historical context
- Include both professional and personal rapport-building elements
- Highlight gaps where information is missing or unclear
- Format with clear headers and bullet points for easy scanning

Generate a comprehensive brief that enables confident, relationship-building engagement:
"""
        
        Task {
            do {
                let response = try await AIService.shared.sendMessage(customPrompt, context: context)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
