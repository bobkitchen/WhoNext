import Foundation
import CloudKit
import CoreData
import SwiftUI

class CloudKitDiagnostics: ObservableObject {
    private let container: CKContainer
    private let database: CKDatabase
    @Published var diagnosticResults: String = ""
    
    init() {
        self.container = CKContainer(identifier: "iCloud.com.bobk.whonext")
        self.database = container.privateCloudDatabase
    }
    
    func runCompleteDiagnostics() {
        diagnosticResults = "🔍 Running Complete CloudKit Diagnostics...\n\n"
        
        // 1. Check account status
        checkAccountStatus { [weak self] in
            // 2. Check if we can create a test record
            self?.createTestRecord { 
                // 3. List all record types
                self?.listAllRecordTypes {
                    // 4. Check Core Data CloudKit metadata
                    self?.checkCoreDataMetadata()
                }
            }
        }
    }
    
    private func checkAccountStatus(completion: @escaping () -> Void) {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.diagnosticResults += "1️⃣ Account Status:\n"
                
                if let error = error {
                    self?.diagnosticResults += "   ❌ Error: \(error.localizedDescription)\n\n"
                } else {
                    switch status {
                    case .available:
                        self?.diagnosticResults += "   ✅ iCloud account available\n\n"
                    case .noAccount:
                        self?.diagnosticResults += "   ❌ No iCloud account signed in\n\n"
                    case .restricted:
                        self?.diagnosticResults += "   ⚠️ iCloud account restricted\n\n"
                    case .couldNotDetermine:
                        self?.diagnosticResults += "   ❓ Could not determine account status\n\n"
                    case .temporarilyUnavailable:
                        self?.diagnosticResults += "   ⏳ iCloud temporarily unavailable\n\n"
                    @unknown default:
                        self?.diagnosticResults += "   ❓ Unknown status\n\n"
                    }
                }
                completion()
            }
        }
    }
    
    private func createTestRecord(completion: @escaping () -> Void) {
        diagnosticResults += "2️⃣ Test Record Creation:\n"
        
        // Create a simple test record
        let testRecord = CKRecord(recordType: "TestRecord")
        testRecord["testField"] = "WhoNext Sync Test - \(Date())"
        
        database.save(testRecord) { [weak self] record, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.diagnosticResults += "   ❌ Failed to create test record: \(error.localizedDescription)\n"
                    if let ckError = error as? CKError {
                        self?.diagnosticResults += "   Error code: \(ckError.code.rawValue)\n"
                    }
                } else if let record = record {
                    self?.diagnosticResults += "   ✅ Test record created successfully\n"
                    self?.diagnosticResults += "   Record ID: \(record.recordID.recordName)\n"
                    
                    // Try to fetch it back
                    self?.database.fetch(withRecordID: record.recordID) { fetchedRecord, fetchError in
                        DispatchQueue.main.async {
                            if fetchError != nil {
                                self?.diagnosticResults += "   ❌ Could not fetch back test record\n\n"
                            } else {
                                self?.diagnosticResults += "   ✅ Test record fetched successfully\n\n"
                            }
                            
                            // Clean up
                            self?.database.delete(withRecordID: record.recordID) { _, _ in
                                completion()
                            }
                        }
                    }
                    return
                }
                self?.diagnosticResults += "\n"
                completion()
            }
        }
    }
    
    private func listAllRecordTypes(completion: @escaping () -> Void) {
        diagnosticResults += "3️⃣ Fetching Core Data CloudKit Records:\n"
        
        // First, let's check what zones exist
        database.fetchAllRecordZones { [weak self] zones, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.diagnosticResults += "   ❌ Failed to fetch zones: \(error.localizedDescription)\n"
                    completion()
                    return
                }
                
                guard let zones = zones else {
                    self.diagnosticResults += "   ❌ No zones found\n"
                    completion()
                    return
                }
                
                self.diagnosticResults += "   ✅ Found \(zones.count) zones:\n"
                for zone in zones {
                    self.diagnosticResults += "      • \(zone.zoneID.zoneName)\n"
                }
                
                // Look for the Core Data zone
                if let cdZone = zones.first(where: { $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone" }) {
                    self.diagnosticResults += "   ✅ Core Data CloudKit zone exists\n"
                    
                    // Try a different approach - fetch zone changes
                    self.fetchZoneChanges(zoneID: cdZone.zoneID, completion: completion)
                } else {
                    self.diagnosticResults += "   ⚠️ Core Data CloudKit zone not found\n"
                    self.diagnosticResults += "   💡 This means no data has been synced to CloudKit yet\n"
                    completion()
                }
            }
        }
    }
    
    private func fetchZoneChanges(zoneID: CKRecordZone.ID, completion: @escaping () -> Void) {
        diagnosticResults += "\n   Attempting to fetch recent changes:\n"
        
        // Use a simple query with modificationDate to avoid recordName issues
        let recordTypes = ["CD_Person", "CD_Conversation"]
        let group = DispatchGroup()
        var foundAnyRecords = false
        
        for recordType in recordTypes {
            group.enter()
            
            // Query by modification date instead of recordName
            let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
            let predicate = NSPredicate(format: "modificationDate > %@", oneYearAgo as NSDate)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = 5
            operation.zoneID = zoneID
            
            var recordCount = 0
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    recordCount += 1
                    foundAnyRecords = true
                    DispatchQueue.main.async { [weak self] in
                        if recordCount == 1 {
                            self?.diagnosticResults += "   ✅ Found \(recordType) records:\n"
                        }
                        let preview = self?.getRecordPreview(record: record, type: recordType) ?? "Unknown"
                        self?.diagnosticResults += "      • \(preview)\n"
                    }
                case .failure(let error):
                    if recordCount == 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.diagnosticResults += "   ❌ \(recordType) error: \(error.localizedDescription)\n"
                            if let ckError = error as? CKError {
                                self?.diagnosticResults += "      Error code: \(ckError.code.rawValue)\n"
                            }
                        }
                    }
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    if recordCount == 0 {
                        DispatchQueue.main.async { [weak self] in
                            self?.diagnosticResults += "   ℹ️ No \(recordType) records found (or query not supported)\n"
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        self?.diagnosticResults += "   ❌ Query failed for \(recordType): \(error.localizedDescription)\n"
                    }
                }
                group.leave()
            }
            
            database.add(operation)
        }
        
        group.notify(queue: .main) { [weak self] in
            if !foundAnyRecords {
                self?.diagnosticResults += "\n   ⚠️ Unable to query Core Data records in CloudKit\n"
                self?.diagnosticResults += "   💡 This is often due to CloudKit query restrictions\n"
                self?.diagnosticResults += "   💡 Your data may still be syncing correctly\n"
                self?.diagnosticResults += "   💡 Check the sync status and try creating a new record\n"
            }
            self?.diagnosticResults += "\n"
            completion()
        }
    }
    
    private func getRecordPreview(record: CKRecord, type: String) -> String {
        switch type {
        case "CD_Person":
            let name = record["CD_name"] as? String ?? "Unknown"
            return "Person: \(name)"
        case "CD_Conversation":
            let content = record["CD_content"] as? String ?? ""
            let preview = String(content.prefix(30)).replacingOccurrences(of: "\n", with: " ")
            return "Conversation: \(preview)..."
        default:
            return "Unknown record type"
        }
    }
    
    private func checkCoreDataMetadata() {
        diagnosticResults += "4️⃣ Core Data CloudKit Metadata:\n"
        
        // Get the persistent container from UserDefaults or a shared instance
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WhoNext")
            .appendingPathComponent("WhoNext.sqlite")
        
        if let storeURL = storeURL {
            diagnosticResults += "   Store URL: \(storeURL.path)\n"
            diagnosticResults += "   Store exists: \(FileManager.default.fileExists(atPath: storeURL.path))\n"
        } else {
            diagnosticResults += "   ❌ Could not determine store URL\n"
        }
        
        // Check CloudKit container identifier
        diagnosticResults += "   CloudKit container: \(container.containerIdentifier ?? "Unknown")\n"
        
        // Check if we're in the right iCloud account
        container.fetchUserRecordID { [weak self] recordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.diagnosticResults += "   ❌ User record error: \(error.localizedDescription)\n"
                } else if let recordID = recordID {
                    self?.diagnosticResults += "   ✅ User record ID: \(recordID.recordName)\n"
                }
                
                self?.diagnosticResults += "\n🏁 Diagnostics Complete\n"
            }
        }
    }
}
