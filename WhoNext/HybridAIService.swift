import Foundation
import SwiftUI

class HybridAIService: ObservableObject {
    @AppStorage("aiProvider") private var aiProvider: String = "apple" {
        didSet {
            // Trigger UI update when provider changes
            objectWillChange.send()
        }
    }
    
    // Secure API key access
    private var openaiApiKey: String {
        SecureStorage.getAPIKey(for: .openai)
    }
    
    private var openrouterApiKey: String {
        SecureStorage.getAPIKey(for: .openrouter)
    }
    
    private var appleIntelligenceService: Any? // Will be AppleIntelligenceService when available
    private var aiService: AIService
    
    init() {
        self.aiService = AIService()
        
        // Migrate API keys to secure storage
        SecureStorage.migrateFromUserDefaults()
        
        // Migrate legacy "local" setting to "apple"
        if aiProvider == "local" {
            print(" [HybridAI] Migrating legacy 'local' setting to 'apple'")
            aiProvider = "apple"
        }
        
        // Initialize Apple Intelligence if available
        if #available(iOS 18.1, macOS 15.5, *) {
            self.appleIntelligenceService = AppleIntelligenceService()
        }
    }
    
    // MARK: - Provider Selection
    var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 18.1, macOS 15.5, *) {
            guard let appleService = appleIntelligenceService as? AppleIntelligenceService else {
                return false
            }
            return appleService.isFoundationModelsAvailable
        }
        return false
    }
    
    var preferredProvider: HybridAIProvider {
        // print(" [HybridAI] Provider selection - aiProvider: '\(aiProvider)', Apple Intelligence available: \(isAppleIntelligenceAvailable)")
        print(" [HybridAI] API Keys - OpenRouter: \(!openrouterApiKey.isEmpty), OpenAI: \(!openaiApiKey.isEmpty)")
        
        // Handle legacy "local" setting by treating it as "apple"
        let normalizedProvider = aiProvider == "local" ? "apple" : aiProvider
        print(" [HybridAI] Normalized provider: '\(normalizedProvider)' (original: '\(aiProvider)')")
        
        if isAppleIntelligenceAvailable && (normalizedProvider == "apple") {
            print(" [HybridAI] Selecting Apple Intelligence")
            return .appleIntelligence
        } else if !openrouterApiKey.isEmpty && normalizedProvider == "openrouter" {
            print(" [HybridAI] Selecting OpenRouter")
            return .openRouter
        } else if !openaiApiKey.isEmpty && normalizedProvider == "openai" {
            print(" [HybridAI] Selecting OpenAI")
            return .openAI
        } else if !openaiApiKey.isEmpty {
            print(" [HybridAI] Selecting OpenAI (fallback)")
            return .openAI
        } else if isAppleIntelligenceAvailable {
            print(" [HybridAI] Selecting Apple Intelligence (fallback)")
            return .appleIntelligence
        } else {
            print(" [HybridAI] No providers available")
            return .none
        }
    }
    
    // MARK: - Sentiment Analysis
    func analyzeSentiment(text: String) async throws -> ContextualSentiment {
        switch preferredProvider {
        case .appleIntelligence:
            if #available(iOS 18.1, macOS 15.5, *),
               let appleService = appleIntelligenceService as? AppleIntelligenceService {
                do {
                    return try await appleService.analyzeSentiment(text: text)
                } catch {
                    print("Apple Intelligence failed, falling back to cloud: \(error)")
                    return try await aiService.analyzeSentiment(text: text)
                }
            }
            fallthrough
        case .openRouter, .openAI:
            return try await aiService.analyzeSentiment(text: text)
        case .none:
            throw HybridAIError.noProviderAvailable
        }
    }
    
    // MARK: - Meeting Summary Generation
    func generateMeetingSummary(transcript: String) async throws -> String {
        switch preferredProvider {
        case .appleIntelligence:
            if #available(iOS 18.1, macOS 15.5, *),
               let appleService = appleIntelligenceService as? AppleIntelligenceService {
                do {
                    return try await appleService.generateMeetingSummary(transcript: transcript)
                } catch {
                    print("Apple Intelligence failed, falling back to cloud: \(error)")
                    return try await aiService.generateMeetingSummary(transcript: transcript)
                }
            }
            fallthrough
        case .openRouter, .openAI:
            return try await aiService.generateMeetingSummary(transcript: transcript)
        case .none:
            throw HybridAIError.noProviderAvailable
        }
    }
    
    // MARK: - Pre-Meeting Brief Generation
    func generatePreMeetingBrief(personData: [Person], context: String) async throws -> String {
        switch preferredProvider {
        case .appleIntelligence:
            if #available(iOS 18.1, macOS 15.5, *),
               let appleService = appleIntelligenceService as? AppleIntelligenceService {
                do {
                    return try await appleService.generatePreMeetingBrief(personData: personData, context: context)
                } catch {
                    print("Apple Intelligence failed, falling back to cloud: \(error)")
                    return try await aiService.generatePreMeetingBrief(personData: personData, context: context)
                }
            }
            fallthrough
        case .openRouter, .openAI:
            return try await aiService.generatePreMeetingBrief(personData: personData, context: context)
        case .none:
            throw HybridAIError.noProviderAvailable
        }
    }
    
    // MARK: - Pre-Meeting Brief Generation (with callback for compatibility)
    func generateBrief(for person: Person, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                // Use the enhanced context generation
                let context = PreMeetingBriefContextHelper.generateContext(for: person)
                let personData = [person]
                let brief = try await generatePreMeetingBrief(personData: personData, context: context)
                completion(.success(brief))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Chat Enhancement
    func sendMessage(_ message: String, context: String) async throws -> String {
        let provider = preferredProvider
        print(" [HybridAI] Preferred provider: \(provider)")
        print(" [HybridAI] Apple Intelligence available: \(isAppleIntelligenceAvailable)")
        
        switch provider {
        case .appleIntelligence:
            print(" [HybridAI] Attempting Apple Intelligence...")
            do {
                if #available(iOS 18.1, macOS 15.5, *) {
                    if let appleService = appleIntelligenceService as? AppleIntelligenceService {
                        return try await appleService.enhanceChat(message: message, context: context)
                    } else {
                        print(" [HybridAI] Apple Intelligence service not initialized")
                        throw HybridAIError.serviceUnavailable
                    }
                } else {
                    print(" [HybridAI] Apple Intelligence requires macOS 15.5 or later")
                    throw HybridAIError.serviceUnavailable
                }
            } catch {
                print(" [HybridAI] Apple Intelligence failed: \(error)")
                print(" [HybridAI] Falling back to cloud providers...")
                // Fall through to cloud providers
            }
            
            // Fallback to OpenRouter
            if !openrouterApiKey.isEmpty {
                print(" [HybridAI] Falling back to OpenRouter...")
                return try await aiService.sendMessage(message, context: context)
            }
            
            // Fallback to OpenAI
            if !openaiApiKey.isEmpty {
                print(" [HybridAI] Falling back to OpenAI...")
                let openAIService = AIService()
                openAIService.openaiApiKey = openaiApiKey
                openAIService.currentProvider = .openai
                return try await openAIService.sendMessage(message, context: context)
            }
            
            throw HybridAIError.noProvidersAvailable
            
        case .openRouter:
            print(" [HybridAI] Using OpenRouter...")
            return try await aiService.sendMessage(message, context: context)
            
        case .openAI:
            print(" [HybridAI] Using OpenAI...")
            let openAIService = AIService()
            openAIService.openaiApiKey = openaiApiKey
            openAIService.currentProvider = .openai
            return try await openAIService.sendMessage(message, context: context)
            
        case .none:
            print(" [HybridAI] No AI providers available")
            throw HybridAIError.noProvidersAvailable
        }
    }
    
    // MARK: - Participant Extraction
    func extractParticipants(from transcript: String) async throws -> [String] {
        let provider = preferredProvider
        print(" [HybridAI] Preferred provider for participant extraction: \(provider)")
        
        switch provider {
        case .appleIntelligence:
            if #available(iOS 18.1, macOS 15.5, *),
               let appleService = appleIntelligenceService as? AppleIntelligenceService {
                do {
                    return try await appleService.extractParticipants(from: transcript)
                } catch {
                    print("Apple Intelligence failed, falling back to cloud: \(error)")
                    // Ensure we have a valid fallback
                    if !openrouterApiKey.isEmpty || !openaiApiKey.isEmpty {
                        return try await aiService.extractParticipants(from: transcript)
                    } else {
                        // If no cloud API keys, try manual extraction as last resort
                        print("No cloud API keys available, using manual extraction")
                        throw error
                    }
                }
            }
            fallthrough
        case .openRouter, .openAI:
            let prompt = """
            Extract the names of all SPEAKERS/PARTICIPANTS from this meeting transcript.
            Only include people who are actually speaking in the meeting, not people mentioned in conversation.
            Look for names that appear before colons (Name:) or in speaker labels.
            Do NOT include names that are only mentioned within the conversation content.
            
            Return only a JSON array of actual speaker names as strings.
            
            Transcript:
            \(transcript)
            
            Example response: ["John Smith", "Jane Doe"]
            
            Only return the JSON array, nothing else.
            """
            
            let response = try await sendMessage(prompt, context: "")
            print("🤖 AI participant extraction response: \(response)")
            
            // Clean up response - remove markdown code blocks if present
            let cleanedResponse = response
                .replacingOccurrences(of: "```json\n", with: "")
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "\n```", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🤖 Cleaned response: \(cleanedResponse)")
            
            // Try to parse JSON response
            guard let data = cleanedResponse.data(using: .utf8) else {
                print("🤖 Failed to convert response to data")
                throw HybridAIError.allProvidersFailed
            }
            
            do {
                let decoder = JSONDecoder()
                let participants = try decoder.decode([String].self, from: data)
                print("🤖 Successfully parsed \(participants.count) participants: \(participants)")
                return participants
            } catch {
                print("🤖 JSON parsing failed: \(error)")
                print("🤖 Raw response was: \(response)")
                
                // Try to extract from response manually if JSON parsing fails
                let lines = response.components(separatedBy: .newlines)
                var extractedNames: [String] = []
                
                for line in lines {
                    // Look for quoted names
                    let quotedPattern = "\"([^\"]+)\""
                    if let regex = try? NSRegularExpression(pattern: quotedPattern) {
                        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                        for match in matches {
                            if let range = Range(match.range(at: 1), in: line) {
                                let name = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if name.count > 1 && name.contains(" ") {
                                    extractedNames.append(name)
                                }
                            }
                        }
                    }
                }
                
                print("🤖 Manual extraction found \(extractedNames.count) names: \(extractedNames)")
                return extractedNames
            }
        case .none:
            throw HybridAIError.noProviderAvailable
        }
    }
    
    // MARK: - Provider Status
    func getProviderStatus() -> String {
        let provider = preferredProvider
        print(" [HybridAI] getProviderStatus() - current provider: \(provider)")
        print(" [HybridAI] getProviderStatus() - aiProvider setting: '\(aiProvider)'")
        
        switch provider {
        case .appleIntelligence:
            return " Apple Intelligence (On-Device)"
        case .openRouter:
            return " OpenRouter (Cloud)"
        case .openAI:
            return " OpenAI (Cloud)"
        case .none:
            return " No AI Provider Available"
        }
    }
    
    func getProviderBenefits() -> [String] {
        switch preferredProvider {
        case .appleIntelligence:
            return [
                " Complete Privacy - Processing stays on device",
                " No API costs",
                " Works offline",
                " Fast response times",
                " No data sent to cloud"
            ]
        case .openRouter, .openAI:
            return [
                " Advanced AI capabilities",
                " Large context windows",
                " Continuously updated models",
                " Requires internet connection",
                " API costs apply"
            ]
        case .none:
            return [" Please configure an AI provider in Settings"]
        }
    }
}

// MARK: - Supporting Types
enum HybridAIProvider {
    case appleIntelligence
    case openRouter
    case openAI
    case none
}

enum HybridAIError: Error {
    case noProviderAvailable
    case allProvidersFailed
    case serviceUnavailable
    case noProvidersAvailable
}

// MARK: - AIService Extension
extension AIService {
    func generateMeetingSummary(transcript: String) async throws -> String {
        // Check if we're using GPT-5 model
        let isGPT5 = openaiModel.starts(with: "gpt-5")
        
        // Get the user's custom summarization prompt from settings
        let userCustomPrompt = UserDefaults.standard.string(forKey: "customSummarizationPrompt")
        
        // Log which prompt is being used
        if let customPrompt = userCustomPrompt, !customPrompt.isEmpty {
            print("📝 [AIService] Using custom summarization prompt from user settings")
        } else {
            print("📝 [AIService] Using default summarization prompt")
        }
        
        let customPrompt = userCustomPrompt ?? """
        Create comprehensive meeting minutes from the transcript below.
        
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
        """
        
        // Check if transcript is too large and needs chunking
        // GPT-5-nano has 272k token input limit, but we'll chunk for better quality
        // Estimate: 1 token ≈ 4 characters, so 200k chars ≈ 50k tokens (safe margin)
        let maxCharsPerChunk = 150000
        
        if transcript.count > maxCharsPerChunk {
            print("📊 [AIService] Large transcript detected (\(transcript.count) chars), using chunked processing")
            
            // Split transcript into overlapping chunks
            var chunks: [String] = []
            let overlapSize = 10000 // 10k char overlap to maintain context
            var startIndex = transcript.startIndex
            
            while startIndex < transcript.endIndex {
                let endIndex = transcript.index(startIndex, offsetBy: maxCharsPerChunk, limitedBy: transcript.endIndex) ?? transcript.endIndex
                let chunk = String(transcript[startIndex..<endIndex])
                chunks.append(chunk)
                
                // Move to next chunk with overlap
                if endIndex < transcript.endIndex {
                    startIndex = transcript.index(endIndex, offsetBy: -overlapSize, limitedBy: transcript.startIndex) ?? startIndex
                } else {
                    break
                }
            }
            
            print("📊 [AIService] Split into \(chunks.count) chunks for processing")
            
            // Process each chunk
            var chunkSummaries: [String] = []
            for (index, chunk) in chunks.enumerated() {
                print("📊 [AIService] Processing chunk \(index + 1) of \(chunks.count)")
                
                // Use appropriate prompt based on model
                let chunkPrompt: String
                if isGPT5 {
                    // Simplified prompt for GPT-5
                    chunkPrompt = """
                    Summarize part \(index + 1) of \(chunks.count) of this meeting transcript.
                    
                    Include key discussion points, decisions, and action items from this section.
                    
                    Transcript Section:
                    \(chunk)
                    """
                } else {
                    // Full custom prompt for GPT-4 and other models
                    chunkPrompt = """
                    \(customPrompt)
                    
                    Note: This is part \(index + 1) of \(chunks.count) of a longer transcript.
                    Focus on summarizing this section while maintaining context.
                    
                    Transcript Section:
                    \(chunk)
                    """
                }
                
                // Add a small delay between chunks to avoid rate limits
                if index > 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
                
                let chunkSummary = try await sendMessage(chunkPrompt, context: "")
                chunkSummaries.append(chunkSummary)
            }
            
            // Combine chunk summaries into final summary
            print("📊 [AIService] Combining \(chunkSummaries.count) chunk summaries")
            
            let combinedSummaries = chunkSummaries.enumerated().map { index, summary in
                "=== Section \(index + 1) ===\n\(summary)"
            }.joined(separator: "\n\n")
            
            // Use appropriate prompt for combining based on model
            let finalPrompt: String
            if isGPT5 {
                // Simplified combining prompt for GPT-5
                finalPrompt = """
                Combine these section summaries into unified meeting minutes.
                
                Include all key points, decisions, and action items.
                Use clear headers and bullet points.
                
                Section Summaries:
                \(combinedSummaries)
                """
            } else {
                // Full custom prompt for combining for GPT-4 and other models
                finalPrompt = """
                You have been provided with summaries from different sections of a meeting transcript.
                Please combine these into a single, coherent set of meeting minutes following this format:
                
                \(customPrompt)
                
                Section Summaries:
                \(combinedSummaries)
                
                Create unified meeting minutes that integrate all sections seamlessly.
                """
            }
            
            return try await sendMessage(finalPrompt, context: "")
            
        } else {
            // Normal processing for smaller transcripts
            let fullPrompt: String
            
            if isGPT5 {
                // Simplified prompt for GPT-5 compatibility - be more direct while using custom prompt
                // Extract just the essential instruction from the custom prompt
                let simplifiedCustom = customPrompt
                    .replacingOccurrences(of: "Format your response with these sections:", with: "Include:")
                    .replacingOccurrences(of: "Additional Notes:", with: "")
                    .components(separatedBy: "\n\n")
                    .prefix(3)  // Take only the first few sections
                    .joined(separator: "\n")
                
                fullPrompt = """
                Please summarize this meeting transcript into comprehensive meeting minutes.
                
                \(simplifiedCustom)
                
                Be thorough but well-organized. Use clear headers and bullet points.
                
                Transcript:
                \(transcript)
                """
            } else {
                // For GPT-4 and other models, use the full custom prompt
                fullPrompt = """
                \(customPrompt)
                
                Transcript:
                \(transcript)
                """
            }
            
            return try await sendMessage(fullPrompt, context: "")
        }
    }
    
    func generatePreMeetingBrief(personData: [Person], context: String) async throws -> String {
        // Get the user's custom prompt
        let customPrompt = UserDefaults.standard.string(forKey: "customPreMeetingPrompt") ?? """
You are an executive assistant preparing a comprehensive pre-meeting intelligence brief. Analyze the conversation history and generate actionable insights to help the user engage confidently and build stronger relationships.

## Required Analysis Sections:

**🎯 MEETING FOCUS**
- Primary topics likely to be discussed based on recent patterns
- Key decisions or follow-ups pending from previous conversations
- Strategic priorities this person is currently focused on

**🔍 RELATIONSHIP INTELLIGENCE** 
- Communication style and preferences observed
- Working relationship trajectory and current dynamic
- Personal interests, motivations, or concerns mentioned
- Trust level and rapport-building opportunities

**⚡ ACTIONABLE INSIGHTS**
- Specific tasks, commitments, or deadlines to reference
- Wins, achievements, or positive developments to acknowledge  
- Challenges, concerns, or support needs to address
- Conversation starters that demonstrate you remember past discussions

**📈 PATTERNS & TRENDS**
- Evolution of topics or priorities over time
- Meeting frequency patterns and optimal timing
- Engagement levels and conversation quality trends
- Any recurring themes or persistent issues

**🎪 STRATEGIC RECOMMENDATIONS**
- Key talking points to strengthen the relationship
- Questions to ask that show engagement and care
- Potential challenges to navigate carefully
- Follow-up actions to propose or discuss

## Output Guidelines:
- Be specific with dates, quotes, and concrete details
- Prioritize recent conversations but reference historical context
- Include both professional and personal rapport-building elements
- Highlight gaps where information is missing or unclear
- Format with clear headers and bullet points for easy scanning

Generate a comprehensive brief that enables confident, relationship-building engagement:
"""
        
        // Enhanced prompt with analysis instructions
        let enhancedPrompt = """
\(customPrompt)

CONTEXT TO ANALYZE:
\(context)

ANALYSIS INSTRUCTIONS:
- Extract specific insights, patterns, and actionable intelligence from the conversation history
- Identify relationship dynamics, communication preferences, and working styles  
- Highlight any recurring themes, concerns, or opportunities mentioned across conversations
- Note any commitments, deadlines, or follow-up items that need attention
- Suggest specific talking points that would demonstrate understanding and build rapport
- Be specific with dates, details, and quotes when relevant

Generate a comprehensive pre-meeting brief following the format above.
"""
        
        return try await sendMessage(enhancedPrompt, context: "")
    }
    
    func extractParticipants(from transcript: String) async throws -> [String] {
        let prompt = """
        Extract the names of all SPEAKERS/PARTICIPANTS from this meeting transcript.
        Only include people who are actually speaking in the meeting, not people mentioned in conversation.
        Look for names that appear before colons (Name:) or in speaker labels.
        Do NOT include names that are only mentioned within the conversation content.
        
        Return only a JSON array of actual speaker names as strings.
        
        Transcript:
        \(transcript)
        
        Example response: ["John Smith", "Jane Doe"]
        
        Only return the JSON array, nothing else.
        """
        
        let response = try await sendMessage(prompt, context: "")
        
        // Try to parse JSON response
        guard let data = response.data(using: .utf8) else {
            throw HybridAIError.allProvidersFailed
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([String].self, from: data)
    }
    
    func analyzeSentiment(text: String) async throws -> ContextualSentiment {
        let prompt = """
        Analyze the sentiment and emotional context of this conversation transcript. 
        Provide a detailed analysis including overall sentiment, confidence level, relationship health, 
        communication style, engagement level, energy level, key observations, support needs, 
        follow-up recommendations, risk factors, and strengths.
        
        Transcript:
        \(text)
        
        Please respond with a JSON object containing:
        - overallSentiment: string (Positive, Negative, Neutral)
        - sentimentScore: number (0-100)
        - confidence: number (0-100)
        - relationshipHealth: string (Excellent, Good, Fair, Poor)
        - communicationStyle: string
        - engagementLevel: string (High, Medium, Low)
        - energyLevel: string (High, Medium, Low)
        - keyObservations: array of strings
        - supportNeeds: array of strings
        - followUpRecommendations: array of strings
        - riskFactors: array of strings
        - strengths: array of strings
        """
        
        let response = try await sendMessage(prompt, context: "")
        
        // Parse JSON response
        guard let data = response.data(using: .utf8) else {
            throw HybridAIError.allProvidersFailed
        }
        
        let decoder = JSONDecoder()
        let sentimentData = try decoder.decode(SentimentData.self, from: data)
        
        return ContextualSentiment(
            overallSentiment: sentimentData.overallSentiment,
            sentimentScore: sentimentData.sentimentScore,
            confidence: sentimentData.confidence,
            engagementLevel: sentimentData.engagementLevel,
            relationshipHealth: sentimentData.relationshipHealth,
            communicationStyle: sentimentData.communicationStyle,
            energyLevel: sentimentData.energyLevel,
            participantDynamics: ParticipantDynamics(
                dominantSpeaker: "balanced",
                collaborationLevel: "medium",
                conflictIndicators: "none"
            ),
            keyObservations: sentimentData.keyObservations,
            supportNeeds: sentimentData.supportNeeds,
            followUpRecommendations: sentimentData.followUpRecommendations,
            riskFactors: sentimentData.riskFactors,
            strengths: sentimentData.strengths
        )
    }
}
