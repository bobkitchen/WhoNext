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
    
    /// Truncates context to fit Foundation Models' 4k token limit
    /// Using more conservative estimate: 1 token ≈ 3 characters for safety
    private func truncateContextForFoundationModels(_ context: String, maxTokens: Int = 2000) -> String {
        let maxCharacters = maxTokens * 3 // More conservative: 1 token ≈ 3 characters
        
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
                
                // Get the user's custom summarization prompt from settings
                let userCustomPrompt = UserDefaults.standard.string(forKey: "customSummarizationPrompt")
                
                // Log which prompt is being used
                if let customPrompt = userCustomPrompt, !customPrompt.isEmpty {
                    print("📝 [AppleIntelligence] Using custom summarization prompt from user settings")
                } else {
                    print("📝 [AppleIntelligence] Using default summarization prompt")
                }
                
                let customPrompt = userCustomPrompt ?? """
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
                
                // Truncate the transcript first
                let truncatedTranscript = truncateContextForFoundationModels(transcript)
                
                // If transcript is very short after truncation, use a simpler prompt
                let finalPrompt: String
                if truncatedTranscript.count < 1000 {
                    finalPrompt = """
                    Based on this partial meeting transcript, provide a brief summary of what was discussed:
                    
                    Transcript:
                    \(truncatedTranscript)
                    
                    Note: This appears to be a partial or very short transcript. Please summarize what is available.
                    """
                } else {
                    // Use the full custom prompt for longer transcripts
                    finalPrompt = """
                    \(customPrompt)
                    
                    Meeting Transcript:
                    \(truncatedTranscript)
                    """
                }
                
                let prompt = finalPrompt
                
                print("🤖 [AppleIntelligence] Sending transcript to Foundation Models for summary...")
                
                // Send the prompt and get response using simpler API without options
                // Research shows the simpler API is more stable in beta
                do {
                    print("🤖 [AppleIntelligence] Calling session.respond...")
                    let response = try await session.respond(to: prompt)
                    
                    // The response.content is already a String
                    let content = response.content
                    
                    guard !content.isEmpty else {
                        print("⚠️ [AppleIntelligence] Response had empty content")
                        throw AppleIntelligenceError.processingFailed
                    }
                    
                    print("✅ [AppleIntelligence] Meeting summary generated successfully")
                    return content
                } catch {
                    print("❌ [AppleIntelligence] Failed to generate summary: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    throw AppleIntelligenceError.processingFailed
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
                    if #available(macOS 26.0, *) {
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
                        
                        // Send the prompt and get response using simpler API without options
                        // Research shows the simpler API is more stable in beta
                        do {
                            print("🤖 [AppleIntelligence] Calling session.respond for pre-meeting brief...")
                            let response = try await session.respond(to: prompt)
                            
                            // The response.content is already a String
                            let content = response.content
                            
                            guard !content.isEmpty else {
                                print("⚠️ [AppleIntelligence] Response had empty content")
                                throw AppleIntelligenceError.processingFailed
                            }
                            
                            print("✅ [AppleIntelligence] Pre-meeting brief generated successfully")
                            return content
                        } catch {
                            print("❌ [AppleIntelligence] Failed to generate pre-meeting brief: \(error)")
                            print("❌ Error type: \(type(of: error))")
                            print("❌ Error description: \(error.localizedDescription)")
                            throw AppleIntelligenceError.processingFailed
                        }
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
                // Keep prompt professional to avoid triggering safety guardrails
                let prompt = """
                You are a professional assistant helping analyze business meeting information.
                
                User Question: \(message)
                
                Available Information:
                \(truncateContextForFoundationModels(context))
                
                Please provide a helpful, professional response based on the available information.
                If the information is limited, acknowledge this and provide what details are available.
                """
                
                print("🤖 [AppleIntelligence] Sending prompt to Foundation Models...")
                
                // Send the prompt and get response using simpler API without options
                // Research shows the simpler API is more stable in beta
                do {
                    print("🤖 [AppleIntelligence] Calling session.respond for chat enhancement...")
                    let response = try await session.respond(to: prompt)
                    
                    // The response.content is already a String
                    let content = response.content
                    
                    guard !content.isEmpty else {
                        print("⚠️ [AppleIntelligence] Response had empty content")
                        throw AppleIntelligenceError.processingFailed
                    }
                    
                    print("✅ [AppleIntelligence] Chat response generated successfully")
                    return content
                } catch {
                    print("❌ [AppleIntelligence] Failed to enhance chat: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    throw AppleIntelligenceError.processingFailed
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
            print("⚠️ [AppleIntelligence] macOS 26.0+ required, current version too old")
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        
        // Additional runtime check for framework availability
        if !isFoundationModelsAvailable {
            print("⚠️ [AppleIntelligence] Foundation Models not available on this system")
            throw AppleIntelligenceError.frameworkNotAvailable
        }
        
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
                
                // Check if transcript includes voice analysis metadata
                var voiceAnalysisInfo = ""
                if transcript.contains("[Voice Analysis:") {
                    voiceAnalysisInfo = """
                    IMPORTANT: Voice analysis has already been performed on this recording.
                    The voice analysis metadata is included at the beginning of the transcript.
                    Please respect the speaker count detected by voice analysis.
                    
                    """
                }
                
                // Prepare a more structured prompt
                // Keep prompt professional to avoid triggering safety guardrails
                let prompt = """
                Please identify all participants who spoke in this business meeting transcript.
                
                \(voiceAnalysisInfo)List only the names of people who actively participated in the conversation.
                Do not include people who were only mentioned but did not speak.
                
                If the same speaker name appears multiple times in the transcript (e.g., "Bob: text1" and "Bob: text2"), 
                this is the SAME person speaking multiple times, not different people.
                
                Meeting Transcript:
                \(truncateContextForFoundationModels(transcript))
                
                Please list each UNIQUE participant's name on a separate line.
                Do not repeat the same name multiple times.
                """
                
                print("🤖 [AppleIntelligence] Extracting participants from transcript...")
                
                // Send the prompt and get response using simpler API without options
                // Research shows the simpler API is more stable in beta
                do {
                    print("🤖 [AppleIntelligence] Calling session.respond for participant extraction...")
                    let response = try await session.respond(to: prompt)
                    
                    // The response.content is already a String
                    let content = response.content
                    
                    guard !content.isEmpty else {
                        print("⚠️ [AppleIntelligence] Response had empty content")
                        throw AppleIntelligenceError.processingFailed
                    }
                    
                    // Parse the response into an array of participant names
                    // Clean up any bullet points or formatting Apple Intelligence might add
                    let participants = content
                        .components(separatedBy: CharacterSet.newlines)
                        .map { line in
                            var cleaned = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            // Remove common bullet point formats
                            if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                            if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                            if cleaned.hasPrefix("• ") { cleaned = String(cleaned.dropFirst(2)) }
                            if cleaned.hasPrefix("· ") { cleaned = String(cleaned.dropFirst(2)) }
                            // Remove numbers like "1. ", "2. ", etc.
                            if let range = cleaned.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
                                cleaned.removeSubrange(range)
                            }
                            return cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        }
                        .filter { !$0.isEmpty }
                    
                    print("✅ [AppleIntelligence] Found \(participants.count) participants: \(participants)")
                    return participants
                } catch {
                    print("❌ [AppleIntelligence] Failed to extract participants: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    throw AppleIntelligenceError.processingFailed
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
