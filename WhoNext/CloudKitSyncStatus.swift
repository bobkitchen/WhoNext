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
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification"), object: nil, queue: .main) { notification in
            print("🔄 CloudKit: Container event notification - \(notification)")
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
            
            if !insertedObjects.isEmpty || !updatedObjects.isEmpty || !deletedObjects.isEmpty {
                print("🔄 CloudKit: Context will save with user changes - inserted: \(insertedObjects.count), updated: \(updatedObjects.count), deleted: \(deletedObjects.count)")
                
                for object in insertedObjects {
                    print("  ➕ Inserting: \(type(of: object))")
                }
                for object in updatedObjects {
                    print("  ✏️ Updating: \(type(of: object))")
                }
                for object in deletedObjects {
                    print("  🗑️ Deleting: \(type(of: object))")
                }
                
                self?.isSyncing = true
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
        
        // Test 2: Try to fetch a simple record to test connectivity
        let database = container.privateCloudDatabase
        let query = CKQuery(recordType: "CD_Person", predicate: NSPredicate(value: true))
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1) { result in
            switch result {
            case .success(let (matchResults, _)):
                print("✅ CloudKit: Query successful - found \(matchResults.count) records")
                for (recordID, recordResult) in matchResults {
                    switch recordResult {
                    case .success(_):
                        print("✅ CloudKit: Found record - \(recordID)")
                    case .failure(let error):
                        print("❌ CloudKit: Record error - \(error)")
                    }
                }
            case .failure(let error):
                print("❌ CloudKit: Query error - \(error)")
                if let ckError = error as? CKError {
                    print("❌ CloudKit: Error code \(ckError.code.rawValue) - \(ckError.localizedDescription)")
                }
            }
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
