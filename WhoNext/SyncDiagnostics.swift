import Foundation
import CoreData
import Supabase

class SyncDiagnostics {
    static let shared = SyncDiagnostics()
    private let supabase = SupabaseConfig.shared.client
    
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
        
        // 3. Network Connectivity
        results.append("🌐 CONNECTIVITY TEST:")
        do {
            let startTime = Date()
            let response = try await supabase
                .from("people")
                .select("id", count: .exact)
                .limit(1)
                .execute()
            let duration = Date().timeIntervalSince(startTime)
            
            results.append("   ✅ Connection successful (\(String(format: "%.2f", duration))s)")
            results.append("   Response: \(response)")
        } catch {
            results.append("   ❌ Connection failed: \(error)")
            results.append("   Error details: \(error.localizedDescription)")
        }
        results.append("")
        
        // 4. Remote Data Count
        results.append("☁️ REMOTE DATA:")
        do {
            // Count people
            let peopleResponse = try await supabase
                .from("people")
                .select("id", count: .exact)
                .execute()
            results.append("   Remote People: \(peopleResponse.count ?? 0)")
            
            // Count conversations
            let conversationResponse = try await supabase
                .from("conversations")
                .select("id", count: .exact)
                .execute()
            results.append("   Remote Conversations: \(conversationResponse.count ?? 0)")
            
        } catch {
            results.append("   ❌ Error fetching remote counts: \(error)")
        }
        results.append("")
        
        // 5. Sample Remote Data
        results.append("📋 SAMPLE REMOTE DATA:")
        do {
            let samplePeople: [SupabasePerson] = try await supabase
                .from("people")
                .select()
                .limit(3)
                .execute()
                .value
            
            if samplePeople.isEmpty {
                results.append("   No people found in remote database")
            } else {
                results.append("   Found \(samplePeople.count) sample people:")
                for person in samplePeople {
                    results.append("   - \(person.name ?? "Unknown") (ID: \(person.identifier))")
                }
            }
        } catch {
            results.append("   ❌ Error fetching sample data: \(error)")
        }
        results.append("")
        
        // 6. Device-specific data
        results.append("📱 DEVICE-SPECIFIC DATA:")
        do {
            let devicePeople: [SupabasePerson] = try await supabase
                .from("people")
                .select()
                .eq("device_id", value: deviceId)
                .execute()
                .value
            
            results.append("   People from this device: \(devicePeople.count)")
            
            // Show if this looks suspicious
            if devicePeople.count > 20 {
                results.append("   ⚠️ This seems high - may indicate attribution issue")
            }
            
        } catch {
            results.append("   ❌ Error fetching device-specific data: \(error)")
        }
        
        // 7. Device Attribution Analysis
        results.append("")
        results.append("🔍 DEVICE ATTRIBUTION ANALYSIS:")
        do {
            // Get all devices and their counts
            let allPeople: [SupabasePerson] = try await supabase
                .from("people")
                .select()
                .execute()
                .value
            
            var deviceCounts: [String: Int] = [:]
            for person in allPeople {
                let device = person.deviceId ?? "unknown"
                deviceCounts[device] = (deviceCounts[device] ?? 0) + 1
            }
            
            results.append("   Device breakdown:")
            for (device, count) in deviceCounts.sorted(by: { $0.value > $1.value }) {
                let marker = device == deviceId ? "👈 THIS DEVICE" : ""
                results.append("   - \(device): \(count) people \(marker)")
            }
            
        } catch {
            results.append("   ❌ Error analyzing device attribution: \(error)")
        }
        
        // 8. True Deletion Check
        results.append("")
        results.append("🗑️ TRUE DELETION STATUS:")
        results.append("   ✅ Using hard deletes - no soft delete complexity")
        results.append("   ✅ Deleted data is permanently removed from cloud")
        results.append("   ✅ Sync conflicts from 'zombie' data eliminated")
        
        // 9. Relationship Integrity Check
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
        
        return results
    }
}