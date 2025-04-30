import Foundation

class PreMeetingBriefService {
    static func generateBrief(for person: Person, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Use the same context logic as the main chatbot, filtered for this person
        let context = PreMeetingBriefContextHelper.generateContext(for: person)
        let prompt = """
You are an executive assistant preparing a pre-meeting brief. Your job is to help the user engage with this person confidently by surfacing:
- Key personal details or preferences shared in past conversations
- Trends or changes in topics over time
- Any agreed tasks, deadlines, or follow-ups
- Recent wins, challenges, or important events
- Anything actionable or worth mentioning for the next meeting

Use the provided context to be specific and actionable. Highlight details that would help the user build rapport and recall important facts. If any information is missing, state so.

Pre-Meeting Brief:
"""
        Task {
            do {
                let response = try await AIService.shared.sendMessage(prompt, context: context)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
