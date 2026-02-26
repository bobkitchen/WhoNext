//
//  Persistence.swift
//  WhoNext
//
//  Updated for CloudKit sync with proper monitoring
//  Following Apple's best practices from WWDC19-22 and TN3163/TN3164
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    // MARK: - CloudKit Configuration
    /// Single source of truth for CloudKit container ID - matches entitlements
    static let cloudKitContainerID = "iCloud.com.bobkitchen.WhoNext"

    // MARK: - CloudKit Status
    @MainActor
    static var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @MainActor
    static var lastRemoteChangeDate: Date?
    @MainActor
    static var isSyncing: Bool = false
    @MainActor
    static var lastSyncError: Error?
    @MainActor
    static var syncProgress: SyncProgress = .idle

    enum SyncProgress: Equatable {
        case idle
        case setup
        case importing
        case exporting
        case completed(Date)
        case failed(String)
    }

    // MARK: - Preview ---------------------------------------------------------

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        let person          = Person(context: viewContext)
        person.name         = "Preview Person"
        person.role         = "Test Role"
        person.identifier   = UUID()
        person.personCategory = PersonCategory.colleague.rawValue

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

        // 3. CRITICAL: Set CloudKit container options - THIS IS REQUIRED FOR SYNC
        if !inMemory {
            store.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: PersistenceController.cloudKitContainerID
            )
            debugLog("☁️ [CloudKit] Container options set: \(PersistenceController.cloudKitContainerID)")
        }

        // 4. In-memory override for previews
        if inMemory { store.url = URL(fileURLWithPath: "/dev/null") }

        // ---------------------------------------------------------------------
        // Load stores
        // ---------------------------------------------------------------------
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                debugLog("❌ Core Data load error: \(error)")
                debugLog("❌ Store description: \(storeDescription)")
                fatalError("❌ Core Data load error: \(error)")
            } else {
                debugLog("✅ Core Data store loaded successfully")
                debugLog("✅ Store URL: \(storeDescription.url?.absoluteString ?? "unknown")")
            }
        }

        // CRITICAL: Configure viewContext for CloudKit
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        container.viewContext.name = "viewContext"

        // Prevent Core Data from turning registered objects into faults while
        // they're still referenced by SwiftUI views. Without this, CloudKit
        // merges can invalidate/free managed objects that views still hold,
        // causing EXC_BAD_ACCESS in objc_release during view teardown
        // (the "entangle context after pre-commit" crash).
        container.viewContext.retainsRegisteredObjects = true

        // One-time migration: isDirectReport → personCategory
        migrateDirectReportToCategory()

        // NOTE: Do NOT use setQueryGenerationFrom(.current) with CloudKit
        // It can cause crashes when combined with refreshAllObjects() and remote sync
        // The automaticallyMergesChangesFromParent handles this automatically

        // ---------------------------------------------------------------------
        // CloudKit Schema Initialization
        // Runs in all builds to ensure Production schema includes all fields
        // (e.g., personCategory added after initial CloudKit deployment)
        // ---------------------------------------------------------------------
        if !inMemory {
            initializeCloudKitSchemaIfNeeded()
        }

        // ---------------------------------------------------------------------
        // CloudKit Monitoring
        // ---------------------------------------------------------------------
        setupCloudKitMonitoring()
        setupCloudKitEventMonitoring()
        checkiCloudAccountStatus()
    }

    // MARK: - Schema Initialization

    private func initializeCloudKitSchemaIfNeeded() {
        // Uses a versioned key so adding new fields (e.g., personCategory)
        // triggers a re-initialization that pushes them to CloudKit.
        let hasInitializedKey = "CloudKitSchemaInitialized_v2"
        guard !UserDefaults.standard.bool(forKey: hasInitializedKey) else {
            debugLog("☁️ [CloudKit] Schema already initialized (v2)")
            return
        }

        Task {
            do {
                try container.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(true, forKey: hasInitializedKey)
                print("☁️ [CloudKit] ✅ Schema initialized successfully (v2 — includes personCategory)")
            } catch {
                print("☁️ [CloudKit] ⚠️ Schema initialization failed: \(error)")
                // Don't save the flag - try again next launch
            }
        }
    }

    // MARK: - CloudKit Monitoring

    /// Dedicated background queue for CloudKit remote change notifications.
    /// CRITICAL: Using .main caused "entangle context after pre-commit" crashes
    /// because the notification handler ran synchronously on the main thread while
    /// CloudKit was mid-transaction, causing context merge conflicts with SwiftUI
    /// view teardown and other main-thread Core Data operations.
    private static let cloudKitNotificationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.bobk.WhoNext.CloudKitNotifications"
        queue.maxConcurrentOperationCount = 1  // Serial to prevent reentrant merges
        queue.qualityOfService = .utility
        return queue
    }()

    private func setupCloudKitMonitoring() {
        // Listen for remote changes from CloudKit on a BACKGROUND queue.
        // The viewContext's automaticallyMergesChangesFromParent handles merging
        // on the correct queue internally — we must not interfere by running
        // our handler on .main where it competes with view lifecycle events.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: Self.cloudKitNotificationQueue
        ) { notification in
            debugLog("☁️ [CloudKit] Remote changes received from iCloud!")
            debugLog("☁️ [CloudKit] Timestamp: \(Date())")

            // Update UI state on MainActor (async — does not block the notification)
            Task { @MainActor in
                PersistenceController.lastRemoteChangeDate = Date()
            }

            // Log what changed (if available in userInfo)
            if let userInfo = notification.userInfo {
                if let historyToken = userInfo[NSPersistentHistoryTokenKey] {
                    debugLog("☁️ [CloudKit] History token updated: \(historyToken)")
                }
                if let storeUUID = userInfo[NSStoreUUIDKey] {
                    debugLog("☁️ [CloudKit] Store UUID: \(storeUUID)")
                }
            }

            debugLog("☁️ [CloudKit] Changes will be merged automatically")
        }

        // Listen for store change events on background queue too
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreCoordinatorStoresDidChange,
            object: container.persistentStoreCoordinator,
            queue: Self.cloudKitNotificationQueue
        ) { notification in
            debugLog("☁️ [CloudKit] Persistent stores changed")
        }

        debugLog("☁️ [CloudKit] Monitoring setup complete - listening for remote changes")
    }

    /// Monitor CloudKit sync events for detailed status and error handling
    private func setupCloudKitEventMonitoring() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: Self.cloudKitNotificationQueue
        ) { notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            Task { @MainActor in
                // Update sync status
                switch event.type {
                case .setup:
                    PersistenceController.syncProgress = .setup
                    PersistenceController.isSyncing = true
                    debugLog("☁️ [CloudKit] Setup phase started")
                case .import:
                    PersistenceController.syncProgress = .importing
                    PersistenceController.isSyncing = true
                    // Only log start of event (when endDate is nil), not completion
                    if event.endDate == nil {
                        debugLog("☁️ [CloudKit] Importing data from iCloud...")
                    }
                case .export:
                    PersistenceController.syncProgress = .exporting
                    PersistenceController.isSyncing = true
                    if event.endDate == nil {
                        debugLog("☁️ [CloudKit] Exporting data to iCloud...")
                    }
                @unknown default:
                    break
                }

                // Check if event has completed
                if event.endDate != nil {
                    PersistenceController.isSyncing = false

                    if let error = event.error {
                        PersistenceController.lastSyncError = error
                        PersistenceController.syncProgress = .failed(error.localizedDescription)
                        handleCloudKitError(error)
                    } else {
                        PersistenceController.syncProgress = .completed(Date())
                        PersistenceController.lastSyncError = nil
                        debugLog("☁️ [CloudKit] ✅ Sync completed successfully")
                    }
                }
            }
        }

        debugLog("☁️ [CloudKit] Event monitoring setup complete")
    }

    // MARK: - CloudKit Error Handling

    /// Translate CKError code to human-readable description
    private func translateCKErrorCode(_ code: Int) -> String {
        switch code {
        case 0: return "internalError - Internal CloudKit error"
        case 1: return "partialFailure - Some operations failed"
        case 2: return "networkUnavailable - No network connection"
        case 3: return "networkFailure - Network request failed"
        case 4: return "badContainer - Invalid container ID"
        case 5: return "serviceUnavailable - CloudKit service down"
        case 6: return "requestRateLimited - Too many requests"
        case 7: return "missingEntitlement - Missing iCloud entitlement"
        case 8: return "notAuthenticated - Not signed into iCloud"
        case 9: return "permissionFailure - Permission denied"
        case 10: return "unknownItem - Record/zone doesn't exist"
        case 11: return "invalidArguments - Invalid query parameters"
        case 12: return "resultsTruncated - Results were truncated"
        case 13: return "serverRecordChanged - Conflict detected"
        case 14: return "serverRejectedRequest - Server rejected request"
        case 15: return "assetFileNotFound - Binary asset missing"
        case 16: return "assetFileModified - Asset was modified"
        case 17: return "incompatibleVersion - Schema version mismatch"
        case 18: return "constraintViolation - Unique constraint failed"
        case 19: return "operationCancelled - Operation was cancelled"
        case 20: return "changeTokenExpired - Need to re-sync"
        case 21: return "batchRequestFailed - Batch operation failed"
        case 22: return "zoneBusy - Zone is temporarily busy"
        case 23: return "badDatabase - Invalid database"
        case 24: return "quotaExceeded - iCloud storage full"
        case 25: return "zoneNotFound - Zone doesn't exist"
        case 26: return "limitExceeded - Request limit exceeded"
        case 27: return "userDeletedZone - User deleted the zone"
        case 28: return "tooManyParticipants - Too many shares"
        case 29: return "alreadyShared - Already shared"
        case 30: return "referenceViolation - Reference constraint failed"
        case 31: return "managedAccountRestricted - MDM restriction"
        case 32: return "participantMayNeedVerification - Needs verification"
        case 33: return "serverResponseLost - Response was lost"
        case 34: return "assetNotAvailable - Asset not downloaded"
        case 35: return "accountTemporarilyUnavailable - Account temp unavailable"
        default: return "unknown (\(code))"
        }
    }

    /// Handle specific CloudKit errors with appropriate user feedback
    private func handleCloudKitError(_ error: Error) {
        let nsError = error as NSError

        // Log the raw error details first
        debugLog("☁️ [CloudKit] ❌ ERROR DETAILS:")
        debugLog("☁️ [CloudKit]   Domain: \(nsError.domain)")
        debugLog("☁️ [CloudKit]   Code: \(nsError.code) - \(translateCKErrorCode(nsError.code))")
        debugLog("☁️ [CloudKit]   Description: \(nsError.localizedDescription)")

        // Log underlying errors if present
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            debugLog("☁️ [CloudKit]   Underlying: \(underlying.domain) code \(underlying.code)")
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .quotaExceeded:
                debugLog("☁️ [CloudKit] ❌ QUOTA EXCEEDED - iCloud storage is full")
                debugLog("☁️ [CloudKit] → User needs to free up iCloud storage or upgrade plan")

            case .networkFailure, .networkUnavailable:
                debugLog("☁️ [CloudKit] ⚠️ Network error - will retry automatically")

            case .partialFailure:
                debugLog("☁️ [CloudKit] ⚠️ Partial failure - some records synced")
                if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                    debugLog("☁️ [CloudKit]   Partial errors (\(partialErrors.count) items):")
                    for (recordID, recordError) in partialErrors.prefix(5) {
                        let recordNSError = recordError as NSError
                        debugLog("☁️ [CloudKit]   - \(recordID): code \(recordNSError.code) - \(translateCKErrorCode(recordNSError.code))")
                    }
                    if partialErrors.count > 5 {
                        debugLog("☁️ [CloudKit]   ... and \(partialErrors.count - 5) more errors")
                    }
                }

            case .notAuthenticated:
                debugLog("☁️ [CloudKit] ❌ NOT AUTHENTICATED - user needs to sign in to iCloud")

            case .serverResponseLost:
                debugLog("☁️ [CloudKit] ⚠️ Server response lost - will retry")

            case .zoneBusy:
                debugLog("☁️ [CloudKit] ⚠️ CloudKit server busy - will retry")

            case .zoneNotFound:
                debugLog("☁️ [CloudKit] ❌ ZONE NOT FOUND - The CloudKit zone doesn't exist!")
                debugLog("☁️ [CloudKit] → This is likely the root cause of sync failures")
                debugLog("☁️ [CloudKit] → Try 'Repair Sync' in Settings to recreate the zone")

            case .unknownItem:
                debugLog("☁️ [CloudKit] ❌ UNKNOWN ITEM - Record or zone doesn't exist in CloudKit")
                debugLog("☁️ [CloudKit] → Schema may not be deployed or zone is missing")
                debugLog("☁️ [CloudKit] → Try 'Repair Sync' in Settings")

            case .operationCancelled:
                debugLog("☁️ [CloudKit] ⚠️ Operation cancelled")

            case .incompatibleVersion:
                debugLog("☁️ [CloudKit] ❌ Incompatible version - schema mismatch")
                debugLog("☁️ [CloudKit] → May need to run initializeCloudKitSchema()")

            case .assetFileNotFound:
                debugLog("☁️ [CloudKit] ⚠️ Asset file not found - binary data issue")

            case .invalidArguments:
                debugLog("☁️ [CloudKit] ❌ INVALID ARGUMENTS - Query or schema issue")
                debugLog("☁️ [CloudKit] → Check if schema is deployed to Production")

            default:
                debugLog("☁️ [CloudKit] ⚠️ CloudKit error (\(ckError.code.rawValue)): \(ckError.localizedDescription)")
            }
        } else {
            debugLog("☁️ [CloudKit] ⚠️ Non-CKError sync error: \(error.localizedDescription)")
        }
    }

    private func checkiCloudAccountStatus() {
        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                PersistenceController.iCloudStatus = status

                switch status {
                case .available:
                    debugLog("☁️ [CloudKit] ✅ iCloud account AVAILABLE - sync will work")
                    // Fetch container identifier for debugging
                    let containerID = CKContainer.default().containerIdentifier ?? "unknown"
                    debugLog("☁️ [CloudKit] Container: \(containerID)")
                case .noAccount:
                    debugLog("☁️ [CloudKit] ❌ NO iCloud account signed in!")
                    debugLog("☁️ [CloudKit] ⚠️ Data will NOT sync between devices")
                    debugLog("☁️ [CloudKit] → Sign in to iCloud in System Preferences")
                case .restricted:
                    debugLog("☁️ [CloudKit] ⚠️ iCloud account RESTRICTED")
                    debugLog("☁️ [CloudKit] → Check parental controls or MDM settings")
                case .couldNotDetermine:
                    debugLog("☁️ [CloudKit] ⚠️ Could not determine iCloud status")
                    if let error = error {
                        debugLog("☁️ [CloudKit] Error: \(error.localizedDescription)")
                    }
                case .temporarilyUnavailable:
                    debugLog("☁️ [CloudKit] ⚠️ iCloud temporarily unavailable")
                    debugLog("☁️ [CloudKit] → Check internet connection")
                @unknown default:
                    debugLog("☁️ [CloudKit] ⚠️ Unknown iCloud status: \(status.rawValue)")
                }
            }
        }

        // Also check for specific CloudKit container access
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        ckContainer.accountStatus { status, error in
            if status == .available {
                debugLog("☁️ [CloudKit] ✅ WhoNext container accessible")
            } else {
                debugLog("☁️ [CloudKit] ⚠️ WhoNext container status: \(status.rawValue)")
            }
        }
    }

    // MARK: - Migration: isDirectReport → personCategory

    private func migrateDirectReportToCategory() {
        let migrationKey = "PersonCategoryMigration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform {
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "personCategory == nil OR personCategory == ''")
            guard let people = try? context.fetch(request) else { return }

            for person in people {
                if person.isDirectReport {
                    person.personCategory = PersonCategory.directReport.rawValue
                } else {
                    person.personCategory = PersonCategory.colleague.rawValue
                }
            }

            if context.hasChanges {
                do {
                    try context.save()
                    debugLog("✅ Migrated \(people.count) people to personCategory")
                } catch {
                    debugLog("❌ personCategory migration failed: \(error)")
                    return // Don't set the flag if migration failed
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
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
                debugLog("☁️ [CloudKit] Saved pending changes - should trigger sync")
            } else {
                debugLog("☁️ [CloudKit] No pending changes to sync")
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

    // MARK: - CloudKit Debugging

    /// Dump local Core Data record counts for debugging
    func dumpLocalRecordCounts() {
        let context = container.viewContext
        context.perform {
            debugLog("\n☁️ ========== LOCAL CORE DATA RECORD COUNTS ==========")

            // Person count
            let personRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let personCount = (try? context.count(for: personRequest)) ?? 0
            debugLog("☁️ Person records: \(personCount)")

            // Conversation count
            let convRequest = NSFetchRequest<NSManagedObject>(entityName: "Conversation")
            let convCount = (try? context.count(for: convRequest)) ?? 0
            debugLog("☁️ Conversation records: \(convCount)")

            // UserProfileEntity count
            let profileRequest = NSFetchRequest<NSManagedObject>(entityName: "UserProfileEntity")
            let profileCount = (try? context.count(for: profileRequest)) ?? 0
            debugLog("☁️ UserProfileEntity records: \(profileCount)")

            // Group count
            let groupRequest = NSFetchRequest<NSManagedObject>(entityName: "Group")
            let groupCount = (try? context.count(for: groupRequest)) ?? 0
            debugLog("☁️ Group records: \(groupCount)")

            // GroupMeeting count
            let meetingRequest = NSFetchRequest<NSManagedObject>(entityName: "GroupMeeting")
            let meetingCount = (try? context.count(for: meetingRequest)) ?? 0
            debugLog("☁️ GroupMeeting records: \(meetingCount)")

            debugLog("☁️ =====================================================\n")
        }
    }

    /// Query CloudKit directly to verify what records exist
    func verifyCloudKitRecords() {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase

        debugLog("\n☁️ ========== CLOUDKIT RECORD VERIFICATION ==========")
        debugLog("☁️ Querying CloudKit private database...")

        // Query for CD_Person records (Core Data prefixes with CD_)
        let recordTypes = ["CD_Person", "CD_Conversation", "CD_UserProfileEntity", "CD_Group", "CD_GroupMeeting"]

        for recordType in recordTypes {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            privateDB.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100) { result in
                switch result {
                case .success(let (matchResults, _)):
                    let count = matchResults.count
                    debugLog("☁️ \(recordType): \(count) records in CloudKit")

                    // Log first few record IDs for debugging
                    for (recordID, recordResult) in matchResults.prefix(3) {
                        switch recordResult {
                        case .success(let record):
                            debugLog("☁️   - \(recordID.recordName): modified \(record.modificationDate ?? Date())")
                        case .failure(let error):
                            debugLog("☁️   - \(recordID.recordName): error \(error.localizedDescription)")
                        }
                    }

                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        debugLog("☁️ \(recordType): Record type not found in schema")
                    } else {
                        debugLog("☁️ \(recordType): Error querying - \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Force re-initialize CloudKit schema
    /// This creates sample records to ensure all fields are in the schema
    func forceSchemaReinitialization() {
        print("☁️ [CloudKit] Forcing schema re-initialization...")

        // Clear both old and new flags so schema initialization runs again
        UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v1")
        UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v2")

        Task {
            do {
                // Now do the actual initialization
                try container.initializeCloudKitSchema(options: [])
                print("☁️ [CloudKit] ✅ Schema force-initialized successfully")
                print("☁️ [CloudKit] ⚠️ IMPORTANT: Deploy schema to Production in CloudKit Dashboard!")

                UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized_v2")
            } catch {
                print("☁️ [CloudKit] ❌ Schema initialization failed: \(error)")
            }
        }
    }

    /// Check CloudKit zone status
    func checkCloudKitZoneStatus() {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase

        // The default zone for NSPersistentCloudKitContainer
        // "_defaultOwner" represents the current user's zone
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: "_defaultOwner")

        privateDB.fetch(withRecordZoneID: zoneID) { zone, error in
            if let zone = zone {
                debugLog("☁️ [CloudKit] ✅ Zone exists: \(zone.zoneID.zoneName)")
                debugLog("☁️ [CloudKit] Zone capabilities: \(zone.capabilities)")
            } else if let error = error {
                debugLog("☁️ [CloudKit] ❌ Zone error: \(error.localizedDescription)")

                // Check if zone doesn't exist
                if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                    debugLog("☁️ [CloudKit] Zone not found - this means no data has ever synced!")
                    debugLog("☁️ [CloudKit] Try saving some data to create the zone")
                }
            }
        }
    }

    /// Force sync all existing data by touching modifiedAt timestamps
    /// This is needed because data created before history tracking was enabled won't sync
    func forceSyncAllExistingData() {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform {
            debugLog("☁️ [CloudKit] Force-syncing all existing data...")
            var touchedCount = 0

            // Touch all Person records
            let personRequest: NSFetchRequest<Person> = Person.fetchRequest()
            if let people = try? context.fetch(personRequest) {
                for person in people {
                    person.modifiedAt = Date()
                    touchedCount += 1
                }
                debugLog("☁️ [CloudKit] Touched \(people.count) Person records")
            }

            // Touch all Conversation records
            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            if let conversations = try? context.fetch(convRequest) {
                for conversation in conversations {
                    conversation.modifiedAt = Date()
                    touchedCount += 1
                }
                debugLog("☁️ [CloudKit] Touched \(conversations.count) Conversation records")
            }

            // Touch UserProfileEntity
            let profileRequest = NSFetchRequest<UserProfileEntity>(entityName: "UserProfileEntity")
            if let profiles = try? context.fetch(profileRequest) {
                for profile in profiles {
                    profile.modifiedAt = Date()
                    touchedCount += 1
                }
                debugLog("☁️ [CloudKit] Touched \(profiles.count) UserProfileEntity records")
            }

            // Touch Group records
            let groupRequest = NSFetchRequest<Group>(entityName: "Group")
            if let groups = try? context.fetch(groupRequest) {
                for group in groups {
                    group.modifiedAt = Date()
                    touchedCount += 1
                }
                debugLog("☁️ [CloudKit] Touched \(groups.count) Group records")
            }

            // Touch GroupMeeting records
            let meetingRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
            if let meetings = try? context.fetch(meetingRequest) {
                for meeting in meetings {
                    meeting.modifiedAt = Date()
                    touchedCount += 1
                }
                debugLog("☁️ [CloudKit] Touched \(meetings.count) GroupMeeting records")
            }

            // Save changes to trigger CloudKit sync
            do {
                if context.hasChanges {
                    try context.save()
                    debugLog("☁️ [CloudKit] ✅ Force-synced \(touchedCount) total records - should trigger CloudKit export")
                } else {
                    debugLog("☁️ [CloudKit] No changes to save")
                }
            } catch {
                debugLog("☁️ [CloudKit] ❌ Error saving force-sync changes: \(error)")
            }
        }
    }

    /// Repair orphaned conversations that reference non-existent Person records
    /// These can cause CloudKit sync failures (CKError 2 - unknownItem)
    func repairOrphanedConversations() -> (deleted: Int, fixed: Int) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var deletedCount = 0
        var fixedCount = 0

        context.performAndWait {
            debugLog("☁️ [CloudKit] Checking for orphaned conversations...")

            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            guard let conversations = try? context.fetch(convRequest) else {
                debugLog("☁️ [CloudKit] Could not fetch conversations")
                return
            }

            for conversation in conversations {
                // Check if person relationship is broken (fault that can't resolve)
                if conversation.person == nil {
                    // Conversation has no person - check if it has any useful data
                    let hasNotes = !(conversation.notes?.isEmpty ?? true)
                    let hasSummary = !(conversation.summary?.isEmpty ?? true)

                    if hasNotes || hasSummary {
                        // Has content but no person - this is an orphan we should keep track of
                        // Set modifiedAt to trigger a clean sync
                        conversation.modifiedAt = Date()
                        fixedCount += 1
                        debugLog("☁️ [CloudKit] Fixed orphan with content: \(conversation.summary?.prefix(30) ?? "no summary")")
                    } else {
                        // Empty orphan - delete it
                        context.delete(conversation)
                        deletedCount += 1
                        debugLog("☁️ [CloudKit] Deleted empty orphan conversation")
                    }
                }
            }

            if context.hasChanges {
                do {
                    try context.save()
                    debugLog("☁️ [CloudKit] ✅ Orphan repair saved: deleted \(deletedCount), fixed \(fixedCount)")
                } catch {
                    debugLog("☁️ [CloudKit] ❌ Error saving orphan repairs: \(error)")
                }
            } else {
                debugLog("☁️ [CloudKit] No orphaned conversations found")
            }
        }

        return (deleted: deletedCount, fixed: fixedCount)
    }

    /// Purge all persistent history - this clears sync tracking metadata
    /// This is needed when sync gets into a corrupted state
    func purgePersistentHistory() async {
        let context = container.newBackgroundContext()

        await context.perform {
            debugLog("☁️ [CloudKit] Purging persistent history transactions...")

            do {
                // Keep at least 7 days of history for CloudKit sync
                let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
                try context.execute(deleteRequest)
                debugLog("☁️ [CloudKit] ✅ Purged persistent history")
            } catch {
                debugLog("☁️ [CloudKit] ⚠️ Error purging history: \(error.localizedDescription)")
            }
        }
    }

    /// Delete ALL orphaned conversations (use with caution)
    func deleteAllOrphanedConversations() -> Int {
        let context = container.viewContext
        var deletedCount = 0

        context.performAndWait {
            debugLog("☁️ [CloudKit] Deleting ALL orphaned conversations...")

            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            guard let conversations = try? context.fetch(convRequest) else {
                debugLog("☁️ [CloudKit] Could not fetch conversations")
                return
            }

            for conversation in conversations {
                if conversation.person == nil {
                    context.delete(conversation)
                    deletedCount += 1
                }
            }

            if context.hasChanges {
                do {
                    try context.save()
                    debugLog("☁️ [CloudKit] ✅ Deleted \(deletedCount) orphaned conversations")
                } catch {
                    debugLog("☁️ [CloudKit] ❌ Error deleting orphans: \(error)")
                }
            }
        }

        return deletedCount
    }

    /// Comprehensive sync diagnostic
    func runSyncDiagnostic() {
        debugLog("\n")
        debugLog("☁️ ╔══════════════════════════════════════════════════════════╗")
        debugLog("☁️ ║           CLOUDKIT SYNC DIAGNOSTIC REPORT                ║")
        debugLog("☁️ ╚══════════════════════════════════════════════════════════╝")
        debugLog("☁️")
        debugLog("☁️ Container ID: \(PersistenceController.cloudKitContainerID)")
        debugLog("☁️")

        // Check iCloud status
        checkiCloudAccountStatus()

        // Check zone
        checkCloudKitZoneStatus()

        // Dump local counts
        dumpLocalRecordCounts()

        // Query CloudKit
        verifyCloudKitRecords()

        debugLog("☁️")
        debugLog("☁️ ════════════════════════════════════════════════════════════")
        debugLog("☁️ TROUBLESHOOTING STEPS:")
        debugLog("☁️ 1. Ensure SAME iCloud account on both devices")
        debugLog("☁️ 2. Check CloudKit Dashboard → Deploy Schema to Production")
        debugLog("☁️ 3. In CloudKit Dashboard, verify records exist in Private DB")
        debugLog("☁️ 4. Try: Settings → iCloud → WhoNext → Toggle OFF then ON")
        debugLog("☁️ 5. Check device storage isn't full")
        debugLog("☁️ ════════════════════════════════════════════════════════════")
    }

    // MARK: - Zone Repair and Reset

    /// Check if CloudKit zone exists (async version)
    func checkZoneExistsAsync() async -> Bool {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        do {
            _ = try await privateDB.recordZone(for: zoneID)
            debugLog("☁️ [CloudKit] ✅ Zone exists")
            return true
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .zoneNotFound {
                debugLog("☁️ [CloudKit] ❌ Zone NOT found - needs to be created")
            } else {
                debugLog("☁️ [CloudKit] ⚠️ Zone check error: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// Create CloudKit zone if it doesn't exist
    func createCloudKitZoneIfNeeded() async throws {
        let zoneExists = await checkZoneExistsAsync()
        if zoneExists {
            debugLog("☁️ [CloudKit] Zone already exists, no action needed")
            return
        }

        debugLog("☁️ [CloudKit] Creating CloudKit zone...")
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")

        do {
            let savedZone = try await privateDB.save(zone)
            debugLog("☁️ [CloudKit] ✅ Zone created: \(savedZone.zoneID.zoneName)")
        } catch {
            debugLog("☁️ [CloudKit] ❌ Failed to create zone: \(error)")
            throw error
        }
    }

    /// Repair CloudKit sync - tries to fix common issues
    func repairCloudKitSync() async throws {
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
        debugLog("☁️ [CloudKit] Starting CloudKit Sync Repair...")
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")

        // Step 1: Check iCloud account status
        debugLog("☁️ [CloudKit] Step 1: Checking iCloud account...")
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }

        guard status == .available else {
            debugLog("☁️ [CloudKit] ❌ iCloud not available (status: \(status.rawValue))")
            throw NSError(domain: "CloudKitRepair", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud account not available. Please sign in to iCloud."])
        }
        debugLog("☁️ [CloudKit] ✅ iCloud account available")

        // Step 2: Check/create zone
        debugLog("☁️ [CloudKit] Step 2: Checking CloudKit zone...")
        try await createCloudKitZoneIfNeeded()

        // Step 3: Re-initialize schema
        debugLog("☁️ [CloudKit] Step 3: Re-initializing schema...")
        #if DEBUG
        do {
            // Clear the initialization flag
            UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v1")

            // Re-initialize
            try container.initializeCloudKitSchema(options: [])
            UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized_v1")
            print("☁️ [CloudKit] ✅ Schema re-initialized")
        } catch {
            print("☁️ [CloudKit] ⚠️ Schema initialization warning: \(error.localizedDescription)")
            // Don't throw - this is sometimes expected
        }
        #else
        debugLog("☁️ [CloudKit] ⚠️ Schema initialization skipped (not DEBUG build)")
        #endif

        // Step 4: Repair orphaned conversations (can cause sync failures)
        debugLog("☁️ [CloudKit] Step 4: Repairing orphaned conversations...")
        let orphanResult = repairOrphanedConversations()
        debugLog("☁️ [CloudKit] ✅ Orphan repair: deleted \(orphanResult.deleted), fixed \(orphanResult.fixed)")

        // Step 5: Force sync all records
        debugLog("☁️ [CloudKit] Step 5: Forcing sync of all records...")
        forceSyncAllExistingData()

        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
        debugLog("☁️ [CloudKit] ✅ Repair complete! Wait 1-2 minutes for sync.")
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
    }

    /// Nuclear option: Reset CloudKit sync completely
    /// WARNING: This deletes ALL CloudKit data and re-uploads from this device
    func resetCloudKitSync() async throws {
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
        debugLog("☁️ [CloudKit] ⚠️ NUCLEAR RESET: Deleting CloudKit zone...")
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")

        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Step 1: Delete the zone (removes all cloud data)
        debugLog("☁️ [CloudKit] Step 1: Deleting CloudKit zone...")
        do {
            try await privateDB.deleteRecordZone(withID: zoneID)
            debugLog("☁️ [CloudKit] ✅ Zone deleted")
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .zoneNotFound {
                debugLog("☁️ [CloudKit] Zone didn't exist, continuing...")
            } else {
                debugLog("☁️ [CloudKit] ⚠️ Zone deletion warning: \(error.localizedDescription)")
                // Continue anyway
            }
        }

        // Step 2: Wait a moment for CloudKit to process
        debugLog("☁️ [CloudKit] Step 2: Waiting for CloudKit to process...")
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Step 3: Clear local sync metadata and purge persistent history
        debugLog("☁️ [CloudKit] Step 3: Clearing local sync metadata...")
        UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v1")

        // Purge ALL persistent history - this is where sync metadata lives
        debugLog("☁️ [CloudKit] Step 3b: Purging persistent history...")
        await purgePersistentHistory()

        // Step 4: Create new zone
        debugLog("☁️ [CloudKit] Step 4: Creating new zone...")
        let zone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")
        _ = try await privateDB.save(zone)
        debugLog("☁️ [CloudKit] ✅ New zone created")

        // Step 5: Re-initialize schema
        debugLog("☁️ [CloudKit] Step 5: Initializing schema...")
        #if DEBUG
        try container.initializeCloudKitSchema(options: [])
        UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized_v1")
        print("☁️ [CloudKit] ✅ Schema initialized")
        #endif

        // Step 6: Clean up orphaned conversations before uploading
        debugLog("☁️ [CloudKit] Step 6: Cleaning orphaned conversations...")
        let deletedOrphans = deleteAllOrphanedConversations()
        debugLog("☁️ [CloudKit] ✅ Deleted \(deletedOrphans) orphaned conversations")

        // Step 7: Force sync all records
        debugLog("☁️ [CloudKit] Step 7: Uploading all local data...")
        forceSyncAllExistingData()

        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
        debugLog("☁️ [CloudKit] ✅ RESET COMPLETE!")
        debugLog("☁️ [CloudKit] All data from THIS device will be uploaded.")
        debugLog("☁️ [CloudKit] Other devices will receive data after sync.")
        debugLog("☁️ [CloudKit] ═══════════════════════════════════════════════")
    }

    /// Get detailed sync status for UI display
    @MainActor
    static func getDetailedSyncStatus() -> (status: String, isError: Bool, actionHint: String?) {
        switch syncProgress {
        case .idle:
            return ("Idle", false, nil)
        case .setup:
            return ("Setting up sync...", false, nil)
        case .importing:
            return ("Importing from iCloud...", false, nil)
        case .exporting:
            return ("Exporting to iCloud...", false, nil)
        case .completed(let date):
            let formatter = RelativeDateTimeFormatter()
            return ("Synced \(formatter.localizedString(for: date, relativeTo: Date()))", false, nil)
        case .failed(let message):
            // Provide actionable hints based on the error
            var hint: String? = nil
            if message.contains("2") || message.lowercased().contains("unknown") {
                hint = "Try 'Repair Sync' to fix zone issues"
            } else if message.lowercased().contains("network") {
                hint = "Check your internet connection"
            } else if message.lowercased().contains("quota") {
                hint = "Free up iCloud storage space"
            } else if message.lowercased().contains("auth") {
                hint = "Sign in to iCloud in System Settings"
            }
            return ("Failed: \(message)", true, hint)
        }
    }
}
