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

        // 3. CRITICAL: Set CloudKit container options - THIS IS REQUIRED FOR SYNC
        if !inMemory {
            store.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: PersistenceController.cloudKitContainerID
            )
            print("☁️ [CloudKit] Container options set: \(PersistenceController.cloudKitContainerID)")
        }

        // 4. In-memory override for previews
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

        // CRITICAL: Configure viewContext for CloudKit
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // NOTE: Do NOT use setQueryGenerationFrom(.current) with CloudKit
        // It can cause crashes when combined with refreshAllObjects() and remote sync
        // The automaticallyMergesChangesFromParent handles this automatically

        // ---------------------------------------------------------------------
        // CloudKit Schema Initialization (DEBUG only)
        // This ensures ckAsset fields are created for binary data attributes
        // ---------------------------------------------------------------------
        #if DEBUG
        if !inMemory {
            initializeCloudKitSchemaIfNeeded()
        }
        #endif

        // ---------------------------------------------------------------------
        // CloudKit Monitoring
        // ---------------------------------------------------------------------
        setupCloudKitMonitoring()
        setupCloudKitEventMonitoring()
        checkiCloudAccountStatus()
    }

    // MARK: - Schema Initialization

    #if DEBUG
    private func initializeCloudKitSchemaIfNeeded() {
        // Only run this once - it creates representative records in CloudKit
        // and ensures schema is synchronized (especially for ckAsset fields)
        let hasInitializedKey = "CloudKitSchemaInitialized_v1"
        guard !UserDefaults.standard.bool(forKey: hasInitializedKey) else {
            print("☁️ [CloudKit] Schema already initialized")
            return
        }

        Task {
            do {
                try container.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(true, forKey: hasInitializedKey)
                print("☁️ [CloudKit] ✅ Schema initialized successfully")
            } catch {
                print("☁️ [CloudKit] ⚠️ Schema initialization failed: \(error)")
                // Don't save the flag - try again next launch
            }
        }
    }
    #endif

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

            // NOTE: Do NOT call refreshAllObjects() here - it can cause crashes
            // when combined with CloudKit sync. The automaticallyMergesChangesFromParent
            // setting handles this automatically and safely.
            print("☁️ [CloudKit] Changes will be merged automatically")
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

    /// Monitor CloudKit sync events for detailed status and error handling
    private func setupCloudKitEventMonitoring() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
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
                    print("☁️ [CloudKit] Setup phase started")
                case .import:
                    PersistenceController.syncProgress = .importing
                    PersistenceController.isSyncing = true
                    // Only log start of event (when endDate is nil), not completion
                    if event.endDate == nil {
                        print("☁️ [CloudKit] Importing data from iCloud...")
                    }
                case .export:
                    PersistenceController.syncProgress = .exporting
                    PersistenceController.isSyncing = true
                    if event.endDate == nil {
                        print("☁️ [CloudKit] Exporting data to iCloud...")
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
                        print("☁️ [CloudKit] ✅ Sync completed successfully")
                    }
                }
            }
        }

        print("☁️ [CloudKit] Event monitoring setup complete")
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
        print("☁️ [CloudKit] ❌ ERROR DETAILS:")
        print("☁️ [CloudKit]   Domain: \(nsError.domain)")
        print("☁️ [CloudKit]   Code: \(nsError.code) - \(translateCKErrorCode(nsError.code))")
        print("☁️ [CloudKit]   Description: \(nsError.localizedDescription)")

        // Log underlying errors if present
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("☁️ [CloudKit]   Underlying: \(underlying.domain) code \(underlying.code)")
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .quotaExceeded:
                print("☁️ [CloudKit] ❌ QUOTA EXCEEDED - iCloud storage is full")
                print("☁️ [CloudKit] → User needs to free up iCloud storage or upgrade plan")

            case .networkFailure, .networkUnavailable:
                print("☁️ [CloudKit] ⚠️ Network error - will retry automatically")

            case .partialFailure:
                print("☁️ [CloudKit] ⚠️ Partial failure - some records synced")
                if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                    print("☁️ [CloudKit]   Partial errors (\(partialErrors.count) items):")
                    for (recordID, recordError) in partialErrors.prefix(5) {
                        let recordNSError = recordError as NSError
                        print("☁️ [CloudKit]   - \(recordID): code \(recordNSError.code) - \(translateCKErrorCode(recordNSError.code))")
                    }
                    if partialErrors.count > 5 {
                        print("☁️ [CloudKit]   ... and \(partialErrors.count - 5) more errors")
                    }
                }

            case .notAuthenticated:
                print("☁️ [CloudKit] ❌ NOT AUTHENTICATED - user needs to sign in to iCloud")

            case .serverResponseLost:
                print("☁️ [CloudKit] ⚠️ Server response lost - will retry")

            case .zoneBusy:
                print("☁️ [CloudKit] ⚠️ CloudKit server busy - will retry")

            case .zoneNotFound:
                print("☁️ [CloudKit] ❌ ZONE NOT FOUND - The CloudKit zone doesn't exist!")
                print("☁️ [CloudKit] → This is likely the root cause of sync failures")
                print("☁️ [CloudKit] → Try 'Repair Sync' in Settings to recreate the zone")

            case .unknownItem:
                print("☁️ [CloudKit] ❌ UNKNOWN ITEM - Record or zone doesn't exist in CloudKit")
                print("☁️ [CloudKit] → Schema may not be deployed or zone is missing")
                print("☁️ [CloudKit] → Try 'Repair Sync' in Settings")

            case .operationCancelled:
                print("☁️ [CloudKit] ⚠️ Operation cancelled")

            case .incompatibleVersion:
                print("☁️ [CloudKit] ❌ Incompatible version - schema mismatch")
                print("☁️ [CloudKit] → May need to run initializeCloudKitSchema()")

            case .assetFileNotFound:
                print("☁️ [CloudKit] ⚠️ Asset file not found - binary data issue")

            case .invalidArguments:
                print("☁️ [CloudKit] ❌ INVALID ARGUMENTS - Query or schema issue")
                print("☁️ [CloudKit] → Check if schema is deployed to Production")

            default:
                print("☁️ [CloudKit] ⚠️ CloudKit error (\(ckError.code.rawValue)): \(ckError.localizedDescription)")
            }
        } else {
            print("☁️ [CloudKit] ⚠️ Non-CKError sync error: \(error.localizedDescription)")
        }
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
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        ckContainer.accountStatus { status, error in
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

    // MARK: - CloudKit Debugging

    /// Dump local Core Data record counts for debugging
    func dumpLocalRecordCounts() {
        let context = container.viewContext
        context.perform {
            print("\n☁️ ========== LOCAL CORE DATA RECORD COUNTS ==========")

            // Person count
            let personRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let personCount = (try? context.count(for: personRequest)) ?? 0
            print("☁️ Person records: \(personCount)")

            // Conversation count
            let convRequest = NSFetchRequest<NSManagedObject>(entityName: "Conversation")
            let convCount = (try? context.count(for: convRequest)) ?? 0
            print("☁️ Conversation records: \(convCount)")

            // UserProfileEntity count
            let profileRequest = NSFetchRequest<NSManagedObject>(entityName: "UserProfileEntity")
            let profileCount = (try? context.count(for: profileRequest)) ?? 0
            print("☁️ UserProfileEntity records: \(profileCount)")

            // Group count
            let groupRequest = NSFetchRequest<NSManagedObject>(entityName: "Group")
            let groupCount = (try? context.count(for: groupRequest)) ?? 0
            print("☁️ Group records: \(groupCount)")

            // GroupMeeting count
            let meetingRequest = NSFetchRequest<NSManagedObject>(entityName: "GroupMeeting")
            let meetingCount = (try? context.count(for: meetingRequest)) ?? 0
            print("☁️ GroupMeeting records: \(meetingCount)")

            print("☁️ =====================================================\n")
        }
    }

    /// Query CloudKit directly to verify what records exist
    func verifyCloudKitRecords() {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase

        print("\n☁️ ========== CLOUDKIT RECORD VERIFICATION ==========")
        print("☁️ Querying CloudKit private database...")

        // Query for CD_Person records (Core Data prefixes with CD_)
        let recordTypes = ["CD_Person", "CD_Conversation", "CD_UserProfileEntity", "CD_Group", "CD_GroupMeeting"]

        for recordType in recordTypes {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            privateDB.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100) { result in
                switch result {
                case .success(let (matchResults, _)):
                    let count = matchResults.count
                    print("☁️ \(recordType): \(count) records in CloudKit")

                    // Log first few record IDs for debugging
                    for (recordID, recordResult) in matchResults.prefix(3) {
                        switch recordResult {
                        case .success(let record):
                            print("☁️   - \(recordID.recordName): modified \(record.modificationDate ?? Date())")
                        case .failure(let error):
                            print("☁️   - \(recordID.recordName): error \(error.localizedDescription)")
                        }
                    }

                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        print("☁️ \(recordType): Record type not found in schema")
                    } else {
                        print("☁️ \(recordType): Error querying - \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Force re-initialize CloudKit schema (DEBUG only)
    /// This creates sample records to ensure all fields are in the schema
    func forceSchemaReinitialization() {
        #if DEBUG
        print("☁️ [CloudKit] Forcing schema re-initialization...")

        // Clear the flag so schema initialization runs again
        UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v1")

        Task {
            do {
                // Use dryRun first to see what would happen
                try container.initializeCloudKitSchema(options: [.dryRun])
                print("☁️ [CloudKit] Schema dry run successful")

                // Now do the actual initialization
                try container.initializeCloudKitSchema(options: [])
                print("☁️ [CloudKit] ✅ Schema force-initialized successfully")
                print("☁️ [CloudKit] ⚠️ IMPORTANT: Deploy schema to Production in CloudKit Dashboard!")

                UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized_v1")
            } catch {
                print("☁️ [CloudKit] ❌ Schema initialization failed: \(error)")
            }
        }
        #else
        print("☁️ [CloudKit] Schema reinitialization only available in DEBUG builds")
        #endif
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
                print("☁️ [CloudKit] ✅ Zone exists: \(zone.zoneID.zoneName)")
                print("☁️ [CloudKit] Zone capabilities: \(zone.capabilities)")
            } else if let error = error {
                print("☁️ [CloudKit] ❌ Zone error: \(error.localizedDescription)")

                // Check if zone doesn't exist
                if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                    print("☁️ [CloudKit] Zone not found - this means no data has ever synced!")
                    print("☁️ [CloudKit] Try saving some data to create the zone")
                }
            }
        }
    }

    /// Force sync all existing data by touching modifiedAt timestamps
    /// This is needed because data created before history tracking was enabled won't sync
    func forceSyncAllExistingData() {
        let context = container.viewContext

        context.perform {
            print("☁️ [CloudKit] Force-syncing all existing data...")
            var touchedCount = 0

            // Touch all Person records
            let personRequest: NSFetchRequest<Person> = Person.fetchRequest()
            if let people = try? context.fetch(personRequest) {
                for person in people {
                    person.modifiedAt = Date()
                    touchedCount += 1
                }
                print("☁️ [CloudKit] Touched \(people.count) Person records")
            }

            // Touch all Conversation records
            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            if let conversations = try? context.fetch(convRequest) {
                for conversation in conversations {
                    conversation.modifiedAt = Date()
                    touchedCount += 1
                }
                print("☁️ [CloudKit] Touched \(conversations.count) Conversation records")
            }

            // Touch UserProfileEntity
            let profileRequest = NSFetchRequest<UserProfileEntity>(entityName: "UserProfileEntity")
            if let profiles = try? context.fetch(profileRequest) {
                for profile in profiles {
                    profile.modifiedAt = Date()
                    touchedCount += 1
                }
                print("☁️ [CloudKit] Touched \(profiles.count) UserProfileEntity records")
            }

            // Touch Group records
            let groupRequest = NSFetchRequest<Group>(entityName: "Group")
            if let groups = try? context.fetch(groupRequest) {
                for group in groups {
                    group.modifiedAt = Date()
                    touchedCount += 1
                }
                print("☁️ [CloudKit] Touched \(groups.count) Group records")
            }

            // Touch GroupMeeting records
            let meetingRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
            if let meetings = try? context.fetch(meetingRequest) {
                for meeting in meetings {
                    meeting.modifiedAt = Date()
                    touchedCount += 1
                }
                print("☁️ [CloudKit] Touched \(meetings.count) GroupMeeting records")
            }

            // Save changes to trigger CloudKit sync
            do {
                if context.hasChanges {
                    try context.save()
                    print("☁️ [CloudKit] ✅ Force-synced \(touchedCount) total records - should trigger CloudKit export")
                } else {
                    print("☁️ [CloudKit] No changes to save")
                }
            } catch {
                print("☁️ [CloudKit] ❌ Error saving force-sync changes: \(error)")
            }
        }
    }

    /// Repair orphaned conversations that reference non-existent Person records
    /// These can cause CloudKit sync failures (CKError 2 - unknownItem)
    func repairOrphanedConversations() -> (deleted: Int, fixed: Int) {
        let context = container.viewContext
        var deletedCount = 0
        var fixedCount = 0

        context.performAndWait {
            print("☁️ [CloudKit] Checking for orphaned conversations...")

            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            guard let conversations = try? context.fetch(convRequest) else {
                print("☁️ [CloudKit] Could not fetch conversations")
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
                        print("☁️ [CloudKit] Fixed orphan with content: \(conversation.summary?.prefix(30) ?? "no summary")")
                    } else {
                        // Empty orphan - delete it
                        context.delete(conversation)
                        deletedCount += 1
                        print("☁️ [CloudKit] Deleted empty orphan conversation")
                    }
                }
            }

            if context.hasChanges {
                do {
                    try context.save()
                    print("☁️ [CloudKit] ✅ Orphan repair saved: deleted \(deletedCount), fixed \(fixedCount)")
                } catch {
                    print("☁️ [CloudKit] ❌ Error saving orphan repairs: \(error)")
                }
            } else {
                print("☁️ [CloudKit] No orphaned conversations found")
            }
        }

        return (deleted: deletedCount, fixed: fixedCount)
    }

    /// Purge all persistent history - this clears sync tracking metadata
    /// This is needed when sync gets into a corrupted state
    func purgePersistentHistory() async {
        let context = container.newBackgroundContext()

        await context.perform {
            print("☁️ [CloudKit] Purging persistent history transactions...")

            do {
                // Delete all history before the current date - this clears sync metadata
                let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: Date())
                try context.execute(deleteRequest)
                print("☁️ [CloudKit] ✅ Purged persistent history")
            } catch {
                print("☁️ [CloudKit] ⚠️ Error purging history: \(error.localizedDescription)")
            }
        }
    }

    /// Delete ALL orphaned conversations (use with caution)
    func deleteAllOrphanedConversations() -> Int {
        let context = container.viewContext
        var deletedCount = 0

        context.performAndWait {
            print("☁️ [CloudKit] Deleting ALL orphaned conversations...")

            let convRequest = NSFetchRequest<Conversation>(entityName: "Conversation")
            guard let conversations = try? context.fetch(convRequest) else {
                print("☁️ [CloudKit] Could not fetch conversations")
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
                    print("☁️ [CloudKit] ✅ Deleted \(deletedCount) orphaned conversations")
                } catch {
                    print("☁️ [CloudKit] ❌ Error deleting orphans: \(error)")
                }
            }
        }

        return deletedCount
    }

    /// Comprehensive sync diagnostic
    func runSyncDiagnostic() {
        print("\n")
        print("☁️ ╔══════════════════════════════════════════════════════════╗")
        print("☁️ ║           CLOUDKIT SYNC DIAGNOSTIC REPORT                ║")
        print("☁️ ╚══════════════════════════════════════════════════════════╝")
        print("☁️")
        print("☁️ Container ID: \(PersistenceController.cloudKitContainerID)")
        print("☁️")

        // Check iCloud status
        checkiCloudAccountStatus()

        // Check zone
        checkCloudKitZoneStatus()

        // Dump local counts
        dumpLocalRecordCounts()

        // Query CloudKit
        verifyCloudKitRecords()

        print("☁️")
        print("☁️ ════════════════════════════════════════════════════════════")
        print("☁️ TROUBLESHOOTING STEPS:")
        print("☁️ 1. Ensure SAME iCloud account on both devices")
        print("☁️ 2. Check CloudKit Dashboard → Deploy Schema to Production")
        print("☁️ 3. In CloudKit Dashboard, verify records exist in Private DB")
        print("☁️ 4. Try: Settings → iCloud → WhoNext → Toggle OFF then ON")
        print("☁️ 5. Check device storage isn't full")
        print("☁️ ════════════════════════════════════════════════════════════")
    }

    // MARK: - Zone Repair and Reset

    /// Check if CloudKit zone exists (async version)
    func checkZoneExistsAsync() async -> Bool {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        do {
            _ = try await privateDB.recordZone(for: zoneID)
            print("☁️ [CloudKit] ✅ Zone exists")
            return true
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .zoneNotFound {
                print("☁️ [CloudKit] ❌ Zone NOT found - needs to be created")
            } else {
                print("☁️ [CloudKit] ⚠️ Zone check error: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// Create CloudKit zone if it doesn't exist
    func createCloudKitZoneIfNeeded() async throws {
        let zoneExists = await checkZoneExistsAsync()
        if zoneExists {
            print("☁️ [CloudKit] Zone already exists, no action needed")
            return
        }

        print("☁️ [CloudKit] Creating CloudKit zone...")
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")

        do {
            let savedZone = try await privateDB.save(zone)
            print("☁️ [CloudKit] ✅ Zone created: \(savedZone.zoneID.zoneName)")
        } catch {
            print("☁️ [CloudKit] ❌ Failed to create zone: \(error)")
            throw error
        }
    }

    /// Repair CloudKit sync - tries to fix common issues
    func repairCloudKitSync() async throws {
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
        print("☁️ [CloudKit] Starting CloudKit Sync Repair...")
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")

        // Step 1: Check iCloud account status
        print("☁️ [CloudKit] Step 1: Checking iCloud account...")
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
            print("☁️ [CloudKit] ❌ iCloud not available (status: \(status.rawValue))")
            throw NSError(domain: "CloudKitRepair", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud account not available. Please sign in to iCloud."])
        }
        print("☁️ [CloudKit] ✅ iCloud account available")

        // Step 2: Check/create zone
        print("☁️ [CloudKit] Step 2: Checking CloudKit zone...")
        try await createCloudKitZoneIfNeeded()

        // Step 3: Re-initialize schema
        print("☁️ [CloudKit] Step 3: Re-initializing schema...")
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
        print("☁️ [CloudKit] ⚠️ Schema initialization skipped (not DEBUG build)")
        #endif

        // Step 4: Repair orphaned conversations (can cause sync failures)
        print("☁️ [CloudKit] Step 4: Repairing orphaned conversations...")
        let orphanResult = repairOrphanedConversations()
        print("☁️ [CloudKit] ✅ Orphan repair: deleted \(orphanResult.deleted), fixed \(orphanResult.fixed)")

        // Step 5: Force sync all records
        print("☁️ [CloudKit] Step 5: Forcing sync of all records...")
        forceSyncAllExistingData()

        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
        print("☁️ [CloudKit] ✅ Repair complete! Wait 1-2 minutes for sync.")
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
    }

    /// Nuclear option: Reset CloudKit sync completely
    /// WARNING: This deletes ALL CloudKit data and re-uploads from this device
    func resetCloudKitSync() async throws {
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
        print("☁️ [CloudKit] ⚠️ NUCLEAR RESET: Deleting CloudKit zone...")
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")

        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Step 1: Delete the zone (removes all cloud data)
        print("☁️ [CloudKit] Step 1: Deleting CloudKit zone...")
        do {
            try await privateDB.deleteRecordZone(withID: zoneID)
            print("☁️ [CloudKit] ✅ Zone deleted")
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .zoneNotFound {
                print("☁️ [CloudKit] Zone didn't exist, continuing...")
            } else {
                print("☁️ [CloudKit] ⚠️ Zone deletion warning: \(error.localizedDescription)")
                // Continue anyway
            }
        }

        // Step 2: Wait a moment for CloudKit to process
        print("☁️ [CloudKit] Step 2: Waiting for CloudKit to process...")
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Step 3: Clear local sync metadata and purge persistent history
        print("☁️ [CloudKit] Step 3: Clearing local sync metadata...")
        UserDefaults.standard.removeObject(forKey: "CloudKitSchemaInitialized_v1")

        // Purge ALL persistent history - this is where sync metadata lives
        print("☁️ [CloudKit] Step 3b: Purging persistent history...")
        await purgePersistentHistory()

        // Step 4: Create new zone
        print("☁️ [CloudKit] Step 4: Creating new zone...")
        let zone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")
        _ = try await privateDB.save(zone)
        print("☁️ [CloudKit] ✅ New zone created")

        // Step 5: Re-initialize schema
        print("☁️ [CloudKit] Step 5: Initializing schema...")
        #if DEBUG
        try container.initializeCloudKitSchema(options: [])
        UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized_v1")
        print("☁️ [CloudKit] ✅ Schema initialized")
        #endif

        // Step 6: Clean up orphaned conversations before uploading
        print("☁️ [CloudKit] Step 6: Cleaning orphaned conversations...")
        let deletedOrphans = deleteAllOrphanedConversations()
        print("☁️ [CloudKit] ✅ Deleted \(deletedOrphans) orphaned conversations")

        // Step 7: Force sync all records
        print("☁️ [CloudKit] Step 7: Uploading all local data...")
        forceSyncAllExistingData()

        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
        print("☁️ [CloudKit] ✅ RESET COMPLETE!")
        print("☁️ [CloudKit] All data from THIS device will be uploaded.")
        print("☁️ [CloudKit] Other devices will receive data after sync.")
        print("☁️ [CloudKit] ═══════════════════════════════════════════════")
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
