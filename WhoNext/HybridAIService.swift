import Foundation
import SwiftUI

class HybridAIService: ObservableObject {
    @AppStorage("openaiApiKey") private var openaiApiKey: String = ""
    @AppStorage("openrouterApiKey") private var openrouterApiKey: String = ""
    @AppStorage("aiProvider") private var aiProvider: String = "apple" {
        didSet {
            // Trigger UI update when provider changes
            objectWillChange.send()
        }
    }
    
    private var appleIntelligenceService: AppleIntelligenceService?
    private var aiService: AIService
    
    init() {
        self.aiService = AIService()
        
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
        guard let appleService = appleIntelligenceService else {
            return false
        }
        return appleService.isFoundationModelsAvailable
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
               let appleService = appleIntelligenceService {
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
               let appleService = appleIntelligenceService {
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
               let appleService = appleIntelligenceService {
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
                let personData = [person]
                let context = "Pre-meeting preparation for \(person.name ?? "Unknown")"
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
                if let appleService = appleIntelligenceService {
                    return try await appleService.enhanceChat(message: message, context: context)
                } else {
                    print(" [HybridAI] Apple Intelligence service not initialized")
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
               let appleService = appleIntelligenceService {
                do {
                    return try await appleService.extractParticipants(from: transcript)
                } catch {
                    print("Apple Intelligence failed, falling back to cloud: \(error)")
                    return try await aiService.extractParticipants(from: transcript)
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
        // Use existing sendMessage method for transcript processing
        let prompt = """
        Generate a comprehensive meeting summary from this transcript. 
        Include purpose and context, key themes, and primary objectives discussed.
        Format as bullet points with clear sections.
        
        Transcript:
        \(transcript)
        """
        
        return try await sendMessage(prompt, context: "")
    }
    
    func generatePreMeetingBrief(personData: [Person], context: String) async throws -> String {
        let peopleInfo = personData.map { person in
            """
            **\(person.name ?? "Unknown")**
            - Role: \(person.role ?? "N/A")
            - Notes: \(person.notes ?? "N/A")
            """
        }.joined(separator: "\n\n")
        
        let prompt = """
        Generate a comprehensive pre-meeting brief based on the following information:
        
        Meeting Context: \(context)
        
        Participants:
        \(peopleInfo)
        
        Please provide:
        ## Meeting Overview
        ## Key Participants
        ## Discussion Topics
        ## Preparation Recommendations
        ## Potential Talking Points
        
        Format with markdown headers and bullet points for easy reading.
        """
        
        return try await sendMessage(prompt, context: "")
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
