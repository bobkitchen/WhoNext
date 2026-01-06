//
//  Persistence.swift
//  WhoNext
//
//  Updated for CloudKit sync with proper monitoring
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    // MARK: - CloudKit Status
    @MainActor
    static var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @MainActor
    static var lastRemoteChangeDate: Date?

    // MARK: - Preview ---------------------------------------------------------

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        let person          = Person(context: viewContext)
        person.name         = "Preview Person"
        person.role         = "Test Role"
        person.identifier   = UUID()
        person.isDirectReport = false

        try? viewContext.save()
        return controller
    }()

    // MARK: - Core stack ------------------------------------------------------

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {

        let modelName = "WhoNext"

        // Load the compiled model (.momd or .mom)
        guard
            let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd") ??
                           Bundle.main.url(forResource: modelName, withExtension: "mom"),
            let model    = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("❌ Unable to locate Core Data model.")
        }

        // Create CloudKit container for automatic iCloud sync
        container = NSPersistentCloudKitContainer(name: modelName,
                                                  managedObjectModel: model)

        // ---------------------------------------------------------------------
        // TUNE THE PERSISTENT-STORE DESCRIPTION
        // ---------------------------------------------------------------------
        guard let store = container.persistentStoreDescriptions.first else {
            fatalError("❌ Missing persistent-store description.")
        }

        // 1. Allow lightweight migration
        store.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        store.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        // 2. Enable persistent history tracking (required for CloudKit)
        store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        store.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // 3. In-memory override for previews
        if inMemory { store.url = URL(fileURLWithPath: "/dev/null") }

        // ---------------------------------------------------------------------
        // Load stores
        // ---------------------------------------------------------------------
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("❌ Core Data load error: \(error)")
                print("❌ Store description: \(storeDescription)")
                fatalError("❌ Core Data load error: \(error)")
            } else {
                print("✅ Core Data store loaded successfully")
                print("✅ Store URL: \(storeDescription.url?.absoluteString ?? "unknown")")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // ---------------------------------------------------------------------
        // CloudKit Monitoring
        // ---------------------------------------------------------------------
        setupCloudKitMonitoring()
        checkiCloudAccountStatus()
    }

    // MARK: - CloudKit Monitoring

    private func setupCloudKitMonitoring() {
        // Listen for remote changes from CloudKit
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("☁️ [CloudKit] Remote changes received from iCloud!")
            print("☁️ [CloudKit] Timestamp: \(Date())")

            Task { @MainActor in
                PersistenceController.lastRemoteChangeDate = Date()
            }

            // Log what changed (if available in userInfo)
            if let userInfo = notification.userInfo {
                if let historyToken = userInfo[NSPersistentHistoryTokenKey] {
                    print("☁️ [CloudKit] History token updated: \(historyToken)")
                }
                if let storeUUID = userInfo[NSStoreUUIDKey] {
                    print("☁️ [CloudKit] Store UUID: \(storeUUID)")
                }
            }

            // Refresh the view context to pick up remote changes
            PersistenceController.shared.container.viewContext.perform {
                PersistenceController.shared.container.viewContext.refreshAllObjects()
                print("☁️ [CloudKit] View context refreshed with remote changes")
            }
        }

        // Listen for import events (CloudKit data being imported)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreCoordinatorStoresDidChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("☁️ [CloudKit] Persistent stores changed")
        }

        print("☁️ [CloudKit] Monitoring setup complete - listening for remote changes")
    }

    private func checkiCloudAccountStatus() {
        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                PersistenceController.iCloudStatus = status

                switch status {
                case .available:
                    print("☁️ [CloudKit] ✅ iCloud account AVAILABLE - sync will work")
                    // Fetch container identifier for debugging
                    let containerID = CKContainer.default().containerIdentifier ?? "unknown"
                    print("☁️ [CloudKit] Container: \(containerID)")
                case .noAccount:
                    print("☁️ [CloudKit] ❌ NO iCloud account signed in!")
                    print("☁️ [CloudKit] ⚠️ Data will NOT sync between devices")
                    print("☁️ [CloudKit] → Sign in to iCloud in System Preferences")
                case .restricted:
                    print("☁️ [CloudKit] ⚠️ iCloud account RESTRICTED")
                    print("☁️ [CloudKit] → Check parental controls or MDM settings")
                case .couldNotDetermine:
                    print("☁️ [CloudKit] ⚠️ Could not determine iCloud status")
                    if let error = error {
                        print("☁️ [CloudKit] Error: \(error.localizedDescription)")
                    }
                case .temporarilyUnavailable:
                    print("☁️ [CloudKit] ⚠️ iCloud temporarily unavailable")
                    print("☁️ [CloudKit] → Check internet connection")
                @unknown default:
                    print("☁️ [CloudKit] ⚠️ Unknown iCloud status: \(status.rawValue)")
                }
            }
        }

        // Also check for specific CloudKit container access
        let container = CKContainer(identifier: "iCloud.com.bobkitchen.WhoNext")
        container.accountStatus { status, error in
            if status == .available {
                print("☁️ [CloudKit] ✅ WhoNext container accessible")
            } else {
                print("☁️ [CloudKit] ⚠️ WhoNext container status: \(status.rawValue)")
            }
        }
    }

    // MARK: - Force Sync (for debugging)

    /// Force a sync by saving an empty change to trigger CloudKit
    func forceSyncTrigger() {
        container.viewContext.perform {
            // Touch a timestamp to trigger sync
            let context = self.container.viewContext
            if context.hasChanges {
                try? context.save()
                print("☁️ [CloudKit] Saved pending changes - should trigger sync")
            } else {
                print("☁️ [CloudKit] No pending changes to sync")
            }
        }
    }

    /// Get sync status summary
    @MainActor
    static func getSyncStatusSummary() -> String {
        var summary = "CloudKit Sync Status:\n"

        switch iCloudStatus {
        case .available:
            summary += "✅ iCloud: Available\n"
        case .noAccount:
            summary += "❌ iCloud: No account signed in\n"
        case .restricted:
            summary += "⚠️ iCloud: Restricted\n"
        case .couldNotDetermine:
            summary += "⚠️ iCloud: Unknown status\n"
        case .temporarilyUnavailable:
            summary += "⚠️ iCloud: Temporarily unavailable\n"
        @unknown default:
            summary += "⚠️ iCloud: Unknown\n"
        }

        if let lastChange = lastRemoteChangeDate {
            let formatter = RelativeDateTimeFormatter()
            summary += "Last remote change: \(formatter.localizedString(for: lastChange, relativeTo: Date()))\n"
        } else {
            summary += "Last remote change: None since app launch\n"
        }

        return summary
    }
}
