import Foundation
import CloudKit
import SwiftUI

class CloudKitDirectTest: ObservableObject {
    @Published var testResults = ""
    
    func runDirectTest() {
        testResults = "🔬 Direct CloudKit Test\nStarted at: \(Date())\n\n"
        
        let container = CKContainer(identifier: "iCloud.com.bobk.whonext")
        
        // Test 1: Account Status
        testResults += "1️⃣ Testing Account Status...\n"
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.testResults += "❌ Account Error: \(error.localizedDescription)\n"
                } else {
                    let statusText = self?.statusDescription(status) ?? "Unknown"
                    self?.testResults += "✅ Account Status: \(statusText)\n"
                }
                
                // Test 2: User Record ID
                self?.testResults += "\n2️⃣ Testing User Record ID...\n"
                container.fetchUserRecordID { recordID, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.testResults += "❌ User Record Error: \(error.localizedDescription)\n"
                        } else if let recordID = recordID {
                            self?.testResults += "✅ User Record ID: \(recordID.recordName)\n"
                        }
                        
                        // Test 3: Database Zones
                        self?.testResults += "\n3️⃣ Testing Database Zones...\n"
                        let privateDB = container.privateCloudDatabase
                        privateDB.fetchAllRecordZones { zones, error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    self?.testResults += "❌ Zones Error: \(error.localizedDescription)\n"
                                } else if let zones = zones {
                                    self?.testResults += "✅ Found \(zones.count) zones:\n"
                                    for zone in zones {
                                        self?.testResults += "   • \(zone.zoneID.zoneName)\n"
                                    }
                                } else {
                                    self?.testResults += "⚠️ No zones found\n"
                                }
                                
                                // Test 4: Create a simple test record
                                self?.createTestRecord(in: privateDB)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func createTestRecord(in database: CKDatabase) {
        testResults += "\n4️⃣ Testing Record Creation...\n"
        
        let testRecord = CKRecord(recordType: "TestRecord")
        testRecord["testField"] = "Direct test at \(Date())"
        
        database.save(testRecord) { [weak self] record, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.testResults += "❌ Record Creation Error: \(error.localizedDescription)\n"
                    if let ckError = error as? CKError {
                        self?.testResults += "   CKError Code: \(ckError.code.rawValue)\n"
                        self?.testResults += "   Description: \(ckError.localizedDescription)\n"
                    }
                } else if let record = record {
                    self?.testResults += "✅ Test Record Created: \(record.recordID.recordName)\n"
                }
                
                self?.testResults += "\n🏁 Direct Test Complete\n"
            }
        }
    }
    
    private func statusDescription(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Available"
        case .noAccount:
            return "No Account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Could Not Determine"
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}
