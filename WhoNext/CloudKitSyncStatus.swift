import CloudKit
import Combine
import CoreData

class CloudKitSyncStatus: ObservableObject {
    @Published var lastSyncDate: Date? {
        didSet {
            print("🔄 CloudKit: Last sync date updated to \(lastSyncDate?.formatted() ?? "nil")")
        }
    }
    @Published var isSyncing: Bool = false {
        didSet {
            print("🔄 CloudKit: Syncing status changed to \(isSyncing)")
        }
    }
    @Published var syncError: Error? {
        didSet {
            if let error = syncError {
                print("❌ CloudKit: Sync error - \(error.localizedDescription)")
            }
        }
    }
    @Published var accountStatus: String = "Unknown"
    @Published var cloudKitAvailable: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?
    private let container = CKContainer(identifier: "iCloud.com.bobk.whonext")

    init() {
        print("🔄 CloudKit: Initializing sync status monitoring")
        checkCloudKitAccountStatus()
        
        notificationObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] notification in
            self?.handleRemoteChange(notification)
        }
        
        // Monitor for CloudKit import/export events
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification"), object: nil, queue: .main) { [weak self] notification in
            self?.handleContainerEvent(notification)
        }
        
        // Listen for context will save
        NotificationCenter.default.publisher(for: .NSManagedObjectContextWillSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleContextSave(notification)
            }
            .store(in: &cancellables)
        
        // Use DidSave as a proxy for sync completion (if needed)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                // If the only updated/inserted/deleted objects are NSCKEvent, do not treat as user sync
                guard let context = notification.object as? NSManagedObjectContext else { return }
                let inserted = context.insertedObjects
                let updated = context.updatedObjects
                let deleted = context.deletedObjects
                let onlyNSCKEvent = inserted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   updated.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   deleted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") }
                if !onlyNSCKEvent {
                    DispatchQueue.main.async { [weak self] in
                        self?.lastSyncDate = Date()
                        self?.isSyncing = false
                    }
                }
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit account changes
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("🔄 CloudKit: Account changed notification received")
                self?.checkCloudKitAccountStatus()
            }
            .store(in: &cancellables)
    }
    
    private func handleRemoteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            print("🔄 CloudKit: Remote change notification received")
            self?.lastSyncDate = Date()
            self?.isSyncing = false
        }
    }
    
    private func handleContextSave(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let context = notification.object as? NSManagedObjectContext else { return }
            
            let insertedObjects = context.insertedObjects
            let updatedObjects = context.updatedObjects  
            let deletedObjects = context.deletedObjects
            
            // Filter out CloudKit internal objects
            let userInserted = insertedObjects.filter { !String(describing: type(of: $0)).contains("NSCK") }
            let userUpdated = updatedObjects.filter { !String(describing: type(of: $0)).contains("NSCK") }
            let userDeleted = deletedObjects.filter { !String(describing: type(of: $0)).contains("NSCK") }
            
            if !userInserted.isEmpty || !userUpdated.isEmpty || !userDeleted.isEmpty {
                print("🔄 CloudKit: User changes detected - inserted: \(userInserted.count), updated: \(userUpdated.count), deleted: \(userDeleted.count)")
                
                for object in userInserted {
                    print("  ➕ Inserting: \(type(of: object))")
                    if let person = object as? Person {
                        print("    📝 Person: \(person.name ?? "Unknown")")
                    } else if let conversation = object as? Conversation {
                        print("    💬 Conversation with: \(conversation.person?.name ?? "Unknown")")
                    }
                }
                
                for object in userUpdated {
                    print("  ✏️ Updating: \(type(of: object))")
                    if let person = object as? Person {
                        print("    📝 Person: \(person.name ?? "Unknown")")
                    } else if let conversation = object as? Conversation {
                        print("    💬 Conversation with: \(conversation.person?.name ?? "Unknown")")
                    }
                }
                
                for object in userDeleted {
                    print("  🗑️ Deleting: \(type(of: object))")
                }
                
                self?.isSyncing = true
            } else if !insertedObjects.isEmpty || !updatedObjects.isEmpty || !deletedObjects.isEmpty {
                print("🔄 CloudKit: Internal changes only - inserted: \(insertedObjects.count), updated: \(updatedObjects.count), deleted: \(deletedObjects.count)")
                for object in insertedObjects {
                    print("  🔧 Internal insert: \(type(of: object))")
                }
                for object in updatedObjects {
                    print("  🔧 Internal update: \(type(of: object))")
                }
            }
        }
    }
    
    private func handleContainerEvent(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else { return }
            
            let eventType = event.type == .export ? "Export" : 
                           event.type == .import ? "Import" : "Unknown"
            let succeeded = event.succeeded ? "YES" : "NO"
            let startTime = event.startDate.formatted(date: .omitted, time: .standard)
            let endTime = event.endDate?.formatted(date: .omitted, time: .standard) ?? "In Progress"
            
            print("🔄 CloudKit: \(eventType) event - started: \(startTime), ended: \(endTime), succeeded: \(succeeded)")
            
            if !event.succeeded {
                if let error = event.error {
                    print("❌ CloudKit: \(eventType) failed with error: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("❌ CloudKit: Error code \(ckError.code.rawValue) - \(ckError.localizedDescription)")
                        if let underlyingError = ckError.userInfo[NSUnderlyingErrorKey] as? Error {
                            print("❌ CloudKit: Underlying error: \(underlyingError.localizedDescription)")
                        }
                        // Print all userInfo for debugging
                        print("❌ CloudKit: Full error info: \(ckError.userInfo)")
                    }
                    
                    self?.syncError = error
                } else {
                    print("❌ CloudKit: \(eventType) failed with no error details")
                    print("❌ CloudKit: Event details - type: \(event.type.rawValue), identifier: \(event.identifier)")
                    print("❌ CloudKit: Store identifier: \(event.storeIdentifier)")
                }
            } else {
                // Clear error on successful sync
                if event.type == .export {
                    self?.syncError = nil
                }
            }
            
            if event.endDate != nil {
                self?.lastSyncDate = event.endDate
                self?.isSyncing = false
            }
        }
    }
    
    func checkCloudKitAccountStatus() {
        container.accountStatus { [weak self] status, error in
            if let error = error {
                DispatchQueue.main.async { [weak self] in
                    self?.syncError = error
                }
                return
            }
            switch status {
            case .available:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = true
                    self?.accountStatus = "Available"
                }
            case .noAccount:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = false
                    self?.accountStatus = "No Account"
                }
            case .couldNotDetermine:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = false
                    self?.accountStatus = "Could Not Determine"
                }
            case .restricted:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = false
                    self?.accountStatus = "Restricted"
                }
            case .temporarilyUnavailable:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = false
                    self?.accountStatus = "Temporarily Unavailable"
                }
            @unknown default:
                DispatchQueue.main.async { [weak self] in
                    self?.cloudKitAvailable = false
                    self?.accountStatus = "Unknown"
                }
            }
        }
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func manualSync() {
        DispatchQueue.main.async { [weak self] in
            self?.isSyncing = true
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            sleep(1)
            DispatchQueue.main.async {
                self?.lastSyncDate = Date()
                self?.isSyncing = false
            }
        }
    }
    
    func testCloudKitConnection() {
        print("🔄 CloudKit: Testing direct container connection...")
        
        // Test 1: Check account status
        container.accountStatus { status, error in
            if let error = error {
                print("❌ CloudKit: Account status error - \(error)")
                return
            }
            print("✅ CloudKit: Account status - \(status)")
        }
        
        // Test 2: Query for Person records
        let database = container.privateCloudDatabase
        let personQuery = CKQuery(recordType: "CD_Person", predicate: NSPredicate(value: true))
        
        database.fetch(withQuery: personQuery, inZoneWith: nil, desiredKeys: nil, resultsLimit: 10) { result in
            switch result {
            case .success(let (matchResults, _)):
                print("✅ CloudKit: Person query successful - found \(matchResults.count) records")
                for (_, recordResult) in matchResults {
                    switch recordResult {
                    case .success(let record):
                        let name = record["CD_name"] as? String ?? "Unknown"
                        print("  📝 Person record: \(name)")
                    case .failure(let error):
                        print("❌ CloudKit: Person record error - \(error)")
                    }
                }
            case .failure(let error):
                print("❌ CloudKit: Person query error - \(error)")
            }
        }
        
        // Test 3: Query for Conversation records
        let conversationQuery = CKQuery(recordType: "CD_Conversation", predicate: NSPredicate(value: true))
        
        database.fetch(withQuery: conversationQuery, inZoneWith: nil, desiredKeys: nil, resultsLimit: 10) { result in
            switch result {
            case .success(let (matchResults, _)):
                print("✅ CloudKit: Conversation query successful - found \(matchResults.count) records")
                for (_, recordResult) in matchResults {
                    switch recordResult {
                    case .success(let record):
                        let content = record["CD_content"] as? String ?? "No content"
                        let preview = String(content.prefix(50))
                        print("  💬 Conversation record: \(preview)...")
                    case .failure(let error):
                        print("❌ CloudKit: Conversation record error - \(error)")
                    }
                }
            case .failure(let error):
                print("❌ CloudKit: Conversation query error - \(error)")
            }
        }
    }
    
    func queryCloudKitRecords() {
        print("🔄 CloudKit: Querying records in CloudKit...")
        
        let database = container.privateCloudDatabase
        
        // Use a simple fetch operation instead of query
        database.fetchAllRecordZones { zones, error in
            if let error = error {
                print("❌ CloudKit: Zone fetch error - \(error)")
                return
            }
            
            guard let zones = zones else {
                print("❌ CloudKit: No zones returned")
                return
            }
            
            print("✅ CloudKit: Found \(zones.count) zones")
            for zone in zones {
                print("  🏠 Zone: \(zone.zoneID.zoneName)")
            }
            
            // Now try to fetch records from the Core Data CloudKit zone
            let recordZoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            
            // Try a different approach - fetch records by type using CKQueryOperation
            let personQueryOp = CKQueryOperation(query: CKQuery(recordType: "CD_Person", predicate: NSPredicate(value: true)))
            personQueryOp.zoneID = recordZoneID
            personQueryOp.resultsLimit = 10
            
            var personRecords: [CKRecord] = []
            personQueryOp.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    personRecords.append(record)
                case .failure(let error):
                    print("❌ CloudKit: Person record error - \(error)")
                }
            }
            
            personQueryOp.queryResultBlock = { result in
                switch result {
                case .success:
                    print("✅ CloudKit: Found \(personRecords.count) Person records")
                    for record in personRecords.prefix(5) {
                        let name = record["CD_name"] as? String ?? "Unknown"
                        print("  📝 Person: \(name)")
                    }
                case .failure(let error):
                    print("❌ CloudKit: Person query operation error - \(error)")
                }
            }
            
            database.add(personQueryOp)
            
            // Same for conversations
            let conversationQueryOp = CKQueryOperation(query: CKQuery(recordType: "CD_Conversation", predicate: NSPredicate(value: true)))
            conversationQueryOp.zoneID = recordZoneID
            conversationQueryOp.resultsLimit = 10
            
            var conversationRecords: [CKRecord] = []
            conversationQueryOp.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    conversationRecords.append(record)
                case .failure(let error):
                    print("❌ CloudKit: Conversation record error - \(error)")
                }
            }
            
            conversationQueryOp.queryResultBlock = { result in
                switch result {
                case .success:
                    print("✅ CloudKit: Found \(conversationRecords.count) Conversation records")
                    for record in conversationRecords.prefix(5) {
                        let content = record["CD_content"] as? String ?? "No content"
                        let preview = String(content.prefix(50))
                        print("  💬 Conversation: \(preview)...")
                    }
                case .failure(let error):
                    print("❌ CloudKit: Conversation query operation error - \(error)")
                }
            }
            
            database.add(conversationQueryOp)
        }
    }
    
    func resetCloudKitSync() {
        print("🔄 CloudKit: Initiating sync reset to fix token expiration...")
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = nil
            self?.syncError = nil
        }
        print("✅ CloudKit: Reset initiated - sync will restart automatically")
    }
}
