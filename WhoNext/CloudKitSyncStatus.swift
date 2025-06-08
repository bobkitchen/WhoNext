import Foundation
import CloudKit
import Combine
import CoreData

class CloudKitSyncStatus: ObservableObject {
    @Published var lastSyncDate: Date? {
        didSet {
        }
    }
    @Published var isSyncing: Bool = false {
        didSet {
        }
    }
    @Published var syncError: Error? {
        didSet {
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?

    init() {
        notificationObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] notification in
            self?.lastSyncDate = Date()
            self?.isSyncing = false
        }
        
        // Listen for context will save
        NotificationCenter.default.publisher(for: .NSManagedObjectContextWillSave)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let context = notification.object as? NSManagedObjectContext else { return }
                let inserted = context.insertedObjects
                let updated = context.updatedObjects
                let deleted = context.deletedObjects
                let onlyNSCKEvent = inserted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   updated.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") } &&
                                   deleted.allSatisfy { String(describing: type(of: $0)).contains("NSCKEvent") }
                if context.hasChanges && !onlyNSCKEvent {
                    // Removed debug logging
                }
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
}
