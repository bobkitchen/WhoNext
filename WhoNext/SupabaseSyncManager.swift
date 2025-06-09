import Foundation
import CoreData
import Supabase
import Realtime
import Combine

@MainActor
class SupabaseSyncManager: ObservableObject {
    static let shared = SupabaseSyncManager()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncStatus = "Ready"
    @Published var syncProgress: Double = 0.0
    @Published var syncStep: String = ""
    @Published var errorMessage: String?
    @Published var error: String?
    @Published var success: String?
    
    private let supabase = SupabaseConfig.shared.client
    private let deviceId: String = {
        #if os(macOS)
        return ProcessInfo.processInfo.hostName + "-" + (ProcessInfo.processInfo.environment["USER"] ?? "unknown")
        #else
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #endif
    }()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupRealtimeSubscriptions()
    }
    
    // MARK: - Core Data Integration
    func syncWithSupabase(context: NSManagedObjectContext) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncStatus = "Syncing..."
        syncProgress = 0.0
        syncStep = ""
        errorMessage = nil
        error = nil
        success = nil
        
        do {
            try await performSync(context: context)
            lastSyncDate = Date()
            syncStatus = "Sync completed"
            success = "Sync completed successfully"
        } catch let syncError {
            await MainActor.run {
                isSyncing = false
                errorMessage = "Sync failed: \(syncError.localizedDescription)"
                syncStatus = "Sync failed"
            }
            print("❌ Supabase sync error: \(syncError)")
        }
        
        isSyncing = false
    }
    
    func syncNow(context: NSManagedObjectContext) async {
        await syncWithSupabase(context: context)
    }
    
    // MARK: - People Sync
    private func syncPeople(context: NSManagedObjectContext) async throws {
        syncStatus = "Syncing people..."
        syncStep = "Syncing people"
        syncProgress = 0.25
        
        // 1. Upload local changes to Supabase
        try await uploadPeopleToSupabase(context: context)
        
        // 2. Download remote changes from Supabase
        try await downloadPeopleFromSupabase(context: context)
        
        try context.save()
    }
    
    private func uploadPeopleToSupabase(context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let people = try context.fetch(request)
        
        for person in people {
            // Check if this person already exists in Supabase
            let existingResponse: [SupabasePerson] = try await supabase.database
                .from("people")
                .select()
                .eq("identifier", value: person.identifier?.uuidString ?? "")
                .execute()
                .value
            
            // Skip if person already exists in Supabase
            if !existingResponse.isEmpty {
                continue
            }
            
            let now = ISO8601DateFormatter().string(from: Date())
            let supabasePerson = SupabasePerson(
                id: nil, // Supabase auto-generates this
                identifier: person.identifier?.uuidString ?? UUID().uuidString,
                name: person.name,
                photoBase64: person.photo?.base64EncodedString(),
                notes: person.notes,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
                isDeleted: false,  // New records are not deleted
                deletedAt: nil,    // No deletion timestamp
                role: person.role,
                timezone: person.timezone,
                scheduledConversationDate: person.scheduledConversationDate?.ISO8601Format(),
                isDirectReport: person.isDirectReport
            )
            
            try await supabase.database
                .from("people")
                .insert(supabasePerson)
                .execute()
        }
    }
    
    private func downloadPeopleFromSupabase(context: NSManagedObjectContext) async throws {
        print("📥 Downloading people from Supabase...")
        
        let response: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
            .eq("is_deleted", value: false)  // Only get non-deleted records
            .execute()
            .value
        
        for remotePerson in response {
            let searchId = remotePerson.identifier ?? (remotePerson.id ?? "")
            
            // Check if person already exists locally
            let personRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            personRequest.predicate = NSPredicate(format: "identifier == %@", searchId as CVarArg)
            
            let person: Person
            if let existingPerson = try context.fetch(personRequest).first {
                person = existingPerson
            } else {
                person = Person(context: context)
            }
            
            // Update person with remote data
            person.identifier = UUID(uuidString: searchId) ?? UUID()
            person.name = remotePerson.name
            person.role = remotePerson.role
            person.notes = remotePerson.notes
            person.isDirectReport = remotePerson.isDirectReport ?? false
            person.timezone = remotePerson.timezone
            person.scheduledConversationDate = {
                if let dateString = remotePerson.scheduledConversationDate {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            person.photo = remotePerson.photoBase64 != nil ? Data(base64Encoded: remotePerson.photoBase64!) : nil
        }
    }
    
    // MARK: - Conversations Sync
    private func syncConversations(context: NSManagedObjectContext) async throws {
        syncStatus = "Syncing conversations..."
        syncStep = "Syncing conversations"
        syncProgress = 0.75
        
        // 1. Upload local changes
        try await uploadConversationsToSupabase(context: context)
        
        // 2. Download remote changes
        try await downloadConversationsFromSupabase(context: context)
        
        try context.save()
    }
    
    private func uploadConversationsToSupabase(context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let conversations = try context.fetch(request)
        
        for conversation in conversations {
            // Check if this conversation already exists in Supabase
            let existingResponse: [SupabaseConversation] = try await supabase.database
                .from("conversations")
                .select()
                .eq("uuid", value: conversation.uuid?.uuidString ?? "")
                .execute()
                .value
            
            // Skip if conversation already exists in Supabase
            if !existingResponse.isEmpty {
                continue
            }
            
            let now = ISO8601DateFormatter().string(from: Date())
            let supabaseConversation = SupabaseConversation(
                id: nil, // Supabase auto-generates this
                uuid: conversation.uuid?.uuidString ?? UUID().uuidString,
                personIdentifier: conversation.person?.identifier?.uuidString,
                date: conversation.date?.ISO8601Format(),
                notes: conversation.notes,
                summary: conversation.summary,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId,
                isDeleted: false,  // New records are not deleted
                deletedAt: nil,    // No deletion timestamp
                duration: conversation.duration > 0 ? Int(conversation.duration) : nil,
                engagementLevel: conversation.engagementLevel,
                analysisVersion: conversation.analysisVersion,
                keyTopics: conversation.keyTopics,
                qualityScore: conversation.qualityScore,
                sentimentLabel: conversation.sentimentLabel,
                sentimentScore: conversation.sentimentScore,
                lastAnalyzed: conversation.lastAnalyzed?.ISO8601Format(),
                lastSentimentAnalysis: conversation.lastSentimentAnalysis?.ISO8601Format(),
                legacyId: conversation.legacyId?.ISO8601Format()
            )
            
            try await supabase.database
                .from("conversations")
                .insert(supabaseConversation)
                .execute()
        }
    }
    
    private func downloadConversationsFromSupabase(context: NSManagedObjectContext) async throws {
        print("📥 Downloading conversations from Supabase...")
        
        let response: [SupabaseConversation] = try await supabase.database
            .from("conversations")
            .select()
            .eq("is_deleted", value: false)  // Only get non-deleted records
            .execute()
            .value
        
        for remoteConversation in response {
            let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            request.predicate = NSPredicate(format: "uuid == %@", remoteConversation.uuid as CVarArg)
            
            let existingConversations = try context.fetch(request)
            let conversation = existingConversations.first ?? Conversation(context: context)
            
            // Update conversation with remote data
            conversation.uuid = UUID(uuidString: remoteConversation.uuid) ?? UUID()
            conversation.date = {
                if let dateString = remoteConversation.date {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            conversation.duration = Int32(remoteConversation.duration ?? 0)
            conversation.engagementLevel = remoteConversation.engagementLevel
            conversation.notes = remoteConversation.notes
            conversation.summary = remoteConversation.summary
            conversation.analysisVersion = remoteConversation.analysisVersion
            conversation.keyTopics = remoteConversation.keyTopics
            conversation.qualityScore = remoteConversation.qualityScore
            conversation.sentimentLabel = remoteConversation.sentimentLabel
            conversation.sentimentScore = remoteConversation.sentimentScore
            conversation.lastAnalyzed = {
                if let dateString = remoteConversation.lastAnalyzed {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            conversation.lastSentimentAnalysis = {
                if let dateString = remoteConversation.lastSentimentAnalysis {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            conversation.legacyId = {
                if let dateString = remoteConversation.legacyId {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            
            // Link to person if exists
            if let personId = remoteConversation.personIdentifier {
                let personRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
                personRequest.predicate = NSPredicate(format: "identifier == %@", personId as CVarArg)
                if let person = try context.fetch(personRequest).first {
                    conversation.person = person
                }
            }
        }
    }
    
    // MARK: - Real-time Subscriptions
    private func setupRealtimeSubscriptions() {
        // TODO: Implement real-time subscriptions when Supabase Swift SDK API is stable
        // For now, we'll rely on manual sync
        print("Real-time subscriptions will be implemented in a future update")
    }
    
    // MARK: - Manual Sync Trigger
    func triggerManualSync() {
        Task {
            if let context = PersistenceController.shared.container.viewContext as NSManagedObjectContext? {
                await syncWithSupabase(context: context)
            }
        }
    }
    
    // MARK: - Utility Methods
    func resetSyncStatus() {
        errorMessage = nil
        error = nil
        success = nil
        syncStatus = "Ready"
        syncProgress = 0.0
        syncStep = ""
    }
    
    private func performSync(context: NSManagedObjectContext) async throws {
        print("🔄 Starting Supabase sync...")
        
        // Test basic connectivity first
        syncStep = "Testing connection"
        syncProgress = 0.1
        do {
            // Try a simple query to test connection - just count records
            let _ = try await supabase.database
                .from("people")
                .select("id", count: .exact)
                .limit(1)
                .execute()
            print("✅ Supabase connection test successful")
        } catch {
            print("❌ Supabase connection test failed: \(error)")
            throw error
        }
        
        // Upload local changes to Supabase
        syncStep = "Uploading local changes"
        syncProgress = 0.3
        try await uploadLocalChanges(context: context)
        
        // Download remote changes from Supabase
        syncStep = "Downloading remote changes"
        syncProgress = 0.8
        try await downloadRemoteChanges(context: context)
        
        syncStep = "Completing sync"
        syncProgress = 1.0
        print("✅ Supabase sync completed successfully")
    }
    
    private func uploadLocalChanges(context: NSManagedObjectContext) async throws {
        try await uploadPeopleToSupabase(context: context)
        try await uploadConversationsToSupabase(context: context)
        try await syncLocalDeletionsToSupabase(context: context)
    }
    
    public func downloadRemoteChanges(context: NSManagedObjectContext) async throws {
        try await downloadPeopleFromSupabase(context: context)
        try await downloadConversationsFromSupabase(context: context)
        try await syncRemoteDeletionsToLocal(context: context)
    }
    
    private func syncLocalDeletionsToSupabase(context: NSManagedObjectContext) async throws {
        print("🗑️ Syncing local deletions to Supabase using soft deletes...")
        
        let localPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let localPeople = try context.fetch(localPeopleRequest)
        let localPeopleIdentifiers = Set(localPeople.compactMap { $0.identifier?.uuidString })
        
        print("🔍 Debug: Found \(localPeople.count) local people with \(localPeopleIdentifiers.count) valid identifiers")
        
        // Get all remote people that are NOT marked as deleted
        let remotePeople: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
            .eq("is_deleted", value: false)
            .execute()
            .value
        
        let remotePeopleIdentifiers = Set(remotePeople.compactMap { $0.identifier })
        
        print("🔍 Debug: Found \(remotePeople.count) remote people with \(remotePeopleIdentifiers.count) valid identifiers")
        
        // Find people that exist remotely but not locally (deleted locally)
        let deletedPeopleIdentifiers = remotePeopleIdentifiers.subtracting(localPeopleIdentifiers)
        
        print("🔍 Debug: \(deletedPeopleIdentifiers.count) people appear to be deleted locally")
        
        // If this seems wrong, let's investigate further
        if deletedPeopleIdentifiers.count > 10 {
            print("⚠️ Warning: Large number of deletions detected. First few local identifiers:")
            for (index, identifier) in localPeopleIdentifiers.prefix(5).enumerated() {
                print("  Local \(index + 1): \(identifier)")
            }
            print("⚠️ First few remote identifiers:")
            for (index, identifier) in remotePeopleIdentifiers.prefix(5).enumerated() {
                print("  Remote \(index + 1): \(identifier ?? "nil")")
            }
        }
        
        // Mark them as deleted in Supabase (soft delete)
        var deletedPeopleCount = 0
        for identifier in deletedPeopleIdentifiers {
            do {
                let now = ISO8601DateFormatter().string(from: Date())
                try await supabase.database
                    .from("people")
                    .update(["is_deleted": true])
                    .eq("identifier", value: identifier)
                    .execute()
                
                try await supabase.database
                    .from("people")
                    .update(["deleted_at": now])
                    .eq("identifier", value: identifier)
                    .execute()
                    
                deletedPeopleCount += 1
            } catch {
                print("❌ Failed to soft delete person \(identifier): \(error)")
            }
        }
        
        // Do the same for conversations
        let localConversationsRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let localConversations = try context.fetch(localConversationsRequest)
        let localConversationUUIDs = Set(localConversations.compactMap { $0.uuid?.uuidString })
        
        let remoteConversations: [SupabaseConversation] = try await supabase.database
            .from("conversations")
            .select()
            .eq("is_deleted", value: false)
            .execute()
            .value
        
        let remoteConversationUUIDs = Set(remoteConversations.map { $0.uuid })
        
        // Find conversations that exist remotely but not locally (deleted locally)
        let deletedConversationUUIDs = remoteConversationUUIDs.subtracting(localConversationUUIDs)
        
        // Mark them as deleted in Supabase (soft delete)
        var deletedConversationsCount = 0
        for uuid in deletedConversationUUIDs {
            do {
                let now = ISO8601DateFormatter().string(from: Date())
                try await supabase.database
                    .from("conversations")
                    .update(["is_deleted": true])
                    .eq("uuid", value: uuid)
                    .execute()
                
                try await supabase.database
                    .from("conversations")
                    .update(["deleted_at": now])
                    .eq("uuid", value: uuid)
                    .execute()
                    
                deletedConversationsCount += 1
            } catch {
                print("❌ Failed to soft delete conversation \(uuid): \(error)")
            }
        }
        
        if deletedPeopleCount > 0 || deletedConversationsCount > 0 {
            print("🗑️ Soft deletion sync completed: \(deletedPeopleCount) people, \(deletedConversationsCount) conversations")
        }
        
        print("🗑️ Soft deletion sync completed: \(deletedPeopleCount) people, \(deletedConversationsCount) conversations")
    }
    
    private func syncRemoteDeletionsToLocal(context: NSManagedObjectContext) async throws {
        print("🗑️ Syncing remote deletions to local...")
        
        // Get all remote people that ARE marked as deleted
        let deletedRemotePeople: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
            .eq("is_deleted", value: true)
            .execute()
            .value
        
        let deletedRemotePeopleIdentifiers = Set(deletedRemotePeople.compactMap { $0.identifier })
        
        // Get all local people
        let localPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let localPeople = try context.fetch(localPeopleRequest)
        
        // Find and delete local people that are marked as deleted remotely
        var deletedLocalPeople = 0
        for person in localPeople {
            if let identifier = person.identifier?.uuidString,
               deletedRemotePeopleIdentifiers.contains(identifier) {
                context.delete(person)
                deletedLocalPeople += 1
            }
        }
        
        // Do the same for conversations
        let deletedRemoteConversations: [SupabaseConversation] = try await supabase.database
            .from("conversations")
            .select()
            .eq("is_deleted", value: true)
            .execute()
            .value
        
        let deletedRemoteConversationUUIDs = Set(deletedRemoteConversations.map { $0.uuid })
        
        let localConversationsRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let localConversations = try context.fetch(localConversationsRequest)
        
        // Find and delete local conversations that are marked as deleted remotely
        var deletedLocalConversations = 0
        for conversation in localConversations {
            if let uuid = conversation.uuid?.uuidString,
               deletedRemoteConversationUUIDs.contains(uuid) {
                context.delete(conversation)
                deletedLocalConversations += 1
            }
        }
        
        if deletedLocalPeople > 0 || deletedLocalConversations > 0 {
            print("🗑️ Remote deletion sync completed: \(deletedLocalPeople) people, \(deletedLocalConversations) conversations")
        }
    }
}
