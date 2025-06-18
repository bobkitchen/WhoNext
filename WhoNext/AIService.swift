import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable {
    case openai = "openai"
    case claude = "claude"
    case openrouter = "openrouter"
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .openrouter: return "OpenRouter"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openai, .claude, .openrouter: return true
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
    
    @AppStorage("currentProvider") var currentProvider: AIProvider = .openai
    @AppStorage("openrouterModel") var openrouterModel: String = "meta-llama/llama-3.1-8b-instruct:free"
    
    // Secure API key access
    var openaiApiKey: String {
        get { SecureStorage.getAPIKey(for: .openai) }
        set { SecureStorage.setAPIKey(newValue, for: .openai) }
    }
    
    var claudeApiKey: String {
        get { SecureStorage.getAPIKey(for: .claude) }
        set { SecureStorage.setAPIKey(newValue, for: .claude) }
    }
    
    var openrouterApiKey: String {
        get { SecureStorage.getAPIKey(for: .openrouter) }
        set { SecureStorage.setAPIKey(newValue, for: .openrouter) }
    }
    
    var apiKey: String {
        switch currentProvider {
        case .openai: return openaiApiKey
        case .claude: return claudeApiKey
        case .openrouter: return openrouterApiKey
        }
    }
    
    init() {
        // Migrate keys from UserDefaults to secure storage on first run
        SecureStorage.migrateFromUserDefaults()
    }
    
    func sendMessage(_ message: String, context: String? = nil) async throws -> String {
        print("🔍 [AIService] Using provider: \(currentProvider)")
        switch currentProvider {
        case .openai:
            return try await sendMessageOpenAI(message, context: context)
        case .claude:
            return try await sendMessageClaude(message, context: context)
        case .openrouter:
            do {
                let result = try await sendMessageOpenRouter(message, context: context)
                // Check if OpenRouter gave a meaningful response
                if result.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
                    print("⚠️ [OpenRouter] Response too short, falling back to OpenAI")
                    if !openaiApiKey.isEmpty {
                        return try await sendMessageOpenAI(message, context: context)
                    } else {
                        throw AIError.apiError(message: "OpenRouter response too short and no OpenAI fallback available")
                    }
                }
                return result
            } catch {
                print("⚠️ [OpenRouter] Failed, falling back to OpenAI: \(error)")
                if !openaiApiKey.isEmpty {
                    return try await sendMessageOpenAI(message, context: context)
                } else {
                    throw error
                }
            }
        }
    }
    
    private func sendMessageOpenAI(_ message: String, context: String? = nil) async throws -> String {
        print("🔍 [OpenAI Chat] Starting chat message")
        print("🔍 [OpenAI Chat] Message: \(String(message.prefix(100)))...")
        
        guard !openaiApiKey.isEmpty else {
            print("❌ [OpenAI Chat] API key is missing")
            throw AIError.missingAPIKey
        }
        
        print("🔍 [OpenAI Chat] API key present: \(!openaiApiKey.isEmpty)")
        
        var messages: [[String: String]] = [
            ["role": "system", "content": """
You are an AI assistant that helps with team management and document analysis.
For questions about team members, use only the provided context information.
For document analysis tasks (like transcript processing), analyze the content provided in the user's message.
If you don't have the needed information, say "I don't have that information."
"""]
        ]
        
        if let context = context {
            messages.append(["role": "system", "content": context])
            print("🔍 [OpenAI Chat] Context provided: \(String(context.prefix(100)))...")
        }
        
        messages.append([
            "role": "user",
            "content": message
        ])
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openaiApiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 1000,
            "temperature": 0.7
        ]
        
        print("🔍 [OpenAI Chat] Request body created, sending to API...")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [OpenAI Chat] Invalid HTTP response")
            throw AIError.invalidResponse
        }
        
        print("🔍 [OpenAI Chat] Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            print("🔍 [OpenAI Chat] Raw response: \(String(responseString.prefix(300)))...")
            
            do {
                let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                let content = decodedResponse.choices.first?.message.content ?? "No response content."
                print("🔍 [OpenAI Chat] Success! Response length: \(content.count) characters")
                return content
            } catch {
                print("❌ [OpenAI Chat] JSON decoding error: \(error)")
                print("❌ [OpenAI Chat] Raw response that failed to decode: \(responseString)")
                throw error
            }
        } else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            print("❌ [OpenAI Chat] Error response: \(responseString)")
            
            let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
            print("❌ [OpenAI Chat] API Error (\(httpResponse.statusCode)): \(errorMessage ?? "Unknown error")")
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
            You are a helpful assistant for relationship management and conversation tracking.
            You should only provide information based on data that has been explicitly provided to you.
            If you don't have specific information about people, dates, or conversations, clearly state that you don't have that information.
            Never make up or invent specific names, dates, or details that weren't provided to you.
            When you don't know something, say "I don't have that information" rather than guessing.
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
    
    private func sendMessageOpenRouter(_ message: String, context: String? = nil) async throws -> String {
        print("🔍 [OpenRouter] Starting sendMessageOpenRouter")
        
        var messages: [[String: String]] = [
            ["role": "system", "content": """
You are an AI assistant that helps with team management and document analysis.
For questions about team members, use only the provided context information.
For document analysis tasks (like transcript processing), analyze the content provided in the user's message.
If you don't have the needed information, say "I don't have that information."
"""]
        ]
        
        if let context = context {
            print("🔍 [OpenRouter] Context received length: \(context.count) characters")
            print("🔍 [OpenRouter] Context preview: \(String(context.prefix(200)))...")
            
            // For very large contexts, add it as a separate system message
            if context.count > 10000 {
                print("⚠️ [OpenRouter] Large context detected (\(context.count) chars), splitting into chunks")
                // Add context in chunks to avoid token limits
                let chunkSize = 8000
                var startIndex = context.startIndex
                var chunkNumber = 1
                
                while startIndex < context.endIndex {
                    let endIndex = context.index(startIndex, offsetBy: chunkSize, limitedBy: context.endIndex) ?? context.endIndex
                    let chunk = String(context[startIndex..<endIndex])
                    messages.append(["role": "system", "content": "Context Part \(chunkNumber):\n\(chunk)"])
                    startIndex = endIndex
                    chunkNumber += 1
                }
            } else {
                messages.append(["role": "system", "content": "Team Information Context:\n\(context)"])
            }
        } else {
            print("⚠️ [OpenRouter] No context provided!")
        }
        
        // Add user message with context reminder
        let enhancedMessage = """
        Based on the team information provided in the context above, please answer the following question:
        
        \(message)
        
        Search through all the context parts carefully, especially the LinkedIn profile information in the Background Notes sections.
        """
        messages.append(["role": "user", "content": enhancedMessage])
        
        let requestBody: [String: Any] = [
            "model": openrouterModel, // Use stored model
            "messages": messages,
            "temperature": 0.7
        ]
        
        print("🔍 [OpenRouter] Request body structure: model=\(openrouterModel), messages count=\(messages.count)")
        
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openrouterApiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw error
        }
        
        print("🔍 [OpenRouter] Sending request...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            print("🔍 [OpenRouter] Response status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 [OpenRouter] Response headers: \(httpResponse.allHeaderFields)")
            }
            
            let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            print("🔍 [OpenRouter] Full response: \(jsonResponse ?? [:])")
            
            if let choices = jsonResponse?["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                print("🔍 [OpenRouter] Decoded content: \(content)")
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Check for usage info
            if let usage = jsonResponse?["usage"] as? [String: Any] {
                print("🔍 [OpenRouter] Token usage: \(usage)")
            }
            
            throw AIError.invalidResponse
        } catch {
            print("❌ [OpenRouter] Error: \(error)")
            throw error
        }
    }
    
    func analyzeImageWithVision(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        switch currentProvider {
        case .openai:
            analyzeImageWithVisionOpenAI(imageData: imageData, prompt: prompt, completion: completion)
        case .claude:
            analyzeImageWithVisionClaude(imageData: imageData, prompt: prompt, completion: completion)
        case .openrouter:
            // OpenRouter free models don't support vision - fallback to OpenAI if available
            if !openaiApiKey.isEmpty {
                print("🔄 [Vision] OpenRouter free tier doesn't support vision, using OpenAI fallback")
                analyzeImageWithVisionOpenAI(imageData: imageData, prompt: prompt, completion: completion)
            } else {
                completion(.failure(NSError(domain: "AIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vision analysis requires OpenAI or Claude. Please configure an API key in settings."])))
            }
        }
    }
    
    private func analyzeImageWithVisionOpenAI(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            print("❌ [OpenAI] API key is missing")
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        print("🔍 [OpenAI] Starting single image analysis")
        print("🔍 [OpenAI] Image data length: \(imageData.count)")
        print("🔍 [OpenAI] API key present: \(!apiKey.isEmpty)")
        
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
                                "url": "data:image/jpeg;base64,\(imageData)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 2000
        ]
        
        // Debug request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert"
            print("🔍 [OpenAI] Request body size: \(jsonData.count) bytes")
            print("🔍 [OpenAI] Request preview: \(String(jsonString.prefix(300)))...")
        } catch {
            print("❌ [OpenAI] Failed to serialize request: \(error)")
        }
        
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
            print("❌ [OpenAI] Failed to create request body: \(error)")
            completion(.failure(error))
            return
        }
        
        print("🔍 [OpenAI] Sending request to: \(visionURL)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [OpenAI] Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                print("❌ [OpenAI] No data received")
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            print("🔍 [OpenAI] Response status: \(httpResponse.statusCode)")
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            print("🔍 [OpenAI] Raw response: \(String(responseString.prefix(500)))...")
            
            do {
                if httpResponse.statusCode == 200 {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    print("🔍 [OpenAI] Success! Response length: \(content.count) characters")
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [OpenAI] API Error (\(httpResponse.statusCode)): \(errorMessage ?? "Unknown error")")
                    print("❌ [OpenAI] Full error response: \(responseString)")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "OpenAI API error \(httpResponse.statusCode)")))
                }
            } catch {
                print("❌ [OpenAI] JSON parsing error: \(error)")
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
            You are a helpful assistant for relationship management and conversation tracking.
            You should only provide information based on data that has been explicitly provided to you.
            If you don't have specific information about people, dates, or conversations, clearly state that you don't have that information.
            Never make up or invent specific names, dates, or details that weren't provided to you.
            When you don't know something, say "I don't have that information" rather than guessing.
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
                                "media_type": "image/jpeg",
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
                print("❌ [AI] Claude request failed with error: \(error.localizedDescription)")
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
                    print("🔍 [AI] Image analysis successful, response length: \(content.count) characters")
                    print("🔍 [AI] Response preview: \(String(content.prefix(200)))...")
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [AI] Image analysis failed with status \(httpResponse.statusCode): \(errorMessage ?? "Unknown error")")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                print("❌ [AI] Image analysis parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Multi-Image Analysis with Format Support
    func analyzeMultipleImagesWithVision(imageDataArray: [(base64: String, format: String)], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 [AI] analyzeMultipleImagesWithVision called with provider: \(currentProvider)")
        
        switch currentProvider {
        case .openai:
            analyzeMultipleImagesWithVisionOpenAI(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        case .claude:
            analyzeMultipleImagesWithVisionClaude(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        case .openrouter:
            if !openaiApiKey.isEmpty {
                print("🔄 [Vision] OpenRouter free tier doesn't support vision, using OpenAI fallback")
                analyzeMultipleImagesWithVisionOpenAI(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
            } else {
                completion(.failure(NSError(domain: "AIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vision analysis requires OpenAI or Claude. Please configure an API key in settings."])))
            }
        }
    }
    
    // Legacy method for backward compatibility
    func analyzeMultipleImagesWithVision(imageDataArray: [String], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Convert to new format (assume JPEG for legacy calls)
        let formattedImages = imageDataArray.map { (base64: $0, format: "jpeg") }
        analyzeMultipleImagesWithVision(imageDataArray: formattedImages, prompt: prompt, completion: completion)
    }
    
    private func analyzeMultipleImagesWithVisionOpenAI(imageDataArray: [(base64: String, format: String)], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        print("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        print("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        // Calculate total payload size for logging
        let totalImageSize = imageDataArray.reduce(0) { $0 + $1.base64.count }
        print("🔍 [AI] Total image data size: \(totalImageSize / 1024 / 1024)MB")
        
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
                    "url": "data:image/\(imageData.format);base64,\(imageData.base64)"
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
        
        // Set extended timeout for large image processing
        request.timeoutInterval = 120.0 // 2 minutes instead of default 60 seconds
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Create custom URLSession with extended timeout configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120.0  // 2 minutes for request
        sessionConfig.timeoutIntervalForResource = 300.0 // 5 minutes for entire resource
        let customSession = URLSession(configuration: sessionConfig)
        
        print("🔍 [AI] Sending request with extended timeout (120s request, 300s resource)")
        
        customSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [OpenAI] Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                print("❌ [OpenAI] No data received")
                completion(.failure(AIError.invalidResponse))
                return
            }
            
            do {
                if httpResponse.statusCode == 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                    print("🔍 [OpenAI] Raw response: \(String(responseString.prefix(200)))...")
                    
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    print("🔍 [AI] Multi-image analysis successful, response length: \(content.count) characters")
                    completion(.success(content))
                } else {
                    let errorData = String(data: data, encoding: .utf8) ?? "No error data"
                    print("❌ [OpenAI] Error response data: \(errorData)")
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [OpenAI] Multi-image analysis failed with status \(httpResponse.statusCode): \(errorMessage ?? "Unknown error")")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                print("❌ [OpenAI] Response that failed to parse: \(responseString)")
                print("❌ [AI] Multi-image analysis parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func analyzeMultipleImagesWithVisionClaude(imageDataArray: [(base64: String, format: String)], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !claudeApiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        print("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        print("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        // Calculate total payload size for logging
        let totalImageSize = imageDataArray.reduce(0) { $0 + $1.base64.count }
        print("🔍 [AI] Total image data size: \(totalImageSize / 1024 / 1024)MB")
        
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
                    "media_type": "image/\(imageData.format)",
                    "data": imageData.base64
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 3000, // Increased for multiple images
            "system": """
            You are a helpful assistant for relationship management and conversation tracking.
            You should only provide information based on data that has been explicitly provided to you.
            If you don't have specific information about people, dates, or conversations, clearly state that you don't have that information.
            Never make up or invent specific names, dates, or details that weren't provided to you.
            When you don't know something, say "I don't have that information" rather than guessing.
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
        
        // Set extended timeout for large image processing
        request.timeoutInterval = 120.0 // 2 minutes instead of default 60 seconds
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Create custom URLSession with extended timeout configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120.0  // 2 minutes for request
        sessionConfig.timeoutIntervalForResource = 300.0 // 5 minutes for entire resource
        let customSession = URLSession(configuration: sessionConfig)
        
        print("🔍 [AI] Sending Claude request with extended timeout (120s request, 300s resource)")
        
        customSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [AI] Claude request failed with error: \(error.localizedDescription)")
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
    
    enum AIError: Error {
        case missingAPIKey
        case invalidResponse
        case apiError(message: String)
        case notImplemented
        
        var localizedDescription: String {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key is missing. Please set it in your environment variables or app settings."
            case .invalidResponse:
                return "Received an invalid response from the API."
            case .apiError(let message):
                return "API Error: \(message)"
            case .notImplemented:
                return "This feature is not implemented yet."
            }
        }
    }
}