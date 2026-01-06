import Foundation

/// Service for checking API balance/credits for different providers
class APIBalanceService {

    struct Balance {
        let provider: String
        let credits: Double?
        let limit: Double?
        let errorMessage: String?

        var displayText: String {
            if let error = errorMessage {
                return "Error: \(error)"
            }

            if let credits = credits {
                if let limit = limit {
                    let percentage = (credits / limit) * 100
                    return String(format: "$%.2f / $%.2f (%.0f%%)", credits, limit, percentage)
                } else {
                    return String(format: "$%.2f", credits)
                }
            }

            return "Unable to fetch"
        }

        var color: String {
            guard let credits = credits, let limit = limit else {
                return "secondary"
            }

            let percentage = (credits / limit) * 100
            if percentage < 10 {
                return "red"
            } else if percentage < 30 {
                return "orange"
            } else {
                return "green"
            }
        }
    }

    /// Check OpenAI account balance
    static func checkOpenAIBalance(apiKey: String) async -> Balance {
        guard !apiKey.isEmpty else {
            return Balance(provider: "OpenAI", credits: nil, limit: nil, errorMessage: "No API key")
        }

        // OpenAI doesn't have a simple balance endpoint
        // We can check if the key is valid by making a minimal request
        do {
            let url = URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return Balance(provider: "OpenAI", credits: nil, limit: nil, errorMessage: "✓ API key valid (balance check via billing.openai.com)")
            } else {
                return Balance(provider: "OpenAI", credits: nil, limit: nil, errorMessage: "Invalid API key")
            }
        } catch {
            return Balance(provider: "OpenAI", credits: nil, limit: nil, errorMessage: error.localizedDescription)
        }
    }

    /// Check Claude/Anthropic account balance
    static func checkClaudeBalance(apiKey: String) async -> Balance {
        guard !apiKey.isEmpty else {
            return Balance(provider: "Claude", credits: nil, limit: nil, errorMessage: "No API key")
        }

        // Claude doesn't expose balance via API
        // We can validate the key
        do {
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Minimal request to check key validity
            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "Hi"]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 400 {
                    // 400 is ok, means key is valid but request might be malformed
                    return Balance(provider: "Claude", credits: nil, limit: nil, errorMessage: "✓ API key valid (balance check via console.anthropic.com)")
                } else if httpResponse.statusCode == 401 {
                    return Balance(provider: "Claude", credits: nil, limit: nil, errorMessage: "Invalid API key")
                }
            }

            return Balance(provider: "Claude", credits: nil, limit: nil, errorMessage: "✓ API key valid")
        } catch {
            return Balance(provider: "Claude", credits: nil, limit: nil, errorMessage: error.localizedDescription)
        }
    }

    /// Check OpenRouter credits
    static func checkOpenRouterBalance(apiKey: String) async -> Balance {
        guard !apiKey.isEmpty else {
            return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "No API key")
        }

        do {
            // Use the correct credits endpoint
            let url = URL(string: "https://openrouter.ai/api/v1/credits")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "Invalid response")
            }

            if httpResponse.statusCode == 200 {
                // Parse the response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataDict = json["data"] as? [String: Any] {

                    // Get total_credits (purchased) and total_usage
                    let totalCredits = dataDict["total_credits"] as? Double ?? 0
                    let totalUsage = dataDict["total_usage"] as? Double ?? 0

                    // Calculate remaining balance
                    let remaining = totalCredits - totalUsage

                    print("🔍 OpenRouter API Response:")
                    print("  Total Credits: \(totalCredits)")
                    print("  Total Usage: \(totalUsage)")
                    print("  Remaining: \(remaining)")

                    // Show balance if user has purchased credits
                    if totalCredits > 0 {
                        return Balance(provider: "OpenRouter", credits: remaining, limit: totalCredits, errorMessage: nil)
                    } else {
                        // Free tier (no credits purchased)
                        return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "✓ Free tier active")
                    }
                } else {
                    // Log raw response for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("❌ Unable to parse OpenRouter response:")
                        print(jsonString)
                    }
                    return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "Unable to parse response")
                }
            } else if httpResponse.statusCode == 401 {
                return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "Invalid API key")
            } else {
                return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: "HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return Balance(provider: "OpenRouter", credits: nil, limit: nil, errorMessage: error.localizedDescription)
        }
    }
}
