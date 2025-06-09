import Foundation
import CoreData
import CloudKit

class CloudKitSyncVerifier: ObservableObject {
    @Published var verificationResults = ""
    private let container: NSPersistentCloudKitContainer
    
    init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }
    
    func verifySyncStatus() {
        verificationResults = "🔍 CloudKit Sync Verification\n"
        verificationResults += "Generated at: \(Date().formatted())\n\n"
        
        checkSyncTokenDetails()
        checkRecentChanges()
        checkPendingExports()
        createTestRecord()
    }
    
    private func checkSyncTokenDetails() {
        verificationResults += "1️⃣ Sync Token Analysis:\n"
        
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        
        var tokenCount = 0
        for (key, value) in dict {
            if key.contains("CKServerChangeToken") || key.contains("CKDatabaseToken") {
                tokenCount += 1
                verificationResults += "   Token: \(key)\n"
                
                // Try to decode token data
                if let data = value as? Data {
                    verificationResults += "     Size: \(data.count) bytes\n"
                    
                    // Check if it's an archived token
                    if let _ = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
                        verificationResults += "     Type: CKServerChangeToken\n"
                    } else {
                        verificationResults += "     Type: Data blob\n"
                    }
                }
            }
        }
        
        if tokenCount == 0 {
            verificationResults += "   ⚠️ No sync tokens found - sync may not have started\n"
        } else {
            verificationResults += "   ✅ Found \(tokenCount) sync tokens\n"
        }
        
        verificationResults += "\n"
    }
    
    private func checkRecentChanges() {
        verificationResults += "2️⃣ Recent Local Changes:\n"
        
        let context = container.viewContext
        
        do {
            // Check for recently modified people
            let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
            fetchRequest.fetchLimit = 5
            
            // Sort by objectID to get most recently created
            let people = try context.fetch(fetchRequest)
            
            // Check history
            let historyToken: NSPersistentHistoryToken? = nil
            let historyRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
            
            if let result = try context.execute(historyRequest) as? NSPersistentHistoryResult,
               let history = result.result as? [NSPersistentHistoryTransaction] {
                
                verificationResults += "   Recent transactions: \(history.count)\n"
                
                for transaction in history.prefix(3) {
                    let date = transaction.timestamp.formatted()
                    let author = transaction.author ?? "System"
                    verificationResults += "     • \(date) by \(author)\n"
                }
            } else {
                verificationResults += "   ℹ️ No transaction history available\n"
            }
            
        } catch {
            verificationResults += "   ❌ Error checking history: \(error.localizedDescription)\n"
        }
        
        verificationResults += "\n"
    }
    
    private func checkPendingExports() {
        verificationResults += "3️⃣ Export/Import Status:\n"
        
        // Check for any pending operations
        let stores = container.persistentStoreCoordinator.persistentStores
        
        for store in stores {
            if let storeURL = store.url {
                verificationResults += "   Store: \(storeURL.lastPathComponent)\n"
                
                // Check metadata
                if let metadata = store.metadata {
                    if let lastExport = metadata["NSPersistentCloudKitContainerLastExportDate"] as? Date {
                        verificationResults += "     Last export: \(lastExport.formatted())\n"
                    }
                    if let lastImport = metadata["NSPersistentCloudKitContainerLastImportDate"] as? Date {
                        verificationResults += "     Last import: \(lastImport.formatted())\n"
                    }
                }
            }
        }
        
        verificationResults += "\n"
    }
    
    private func createTestRecord() {
        verificationResults += "4️⃣ Creating Test Record:\n"
        
        let context = container.viewContext
        
        do {
            // Create a test person with a unique identifier
            let testPerson = Person(context: context)
            let timestamp = Date().timeIntervalSince1970
            testPerson.name = "Sync Test \(Int(timestamp))"
            testPerson.role = "CloudKit Sync Verification"
            testPerson.notes = "Created on \(Date().formatted()) to verify sync"
            testPerson.identifier = UUID()
            
            try context.save()
            
            verificationResults += "   ✅ Created test person: \(testPerson.name ?? "Unknown")\n"
            verificationResults += "   📝 Check if this appears on your other Mac within 15 minutes\n"
            verificationResults += "   🆔 Test ID: \(testPerson.identifier?.uuidString ?? "None")\n"
            
        } catch {
            verificationResults += "   ❌ Failed to create test record: \(error.localizedDescription)\n"
        }
        
        verificationResults += "\n"
        verificationResults += "💡 Next Steps:\n"
        verificationResults += "   1. Note the test person name above\n"
        verificationResults += "   2. Wait 15-20 minutes\n"
        verificationResults += "   3. Check if it appears on your other Mac\n"
        verificationResults += "   4. If not, try 'Reset Sync' and repeat\n"
    }
}
