import Foundation
import CoreData
import CloudKit

class SyncDiagnostics {
    static let shared = SyncDiagnostics()

    private let deviceId: String = {
        #if os(macOS)
        return ProcessInfo.processInfo.hostName + "-" + (ProcessInfo.processInfo.environment["USER"] ?? "unknown")
        #else
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #endif
    }()

    func runDiagnostics(context: NSManagedObjectContext) async -> [String] {
        var results: [String] = []

        // 1. Device Info
        results.append("🖥️ DEVICE INFO:")
        results.append("   Device ID: \(deviceId)")
        results.append("   Host: \(ProcessInfo.processInfo.hostName)")
        results.append("   macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        results.append("")

        // 2. Local Data Count
        results.append("💾 LOCAL DATA:")
        do {
            let peopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let localPeopleCount = try context.count(for: peopleRequest)
            results.append("   Local People: \(localPeopleCount)")

            // Also count non-deleted
            let activeRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            activeRequest.predicate = NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil")
            let activePeopleCount = try context.count(for: activeRequest)
            results.append("   Active People (not soft-deleted): \(activePeopleCount)")

            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let localConversationCount = try context.count(for: conversationRequest)
            results.append("   Local Conversations: \(localConversationCount)")
        } catch {
            results.append("   ❌ Error counting local data: \(error)")
        }
        results.append("")

        // 3. Check for stuck records (records that may not have synced)
        let stuckResults = checkForStuckRecords(context: context)
        results.append(contentsOf: stuckResults)

        // 4. Relationship Integrity Check
        results.append("")
        results.append("🔗 RELATIONSHIP INTEGRITY:")
        do {
            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let allConversations = try context.fetch(conversationRequest)

            let orphanedConversations = allConversations.filter { $0.person == nil }
            let linkedConversations = allConversations.filter { $0.person != nil }

            results.append("   Total conversations: \(allConversations.count)")
            results.append("   Linked to people: \(linkedConversations.count)")
            results.append("   Orphaned (no person): \(orphanedConversations.count)")

            if orphanedConversations.count > 0 {
                results.append("   ⚠️ Found orphaned conversations - this causes UI display issues!")
            }

            // Check people without conversations
            let peopleRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let allPeople = try context.fetch(peopleRequest)
            let peopleWithConversations = allPeople.filter { ($0.conversations?.count ?? 0) > 0 }

            results.append("   People with conversations: \(peopleWithConversations.count)/\(allPeople.count)")

        } catch {
            results.append("   ❌ Error checking relationships: \(error)")
        }

        // 5. CloudKit/iCloud Status
        results.append("")
        results.append("☁️ CLOUDKIT SYNC STATUS:")
        let cloudKitResults = await runCloudKitDiagnostics()
        results.append(contentsOf: cloudKitResults)

        // 6. Query CloudKit directly for Person records
        let cloudKitPersonResults = await queryCloudKitPersonRecords()
        results.append(contentsOf: cloudKitPersonResults)

        return results
    }

    // MARK: - CloudKit Diagnostics

    private func runCloudKitDiagnostics() async -> [String] {
        var results: [String] = []

        // Check iCloud account status
        let accountStatus = await withCheckedContinuation { continuation in
            CKContainer.default().accountStatus { status, error in
                continuation.resume(returning: (status, error))
            }
        }

        switch accountStatus.0 {
        case .available:
            results.append("   ✅ iCloud Account: Available")
        case .noAccount:
            results.append("   ❌ iCloud Account: NOT SIGNED IN")
            results.append("   ⚠️ Sign in to iCloud in System Settings to enable sync!")
        case .restricted:
            results.append("   ⚠️ iCloud Account: Restricted (parental controls?)")
        case .couldNotDetermine:
            results.append("   ⚠️ iCloud Account: Could not determine status")
            if let error = accountStatus.1 {
                results.append("   Error: \(error.localizedDescription)")
            }
        case .temporarilyUnavailable:
            results.append("   ⚠️ iCloud Account: Temporarily unavailable")
        @unknown default:
            results.append("   ⚠️ iCloud Account: Unknown status")
        }

        // Check CloudKit container
        let containerID = PersistenceController.cloudKitContainerID
        results.append("   Container ID: \(containerID)")

        let ckContainer = CKContainer(identifier: containerID)

        // Check container status
        let containerStatus = await withCheckedContinuation { continuation in
            ckContainer.accountStatus { status, error in
                continuation.resume(returning: (status, error))
            }
        }

        if containerStatus.0 == .available {
            results.append("   ✅ WhoNext Container: Accessible")
        } else {
            results.append("   ❌ WhoNext Container: Status \(containerStatus.0.rawValue)")
        }

        // Check CloudKit zone status (more reliable than querying records)
        results.append("")
        results.append("☁️ CLOUDKIT ZONE STATUS:")

        let privateDB = ckContainer.privateCloudDatabase
        let zoneStatus = await checkZoneStatus(database: privateDB)
        results.append(contentsOf: zoneStatus)

        // Check sync progress
        results.append("")
        results.append("☁️ SYNC PROGRESS:")
        await MainActor.run {
            switch PersistenceController.syncProgress {
            case .idle:
                results.append("   Status: Idle")
            case .setup:
                results.append("   Status: Setting up...")
            case .importing:
                results.append("   Status: Importing from iCloud...")
            case .exporting:
                results.append("   Status: Exporting to iCloud...")
            case .completed(let date):
                let formatter = RelativeDateTimeFormatter()
                results.append("   Status: Completed \(formatter.localizedString(for: date, relativeTo: Date()))")
            case .failed(let message):
                results.append("   ❌ Status: Failed - \(message)")
            }

            if let lastChange = PersistenceController.lastRemoteChangeDate {
                let formatter = RelativeDateTimeFormatter()
                results.append("   Last remote change: \(formatter.localizedString(for: lastChange, relativeTo: Date()))")
            } else {
                results.append("   Last remote change: None since app launch")
            }

            if let error = PersistenceController.lastSyncError {
                results.append("   ❌ Last error: \(error.localizedDescription)")
            }
        }

        // Troubleshooting tips
        results.append("")
        results.append("💡 CLOUDKIT TROUBLESHOOTING:")
        results.append("   1. Ensure same iCloud account on both devices")
        results.append("   2. Check CloudKit Dashboard - deploy schema to Production")
        results.append("   3. System Settings → iCloud → toggle WhoNext off/on")
        results.append("   4. Wait 5+ minutes for initial sync")
        results.append("   5. Check device has internet connectivity")

        return results
    }

    /// Check CloudKit zone status without requiring queryable indexes
    private func checkZoneStatus(database: CKDatabase) async -> [String] {
        var results: [String] = []
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        do {
            let zone = try await database.recordZone(for: zoneID)
            results.append("   ✅ Zone exists: \(zone.zoneID.zoneName)")

            // Check zone capabilities
            let capabilities = zone.capabilities
            if capabilities.contains(.fetchChanges) {
                results.append("   ✅ Zone supports change tracking")
            }
            if capabilities.contains(.atomic) {
                results.append("   ✅ Zone supports atomic operations")
            }

        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .zoneNotFound:
                    results.append("   ❌ ZONE NOT FOUND!")
                    results.append("   → This is likely the cause of sync failures")
                    results.append("   → Try 'Repair Sync' in Advanced Options to create the zone")
                case .notAuthenticated:
                    results.append("   ❌ Not authenticated to CloudKit")
                default:
                    results.append("   ⚠️ Zone check error: \(ckError.localizedDescription)")
                }
            } else {
                results.append("   ⚠️ Zone check error: \(error.localizedDescription)")
            }
        }

        return results
    }

    /// NOTE: Direct CloudKit queries may fail with "recordName not queryable"
    /// This is expected - NSPersistentCloudKitContainer doesn't require queryable indexes
    /// The queries below are for debugging only and their failure doesn't affect sync
    private func queryCloudKitCount(database: CKDatabase, recordType: String) async -> String {
        await withCheckedContinuation { continuation in
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

            database.fetch(withQuery: query, inZoneWith: zoneID, desiredKeys: nil, resultsLimit: 1000) { result in
                switch result {
                case .success(let (matchResults, _)):
                    continuation.resume(returning: "\(matchResults.count) records")
                case .failure(let error):
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .unknownItem:
                            continuation.resume(returning: "Record type not in schema")
                        case .zoneNotFound:
                            continuation.resume(returning: "Zone not found")
                        case .notAuthenticated:
                            continuation.resume(returning: "Not authenticated")
                        case .invalidArguments:
                            // This includes "recordName not queryable" - it's expected
                            continuation.resume(returning: "(queries not available - this is normal)")
                        default:
                            continuation.resume(returning: "Error: \(ckError.localizedDescription)")
                        }
                    } else {
                        let nsError = error as NSError
                        // Check for "recordName not queryable" in the server message
                        if nsError.localizedDescription.contains("queryable") {
                            continuation.resume(returning: "(queries not available - this is normal)")
                        } else {
                            continuation.resume(returning: "Error: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Record Comparison Diagnostics

    /// Generate a list of all Person records with their identifiers for comparison between devices
    func generatePersonRecordList(context: NSManagedObjectContext) -> [String] {
        var results: [String] = []
        results.append("")
        results.append("📋 PERSON RECORD LIST (for device comparison):")
        results.append("   Copy this list from both devices to compare")
        results.append("")

        let request: NSFetchRequest<Person> = NSFetchRequest(entityName: "Person")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]

        do {
            let people = try context.fetch(request)
            results.append("   Total: \(people.count) records")
            results.append("")

            for person in people {
                let id = person.identifier?.uuidString.prefix(8) ?? "no-id"
                let name = person.name ?? "unnamed"
                let created = person.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "no-date"
                let modified = person.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never"
                let softDeleted = person.isSoftDeleted ? " [DELETED]" : ""

                results.append("   [\(id)] \(name)\(softDeleted)")
                results.append("          Created: \(created) | Modified: \(modified)")
            }

        } catch {
            results.append("   ❌ Error fetching people: \(error)")
        }

        return results
    }

    /// Check for records that might be stuck (created but never synced)
    func checkForStuckRecords(context: NSManagedObjectContext) -> [String] {
        var results: [String] = []
        results.append("")
        results.append("🔍 CHECKING FOR POTENTIALLY STUCK RECORDS:")
        results.append("")

        // Check for Person records without modifiedAt (might not trigger sync)
        let personRequest: NSFetchRequest<Person> = NSFetchRequest(entityName: "Person")
        personRequest.predicate = NSPredicate(format: "modifiedAt == nil")

        do {
            let stuckPeople = try context.fetch(personRequest)
            if stuckPeople.isEmpty {
                results.append("   ✅ All Person records have modifiedAt timestamp")
            } else {
                results.append("   ⚠️ Found \(stuckPeople.count) Person records WITHOUT modifiedAt:")
                for person in stuckPeople.prefix(5) {
                    results.append("      - \(person.name ?? "unnamed") (created: \(person.createdAt?.formatted() ?? "unknown"))")
                }
                results.append("   → These records may not sync! Run 'Force Upload All' to fix.")
            }
        } catch {
            results.append("   ❌ Error: \(error)")
        }

        // Check for records created in last 48 hours (the user's timeframe)
        results.append("")
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let recentRequest: NSFetchRequest<Person> = NSFetchRequest(entityName: "Person")
        recentRequest.predicate = NSPredicate(format: "createdAt >= %@", twoDaysAgo as NSDate)
        recentRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Person.createdAt, ascending: false)]

        do {
            let recentPeople = try context.fetch(recentRequest)
            results.append("   📅 Records created in last 48 hours: \(recentPeople.count)")
            for person in recentPeople {
                let id = person.identifier?.uuidString.prefix(8) ?? "no-id"
                let name = person.name ?? "unnamed"
                let created = person.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
                results.append("      [\(id)] \(name) - Created: \(created)")
            }
        } catch {
            results.append("   ❌ Error: \(error)")
        }

        return results
    }

    /// Query CloudKit directly to see what Person records exist there
    /// NOTE: This may fail with "recordName not queryable" - that's normal and doesn't affect sync
    func queryCloudKitPersonRecords() async -> [String] {
        var results: [String] = []
        results.append("")
        results.append("☁️ CLOUDKIT RECORD QUERY (optional diagnostic):")

        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        let privateDB = ckContainer.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        let query = CKQuery(recordType: "CD_Person", predicate: NSPredicate(value: true))

        return await withCheckedContinuation { continuation in
            privateDB.fetch(withQuery: query, inZoneWith: zoneID, desiredKeys: ["CD_name", "CD_identifier"], resultsLimit: 100) { result in
                switch result {
                case .success(let (matchResults, _)):
                    results.append("   Found \(matchResults.count) Person records in CloudKit:")
                    results.append("")

                    for (recordID, recordResult) in matchResults.prefix(10) {
                        switch recordResult {
                        case .success(let record):
                            let name = record["CD_name"] as? String ?? "unnamed"
                            let modified = record.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
                            results.append("   ☁️ \(name) (modified: \(modified))")
                        case .failure(let error):
                            results.append("   ❌ \(recordID.recordName): \(error.localizedDescription)")
                        }
                    }

                    if matchResults.count > 10 {
                        results.append("   ... and \(matchResults.count - 10) more")
                    }

                case .failure(let error):
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .zoneNotFound:
                            results.append("   ❌ CloudKit zone not found!")
                            results.append("   → Try 'Repair Sync' in Advanced Options")
                        case .notAuthenticated:
                            results.append("   ❌ Not authenticated to CloudKit")
                        case .invalidArguments:
                            // "recordName not queryable" - this is expected
                            results.append("   ℹ️ Direct queries not available (this is normal)")
                            results.append("   → NSPersistentCloudKitContainer doesn't require queryable indexes")
                            results.append("   → Sync may still work - check zone status above")
                        default:
                            results.append("   ⚠️ CloudKit error: \(ckError.localizedDescription)")
                        }
                    } else {
                        let nsError = error as NSError
                        if nsError.localizedDescription.contains("queryable") {
                            results.append("   ℹ️ Direct queries not available (this is normal)")
                            results.append("   → NSPersistentCloudKitContainer doesn't require queryable indexes")
                        } else {
                            results.append("   ⚠️ Error: \(error.localizedDescription)")
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }
}
