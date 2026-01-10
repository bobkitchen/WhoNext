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

            let conversationRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let localConversationCount = try context.count(for: conversationRequest)
            results.append("   Local Conversations: \(localConversationCount)")
        } catch {
            results.append("   ❌ Error counting local data: \(error)")
        }
        results.append("")

        // 3. Relationship Integrity Check
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

        // 4. CloudKit/iCloud Status
        results.append("")
        results.append("☁️ CLOUDKIT SYNC STATUS:")
        let cloudKitResults = await runCloudKitDiagnostics()
        results.append(contentsOf: cloudKitResults)

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

        // Query CloudKit for record counts
        results.append("")
        results.append("☁️ CLOUDKIT RECORD COUNTS:")

        let privateDB = ckContainer.privateCloudDatabase
        let recordTypes = ["CD_Person", "CD_Conversation", "CD_UserProfileEntity"]

        for recordType in recordTypes {
            let count = await queryCloudKitCount(database: privateDB, recordType: recordType)
            results.append("   \(recordType): \(count)")
        }

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

    private func queryCloudKitCount(database: CKDatabase, recordType: String) async -> String {
        await withCheckedContinuation { continuation in
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))

            // Use the custom zone that NSPersistentCloudKitContainer creates
            // ownerName should be "_defaultOwner" for the current user
            let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: "_defaultOwner")

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
                            continuation.resume(returning: "Zone not found (no data synced yet)")
                        case .notAuthenticated:
                            continuation.resume(returning: "Not authenticated")
                        default:
                            continuation.resume(returning: "Error: \(ckError.localizedDescription)")
                        }
                    } else {
                        continuation.resume(returning: "Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
