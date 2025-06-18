import Foundation

// Try importing FoundationModels - it should be available in iOS 18.1+
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 18.1, macOS 15.5, *)
class AppleIntelligenceService: ObservableObject {
    #if canImport(FoundationModels)
    private var isFrameworkAvailable: Bool = false
    #endif
    
    init() {
        #if canImport(FoundationModels)
        print(" [AppleIntelligence] FoundationModels framework available, checking runtime...")
        checkFrameworkAvailability()
        #else
        print(" [AppleIntelligence] FoundationModels framework not available")
        #endif
    }
    
    #if canImport(FoundationModels)
    private func checkFrameworkAvailability() {
        // Foundation Models requires macOS 26.0+ despite the import being available
        if #available(macOS 26.0, *) {
            isFrameworkAvailable = true
            print("✅ [AppleIntelligence] Foundation Models available on macOS 26.0+")
        } else {
            isFrameworkAvailable = false
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            print("ℹ️ [AppleIntelligence] Foundation Models requires macOS 26.0+, current: \(osVersion)")
            print("ℹ️ [AppleIntelligence] App will use fallback AI services on this version")
        }
    }
    #endif
    
    // MARK: - Helper Methods
    
    /// Check if Foundation Models is available on this system
    var isFoundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
        return isFrameworkAvailable && ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
        #else
        return false
        #endif
    }
    
    /// Truncates context to fit Foundation Models' 32k token limit
    /// Roughly estimates 1 token = 4 characters for safety
    private func truncateContextForFoundationModels(_ context: String, maxTokens: Int = 30000) -> String {
        let maxCharacters = maxTokens * 4 // Conservative estimate: 1 token ≈ 4 characters
        
        if context.count <= maxCharacters {
            return context
        }
        
        print("⚠️ [AppleIntelligence] Context too long (\(context.count) chars), truncating to \(maxCharacters) chars")
        
        // Intelligent truncation: keep recent conversations and person metadata
        let lines = context.components(separatedBy: .newlines)
        var result: [String] = []
        var currentLength = 0
        
        // Always include the header and person metadata (first ~10 lines)
        for (index, line) in lines.enumerated() {
            if index < 10 || currentLength + line.count <= maxCharacters {
                result.append(line)
                currentLength += line.count
            } else {
                break
            }
        }
        
        // If we have space, add recent conversations
        if currentLength < Int(Double(maxCharacters) * 0.8) {
            let remainingLines = Array(lines.dropFirst(result.count))
            for line in remainingLines {
                if currentLength + line.count <= maxCharacters {
                    result.append(line)
                    currentLength += line.count
                } else {
                    break
                }
            }
        }
        
        let truncated = result.joined(separator: "\n")
        return truncated + "\n\n[Note: Context intelligently truncated to prioritize recent conversations]"
    }
    
    // MARK: - Sentiment Analysis
    func analyzeSentiment(text: String) async throws -> ContextualSentiment {
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            // TODO: Implement when Foundation Models API is stable
            throw AppleIntelligenceError.processingFailed
        } else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #else
        throw AppleIntelligenceError.frameworkNotAvailable
        #endif
    }
    
    // MARK: - Meeting Summary Generation
    func generateMeetingSummary(transcript: String) async throws -> String {
        // Check if we're on macOS 26.0+ where Foundation Models are actually available
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Generating meeting summary with Foundation Models")
                
                // Create a language model session with specialized instructions
                if #available(macOS 26.0, *) {
                    let session = LanguageModelSession(instructions: """
                    You are a professional assistant for a team management app called WhoNext. 
                    You help users understand their team members' backgrounds, work history, and professional relationships.
                    
                    Guidelines:
                    - Be concise and direct in your responses
                    - Focus on the specific information requested
                    - When discussing work history, organize information chronologically
                    - If asked about specific people, provide relevant details about their roles and experience
                    - If context is limited, acknowledge what information is available
                    """)
                    
                    // Prepare a more structured prompt
                    let prompt = """
                    User Question: What is the meeting summary?
                    
                    Available Context:
                    \(truncateContextForFoundationModels(transcript))

                    Please provide a focused, helpful response based on the available information. If the context doesn't contain enough information to fully answer the question, acknowledge this and provide what details are available.
                    """
                    
                    print("🤖 [AppleIntelligence] Sending transcript to Foundation Models for summary...")
                    
                    // Send the prompt and get response using correct method
                    let response = try await session.respond(to: prompt, options: GenerationOptions())
                    
                    print("✅ [AppleIntelligence] Meeting summary generated successfully")
                    return response.content
                } else {
                    throw AppleIntelligenceError.frameworkNotAvailable
                }
                
            } catch {
                print("❌ [AppleIntelligence] Meeting summary generation failed: \(error)")
                throw AppleIntelligenceError.processingFailed
            }
        } else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #else
        throw AppleIntelligenceError.frameworkNotAvailable
        #endif
    }
    
    // MARK: - Pre-Meeting Brief Generation
    func generatePreMeetingBrief(personData: [Person], context: String) async throws -> String {
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Generating pre-meeting brief with Foundation Models")
                
                if #available(macOS 26.0, *) {
                    // Get the user's custom prompt from UserDefaults
                    let customPrompt = UserDefaults.standard.string(forKey: "customPreMeetingPrompt") ?? """
You are an executive assistant preparing a pre-meeting brief. Your job is to help the user engage with this person confidently by surfacing:
- Key personal details or preferences shared in past conversations
- Trends or changes in topics over time
- Any agreed tasks, deadlines, or follow-ups
- Recent wins, challenges, or important events
- Anything actionable or worth mentioning for the next meeting

Use the provided context to be specific and actionable. Highlight details that would help the user build rapport and recall important facts. If any information is missing, state so.

Pre-Meeting Brief:
"""
                    
                    // Create a session with minimal instructions to let the custom prompt take control
                    let session = LanguageModelSession(instructions: """
                    You are a helpful assistant that follows instructions precisely and provides detailed, actionable responses based on the context provided.
                    """)
                    
                    // Use the custom prompt with the full context
                    let enhancedContext = truncateContextForFoundationModels(context)
                    let prompt = """
\(customPrompt)

CONTEXT TO ANALYZE:
\(enhancedContext)

ANALYSIS INSTRUCTIONS:
- Extract specific insights, patterns, and actionable intelligence from the conversation history
- Identify relationship dynamics, communication preferences, and working styles
- Highlight any recurring themes, concerns, or opportunities mentioned across conversations
- Note any commitments, deadlines, or follow-up items that need attention
- Suggest specific talking points that would demonstrate understanding and build rapport
- Be specific with dates, details, and quotes when relevant

Generate a comprehensive pre-meeting brief following the format above.
"""
                    
                    print("🤖 [AppleIntelligence] Sending enhanced prompt to Foundation Models...")
                    print("🤖 [AppleIntelligence] Context length: \(enhancedContext.count) characters")
                    
                    // Send the prompt and get response using correct method
                    let response = try await session.respond(to: prompt, options: GenerationOptions())
                    
                    print("✅ [AppleIntelligence] Foundation Models response received")
                    return response.content
                } else {
                    throw AppleIntelligenceError.frameworkNotAvailable
                }
                
            } catch {
                print("❌ [AppleIntelligence] Pre-meeting brief generation failed: \(error)")
                throw AppleIntelligenceError.processingFailed
            }
        } else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #else
        throw AppleIntelligenceError.frameworkNotAvailable
        #endif
    }
    
    // MARK: - Chat Enhancement
    func enhanceChat(message: String, context: String) async throws -> String {
        // Check if we're on macOS 26.0+ where Foundation Models are actually available
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Starting chat enhancement with Foundation Models")
                
                if #available(macOS 26.0, *) {
                    // Create a language model session with specialized instructions
                    let session = LanguageModelSession(instructions: """
                    You are a professional assistant for a team management app called WhoNext. 
                    You help users understand their team members' backgrounds, work history, and professional relationships.
                    
                    Guidelines:
                    - Be concise and direct in your responses
                    - Focus on the specific information requested
                    - When discussing work history, organize information chronologically
                    - If asked about specific people, provide relevant details about their roles and experience
                    - If context is limited, acknowledge what information is available
                    """)
                    
                    // Prepare a more structured prompt
                    let prompt = """
                    User Question: \(message)
                    
                    Available Context:
                    \(truncateContextForFoundationModels(context))

                    Please provide a focused, helpful response based on the available information. If the context doesn't contain enough information to fully answer the question, acknowledge this and provide what details are available.
                    """
                    
                    print("🤖 [AppleIntelligence] Sending prompt to Foundation Models...")
                    
                    // Send the prompt and get response using correct method
                    let response = try await session.respond(to: prompt, options: GenerationOptions())
                    
                    print("✅ [AppleIntelligence] Foundation Models response received")
                    return response.content
                } else {
                    throw AppleIntelligenceError.frameworkNotAvailable
                }
                
            } catch {
                print("❌ [AppleIntelligence] Foundation Models error: \(error)")
                throw AppleIntelligenceError.processingFailed
            }
        } else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #else
        throw AppleIntelligenceError.frameworkNotAvailable
        #endif
    }
    
    // MARK: - Participant Extraction
    func extractParticipants(from transcript: String) async throws -> [String] {
        // Check if we're on macOS 26.0+ where Foundation Models are actually available
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Extracting participants with Foundation Models")
                
                if #available(macOS 26.0, *) {
                    // Create a language model session with specialized instructions
                    let session = LanguageModelSession(instructions: """
                    You are a professional assistant for a team management app called WhoNext. 
                    You help users understand their team members' backgrounds, work history, and professional relationships.
                    
                    Guidelines:
                    - Be concise and direct in your responses
                    - Focus on the specific information requested
                    - When discussing work history, organize information chronologically
                    - If asked about specific people, provide relevant details about their roles and experience
                    - If context is limited, acknowledge what information is available
                    """)
                    
                    // Prepare a more structured prompt
                    let prompt = """
                    User Question: Who are the participants in this meeting?
                    
                    Available Context:
                    \(truncateContextForFoundationModels(transcript))

                    Please provide a focused, helpful response based on the available information. If the context doesn't contain enough information to fully answer the question, acknowledge this and provide what details are available.
                    """
                    
                    print("🤖 [AppleIntelligence] Extracting participants from transcript...")
                    
                    // Send the prompt and get response using correct method
                    let response = try await session.respond(to: prompt, options: GenerationOptions())
                    
                    // Parse the response into an array of participant names
                    let participants = response.content
                        .components(separatedBy: CharacterSet.newlines)
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    print("✅ [AppleIntelligence] Found \(participants.count) participants: \(participants)")
                    return participants
                } else {
                    throw AppleIntelligenceError.frameworkNotAvailable
                }
                
            } catch {
                print("❌ [AppleIntelligence] Participant extraction failed: \(error)")
                throw AppleIntelligenceError.processingFailed
            }
        } else {
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        #else
        throw AppleIntelligenceError.frameworkNotAvailable
        #endif
    }
}

// MARK: - Supporting Types
struct SentimentData: Codable {
    let overallSentiment: String
    let sentimentScore: Double
    let confidence: Double
    let relationshipHealth: String
    let communicationStyle: String
    let engagementLevel: String
    let energyLevel: String
    let keyObservations: [String]
    let supportNeeds: [String]
    let followUpRecommendations: [String]
    let riskFactors: [String]
    let strengths: [String]
}

enum AppleIntelligenceError: Error {
    case frameworkNotAvailable
    case sessionNotAvailable
    case invalidResponse
    case processingFailed
    
    var localizedDescription: String {
        switch self {
        case .frameworkNotAvailable:
            return "Apple Intelligence requires macOS 26.0 or later. Using fallback AI service."
        case .sessionNotAvailable:
            return "Apple Intelligence session could not be initialized"
        case .invalidResponse:
            return "Invalid response from Apple Intelligence"
        case .processingFailed:
            return "Apple Intelligence processing failed"
        }
    }
}
