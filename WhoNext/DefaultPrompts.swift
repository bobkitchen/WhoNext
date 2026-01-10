import Foundation

/// Default AI prompts and email templates used by the app
/// Users can customize these, but can always restore to these defaults
enum DefaultPrompts {

    // MARK: - Pre-Meeting Brief

    static let preMeetingBrief = """
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

    // MARK: - Summarization

    static let summarization = """
You are an executive assistant creating comprehensive meeting minutes. Generate detailed, actionable meeting minutes.

Format your response using markdown with ## for main sections and - for bullet points:

## Meeting Overview
- Meeting purpose and context
- Key themes and overall tone
- Primary objectives discussed

## Discussion Details
- Main points raised by each participant
- Key decisions made and rationale
- Areas of agreement and disagreement
- Important insights or revelations
- Questions raised and answers provided

## Action Items & Follow-ups
- Specific tasks assigned with owners
- Deadlines and timelines mentioned
- Next steps and follow-up meetings
- Dependencies and blockers identified

## Outcomes & Conclusions
- Final decisions reached
- Issues resolved or escalated
- Commitments made by participants
- Success metrics or goals established

## Additional Notes
- Context for future reference
- Relationship dynamics observed
- Support needs identified
- Risk factors or concerns noted
- Strengths and positive developments

Format the output in clear, professional meeting minutes suitable for distribution and follow-up preparation.
"""

    // MARK: - Email Templates

    static let emailSubject = "1:1 - {name} + BK"

    static let emailBody = """
Hi {firstName},

I wanted to follow up on our conversation and see how things are going.

Would you have time for a quick chat this week?

Best regards
"""

    // MARK: - Helper Methods

    /// Check if a prompt has been customized from the default
    static func isCustomized(_ current: String, type: PromptType) -> Bool {
        switch type {
        case .preMeetingBrief:
            return current != preMeetingBrief
        case .summarization:
            return current != summarization
        case .emailSubject:
            return current != emailSubject
        case .emailBody:
            return current != emailBody
        }
    }

    /// Get the default prompt for a given type
    static func getDefault(for type: PromptType) -> String {
        switch type {
        case .preMeetingBrief:
            return preMeetingBrief
        case .summarization:
            return summarization
        case .emailSubject:
            return emailSubject
        case .emailBody:
            return emailBody
        }
    }

    enum PromptType {
        case preMeetingBrief
        case summarization
        case emailSubject
        case emailBody
    }
}
