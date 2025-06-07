import Foundation
import CoreData

// MARK: - Sentiment Analysis Migration Helper

class SentimentAnalysisMigration {
    
    /// Checks if the Core Data model needs migration for sentiment analysis fields
    static func needsMigration(context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.fetchLimit = 1
        
        do {
            let conversations = try context.fetch(request)
            if let conversation = conversations.first {
                // Check if the new sentiment fields exist by trying to access them
                _ = conversation.value(forKey: "sentimentScore")
                _ = conversation.value(forKey: "duration")
                return false // Fields exist, no migration needed
            }
            return false // No conversations, no migration needed
        } catch {
            // If we get an error accessing the fields, migration is likely needed
            print("Migration check error: \(error)")
            return true
        }
    }
    
    /// Performs initial setup for sentiment analysis on existing conversations
    static func performInitialSetup(context: NSManagedObjectContext) {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        
        do {
            let conversations = try context.fetch(request)
            var needsSave = false
            
            for conversation in conversations {
                // Set default values for new fields if they're not already set
                let analysisVersion = conversation.value(forKey: "analysisVersion") as? String
                if analysisVersion == nil || analysisVersion?.isEmpty == true {
                    conversation.setValue("0.0", forKey: "analysisVersion") // Mark as needing analysis
                    needsSave = true
                }
                
                // Set default duration if not set (estimate based on content length)
                let duration = conversation.value(forKey: "duration") as? Int32 ?? 0
                if duration == 0 && !(conversation.notes?.isEmpty ?? true) {
                    let estimatedDuration = estimateDurationFromContent(conversation.notes ?? "")
                    conversation.setValue(Int32(estimatedDuration), forKey: "duration")
                    needsSave = true
                }
            }
            
            if needsSave {
                try context.save()
                print("✅ Initial sentiment analysis setup completed for \(conversations.count) conversations")
            }
        } catch {
            print("❌ Error during initial sentiment analysis setup: \(error)")
        }
    }
    
    /// Estimates conversation duration based on content length
    private static func estimateDurationFromContent(_ content: String) -> Int {
        // Rough estimation: 150 words per minute speaking rate
        // Average word length is about 5 characters
        let wordCount = content.count / 5
        let estimatedMinutes = max(5, wordCount / 150) // Minimum 5 minutes
        return min(estimatedMinutes, 120) // Maximum 2 hours
    }
    
    /// Checks if sentiment analysis is available and ready
    static func isAnalysisReady() -> Bool {
        return SentimentAnalysisService.shared.isAvailable
    }
    
    /// Provides migration status information
    static func getMigrationStatus(context: NSManagedObjectContext) -> MigrationStatus {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        
        do {
            let allConversations = try context.fetch(request)
            let totalCount = allConversations.count
            
            if totalCount == 0 {
                return MigrationStatus(
                    totalConversations: 0,
                    analyzedConversations: 0,
                    needsAnalysis: 0,
                    isComplete: true,
                    message: "No conversations to analyze"
                )
            }
            
            let analyzedConversations = allConversations.filter { conversation in
                guard let version = conversation.value(forKey: "analysisVersion") as? String else { return false }
                return version == SentimentAnalysisService.shared.currentAnalysisVersion
            }
            
            let needsAnalysis = totalCount - analyzedConversations.count
            let isComplete = needsAnalysis == 0
            
            let message: String
            if isComplete {
                message = "All conversations analyzed"
            } else {
                message = "\(needsAnalysis) conversations need analysis"
            }
            
            return MigrationStatus(
                totalConversations: totalCount,
                analyzedConversations: analyzedConversations.count,
                needsAnalysis: needsAnalysis,
                isComplete: isComplete,
                message: message
            )
        } catch {
            return MigrationStatus(
                totalConversations: 0,
                analyzedConversations: 0,
                needsAnalysis: 0,
                isComplete: false,
                message: "Error checking status: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Migration Status

struct MigrationStatus {
    let totalConversations: Int
    let analyzedConversations: Int
    let needsAnalysis: Int
    let isComplete: Bool
    let message: String
    
    var completionPercentage: Double {
        guard totalConversations > 0 else { return 1.0 }
        return Double(analyzedConversations) / Double(totalConversations)
    }
}
