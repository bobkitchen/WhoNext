import Foundation
import CoreData
import Supabase

extension SupabaseSyncManager {
    
    // MARK: - Deduplication Functions
    
    func deduplicateAllData(context: NSManagedObjectContext) async throws {
        syncStatus = "Deduplicating data..."
        syncStep = "Analyzing data"
        syncProgress = 0.0
        isSyncing = true
        error = nil
        success = nil
        
        do {
            // First, analyze the data to understand the duplication
            try await analyzeConversationData(context: context)
            
            // Deduplicate local Core Data
            syncStep = "Deduplicating local people"
            syncProgress = 0.25
            try await deduplicateLocalPeople(context: context)
            
            syncStep = "Deduplicating local conversations"
            syncProgress = 0.5
            try await deduplicateLocalConversations(context: context)
            
            // Deduplicate Supabase
            syncStep = "Deduplicating Supabase people"
            syncProgress = 0.75
            try await deduplicateSupabasePeople()
            
            syncStep = "Deduplicating Supabase conversations"
            syncProgress = 0.9
            try await deduplicateSupabaseConversations()
            
            syncStep = "Completing deduplication"
            syncProgress = 1.0
            
            try context.save()
            
            success = "Deduplication completed successfully"
            syncStatus = "Ready"
            lastSyncDate = Date()
            
            print("✅ Deduplication completed successfully")
            
        } catch {
            self.error = "Deduplication failed: \(error.localizedDescription)"
            syncStatus = "Error"
            print("❌ Deduplication failed: \(error)")
            throw error
        }
        
        isSyncing = false
        syncProgress = 0.0
        syncStep = ""
    }
    
    private func deduplicateLocalPeople(context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let allPeople = try context.fetch(request)
        
        var seenIdentifiers = Set<UUID>()
        var duplicatesToDelete: [Person] = []
        
        for person in allPeople {
            if let identifier = person.identifier {
                if seenIdentifiers.contains(identifier) {
                    duplicatesToDelete.append(person)
                } else {
                    seenIdentifiers.insert(identifier)
                }
            }
        }
        
        for duplicate in duplicatesToDelete {
            context.delete(duplicate)
        }
        
        print("🗑️ Removed \(duplicatesToDelete.count) duplicate people from Core Data")
    }
    
    private func deduplicateLocalConversations(context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let allConversations = try context.fetch(request)
        
        // First, handle conversations without UUIDs
        var conversationsWithoutUUID: [Conversation] = []
        var conversationsWithUUID: [Conversation] = []
        
        for conversation in allConversations {
            if conversation.uuid == nil {
                conversationsWithoutUUID.append(conversation)
            } else {
                conversationsWithUUID.append(conversation)
            }
        }
        
        // Delete conversations without UUIDs (they're likely corrupted)
        for conversation in conversationsWithoutUUID {
            context.delete(conversation)
        }
        print("🗑️ Removed \(conversationsWithoutUUID.count) conversations without UUIDs")
        
        // Now deduplicate by content similarity
        var duplicatesToDelete: [Conversation] = []
        var processedConversations: [Conversation] = []
        
        for conversation in conversationsWithUUID {
            var isDuplicate = false
            
            for existing in processedConversations {
                if areConversationsDuplicates(conversation, existing) {
                    // Keep the one with more complete data or newer date
                    if shouldKeepFirstConversation(existing, over: conversation) {
                        duplicatesToDelete.append(conversation)
                    } else {
                        duplicatesToDelete.append(existing)
                        // Remove the existing from processed and add the new one
                        if let index = processedConversations.firstIndex(of: existing) {
                            processedConversations.remove(at: index)
                        }
                        processedConversations.append(conversation)
                    }
                    isDuplicate = true
                    break
                }
            }
            
            if !isDuplicate {
                processedConversations.append(conversation)
            }
        }
        
        // Delete duplicates
        for duplicate in duplicatesToDelete {
            context.delete(duplicate)
        }
        
        print("🗑️ Removed \(duplicatesToDelete.count) duplicate conversations from Core Data")
    }
    
    private func areConversationsDuplicates(_ conv1: Conversation, _ conv2: Conversation) -> Bool {
        // Check if they belong to the same person
        let person1Name = conv1.person?.name ?? "Unknown"
        let person2Name = conv2.person?.name ?? "Unknown"
        
        if person1Name != person2Name {
            return false
        }
        
        // Check if dates are the same or very close (within 1 hour)
        if let date1 = conv1.date, let date2 = conv2.date {
            let timeDifference = abs(date1.timeIntervalSince(date2))
            if timeDifference > 3600 { // More than 1 hour apart
                return false
            }
        } else if conv1.date != conv2.date {
            return false
        }
        
        // Check if content is similar
        let notes1 = conv1.notes ?? ""
        let notes2 = conv2.notes ?? ""
        let summary1 = conv1.summary ?? ""
        let summary2 = conv2.summary ?? ""
        
        // If both have content, compare it
        if !notes1.isEmpty && !notes2.isEmpty {
            return notes1 == notes2
        }
        
        if !summary1.isEmpty && !summary2.isEmpty {
            return summary1 == summary2
        }
        
        // If one has content and the other doesn't, they might be duplicates
        // from different sync states
        if (notes1.isEmpty && !notes2.isEmpty) || (!notes1.isEmpty && notes2.isEmpty) {
            return true
        }
        
        if (summary1.isEmpty && !summary2.isEmpty) || (!summary1.isEmpty && summary2.isEmpty) {
            return true
        }
        
        // If both are empty, consider them duplicates if person and date match
        return true
    }
    
    private func shouldKeepFirstConversation(_ first: Conversation, over second: Conversation) -> Bool {
        // Keep the one with more complete data
        let firstScore = getConversationCompletenessScore(first)
        let secondScore = getConversationCompletenessScore(second)
        
        if firstScore != secondScore {
            return firstScore > secondScore
        }
        
        // If completeness is equal, keep the newer one
        if let date1 = first.date, let date2 = second.date {
            return date1 > date2
        }
        
        // Default to keeping the first one
        return true
    }
    
    private func getConversationCompletenessScore(_ conversation: Conversation) -> Int {
        var score = 0
        
        if !(conversation.notes?.isEmpty ?? true) { score += 3 }
        if !(conversation.summary?.isEmpty ?? true) { score += 2 }
        if conversation.duration > 0 { score += 1 }
        if !(conversation.keyTopics?.isEmpty ?? true) { score += 1 }
        if conversation.sentimentScore != 0 { score += 1 }
        if conversation.qualityScore != 0 { score += 1 }
        
        return score
    }
    
    private func deduplicateSupabasePeople() async throws {
        // Get all people from Supabase
        let allPeople: [SupabasePerson] = try await SupabaseConfig.shared.client.database
            .from("people")
            .select()
            .execute()
            .value
        
        // Group by identifier
        var peopleByIdentifier: [String: [SupabasePerson]] = [:]
        for person in allPeople {
            let identifier = person.identifier
            peopleByIdentifier[identifier, default: []].append(person)
        }
        
        // Find and delete duplicates (keep the most recent one)
        var deletedCount = 0
        for (_, duplicates) in peopleByIdentifier {
            if duplicates.count > 1 {
                // Sort by created_at and keep the most recent
                let sorted = duplicates.sorted { 
                    let date1 = ISO8601DateFormatter().date(from: $0.createdAt ?? "") ?? Date.distantPast
                    let date2 = ISO8601DateFormatter().date(from: $1.createdAt ?? "") ?? Date.distantPast
                    return date1 > date2
                }
                let toDelete = Array(sorted.dropFirst()) // Remove all except the first (most recent)
                
                for person in toDelete {
                    try await SupabaseConfig.shared.client.database
                        .from("people")
                        .delete()
                        .eq("id", value: person.id ?? "")
                        .execute()
                    deletedCount += 1
                }
            }
        }
        
        print("🗑️ Removed \(deletedCount) duplicate people from Supabase")
    }
    
    private func deduplicateSupabaseConversations() async throws {
        // Get all conversations from Supabase
        let allConversations: [SupabaseConversation] = try await SupabaseConfig.shared.client.database
            .from("conversations")
            .select()
            .execute()
            .value
        
        // Group by uuid
        var conversationsByUUID: [String: [SupabaseConversation]] = [:]
        for conversation in allConversations {
            conversationsByUUID[conversation.uuid, default: []].append(conversation)
        }
        
        // Find and delete duplicates (keep the most recent one)
        var deletedCount = 0
        for (_, duplicates) in conversationsByUUID {
            if duplicates.count > 1 {
                // Sort by created_at and keep the most recent
                let sorted = duplicates.sorted { 
                    let date1 = ISO8601DateFormatter().date(from: $0.createdAt ?? "") ?? Date.distantPast
                    let date2 = ISO8601DateFormatter().date(from: $1.createdAt ?? "") ?? Date.distantPast
                    return date1 > date2
                }
                let toDelete = Array(sorted.dropFirst()) // Remove all except the first (most recent)
                
                for conversation in toDelete {
                    try await SupabaseConfig.shared.client.database
                        .from("conversations")
                        .delete()
                        .eq("id", value: conversation.id ?? "")
                        .execute()
                    deletedCount += 1
                }
            }
        }
        
        print("🗑️ Removed \(deletedCount) duplicate conversations from Supabase")
    }
    
    private func analyzeConversationData(context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let allConversations = try context.fetch(request)
        
        print("📊 CONVERSATION ANALYSIS:")
        print("Total conversations: \(allConversations.count)")
        
        var uuidCounts: [String: Int] = [:]
        var conversationsWithoutUUID = 0
        
        for conversation in allConversations {
            if let uuid = conversation.uuid {
                let uuidString = uuid.uuidString
                uuidCounts[uuidString, default: 0] += 1
            } else {
                conversationsWithoutUUID += 1
            }
        }
        
        print("Conversations without UUID: \(conversationsWithoutUUID)")
        print("Unique UUIDs: \(uuidCounts.count)")
        
        let duplicateUUIDs = uuidCounts.filter { $0.value > 1 }
        print("Duplicate UUIDs: \(duplicateUUIDs.count)")
        
        for (uuid, count) in duplicateUUIDs.prefix(5) {
            print("  UUID \(uuid): \(count) copies")
        }
        
        // Group by person to see conversation distribution
        var conversationsByPerson: [String: Int] = [:]
        for conversation in allConversations {
            let personName = conversation.person?.name ?? "Unknown"
            conversationsByPerson[personName, default: 0] += 1
        }
        
        print("Conversations by person:")
        for (person, count) in conversationsByPerson.sorted(by: { $0.value > $1.value }).prefix(10) {
            print("  \(person): \(count) conversations")
        }
    }
}
