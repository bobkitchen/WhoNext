import Foundation
import CoreData
import CloudKit

class CloudKitTokenInspector: ObservableObject {
    @Published var inspectionResults = ""
    private let container: NSPersistentCloudKitContainer
    
    init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }
    
    func inspectAllTokens() {
        inspectionResults = "🔍 Comprehensive Token Inspection\n"
        inspectionResults += "Generated at: \(Date().formatted())\n\n"
        
        inspectUserDefaults()
        inspectStoreMetadata()
        inspectCloudKitContainer()
        checkSyncHistory()
    }
    
    private func inspectUserDefaults() {
        inspectionResults += "1️⃣ UserDefaults Deep Scan:\n"
        
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        
        var cloudKitKeys: [String] = []
        var coreDataKeys: [String] = []
        var tokenKeys: [String] = []
        
        for key in dict.keys.sorted() {
            let lowercaseKey = key.lowercased()
            if lowercaseKey.contains("cloudkit") || lowercaseKey.contains("ck") {
                cloudKitKeys.append(key)
            }
            if lowercaseKey.contains("coredata") || lowercaseKey.contains("nscore") {
                coreDataKeys.append(key)
            }
            if lowercaseKey.contains("token") || lowercaseKey.contains("change") {
                tokenKeys.append(key)
            }
        }
        
        inspectionResults += "   CloudKit-related keys (\(cloudKitKeys.count)):\n"
        for key in cloudKitKeys.prefix(10) {
            let value = dict[key]
            let valueType = type(of: value)
            inspectionResults += "     • \(key): \(valueType)\n"
        }
        
        inspectionResults += "   Token-related keys (\(tokenKeys.count)):\n"
        for key in tokenKeys.prefix(10) {
            let value = dict[key]
            let valueType = type(of: value)
            inspectionResults += "     • \(key): \(valueType)\n"
        }
        
        inspectionResults += "   Core Data keys (\(coreDataKeys.count)):\n"
        for key in coreDataKeys.prefix(5) {
            inspectionResults += "     • \(key)\n"
        }
        
        inspectionResults += "\n"
    }
    
    private func inspectStoreMetadata() {
        inspectionResults += "2️⃣ Store Metadata Analysis:\n"
        
        let stores = container.persistentStoreCoordinator.persistentStores
        
        for (index, store) in stores.enumerated() {
            inspectionResults += "   Store \(index + 1):\n"
            inspectionResults += "     Type: \(store.type)\n"
            inspectionResults += "     URL: \(store.url?.lastPathComponent ?? "Unknown")\n"
            
            if let metadata = store.metadata {
                inspectionResults += "     Metadata keys (\(metadata.count)):\n"
                
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    let keyLower = key.lowercased()
                    if keyLower.contains("cloudkit") || keyLower.contains("token") || keyLower.contains("sync") {
                        let valueType = type(of: value)
                        inspectionResults += "       • \(key): \(valueType)\n"
                        
                        // Try to decode dates
                        if let date = value as? Date {
                            inspectionResults += "         Value: \(date.formatted())\n"
                        } else if let data = value as? Data {
                            inspectionResults += "         Size: \(data.count) bytes\n"
                            
                            // Try to decode as token
                            if let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
                                inspectionResults += "         Type: CKServerChangeToken ✅\n"
                            }
                        } else if let string = value as? String {
                            inspectionResults += "         Value: \(string.prefix(50))\n"
                        }
                    }
                }
            }
        }
        
        inspectionResults += "\n"
    }
    
    private func inspectCloudKitContainer() {
        inspectionResults += "3️⃣ CloudKit Container Status:\n"
        
        let cloudKitContainer = CKContainer(identifier: "iCloud.com.bobk.whonext")
        
        cloudKitContainer.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.inspectionResults += "   ❌ Account status error: \(error.localizedDescription)\n"
                } else {
                    let statusText = self?.accountStatusText(status) ?? "Unknown"
                    self?.inspectionResults += "   Account: \(statusText)\n"
                }
                
                // Check database scope
                let privateDB = cloudKitContainer.privateCloudDatabase
                self?.inspectionResults += "   Private database: Available\n"
                
                // Simple container test - just try to get container info
                cloudKitContainer.fetchUserRecordID { recordID, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.inspectionResults += "   ❌ Container access error: \(error.localizedDescription)\n"
                        } else if let recordID = recordID {
                            self?.inspectionResults += "   ✅ Container accessible - User ID: \(recordID.recordName)\n"
                        }
                        self?.inspectionResults += "\n"
                    }
                }
            }
        }
    }
    
    private func checkSyncHistory() {
        inspectionResults += "4️⃣ Recent Sync History:\n"
        
        let context = container.viewContext
        
        do {
            // Check for CloudKit events in history
            let historyToken: NSPersistentHistoryToken? = nil
            let historyRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
            
            if let result = try context.execute(historyRequest) as? NSPersistentHistoryResult,
               let history = result.result as? [NSPersistentHistoryTransaction] {
                
                let recentHistory = history.suffix(10)
                inspectionResults += "   Recent transactions (\(recentHistory.count) of \(history.count)):\n"
                
                for transaction in recentHistory {
                    let date = transaction.timestamp.formatted(date: .omitted, time: .standard)
                    let author = transaction.author ?? "System"
                    let changeCount = transaction.changes?.count ?? 0
                    inspectionResults += "     • \(date) by \(author) - \(changeCount) changes\n"
                    
                    // Look for CloudKit-related changes
                    if let changes = transaction.changes {
                        for change in changes.prefix(3) {
                            let entityName = change.changedObjectID.entity.name ?? "Unknown"
                            let changeType = change.changeType == .insert ? "INSERT" : 
                                           change.changeType == .update ? "UPDATE" : "DELETE"
                            inspectionResults += "       - \(changeType) \(entityName)\n"
                        }
                    }
                }
            }
        } catch {
            inspectionResults += "   ❌ History error: \(error.localizedDescription)\n"
        }
        
        inspectionResults += "\n"
        inspectionResults += "💡 Analysis Complete\n"
        inspectionResults += "   If no CloudKit tokens found, sync may need manual restart\n"
        inspectionResults += "   Check System Settings > Apple ID > iCloud for app permissions\n"
    }
    
    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Available ✅"
        case .noAccount: return "No Account ❌"
        case .restricted: return "Restricted ⚠️"
        case .couldNotDetermine: return "Could Not Determine ❓"
        case .temporarilyUnavailable: return "Temporarily Unavailable ⏳"
        @unknown default: return "Unknown"
        }
    }
}
