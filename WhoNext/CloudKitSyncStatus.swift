import Foundation
import CloudKit
import Combine
import CoreData

class CloudKitSyncStatus: ObservableObject {
    @Published var lastSyncDate: Date? {
        didSet {
            print("[CloudKitSyncStatus][LOG] lastSyncDate set to: \(String(describing: lastSyncDate))\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        }
    }
    @Published var isSyncing: Bool = false {
        didSet {
            print("[CloudKitSyncStatus][LOG] isSyncing set to: \(isSyncing)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        }
    }
    @Published var syncError: String? {
        didSet {
            print("[CloudKitSyncStatus][LOG] syncError set to: \(String(describing: syncError))\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?

    init() {
        print("[CloudKitSyncStatus] Initializing sync status observer")
        // Listen for Core Data remote change notifications
        notificationObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] notification in
            print("[CloudKitSyncStatus][DEBUG] NSPersistentStoreRemoteChange received: \(notification)")
            print("[CloudKitSyncStatus][DEBUG][RemoteChange CallStack] \(Thread.callStackSymbols.joined(separator: "\n"))")
            self?.lastSyncDate = Date()
            self?.isSyncing = false
        }
        
        // Remove WillSave as a proxy for sync activity
        // Instead, only log and debug why WillSave is firing so much
        NotificationCenter.default.publisher(for: .NSManagedObjectContextWillSave)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let context = notification.object as? NSManagedObjectContext else {
                    print("[CloudKitSyncStatus][DEBUG] NSManagedObjectContextWillSave received (no context)")
                    return
                }
                let inserted = context.insertedObjects
                let updated = context.updatedObjects
                let deleted = context.deletedObjects
                let onlyNSCKEvent = inserted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   updated.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   deleted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") }
                if context.hasChanges && !onlyNSCKEvent {
                    print("[CloudKitSyncStatus][DEBUG] NSManagedObjectContextWillSave received: \(notification)")
                    print("[CloudKitSyncStatus][DEBUG][WillSave CallStack] \(Thread.callStackSymbols.joined(separator: "\n"))")
                    print("[CloudKitSyncStatus][DEBUG][WillSave] context.hasChanges = \(context.hasChanges)")
                    print("[CloudKitSyncStatus][DEBUG][WillSave] Inserted: \(inserted.count), Updated: \(updated.count), Deleted: \(deleted.count)")
                    print("[CloudKitSyncStatus][DEBUG][WillSave] Inserted objects: \(inserted)")
                    print("[CloudKitSyncStatus][DEBUG][WillSave] Updated objects: \(updated)")
                    print("[CloudKitSyncStatus][DEBUG][WillSave] Deleted objects: \(deleted)")
                }
            }
            .store(in: &cancellables)
        // Use DidSave as a proxy for sync completion (if needed)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("[CloudKitSyncStatus][DEBUG] NSManagedObjectContextDidSave received: \(notification)")
                print("[CloudKitSyncStatus][DEBUG][DidSave CallStack] \(Thread.callStackSymbols.joined(separator: "\n"))")
                // If the only updated/inserted/deleted objects are NSCKEvent, do not treat as user sync
                guard let context = notification.object as? NSManagedObjectContext else { return }
                let inserted = context.insertedObjects
                let updated = context.updatedObjects
                let deleted = context.deletedObjects
                let onlyNSCKEvent = inserted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   updated.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   deleted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") }
                if !onlyNSCKEvent {
                    print("[CloudKitSyncStatus][DEBUG][DidSave] User data changed, updating lastSyncDate")
                    self?.lastSyncDate = Date()
                    self?.isSyncing = false
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func manualSync() {
        print("[CloudKitSyncStatus] manualSync triggered\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        // Set isSyncing to true ONLY here
        DispatchQueue.main.async { [weak self] in
            self?.isSyncing = true
        }
        // Optionally trigger a sync by saving the context or using CKContainer APIs
        // This is a placeholder for future expansion
        // Example: Simulate a sync operation on a background thread
        DispatchQueue.global(qos: .background).async { [weak self] in
            print("[CloudKitSyncStatus] manualSync background work started")
            // Simulate some background work
            sleep(1)
            // Any changes to @Published properties MUST be on the main thread
            DispatchQueue.main.async {
                print("[CloudKitSyncStatus] manualSync background work completed, updating state on main thread")
                self?.lastSyncDate = Date()
                // self?.isSyncing = false -- Now handled by DidSave/RemoteChange
            }
        }
    }
}
