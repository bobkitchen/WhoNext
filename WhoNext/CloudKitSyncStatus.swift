import Foundation
import CloudKit
import Combine

class CloudKitSyncStatus: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var isSyncing: Bool = false
    @Published var syncError: String?

    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?

    init() {
        // Listen for Core Data remote change notifications
        notificationObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            self?.lastSyncDate = Date()
            self?.isSyncing = false
        }
        
        // Listen for will/did save notifications as a proxy for sync activity
        NotificationCenter.default.publisher(for: .NSManagedObjectContextWillSave)
            .sink { [weak self] _ in
                self?.isSyncing = true
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                self?.isSyncing = false
            }
            .store(in: &cancellables)
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func manualSync() {
        // Optionally trigger a sync by saving the context or using CKContainer APIs
        // This is a placeholder for future expansion
    }
}
