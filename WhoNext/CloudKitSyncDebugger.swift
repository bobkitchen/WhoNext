import Foundation
import CoreData
import CloudKit
import SwiftUI

class CloudKitSyncDebugger: ObservableObject {
    @Published var debugOutput: String = ""
    private let container: NSPersistentCloudKitContainer
    
    init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }
    
    func runFullSyncDebug() {
        debugOutput = "🔍 CloudKit Sync Debugging Report\n"
        debugOutput += "Generated at: \(Date().formatted())\n\n"
        
        // 1. Check Core Data setup
        checkCoreDataSetup()
        
        // 2. Check CloudKit container setup
        checkCloudKitSetup()
        
        // 3. Force a sync attempt
        forceSyncAttempt()
        
        // 4. Check for sync tokens
        checkSyncTokens()
        
        // 5. Count local records
        countLocalRecords()
    }
    
    private func checkCoreDataSetup() {
        debugOutput += "1️⃣ Core Data Setup:\n"
        
        // Check persistent stores
        let stores = container.persistentStoreCoordinator.persistentStores
        debugOutput += "   Persistent stores: \(stores.count)\n"
        
        for (index, store) in stores.enumerated() {
            debugOutput += "   Store \(index + 1):\n"
            debugOutput += "     Type: \(store.type)\n"
            debugOutput += "     URL: \(store.url?.path ?? "No URL")\n"
            
            // Check CloudKit options
            if let options = store.options {
                let hasCloudKit = options[NSPersistentHistoryTrackingKey] != nil
                let hasRemoteNotifications = options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] != nil
                debugOutput += "     History tracking: \(hasCloudKit ? "✅" : "❌")\n"
                debugOutput += "     Remote notifications: \(hasRemoteNotifications ? "✅" : "❌")\n"
                
                // Check CloudKit container options
                if let ckContainerOptions = options["NSPersistentCloudKitContainerOptions"] as? NSPersistentCloudKitContainerOptions {
                    debugOutput += "     CloudKit container: \(ckContainerOptions.containerIdentifier)\n"
                }
            }
        }
        debugOutput += "\n"
    }
    
    private func checkCloudKitSetup() {
        debugOutput += "2️⃣ CloudKit Configuration:\n"
        
        // Check if CloudKit is properly configured
        let ckContainer = CKContainer(identifier: "iCloud.com.bobk.whonext")
        
        // Check account status
        ckContainer.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.debugOutput += "   ❌ Account status error: \(error.localizedDescription)\n"
                } else {
                    let statusString = switch status {
                    case .available: "Available ✅"
                    case .noAccount: "No Account ❌"
                    case .restricted: "Restricted ⚠️"
                    case .couldNotDetermine: "Could Not Determine ❓"
                    case .temporarilyUnavailable: "Temporarily Unavailable ⏳"
                    @unknown default: "Unknown"
                    }
                    self?.debugOutput += "   Account status: \(statusString)\n"
                }
                
                // Check for schema initialization
                self?.checkSchemaInitialization(container: ckContainer)
            }
        }
    }
    
    private func checkSchemaInitialization(container: CKContainer) {
        debugOutput += "   Checking schema initialization...\n"
        
        // Try to fetch the Core Data zone
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        
        container.privateCloudDatabase.fetch(withRecordZoneID: zoneID) { [weak self] zone, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.debugOutput += "   ❌ Core Data zone error: \(error.localizedDescription)\n"
                    if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                        self?.debugOutput += "   💡 Schema not initialized - try creating a record\n"
                    }
                } else if zone != nil {
                    self?.debugOutput += "   ✅ Core Data zone exists\n"
                }
                self?.debugOutput += "\n"
            }
        }
    }
    
    private func forceSyncAttempt() {
        debugOutput += "3️⃣ Forcing Sync Attempt:\n"
        
        // Try to trigger a sync by saving the context
        let context = container.viewContext
        
        do {
            if context.hasChanges {
                try context.save()
                debugOutput += "   ✅ Saved pending changes\n"
            } else {
                debugOutput += "   ℹ️ No pending changes to save\n"
            }
            
            // Force a small change to trigger sync
            let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
            fetchRequest.fetchLimit = 1
            
            if let person = try context.fetch(fetchRequest).first {
                // Toggle a harmless property to force sync
                let oldNotes = person.notes
                person.notes = (person.notes ?? "") + " "
                try context.save()
                debugOutput += "   ✅ Made test change to trigger sync\n"
                
                // Revert after a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    person.notes = oldNotes
                    try? context.save()
                }
            } else {
                debugOutput += "   ⚠️ No records found to test sync\n"
            }
        } catch {
            debugOutput += "   ❌ Save error: \(error.localizedDescription)\n"
        }
        debugOutput += "\n"
    }
    
    private func checkSyncTokens() {
        debugOutput += "4️⃣ Sync Token Status:\n"
        
        // Check for CloudKit change tokens in user defaults
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        
        var tokenCount = 0
        for key in keys {
            if key.contains("CloudKit") || key.contains("NSPersistent") {
                tokenCount += 1
                if key.contains("Token") || key.contains("token") {
                    debugOutput += "   Found token key: \(key)\n"
                }
            }
        }
        
        if tokenCount > 0 {
            debugOutput += "   ✅ Found \(tokenCount) CloudKit-related keys\n"
        } else {
            debugOutput += "   ⚠️ No CloudKit tokens found\n"
        }
        debugOutput += "\n"
    }
    
    private func countLocalRecords() {
        debugOutput += "5️⃣ Local Record Count:\n"
        
        let context = container.viewContext
        
        do {
            let personCount = try context.count(for: Person.fetchRequest())
            let conversationCount = try context.count(for: Conversation.fetchRequest())
            
            debugOutput += "   People: \(personCount)\n"
            debugOutput += "   Conversations: \(conversationCount)\n"
            
            // Get some sample data
            let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
            fetchRequest.fetchLimit = 3
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: false)]
            
            let recentPeople = try context.fetch(fetchRequest)
            if !recentPeople.isEmpty {
                debugOutput += "   Sample people:\n"
                for person in recentPeople {
                    let name = person.name ?? "Unknown"
                    debugOutput += "     • \(name)\n"
                }
            }
        } catch {
            debugOutput += "   ❌ Count error: \(error.localizedDescription)\n"
        }
        
        debugOutput += "\n"
        debugOutput += "💡 Recommendations:\n"
        debugOutput += "   1. Check that both Macs are signed into the same iCloud account\n"
        debugOutput += "   2. Ensure iCloud Drive is enabled on both Macs\n"
        debugOutput += "   3. Check System Settings > Apple ID > iCloud > Apps Using iCloud\n"
        debugOutput += "   4. Try 'Reset Sync' if tokens are expired\n"
        debugOutput += "   5. Create a test person and wait 15 minutes\n"
    }
}
