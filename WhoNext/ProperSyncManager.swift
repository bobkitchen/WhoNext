import Foundation
import CoreData
import Supabase

@MainActor
class ProperSyncManager: ObservableObject {
    static let shared = ProperSyncManager()
    
    @Published var isSyncing = false
    @Published var syncStatus = "Ready"
    @Published var lastSyncDate: Date?
    
    private let supabase = SupabaseConfig.shared.client
    private let deviceId: String = {
        #if os(macOS)
        return ProcessInfo.processInfo.hostName + "-" + (ProcessInfo.processInfo.environment["USER"] ?? "unknown")
        #else
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #endif
    }()
    
    private let userDefaults = UserDefaults.standard
    private var lastPeopleSync: Date {
        get { userDefaults.object(forKey: "lastPeopleSync") as? Date ?? Date.distantPast }
        set { userDefaults.set(newValue, forKey: "lastPeopleSync") }
    }
    
    private var lastConversationsSync: Date {
        get { userDefaults.object(forKey: "lastConversationsSync") as? Date ?? Date.distantPast }
        set { userDefaults.set(newValue, forKey: "lastConversationsSync") }
    }
    
    private init() {}
    
    // MARK: - Main Sync Method
    func performSync(context: NSManagedObjectContext) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncStatus = "Starting sync..."
        
        do {
            // Sync in proper order: people first, then conversations
            try await syncPeople(context: context)
            try await syncConversations(context: context)
            
            // Update sync timestamps
            lastSyncDate = Date()
            syncStatus = "Sync completed successfully"
            
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription)"
            print("❌ Sync failed: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - People Sync
    private func syncPeople(context: NSManagedObjectContext) async throws {
        syncStatus = "Syncing people..."
        
        // 1. Upload local changes (new/modified/deleted people)
        try await uploadPeopleChanges(context: context)
        
        // 2. Download remote changes since last sync
        try await downloadPeopleChanges(context: context)
        
        // 3. Save changes
        try context.save()
        
        // 4. Update sync timestamp
        lastPeopleSync = Date()
    }
    
    private func uploadPeopleChanges(context: NSManagedObjectContext) async throws {
        // For initial sync, don't upload existing people - they're already in Supabase
        if lastPeopleSync == Date.distantPast {
            print("📤 Skipping initial upload - people already exist in Supabase")
            return
        }
        
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        let localPeople = try context.fetch(request)
        
        print("📤 Uploading changes for \(localPeople.count) people...")
        
        for person in localPeople {
            guard let identifier = person.identifier?.uuidString else { continue }
            
            // Check if this person needs to be synced
            let lastModified = person.modifiedAt ?? person.createdAt ?? Date.distantPast
            if lastModified <= lastPeopleSync {
                continue // Skip unchanged people
            }
            
            let now = Date()
            let supabasePerson = SupabasePerson(
                id: nil,
                identifier: identifier,
                name: person.name?.isEmpty == true ? nil : person.name,
                photoBase64: person.photo?.base64EncodedString(),
                notes: person.notes?.isEmpty == true ? nil : person.notes,
                createdAt: now.ISO8601Format(),
                updatedAt: now.ISO8601Format(),
                deviceId: deviceId,
                isSoftDeleted: false,
                deletedAt: nil,
                role: person.role?.isEmpty == true ? nil : person.role,
                timezone: person.timezone?.isEmpty == true ? nil : person.timezone,
                scheduledConversationDate: person.scheduledConversationDate?.ISO8601Format(),
                isDirectReport: person.isDirectReport
            )
            
            try await supabase
                .from("people")
                .upsert([supabasePerson])
                .execute()
            
            print("✅ Synced person: \(person.name ?? "Unknown")")
        }
    }
    
    private func downloadPeopleChanges(context: NSManagedObjectContext) async throws {
        let response: [SupabasePerson]
        
        if lastPeopleSync == Date.distantPast {
            // Initial sync - get all people
            response = try await supabase
                .from("people")
                .select()
                .execute()
                .value
            print("📥 Initial download: \(response.count) people from Supabase")
        } else {
            // Incremental sync - only get changes since last sync
            let lastSyncISO = ISO8601DateFormatter().string(from: lastPeopleSync)
            response = try await supabase
                .from("people")
                .select()
                .gte("updated_at", value: lastSyncISO)
                .execute()
                .value
            print("📥 Downloaded \(response.count) changed people from Supabase")
        }
        
        for remotePerson in response {
            // Handle deletions first
            if remotePerson.isSoftDeleted == true {
                await handlePersonDeletion(remotePerson, context: context)
                continue
            }
            
            // Handle updates/inserts
            await handlePersonUpsert(remotePerson, context: context)
        }
    }
    
    private func handlePersonDeletion(_ remotePerson: SupabasePerson, context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "identifier == %@", remotePerson.identifier as CVarArg)
        
        do {
            if let localPerson = try context.fetch(request).first {
                context.delete(localPerson)
                print("🗑️ Deleted person locally: \(localPerson.name ?? "Unknown")")
            }
        } catch {
            print("❌ Error handling person deletion: \(error)")
        }
    }
    
    private func handlePersonUpsert(_ remotePerson: SupabasePerson, context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "identifier == %@", remotePerson.identifier as CVarArg)
        
        do {
            let person = try context.fetch(request).first ?? Person(context: context)
            
            // Update person with remote data
            person.identifier = UUID(uuidString: remotePerson.identifier) ?? UUID()
            
            if let name = remotePerson.name, !name.isEmpty {
                person.name = name
            }
            if let role = remotePerson.role, !role.isEmpty {
                person.role = role
            }
            if let notes = remotePerson.notes, !notes.isEmpty {
                person.notes = notes
            }
            if let isDirectReport = remotePerson.isDirectReport {
                person.isDirectReport = isDirectReport
            }
            if let timezone = remotePerson.timezone, !timezone.isEmpty {
                person.timezone = timezone
            }
            if let dateString = remotePerson.scheduledConversationDate {
                person.scheduledConversationDate = ISO8601DateFormatter().date(from: dateString)
            }
            if let photoBase64 = remotePerson.photoBase64, !photoBase64.isEmpty {
                person.photo = Data(base64Encoded: photoBase64)
            }
            
            print("✅ Updated person locally: \(person.name ?? "Unknown")")
            
        } catch {
            print("❌ Error handling person upsert: \(error)")
        }
    }
    
    // MARK: - Conversations Sync
    private func syncConversations(context: NSManagedObjectContext) async throws {
        syncStatus = "Syncing conversations..."
        
        // 1. Upload local changes
        try await uploadConversationsChanges(context: context)
        
        // 2. Download remote changes
        try await downloadConversationsChanges(context: context)
        
        // 3. Update sync timestamp
        lastConversationsSync = Date()
    }
    
    private func uploadConversationsChanges(context: NSManagedObjectContext) async throws {
        // For initial sync, don't upload existing conversations - they're already in Supabase
        if lastConversationsSync == Date.distantPast {
            print("📤 Skipping initial upload - conversations already exist in Supabase")
            return
        }
        
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        let localConversations = try context.fetch(request)
        
        print("📤 Uploading changes for \(localConversations.count) conversations...")
        
        for conversation in localConversations {
            guard let uuid = conversation.uuid?.uuidString else { continue }
            
            // Check if this conversation needs to be synced
            let lastModified = conversation.modifiedAt ?? conversation.createdAt ?? Date.distantPast
            if lastModified <= lastConversationsSync {
                continue // Skip unchanged conversations
            }
            
            let now = Date()
            let supabaseConversation = SupabaseConversation(
                id: nil,
                uuid: uuid,
                personIdentifier: conversation.person?.identifier?.uuidString,
                date: conversation.date?.ISO8601Format(),
                notes: conversation.notes?.isEmpty == true ? nil : conversation.notes,
                summary: conversation.summary?.isEmpty == true ? nil : conversation.summary,
                createdAt: now.ISO8601Format(),
                updatedAt: now.ISO8601Format(),
                deviceId: deviceId,
                isSoftDeleted: false,
                deletedAt: nil,
                duration: conversation.duration > 0 ? Int(conversation.duration) : nil,
                engagementLevel: conversation.engagementLevel?.isEmpty == true ? nil : conversation.engagementLevel,
                analysisVersion: conversation.analysisVersion?.isEmpty == true ? nil : conversation.analysisVersion,
                keyTopics: conversation.keyTopics?.isEmpty == true ? nil : conversation.keyTopics,
                qualityScore: conversation.qualityScore,
                sentimentLabel: conversation.sentimentLabel?.isEmpty == true ? nil : conversation.sentimentLabel,
                sentimentScore: conversation.sentimentScore,
                lastAnalyzed: conversation.lastAnalyzed?.ISO8601Format(),
                lastSentimentAnalysis: conversation.lastSentimentAnalysis?.ISO8601Format(),
                legacyId: conversation.legacyId?.ISO8601Format()
            )
            
            try await supabase
                .from("conversations")
                .upsert([supabaseConversation])
                .execute()
            
            print("✅ Synced conversation: \(uuid)")
        }
    }
    
    private func downloadConversationsChanges(context: NSManagedObjectContext) async throws {
        let response: [SupabaseConversation]
        
        if lastConversationsSync == Date.distantPast {
            // Initial sync - get all conversations
            response = try await supabase
                .from("conversations")
                .select()
                .execute()
                .value
            print("📥 Initial download: \(response.count) conversations from Supabase")
        } else {
            // Incremental sync - only get changes since last sync
            let lastSyncISO = ISO8601DateFormatter().string(from: lastConversationsSync)
            response = try await supabase
                .from("conversations")
                .select()
                .gte("updated_at", value: lastSyncISO)
                .execute()
                .value
            print("📥 Downloaded \(response.count) changed conversations from Supabase")
        }
        
        for remoteConversation in response {
            if remoteConversation.isSoftDeleted == true {
                await handleConversationDeletion(remoteConversation, context: context)
            } else {
                await handleConversationUpsert(remoteConversation, context: context)
            }
        }
    }
    
    private func handleConversationDeletion(_ remoteConversation: SupabaseConversation, context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.predicate = NSPredicate(format: "uuid == %@", remoteConversation.uuid as CVarArg)
        
        do {
            if let localConversation = try context.fetch(request).first {
                context.delete(localConversation)
                print("🗑️ Deleted conversation locally: \(remoteConversation.uuid)")
            }
        } catch {
            print("❌ Error handling conversation deletion: \(error)")
        }
    }
    
    private func handleConversationUpsert(_ remoteConversation: SupabaseConversation, context: NSManagedObjectContext) async {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.predicate = NSPredicate(format: "uuid == %@", remoteConversation.uuid as CVarArg)
        
        do {
            let conversation = try context.fetch(request).first ?? Conversation(context: context)
            
            // Update conversation with remote data
            conversation.uuid = UUID(uuidString: remoteConversation.uuid) ?? UUID()
            conversation.date = {
                if let dateString = remoteConversation.date {
                    return ISO8601DateFormatter().date(from: dateString)
                }
                return nil
            }()
            conversation.duration = Int32(remoteConversation.duration ?? 0)
            
            if let notes = remoteConversation.notes, !notes.isEmpty {
                conversation.notes = notes
            }
            if let summary = remoteConversation.summary, !summary.isEmpty {
                conversation.summary = summary
            }
            if let engagementLevel = remoteConversation.engagementLevel, !engagementLevel.isEmpty {
                conversation.engagementLevel = engagementLevel
            }
            
            conversation.qualityScore = remoteConversation.qualityScore
            conversation.sentimentScore = remoteConversation.sentimentScore
            
            if let sentimentLabel = remoteConversation.sentimentLabel, !sentimentLabel.isEmpty {
                conversation.sentimentLabel = sentimentLabel
            }
            
            if let lastAnalyzed = remoteConversation.lastAnalyzed {
                conversation.lastAnalyzed = ISO8601DateFormatter().date(from: lastAnalyzed)
            }
            if let lastSentimentAnalysis = remoteConversation.lastSentimentAnalysis {
                conversation.lastSentimentAnalysis = ISO8601DateFormatter().date(from: lastSentimentAnalysis)
            }
            
            // Link to person if identifier provided
            if let personIdentifier = remoteConversation.personIdentifier {
                let personRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
                personRequest.predicate = NSPredicate(format: "identifier == %@", personIdentifier as CVarArg)
                if let associatedPerson = try context.fetch(personRequest).first {
                    conversation.person = associatedPerson
                }
            }
            
            print("✅ Updated conversation locally: \(remoteConversation.uuid)")
            
        } catch {
            print("❌ Error handling conversation upsert: \(error)")
        }
    }
    
    // MARK: - Deletion Handling
    func deletePerson(_ person: Person, context: NSManagedObjectContext) async {
        guard let identifier = person.identifier?.uuidString else { return }
        
        print("🗑️ Deleting person: \(person.name ?? "Unknown")")
        
        do {
            // Mark as deleted in Supabase
            try await supabase
                .from("people")
                .update([
                    "is_deleted": "true",
                    "deleted_at": ISO8601DateFormatter().string(from: Date()),
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("identifier", value: identifier)
                .execute()
            
            // Delete locally
            context.delete(person)
            try context.save()
            
            print("✅ Person deleted successfully")
            
        } catch {
            print("❌ Failed to delete person: \(error)")
        }
    }
    
    func deleteConversation(_ conversation: Conversation, context: NSManagedObjectContext) async {
        guard let uuid = conversation.uuid?.uuidString else { return }
        
        print("🗑️ Deleting conversation: \(uuid)")
        
        do {
            // Mark as deleted in Supabase
            try await supabase
                .from("conversations")
                .update([
                    "is_deleted": "true",
                    "deleted_at": ISO8601DateFormatter().string(from: Date()),
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("uuid", value: uuid)
                .execute()
            
            // Delete locally
            context.delete(conversation)
            try context.save()
            
            print("✅ Conversation deleted successfully")
            
        } catch {
            print("❌ Failed to delete conversation: \(error)")
        }
    }
    
    // MARK: - Public API
    func triggerSync() {
        Task {
            if let context = PersistenceController.shared.container.viewContext as NSManagedObjectContext? {
                await performSync(context: context)
            }
        }
    }
    
    func resetSyncStatus() {
        syncStatus = "Ready"
    }
}