import Foundation

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

class AIService {
    static let shared = AIService()
    
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
    }
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init() { }
    
    func sendMessage(_ message: String, context: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else {
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
            // First provide the context as a system message
            messages.append(["role": "system", "content": context])
        }
        
        // Then add the user's actual question
        messages.append(["role": "user", "content": message])
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
    
    func analyzeImageWithVision(imageData: String, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
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
    
    func analyzeMultipleImagesWithVision(imageDataArray: [String], prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
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