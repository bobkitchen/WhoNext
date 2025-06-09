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
            
            let supabasePerson = SupabasePerson(
                id: UUID().uuidString, // Supabase auto-generates this
                identifier: person.identifier?.uuidString ?? UUID().uuidString,
                name: person.name,
                role: person.role,
                notes: person.notes,
                isDirectReport: person.isDirectReport,
                timezone: person.timezone,
                scheduledConversationDate: person.scheduledConversationDate,
                photoBase64: person.photo?.base64EncodedString(),
                createdAt: Date(),
                updatedAt: Date()
            )
            
            try await supabase.database
                .from("people")
                .insert(supabasePerson)
                .execute()
        }
    }
    
    private func downloadPeopleFromSupabase(context: NSManagedObjectContext) async throws {
        let response: [SupabasePerson] = try await supabase.database
            .from("people")
            .select()
            .execute()
            .value
        
        for remotePerson in response {
            let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            
            // Use identifier if available, otherwise use the Supabase id
            let searchId = remotePerson.identifier ?? remotePerson.id
            request.predicate = NSPredicate(format: "identifier == %@", searchId as CVarArg)
            
            let existingPeople = try context.fetch(request)
            let person = existingPeople.first ?? Person(context: context)
            
            // Update person with remote data
            person.identifier = UUID(uuidString: searchId) ?? UUID()
            person.name = remotePerson.name
            person.role = remotePerson.role
            person.notes = remotePerson.notes
            person.isDirectReport = remotePerson.isDirectReport
            person.timezone = remotePerson.timezone
            person.scheduledConversationDate = remotePerson.scheduledConversationDate
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
            
            let supabaseConversation = SupabaseConversation(
                id: UUID().uuidString, // Supabase auto-generates this
                uuid: conversation.uuid?.uuidString ?? UUID().uuidString,
                personId: conversation.person?.identifier?.uuidString,
                date: conversation.date,
                duration: conversation.duration > 0 ? Int(conversation.duration) : nil,
                engagementLevel: conversation.engagementLevel,
                notes: conversation.notes,
                summary: conversation.summary,
                analysisVersion: conversation.analysisVersion,
                keyTopics: conversation.keyTopics,
                qualityScore: conversation.qualityScore,
                sentimentLabel: conversation.sentimentLabel,
                sentimentScore: conversation.sentimentScore,
                lastAnalyzed: conversation.lastAnalyzed,
                lastSentimentAnalysis: conversation.lastSentimentAnalysis,
                legacyId: conversation.legacyId,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            try await supabase.database
                .from("conversations")
                .insert(supabaseConversation)
                .execute()
        }
    }
    
    private func downloadConversationsFromSupabase(context: NSManagedObjectContext) async throws {
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
            
            // Update conversation with remote data
            conversation.uuid = UUID(uuidString: remoteConversation.uuid) ?? UUID()
            conversation.date = remoteConversation.date
            conversation.duration = Int32(remoteConversation.duration ?? 0)
            conversation.engagementLevel = remoteConversation.engagementLevel
            conversation.notes = remoteConversation.notes
            conversation.summary = remoteConversation.summary
            conversation.analysisVersion = remoteConversation.analysisVersion
            conversation.keyTopics = remoteConversation.keyTopics
            conversation.qualityScore = remoteConversation.qualityScore
            conversation.sentimentLabel = remoteConversation.sentimentLabel
            conversation.sentimentScore = remoteConversation.sentimentScore
            conversation.lastAnalyzed = remoteConversation.lastAnalyzed
            conversation.lastSentimentAnalysis = remoteConversation.lastSentimentAnalysis
            conversation.legacyId = remoteConversation.legacyId
            
            // Link to person if exists
            if let personId = remoteConversation.personId {
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
            let response = try await supabase.database
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
        try await syncPeople(context: context)
        try await syncConversations(context: context)
    }
    
    private func downloadRemoteChanges(context: NSManagedObjectContext) async throws {
        try await syncPeople(context: context)
        try await syncConversations(context: context)
    }
}
