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
    private var syncTimer: Timer?
    
    private init() {
        setupRealtimeSubscriptions()
        setupPeriodicSync()
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
            
            let now = ISO8601DateFormatter().string(from: Date())
            let supabasePerson = SupabasePerson(
                id: existingResponse.first?.id, // Use existing ID if updating
                identifier: person.identifier?.uuidString ?? UUID().uuidString,
                name: person.name,
                photoBase64: person.photo?.base64EncodedString(),
                notes: person.notes,
                createdAt: existingResponse.first?.createdAt ?? now,
                updatedAt: now, // Always update timestamp
                deviceId: deviceId,
                isDeleted: nil, // No longer used
                deletedAt: nil, // No longer used
                role: person.role,
                timezone: person.timezone,
                scheduledConversationDate: person.scheduledConversationDate?.ISO8601Format(),
                isDirectReport: person.isDirectReport
            )
            
            if existingResponse.isEmpty {
                // Insert new person
                try await supabase.database
                    .from("people")
                    .insert(supabasePerson)
                    .execute()
                print("📤 Uploaded new person: \(person.name ?? "Unknown")")
            } else {
                // Update existing person with local changes
                try await supabase.database
                    .from("people")
                    .update(supabasePerson)
                    .eq("identifier", value: person.identifier?.uuidString ?? "")
                    .execute()
                print("📤 Updated existing person: \(person.name ?? "Unknown")")
            }
        }
    }
    
    private func downloadPeopleFromSupabase(context: NSManagedObjectContext) async throws {
        print("📥 Downloading people from Supabase...")
        
        let response: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
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
                
                // Check if remote data is newer before updating
                let remoteUpdatedAt = ISO8601DateFormatter().date(from: remotePerson.updatedAt ?? "")
                let localUpdatedAt = person.lastContactDate // Use last contact date as proxy for local updates
                
                // Only update if remote data is newer or if this is a new person
                if existingPerson == nil || (remoteUpdatedAt != nil && localUpdatedAt != nil && remoteUpdatedAt! > localUpdatedAt!) {
                    // Update person with remote data only if remote is newer
                    person.identifier = UUID(uuidString: searchId) ?? UUID()
                    
                    // Only update fields if remote data is not empty/nil
                    if let remoteName = remotePerson.name, !remoteName.isEmpty {
                        person.name = remoteName
                    }
                    if let remoteRole = remotePerson.role, !remoteRole.isEmpty {
                        person.role = remoteRole
                    }
                    if let remoteNotes = remotePerson.notes, !remoteNotes.isEmpty {
                        person.notes = remoteNotes
                    }
                    if let remoteIsDirectReport = remotePerson.isDirectReport {
                        person.isDirectReport = remoteIsDirectReport
                    }
                    if let remoteTimezone = remotePerson.timezone, !remoteTimezone.isEmpty {
                        person.timezone = remoteTimezone
                    }
                    if let remoteDateString = remotePerson.scheduledConversationDate {
                        person.scheduledConversationDate = ISO8601DateFormatter().date(from: remoteDateString)
                    }
                    if let remotePhotoBase64 = remotePerson.photoBase64, !remotePhotoBase64.isEmpty {
                        person.photo = Data(base64Encoded: remotePhotoBase64)
                    }
                }
            } else {
                person = Person(context: context)
                print("📥 Creating new person from remote data")
                
                // Update person with remote data
                person.identifier = UUID(uuidString: searchId) ?? UUID()
                
                // Only update fields if remote data is not empty/nil
                if let remoteName = remotePerson.name, !remoteName.isEmpty {
                    person.name = remoteName
                }
                if let remoteRole = remotePerson.role, !remoteRole.isEmpty {
                    person.role = remoteRole
                }
                if let remoteNotes = remotePerson.notes, !remoteNotes.isEmpty {
                    person.notes = remoteNotes
                }
                if let remoteIsDirectReport = remotePerson.isDirectReport {
                    person.isDirectReport = remoteIsDirectReport
                }
                if let remoteTimezone = remotePerson.timezone, !remoteTimezone.isEmpty {
                    person.timezone = remoteTimezone
                }
                if let remoteDateString = remotePerson.scheduledConversationDate {
                    person.scheduledConversationDate = ISO8601DateFormatter().date(from: remoteDateString)
                }
                if let remotePhotoBase64 = remotePerson.photoBase64, !remotePhotoBase64.isEmpty {
                    person.photo = Data(base64Encoded: remotePhotoBase64)
                }
            }
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
            
            let now = ISO8601DateFormatter().string(from: Date())
            let supabaseConversation = SupabaseConversation(
                id: existingResponse.first?.id, // Use existing ID if updating
                uuid: conversation.uuid?.uuidString ?? UUID().uuidString,
                personIdentifier: conversation.person?.identifier?.uuidString,
                date: conversation.date?.ISO8601Format(),
                notes: conversation.notes,
                summary: conversation.summary,
                createdAt: existingResponse.first?.createdAt ?? now,
                updatedAt: now, // Always update timestamp
                deviceId: deviceId,
                isDeleted: nil,  // No longer used
                deletedAt: nil,  // No longer used
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
            
            if existingResponse.isEmpty {
                // Insert new conversation
                try await supabase.database
                    .from("conversations")
                    .insert(supabaseConversation)
                    .execute()
                print("📤 Uploaded new conversation for: \(conversation.person?.name ?? "Unknown")")
            } else {
                // Update existing conversation with local changes
                try await supabase.database
                    .from("conversations")
                    .update(supabaseConversation)
                    .eq("uuid", value: conversation.uuid?.uuidString ?? "")
                    .execute()
                print("📤 Updated existing conversation for: \(conversation.person?.name ?? "Unknown")")
            }
        }
    }
    
    private func downloadConversationsFromSupabase(context: NSManagedObjectContext) async throws {
        print("📥 Downloading conversations from Supabase...")
        
        let response: [SupabaseConversation] = try await supabase.database
            .from("conversations")
            .select()
            .execute()
            .value
        
        for remoteConversation in response {
            let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            request.predicate = NSPredicate(format: "uuid == %@", remoteConversation.uuid as CVarArg)
            
            let existingConversations = try context.fetch(request)
            let conversation = existingConversations.first ?? Conversation(context: context)
            
            // Check if remote data is newer before updating
            let remoteUpdatedAt = ISO8601DateFormatter().date(from: remoteConversation.updatedAt ?? "")
            let localUpdatedAt = conversation.lastAnalyzed ?? conversation.lastSentimentAnalysis
            
            // Only update if remote data is newer or if this is a new conversation
            if existingConversations.isEmpty || (remoteUpdatedAt != nil && localUpdatedAt != nil && remoteUpdatedAt! > localUpdatedAt!) {
                // Update conversation with remote data only if remote is newer
                conversation.uuid = UUID(uuidString: remoteConversation.uuid) ?? UUID()
                conversation.date = {
                    if let dateString = remoteConversation.date {
                        return ISO8601DateFormatter().date(from: dateString)
                    }
                    return nil
                }()
                conversation.duration = Int32(remoteConversation.duration ?? 0)
                
                // Only update fields if remote data is not empty
                if let remoteEngagementLevel = remoteConversation.engagementLevel, !remoteEngagementLevel.isEmpty {
                    conversation.engagementLevel = remoteEngagementLevel
                }
                if let remoteNotes = remoteConversation.notes, !remoteNotes.isEmpty {
                    conversation.notes = remoteNotes
                }
                if let remoteSummary = remoteConversation.summary, !remoteSummary.isEmpty {
                    conversation.summary = remoteSummary
                }
                if let remoteAnalysisVersion = remoteConversation.analysisVersion, !remoteAnalysisVersion.isEmpty {
                    conversation.analysisVersion = remoteAnalysisVersion
                }
                
                // Handle numeric fields properly
                conversation.qualityScore = remoteConversation.qualityScore
                conversation.sentimentScore = remoteConversation.sentimentScore
                
                if let remoteSentimentLabel = remoteConversation.sentimentLabel, !remoteSentimentLabel.isEmpty {
                    conversation.sentimentLabel = remoteSentimentLabel
                }
                
                // Handle date fields
                if let remoteLastAnalyzed = remoteConversation.lastAnalyzed {
                    conversation.lastAnalyzed = ISO8601DateFormatter().date(from: remoteLastAnalyzed)
                }
                if let remoteLastSentimentAnalysis = remoteConversation.lastSentimentAnalysis {
                    conversation.lastSentimentAnalysis = ISO8601DateFormatter().date(from: remoteLastSentimentAnalysis)
                }
                
                // Find the associated person
                if let personIdentifier = remoteConversation.personIdentifier {
                    let personRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
                    personRequest.predicate = NSPredicate(format: "identifier == %@", personIdentifier as CVarArg)
                    if let associatedPerson = try context.fetch(personRequest).first {
                        conversation.person = associatedPerson
                    }
                }
            }
        }
    }
    
    // MARK: - Real-time Subscriptions
    private func setupRealtimeSubscriptions() {
        print("🔄 Real-time sync setup deferred - using periodic sync instead")
        // Note: Supabase Swift SDK real-time API is complex and version-dependent
        // For now, we'll use app launch + app resume sync as our real-time solution
        // TODO: Implement proper real-time subscriptions when API is more stable
    }
    
    // MARK: - Periodic Sync
    private func setupPeriodicSync() {
        print("⏰ Setting up periodic sync every 5 minutes...")
        
        // Create a timer that syncs every 5 minutes
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                print("⏰ Periodic sync triggered")
                guard let self = self,
                      let context = PersistenceController.shared.container.viewContext as NSManagedObjectContext? else { return }
                await self.syncWithSupabase(context: context)
            }
        }
        
        // Ensure timer runs in all run loop modes
        if let timer = syncTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
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
        try await deleteRemovedPeopleFromSupabase(context: context)
        try await deleteRemovedConversationsFromSupabase(context: context)
    }
    
    public func downloadRemoteChanges(context: NSManagedObjectContext) async throws {
        try await downloadPeopleFromSupabase(context: context)
        try await downloadConversationsFromSupabase(context: context)
    }
    
    // MARK: - True Deletion (Hard Delete)
    private func deleteRemovedPeopleFromSupabase(context: NSManagedObjectContext) async throws {
        print("🗑️ Hard deleting people removed locally from Supabase...")
        
        // Get local people identifiers
        let localPeopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let localPeople = try context.fetch(localPeopleRequest)
        let localPeopleIdentifiers = Set(localPeople.compactMap { $0.identifier?.uuidString })
        
        print("🔍 Local people count: \(localPeople.count)")
        
        // Get all remote people
        let remotePeople: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
            .execute()
            .value
        
        print("🔍 Remote people count: \(remotePeople.count)")
        
        // Find people that exist remotely but not locally (deleted locally)
        var deletedCount = 0
        for remotePerson in remotePeople {
            let remoteIdentifier = remotePerson.identifier
            
            // If this remote person doesn't exist locally, delete it from cloud
            if !localPeopleIdentifiers.contains(remoteIdentifier) {
                do {
                    try await supabase.database
                        .from("people")
                        .delete()
                        .eq("identifier", value: remoteIdentifier)
                        .execute()
                    
                    deletedCount += 1
                    print("🗑️ Hard deleted person: \(remotePerson.name ?? "Unknown") (ID: \(remoteIdentifier))")
                } catch {
                    print("❌ Failed to delete person \(remotePerson.name ?? "Unknown"): \(error)")
                }
            }
        }
        
        print("🗑️ Hard deletion completed: \(deletedCount) people permanently removed from cloud")
    }
    
    private func deleteRemovedConversationsFromSupabase(context: NSManagedObjectContext) async throws {
        print("🗑️ Hard deleting conversations removed locally from Supabase...")
        
        // Get local conversation UUIDs
        let localConversationsRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let localConversations = try context.fetch(localConversationsRequest)
        let localConversationUUIDs = Set(localConversations.compactMap { $0.uuid?.uuidString })
        
        print("🔍 Local conversations count: \(localConversations.count)")
        
        // Get all remote conversations
        let remoteConversations: [SupabaseConversation] = try await supabase.database
            .from("conversations")
            .select()
            .execute()
            .value
        
        print("🔍 Remote conversations count: \(remoteConversations.count)")
        
        // Find conversations that exist remotely but not locally (deleted locally)
        var deletedCount = 0
        for remoteConversation in remoteConversations {
            let remoteUUID = remoteConversation.uuid
            
            // If this remote conversation doesn't exist locally, delete it from cloud
            if !localConversationUUIDs.contains(remoteUUID) {
                do {
                    try await supabase.database
                        .from("conversations")
                        .delete()
                        .eq("uuid", value: remoteUUID)
                        .execute()
                    
                    deletedCount += 1
                    print("🗑️ Hard deleted conversation: \(remoteUUID)")
                } catch {
                    print("❌ Failed to delete conversation \(remoteUUID): \(error)")
                }
            }
        }
        
        print("🗑️ Hard deletion completed: \(deletedCount) conversations permanently removed from cloud")
    }
}
