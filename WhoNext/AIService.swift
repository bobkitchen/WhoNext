import Foundation

enum AIProvider: String, CaseIterable {
    case openai = "openai"
    case claude = "claude"
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        }
    }
}

struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var role: String
            var content: String
        }
        var index: Int
        var message: Message
        var finish_reason: String
    }
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [Choice]
    var usage: Usage
}

struct Usage: Decodable {
    var prompt_tokens: Int
    var completion_tokens: Int
    var total_tokens: Int
}

struct ClaudeResponse: Decodable {
    struct Content: Decodable {
        var type: String
        var text: String
    }
    var id: String
    var type: String
    var role: String
    var content: [Content]
    var model: String
    var stop_reason: String?
    var stop_sequence: String?
    var usage: ClaudeUsage
}

struct ClaudeUsage: Decodable {
    var input_tokens: Int
    var output_tokens: Int
}

class AIService {
    static let shared = AIService()
    
    private var currentProvider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
    }
    
    private var openAIApiKey: String {
        UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
    }
    
    private var claudeApiKey: String {
        UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
    }
    
    private var apiKey: String {
        switch currentProvider {
        case .openai: return openAIApiKey
        case .claude: return claudeApiKey
        }
    }
    
    init() { }
    
    func sendMessage(_ message: String, context: String? = nil) async throws -> String {
        switch currentProvider {
        case .openai:
            return try await sendMessageOpenAI(message, context: context)
        case .claude:
            return try await sendMessageClaude(message, context: context)
        }
    }
    
    private func sendMessageOpenAI(_ message: String, context: String? = nil) async throws -> String {
        guard !openAIApiKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        
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
            messages.append(["role": "system", "content": context])
        }
        
        messages.append(["role": "user", "content": message])
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
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
            let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
            throw AIError.apiError(message: errorMessage ?? "Unknown API error")
        }
    }
    
    private func sendMessageClaude(_ message: String, context: String? = nil) async throws -> String {
        guard !claudeApiKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        
        var messages: [[String: Any]] = []
        
        // Add context as a user message if provided
        if let context = context {
            messages.append([
                "role": "user",
                "content": "Context: \(context)"
            ])
            messages.append([
                "role": "assistant", 
                "content": "I understand the context. How can I help you?"
            ])
        }
        
        messages.append([
            "role": "user",
            "content": message
        ])
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeApiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1000,
            "system": """
            You are a helpful assistant focused on relationship management and conversation tracking. \
            You have access to data about people, their roles, scheduled conversations, and conversation history. \
            When answering questions, you MUST use the provided context to give specific, data-driven responses. \
            Always reference specific people, dates, and conversations from the context in your responses. \
            If asked about team members, conversations, or schedules, look at the actual data provided and mention specific details. \
            If you don't have certain information in the context, clearly state what data is missing.
            """,
            "messages": messages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decodedResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return decodedResponse.content.first?.text ?? "No response content."
        } else {
            let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
            throw AIError.apiError(message: errorMessage ?? "Unknown API error")
        }
    }
    
    func analyzeImageWithVision(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        switch currentProvider {
        case .openai:
            analyzeImageWithVisionOpenAI(imageData: imageData, prompt: prompt, completion: completion)
        case .claude:
            analyzeImageWithVisionClaude(imageData: imageData, prompt: prompt, completion: completion)
        }
    }
    
    private func analyzeImageWithVisionOpenAI(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        let visionURL = "https://api.openai.com/v1/chat/completions"
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(imageData)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 2000
        ]
        
        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            do {
                if httpResponse.statusCode == 200 {
                    let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    let content = decodedResponse.choices.first?.message.content ?? "No response content."
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func analyzeImageWithVisionClaude(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !claudeApiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        let visionURL = "https://api.anthropic.com/v1/messages"
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2000,
            "system": """
            You are a helpful assistant focused on relationship management and conversation tracking. \
            You have access to data about people, their roles, scheduled conversations, and conversation history. \
            When answering questions, you MUST use the provided context to give specific, data-driven responses. \
            Always reference specific people, dates, and conversations from the context in your responses. \
            If asked about team members, conversations, or schedules, look at the actual data provided and mention specific details. \
            If you don't have certain information in the context, clearly state what data is missing.
            """,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": imageData
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(claudeApiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            do {
                if httpResponse.statusCode == 200 {
                    let decodedResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
                    let content = decodedResponse.content.first?.text ?? "No response content."
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func analyzeMultipleImagesWithVision(imageDataArray: [String], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        switch currentProvider {
        case .openai:
            analyzeMultipleImagesWithVisionOpenAI(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        case .claude:
            analyzeMultipleImagesWithVisionClaude(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        }
    }
    
    private func analyzeMultipleImagesWithVisionOpenAI(imageDataArray: [String], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        print("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        print("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        let visionURL = "https://api.openai.com/v1/chat/completions"
        
        // Build content array with text prompt and multiple images
        var contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt
            ]
        ]
        
        // Add each image to the content array
        for imageData in imageDataArray {
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(imageData)"
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ],
            "max_tokens": 3000 // Increased for multiple images
        ]
        
        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            do {
                if httpResponse.statusCode == 200 {
                    let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    let content = decodedResponse.choices.first?.message.content ?? "No response content."
                    print("🔍 [AI] Multi-image analysis successful, response length: \(content.count) characters")
                    print("🔍 [AI] Response preview: \(String(content.prefix(200)))...")
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [AI] Multi-image analysis failed with status \(httpResponse.statusCode): \(errorMessage ?? "Unknown error")")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                print("❌ [AI] Multi-image analysis parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func analyzeMultipleImagesWithVisionClaude(imageDataArray: [String], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !claudeApiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        print("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        print("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        let visionURL = "https://api.anthropic.com/v1/messages"
        
        // Build content array with text prompt and multiple images
        var contentArray: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt
            ]
        ]
        
        // Add each image to the content array
        for imageData in imageDataArray {
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": imageData
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 3000, // Increased for multiple images
            "system": """
            You are a helpful assistant focused on relationship management and conversation tracking. \
            You have access to data about people, their roles, scheduled conversations, and conversation history. \
            When answering questions, you MUST use the provided context to give specific, data-driven responses. \
            Always reference specific people, dates, and conversations from the context in your responses. \
            If asked about team members, conversations, or schedules, look at the actual data provided and mention specific details. \
            If you don't have certain information in the context, clearly state what data is missing.
            """,
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ]
        ]
        
        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(claudeApiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            do {
                if httpResponse.statusCode == 200 {
                    let decodedResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
                    let content = decodedResponse.content.first?.text ?? "No response content."
                    print("🔍 [AI] Multi-image analysis successful, response length: \(content.count) characters")
                    print("🔍 [AI] Response preview: \(String(content.prefix(200)))...")
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [AI] Multi-image analysis failed with status \(httpResponse.statusCode): \(errorMessage ?? "Unknown error")")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                print("❌ [AI] Multi-image analysis parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
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