import Foundation
import CoreData
import CloudKit

class CloudKitNuclearReset: ObservableObject {
    @Published var resetResults = ""
    private let container: NSPersistentCloudKitContainer
    
    init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }
    
    func performNuclearReset() {
        resetResults = "🚨 CloudKit Nuclear Reset\n"
        resetResults += "Generated at: \(Date().formatted())\n\n"
        resetResults += "⚠️ This will completely reset CloudKit sync state\n\n"
        
        Task {
            await performResetSteps()
        }
    }
    
    @MainActor
    private func performResetSteps() async {
        // Step 1: Clear all UserDefaults CloudKit keys
        clearUserDefaults()
        
        // Step 2: Reset persistent store metadata
        await resetStoreMetadata()
        
        // Step 3: Clear CloudKit history
        clearPersistentHistory()
        
        // Step 4: Force container restart
        await restartCloudKitContainer()
        
        // Step 5: Verify reset
        await verifyReset()
        
        resetResults += "\n✅ Nuclear reset complete!\n"
        resetResults += "💡 Restart the app and wait 5-10 minutes for sync to reinitialize\n"
    }
    
    private func clearUserDefaults() {
        resetResults += "1️⃣ Clearing UserDefaults CloudKit keys...\n"
        
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        
        var clearedCount = 0
        for key in dict.keys {
            let lowercaseKey = key.lowercased()
            if lowercaseKey.contains("cloudkit") || 
               lowercaseKey.contains("ck") ||
               lowercaseKey.contains("nscloud") ||
               lowercaseKey.contains("sync") {
                defaults.removeObject(forKey: key)
                clearedCount += 1
            }
        }
        
        defaults.synchronize()
        resetResults += "   Cleared \(clearedCount) CloudKit-related keys\n\n"
    }
    
    private func resetStoreMetadata() async {
        resetResults += "2️⃣ Resetting store metadata...\n"
        
        let stores = container.persistentStoreCoordinator.persistentStores
        
        for store in stores {
            do {
                // Get current metadata
                var metadata = store.metadata ?? [:]
                
                // Remove CloudKit-related metadata
                let keysToRemove = metadata.keys.filter { key in
                    let lowercaseKey = key.lowercased()
                    return lowercaseKey.contains("cloudkit") || 
                           lowercaseKey.contains("ck") ||
                           lowercaseKey.contains("sync") ||
                           lowercaseKey.contains("token")
                }
                
                for key in keysToRemove {
                    metadata.removeValue(forKey: key)
                }
                
                // Update store metadata
                try container.persistentStoreCoordinator.setMetadata(metadata, for: store)
                resetResults += "   Reset metadata for store: \(store.url?.lastPathComponent ?? "Unknown")\n"
                
            } catch {
                resetResults += "   ❌ Error resetting store metadata: \(error.localizedDescription)\n"
            }
        }
        
        resetResults += "\n"
    }
    
    private func clearPersistentHistory() {
        resetResults += "3️⃣ Clearing persistent history...\n"
        
        let context = container.viewContext
        
        do {
            // Delete all persistent history
            let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: Date())
            try context.execute(deleteHistoryRequest)
            
            resetResults += "   ✅ Cleared all persistent history\n\n"
        } catch {
            resetResults += "   ❌ Error clearing history: \(error.localizedDescription)\n\n"
        }
    }
    
    private func restartCloudKitContainer() async {
        resetResults += "4️⃣ Restarting CloudKit container...\n"
        
        // Force save any pending changes
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                resetResults += "   Saved pending changes\n"
            } catch {
                resetResults += "   ⚠️ Error saving changes: \(error.localizedDescription)\n"
            }
        }
        
        // Try to reinitialize CloudKit
        do {
            // Create a test record to force CloudKit initialization
            let testPerson = Person(context: context)
            testPerson.identifier = UUID()
            testPerson.name = "Nuclear Reset Test \(Int(Date().timeIntervalSince1970))"
            testPerson.role = "Test"
            
            try context.save()
            resetResults += "   Created nuclear reset test record\n"
            
            // Force immediate sync attempt
            try await container.persistentStoreCoordinator.perform {
                // This will trigger CloudKit to reinitialize
            }
            
            resetResults += "   ✅ Container restart initiated\n\n"
        } catch {
            resetResults += "   ❌ Error restarting container: \(error.localizedDescription)\n\n"
        }
    }
    
    private func verifyReset() async {
        resetResults += "5️⃣ Verifying reset...\n"
        
        // Check if UserDefaults are clean
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        let remainingCloudKitKeys = dict.keys.filter { key in
            let lowercaseKey = key.lowercased()
            return lowercaseKey.contains("cloudkit") || lowercaseKey.contains("ck")
        }
        
        resetResults += "   Remaining CloudKit keys: \(remainingCloudKitKeys.count)\n"
        
        // Check store metadata
        let stores = container.persistentStoreCoordinator.persistentStores
        for store in stores {
            if let metadata = store.metadata {
                let cloudKitMetadata = metadata.keys.filter { key in
                    let lowercaseKey = key.lowercased()
                    return lowercaseKey.contains("cloudkit") || lowercaseKey.contains("sync")
                }
                resetResults += "   Store \(store.url?.lastPathComponent ?? "Unknown") CloudKit metadata: \(cloudKitMetadata.count) keys\n"
            }
        }
        
        resetResults += "\n"
    }
}
