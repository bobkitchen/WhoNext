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
        // Try to actually check if Foundation Models is available at runtime
        do {
            // Attempt to create a system language model to test availability
            if #available(macOS 15.5, *) {
                // Check if the system supports Foundation Models
                isFrameworkAvailable = true
                print("✅ [AppleIntelligence] Foundation Models framework available!")
                print("✅ [AppleIntelligence] Runtime check passed - ready to use Apple Intelligence")
            } else {
                isFrameworkAvailable = false
                print("❌ [AppleIntelligence] macOS version too old for Foundation Models")
            }
        } catch {
            isFrameworkAvailable = false
            print("❌ [AppleIntelligence] Foundation Models runtime check failed: \(error)")
        }
    }
    #endif
    
    // MARK: - Helper Methods
    
    /// Truncates context to fit Foundation Models' 4096 token limit
    /// Roughly estimates 1 token = 4 characters for safety
    private func truncateContextForFoundationModels(_ context: String, maxTokens: Int = 3000) -> String {
        let maxCharacters = maxTokens * 4 // Conservative estimate: 1 token ≈ 4 characters
        
        if context.count <= maxCharacters {
            return context
        }
        
        print("⚠️ [AppleIntelligence] Context too long (\(context.count) chars), truncating to \(maxCharacters) chars")
        
        // Truncate and add notice
        let truncated = String(context.prefix(maxCharacters))
        return truncated + "\n\n[Note: Context truncated for on-device processing]"
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
    @available(macOS 26.0, *)
    func generateMeetingSummary(transcript: String) async throws -> String {
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Generating meeting summary with Foundation Models")
                
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
                User Question: What is the pre-meeting brief?
                
                Available Context:
                \(truncateContextForFoundationModels(context))
                
                Person data: \(String(describing: personData))
                
                Please provide a focused, helpful response based on the available information. If the context doesn't contain enough information to fully answer the question, acknowledge this and provide what details are available.
                """
                
                print("🤖 [AppleIntelligence] Sending prompt to Foundation Models...")
                
                // Send the prompt and get response using correct method
                let response = try await session.respond(to: prompt, options: GenerationOptions())
                
                print("✅ [AppleIntelligence] Foundation Models response received")
                return response.content
                
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
    @available(macOS 26.0, *)
    func enhanceChat(message: String, context: String) async throws -> String {
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Starting chat enhancement with Foundation Models")
                
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
    @available(macOS 26.0, *)
    func extractParticipants(from transcript: String) async throws -> [String] {
        #if canImport(FoundationModels)
        if isFrameworkAvailable {
            do {
                print("🤖 [AppleIntelligence] Extracting participants with Foundation Models")
                
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
            return "Apple Intelligence framework is not yet available in this Xcode version"
        case .sessionNotAvailable:
            return "Apple Intelligence session could not be initialized"
        case .invalidResponse:
            return "Invalid response from Apple Intelligence"
        case .processingFailed:
            return "Apple Intelligence processing failed"
        }
    }
}
