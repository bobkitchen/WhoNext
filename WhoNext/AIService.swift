import Foundation

class AIService {
    static let shared = AIService()
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Get API key from environment variable or configuration
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            self.apiKey = key
        } else {
            // Fallback to UserDefaults for development
            self.apiKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey") ?? ""
        }
    }
    
    func sendMessage(_ message: String, context: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: String]] = [
            ["role": "system", "content": """
            You are a helpful assistant focused on relationship management and conversation tracking. \
            You have access to data about people, their roles, scheduled conversations, and conversation history. \
            When answering questions, you MUST use the provided context to give specific, data-driven responses. \
            Always reference specific people, dates, and conversations from the context in your responses. \
            If asked about team members, conversations, or schedules, look at the actual data provided and mention specific details. \
            If you don't have certain information in the context, clearly state what data is missing.
            """]
        ]
        
        if let context = context {
            // First provide the context as a system message
            messages.append(["role": "system", "content": context])
            // Then add the user's actual question
            messages.append(["role": "user", "content": message])
        } else {
            messages.append(["role": "user", "content": message])
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4-turbo-preview",
            "messages": messages,
            "max_tokens": 1000,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return decodedResponse.choices.first?.message.content ?? "No response content."
        } else {
            let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorResponse?["error"] as? [String: Any] ?? [:]
            throw AIError.apiError(message: errorMessage["message"] as? String ?? "Unknown API error")
        }
    }
}

enum AIError: Error {
    case missingAPIKey
    case invalidResponse
    case apiError(message: String)
    
    var localizedDescription: String {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Please set it in your environment variables or app settings."
        case .invalidResponse:
            return "Received an invalid response from the API."
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
} 