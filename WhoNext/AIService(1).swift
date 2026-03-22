import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable {
    case openai = "openai"
    case claude = "claude"
    case openrouter = "openrouter"
    case apify = "apify"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .openrouter: return "OpenRouter"
        case .apify: return "Apify"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openai, .claude, .openrouter, .apify: return true
        }
    }

    var isAIProvider: Bool {
        switch self {
        case .openai, .claude, .openrouter: return true
        case .apify: return false
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
    
    @AppStorage("currentProvider") var currentProvider: AIProvider = .openrouter
    @AppStorage("openrouterModel") var openrouterModel: String = "anthropic/claude-sonnet-4.6"
    @AppStorage("openaiModel") var openaiModel: String = "gpt-5-nano"  // Configurable OpenAI model
    
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

    var apifyApiKey: String {
        get { SecureStorage.getAPIKey(for: .apify) }
        set { SecureStorage.setAPIKey(newValue, for: .apify) }
    }

    var apiKey: String {
        switch currentProvider {
        case .openai: return openaiApiKey
        case .claude: return claudeApiKey
        case .openrouter: return openrouterApiKey
        case .apify: return openrouterApiKey
        }
    }
    
    init() {
        // Migrate keys from UserDefaults to secure storage on first run
        SecureStorage.migrateFromUserDefaults()

        // Force migration to OpenRouter if still using old providers
        if currentProvider != .openrouter {
            debugLog("🔄 Migrating provider from \(currentProvider) to OpenRouter")
            currentProvider = .openrouter
        }
    }
    
    func sendMessage(_ message: String, context: String? = nil) async throws -> String {
        debugLog("🔍 [AIService] Using provider: \(currentProvider)")
        switch currentProvider {
        case .openai:
            return try await sendMessageOpenAI(message, context: context)
        case .claude:
            return try await sendMessageClaude(message, context: context)
        case .openrouter, .apify:
            do {
                let result = try await sendMessageOpenRouter(message, context: context)
                // Check if OpenRouter gave a meaningful response
                if result.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
                    debugLog("⚠️ [OpenRouter] Response too short, falling back to OpenAI")
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
        debugLog("🔍 [OpenAI Chat] Starting chat message")
        debugLog("🔍 [OpenAI Chat] Message: \(String(message.prefix(100)))...")
        
        guard !openaiApiKey.isEmpty else {
            print("❌ [OpenAI Chat] API key is missing")
            throw AIError.missingAPIKey
        }
        
        debugLog("🔍 [OpenAI Chat] API key present: \(!openaiApiKey.isEmpty)")
        
        // GPT-5 models have different parameter requirements
        let model = openaiModel  // Use configurable model
        
        // Formatting instructions to ensure good markdown output
        let formattingInstructions = """
IMPORTANT FORMATTING RULES:
- Use ## for main section headers
- Use ### for subsection headers
- Use - for bullet points with proper indentation
- Add blank lines between sections for readability
- Use **bold** for emphasis within text
- Use numbered lists (1. 2. 3.) where appropriate
- Ensure clear hierarchy and structure in your response
"""
        
        var messages: [[String: String]] = []
        
        // GPT-5 models don't support system messages - combine everything into user message
        if model.starts(with: "gpt-5") {
            // For GPT-5, combine formatting instructions with the user message
            var combinedMessage = ""
            
            // Add context if provided
            if let context = context {
                combinedMessage += "Context:\n\(context)\n\n"
                debugLog("🔍 [OpenAI Chat] Context provided: \(String(context.prefix(100)))...")
            }
            
            // Add the user's message/prompt
            combinedMessage += "\(message)\n\n"
            
            // Append formatting instructions at the end
            combinedMessage += formattingInstructions
            
            messages.append([
                "role": "user",
                "content": combinedMessage
            ])
            
            debugLog("🔍 [OpenAI Chat] Using GPT-5 format - combined message length: \(combinedMessage.count) chars")
        } else {
            // GPT-4 and older models support system messages
            // System message with just formatting instructions
            messages.append(["role": "system", "content": formattingInstructions])
            
            if let context = context {
                messages.append(["role": "system", "content": context])
                debugLog("🔍 [OpenAI Chat] Context provided: \(String(context.prefix(100)))...")
            }
            
            messages.append([
                "role": "user",
                "content": message
            ])
        }
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openaiApiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any]
        if model.starts(with: "gpt-5") {
            // GPT-5 configuration: uses max_completion_tokens and no temperature
            requestBody = [
                "model": model,
                "messages": messages,
                "max_completion_tokens": 8000
            ]
            debugLog("🔍 [OpenAI Chat] Using GPT-5 configuration with max_completion_tokens")
        } else {
            // GPT-4 configuration: uses max_tokens and temperature
            requestBody = [
                "model": model,
                "messages": messages,
                "max_tokens": 8000,
                "temperature": 0.7
            ]
            debugLog("🔍 [OpenAI Chat] Using GPT-4 configuration with max_tokens and temperature")
        }
        
        // Log the exact request being sent
        if let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            debugLog("🔍 [OpenAI Chat] Full request body: \(jsonString)")
        }
        
        debugLog("🔍 [OpenAI Chat] Request body created, sending to API...")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [OpenAI Chat] Invalid HTTP response")
            throw AIError.invalidResponse
        }
        
        debugLog("🔍 [OpenAI Chat] Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            debugLog("🔍 [OpenAI Chat] Raw response: \(responseString)")  // Log FULL response for debugging
            
            // Try to parse as JSON first to see structure
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                debugLog("🔍 [OpenAI Chat] JSON structure: \(jsonObject.keys)")
                if let choices = jsonObject["choices"] as? [[String: Any]] {
                    debugLog("🔍 [OpenAI Chat] Choices count: \(choices.count)")
                    if let firstChoice = choices.first {
                        debugLog("🔍 [OpenAI Chat] First choice keys: \(firstChoice.keys)")
                        if let message = firstChoice["message"] as? [String: Any] {
                            debugLog("🔍 [OpenAI Chat] Message keys: \(message.keys)")
                            debugLog("🔍 [OpenAI Chat] Message content: \(message["content"] ?? "nil")")
                        }
                    }
                }
                if let usage = jsonObject["usage"] as? [String: Any] {
                    debugLog("🔍 [OpenAI Chat] Token usage: \(usage)")
                }
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                let content = decodedResponse.choices.first?.message.content ?? "No response content."
                debugLog("🔍 [OpenAI Chat] Success! Response length: \(content.count) characters")
                
                // If content is empty, log more details
                if content.isEmpty || content == "No response content." {
                    debugLog("⚠️ [OpenAI Chat] Empty or default content received")
                    debugLog("⚠️ [OpenAI Chat] Choices count: \(decodedResponse.choices.count)")
                    debugLog("⚠️ [OpenAI Chat] Usage: \(decodedResponse.usage)")
                    debugLog("⚠️ [OpenAI Chat] Model: \(decodedResponse.model)")
                }
                
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
        
        // Formatting instructions to ensure good markdown output
        let formattingInstructions = """
IMPORTANT FORMATTING RULES:
- Use ## for main section headers
- Use ### for subsection headers
- Use - for bullet points with proper indentation
- Add blank lines between sections for readability
- Use **bold** for emphasis within text
- Use numbered lists (1. 2. 3.) where appropriate
- Ensure clear hierarchy and structure in your response
"""
        
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
            "model": "claude-sonnet-4-6-20250514",
            "max_tokens": 8000,
            "system": formattingInstructions,
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
        debugLog("🔍 [OpenRouter] Starting sendMessageOpenRouter")
        
        // Formatting instructions to ensure good markdown output
        let formattingInstructions = """
IMPORTANT FORMATTING RULES:
- Use ## for main section headers
- Use ### for subsection headers
- Use - for bullet points with proper indentation
- Add blank lines between sections for readability
- Use **bold** for emphasis within text
- Use numbered lists (1. 2. 3.) where appropriate
- Ensure clear hierarchy and structure in your response
"""
        
        var messages: [[String: String]] = [
            ["role": "system", "content": formattingInstructions]
        ]
        
        if let context = context {
            debugLog("🔍 [OpenRouter] Context received length: \(context.count) characters")
            debugLog("🔍 [OpenRouter] Context preview: \(String(context.prefix(200)))...")
            
            // For very large contexts, add it as a separate system message
            if context.count > 10000 {
                debugLog("⚠️ [OpenRouter] Large context detected (\(context.count) chars), splitting into chunks")
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
            debugLog("⚠️ [OpenRouter] No context provided!")
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
        
        debugLog("🔍 [OpenRouter] Request body structure: model=\(openrouterModel), messages count=\(messages.count)")
        
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
        
        debugLog("🔍 [OpenRouter] Sending request...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLog("🔍 [OpenRouter] Response status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            
            if let httpResponse = response as? HTTPURLResponse {
                debugLog("🔍 [OpenRouter] Response headers: \(httpResponse.allHeaderFields)")
            }
            
            let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            debugLog("🔍 [OpenRouter] Full response: \(jsonResponse ?? [:])")
            
            if let choices = jsonResponse?["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                debugLog("🔍 [OpenRouter] Decoded content: \(content)")
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Check for usage info
            if let usage = jsonResponse?["usage"] as? [String: Any] {
                debugLog("🔍 [OpenRouter] Token usage: \(usage)")
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
        case .openrouter, .apify:
            analyzeImageWithVisionOpenRouter(imageData: imageData, prompt: prompt, completion: completion)
        }
    }
    
    private func analyzeImageWithVisionOpenAI(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            print("❌ [OpenAI] API key is missing")
            completion(.failure(AIError.missingAPIKey))
            return
        }
        
        debugLog("🔍 [OpenAI] Starting single image analysis")
        debugLog("🔍 [OpenAI] Image data length: \(imageData.count)")
        debugLog("🔍 [OpenAI] API key present: \(!apiKey.isEmpty)")
        
        let visionURL = "https://api.openai.com/v1/chat/completions"
        
        // Use GPT-5 for best-in-class visual perception and OCR accuracy (Jan 2026)
        // GPT-5 uses max_completion_tokens instead of max_tokens
        let requestBody: [String: Any] = [
            "model": "gpt-5",
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
            "max_completion_tokens": 8000
        ]
        
        // Debug request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert"
            debugLog("🔍 [OpenAI] Request body size: \(jsonData.count) bytes")
            debugLog("🔍 [OpenAI] Request preview: \(String(jsonString.prefix(300)))...")
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
        
        debugLog("🔍 [OpenAI] Sending request to: \(visionURL)")
        
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
            
            debugLog("🔍 [OpenAI] Response status: \(httpResponse.statusCode)")
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            debugLog("🔍 [OpenAI] Raw response: \(String(responseString.prefix(500)))...")
            
            do {
                if httpResponse.statusCode == 200 {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    debugLog("🔍 [OpenAI] Success! Response length: \(content.count) characters")
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
            "model": "claude-sonnet-4-6-20250514",
            "max_tokens": 8000,
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
                    debugLog("🔍 [AI] Image analysis successful, response length: \(content.count) characters")
                    debugLog("🔍 [AI] Response preview: \(String(content.prefix(200)))...")
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

    private func analyzeImageWithVisionOpenRouter(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !openrouterApiKey.isEmpty else {
            print("❌ [OpenRouter] API key is missing")
            completion(.failure(AIError.missingAPIKey))
            return
        }

        debugLog("🔍 [OpenRouter] Starting vision analysis with model: \(openrouterModel)")
        debugLog("🔍 [OpenRouter] Image data length: \(imageData.count)")

        let visionURL = "https://openrouter.ai/api/v1/chat/completions"

        // Determine if we need max_completion_tokens (GPT-5 family) or max_tokens
        let useCompletionTokens = openrouterModel.contains("gpt-5") || openrouterModel.contains("openai/gpt-5")

        var requestBody: [String: Any] = [
            "model": openrouterModel,
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
            ]
        ]

        // Add the correct token parameter based on model
        if useCompletionTokens {
            requestBody["max_completion_tokens"] = 8000
        } else {
            requestBody["max_tokens"] = 8000
        }

        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openrouterApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("❌ [OpenRouter] Failed to create request body: \(error)")
            completion(.failure(error))
            return
        }

        debugLog("🔍 [OpenRouter] Sending request to: \(visionURL)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [OpenRouter] Network error: \(error)")
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                print("❌ [OpenRouter] No data received")
                completion(.failure(AIError.invalidResponse))
                return
            }

            debugLog("🔍 [OpenRouter] Response status: \(httpResponse.statusCode)")
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            debugLog("🔍 [OpenRouter] Raw response: \(String(responseString.prefix(500)))...")

            do {
                if httpResponse.statusCode == 200 {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    debugLog("🔍 [OpenRouter] Success! Response length: \(content.count) characters")
                    completion(.success(content))
                } else {
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [OpenRouter] API Error (\(httpResponse.statusCode)): \(errorMessage ?? "Unknown error")")
                    print("❌ [OpenRouter] Full error response: \(responseString)")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "OpenRouter API error \(httpResponse.statusCode)")))
                }
            } catch {
                print("❌ [OpenRouter] JSON parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Multi-Image Analysis with Format Support
    func analyzeMultipleImagesWithVision(imageDataArray: [(base64: String, format: String)], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        debugLog("🔍 [AI] analyzeMultipleImagesWithVision called with provider: \(currentProvider)")
        
        switch currentProvider {
        case .openai:
            analyzeMultipleImagesWithVisionOpenAI(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        case .claude:
            analyzeMultipleImagesWithVisionClaude(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
        case .openrouter, .apify:
            analyzeMultipleImagesWithVisionOpenRouter(imageDataArray: imageDataArray, prompt: prompt, completion: completion)
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
        
        debugLog("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        debugLog("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        // Calculate total payload size for logging
        let totalImageSize = imageDataArray.reduce(0) { $0 + $1.base64.count }
        debugLog("🔍 [AI] Total image data size: \(totalImageSize / 1024 / 1024)MB")
        
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
            "model": "gpt-5",
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ],
            "max_completion_tokens": 8000 // GPT-5 requires max_completion_tokens
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
        
        debugLog("🔍 [AI] Sending request with extended timeout (120s request, 300s resource)")
        
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
                    debugLog("🔍 [OpenAI] Raw response: \(String(responseString.prefix(200)))...")
                    
                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    debugLog("🔍 [AI] Multi-image analysis successful, response length: \(content.count) characters")
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
        
        debugLog("🔍 [AI] Starting multi-image analysis with \(imageDataArray.count) images")
        debugLog("🔍 [AI] Prompt length: \(prompt.count) characters")
        
        // Calculate total payload size for logging
        let totalImageSize = imageDataArray.reduce(0) { $0 + $1.base64.count }
        debugLog("🔍 [AI] Total image data size: \(totalImageSize / 1024 / 1024)MB")
        
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
            "model": "claude-sonnet-4-6-20250514",
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
        
        debugLog("🔍 [AI] Sending Claude request with extended timeout (120s request, 300s resource)")
        
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
                    debugLog("🔍 [AI] Multi-image analysis successful, response length: \(content.count) characters")
                    debugLog("🔍 [AI] Response preview: \(String(content.prefix(200)))...")
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

    private func analyzeMultipleImagesWithVisionOpenRouter(imageDataArray: [(base64: String, format: String)], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !openrouterApiKey.isEmpty else {
            completion(.failure(AIError.missingAPIKey))
            return
        }

        debugLog("🔍 [OpenRouter] Starting multi-image analysis with \(imageDataArray.count) images")
        debugLog("🔍 [OpenRouter] Prompt length: \(prompt.count) characters")

        let totalImageSize = imageDataArray.reduce(0) { $0 + $1.base64.count }
        debugLog("🔍 [OpenRouter] Total image data size: \(totalImageSize / 1024 / 1024)MB")

        let visionURL = "https://openrouter.ai/api/v1/chat/completions"

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

        // Determine if we need max_completion_tokens (GPT-5 family) or max_tokens
        let useCompletionTokens = openrouterModel.contains("gpt-5") || openrouterModel.contains("openai/gpt-5")

        var requestBody: [String: Any] = [
            "model": openrouterModel,
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ]
        ]

        // Add the correct token parameter based on model
        if useCompletionTokens {
            requestBody["max_completion_tokens"] = 8000
        } else {
            requestBody["max_tokens"] = 8000
        }

        guard let url = URL(string: visionURL) else {
            completion(.failure(AIError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openrouterApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set extended timeout for large image processing
        request.timeoutInterval = 120.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }

        // Create custom URLSession with extended timeout configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120.0
        sessionConfig.timeoutIntervalForResource = 300.0
        let customSession = URLSession(configuration: sessionConfig)

        debugLog("🔍 [OpenRouter] Sending request with extended timeout (120s request, 300s resource)")

        customSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [OpenRouter] Network error: \(error)")
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                print("❌ [OpenRouter] No data received")
                completion(.failure(AIError.invalidResponse))
                return
            }

            do {
                if httpResponse.statusCode == 200 {
                    let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                    debugLog("🔍 [OpenRouter] Raw response: \(String(responseString.prefix(200)))...")

                    let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = jsonResponse?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    let content = message?["content"] as? String ?? "No response content."
                    debugLog("🔍 [OpenRouter] Multi-image analysis successful, response length: \(content.count) characters")
                    completion(.success(content))
                } else {
                    let errorData = String(data: data, encoding: .utf8) ?? "No error data"
                    print("❌ [OpenRouter] Error response data: \(errorData)")
                    let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorResponse?["error"] as? [String: Any])?["message"] as? String
                    print("❌ [OpenRouter] Multi-image analysis failed with status \(httpResponse.statusCode): \(errorMessage ?? "Unknown error")")
                    completion(.failure(AIError.apiError(message: errorMessage ?? "Unknown API error")))
                }
            } catch {
                let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                print("❌ [OpenRouter] Response that failed to parse: \(responseString)")
                print("❌ [OpenRouter] Multi-image analysis parsing error: \(error)")
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