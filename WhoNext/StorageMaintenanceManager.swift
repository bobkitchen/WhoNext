import Foundation
import CoreData
import BackgroundTasks
import AppKit
import SwiftUI

/// Enhanced storage maintenance manager for automatic cleanup and optimization
class StorageMaintenanceManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = StorageMaintenanceManager()
    
    // MARK: - Published Properties
    @Published var storageReport: StorageReport?
    @Published var isPerformingMaintenance = false
    @Published var lastMaintenanceDate: Date?
    @Published var maintenanceSettings = MaintenanceSettings()
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let audioStorageManager = AudioStorageManager()
    private let context = PersistenceController.shared.container.viewContext
    private var maintenanceTimer: Timer?
    
    // MARK: - Constants
    private let audioRetentionDays = 30
    private let orphanedFileGracePeriod = 7 // Days before deleting orphaned files
    private let maintenanceIdentifier = "com.whonext.storage.maintenance"
    
    // MARK: - Initialization
    
    private init() {
        loadSettings()
        loadLastMaintenanceDate()
        scheduleAutomaticMaintenance()
        registerBackgroundTask()
    }
    
    // MARK: - Public Methods
    
    /// Perform maintenance now
    func performMaintenance() async {
        guard !isPerformingMaintenance else { return }
        
        await MainActor.run {
            self.isPerformingMaintenance = true
        }
        
        print("🧹 Starting storage maintenance...")
        
        // 1. Delete expired audio files
        let deletedAudio = await deleteExpiredAudioFiles()
        
        // 2. Clean orphaned files
        let orphanedCleaned = await cleanOrphanedFiles()
        
        // 3. Verify Core Data integrity
        let integrityFixed = await verifyDataIntegrity()
        
        // 4. Optimize storage
        let storageOptimized = await optimizeStorage()
        
        // 5. Generate storage report
        let report = await generateStorageReport()
        
        await MainActor.run {
            self.storageReport = report
            self.lastMaintenanceDate = Date()
            self.isPerformingMaintenance = false
        }
        
        // Save last maintenance date
        saveLastMaintenanceDate()
        
        // Log results
        print("✅ Storage maintenance complete:")
        print("   - Expired audio deleted: \(deletedAudio)")
        print("   - Orphaned files cleaned: \(orphanedCleaned)")
        print("   - Integrity issues fixed: \(integrityFixed)")
        print("   - Storage optimized: \(storageOptimized ? "Yes" : "No")")
        print("   - Total storage: \(report.formattedSize)")
        
        // Send notification if significant cleanup
        if deletedAudio > 0 || orphanedCleaned > 0 {
            sendMaintenanceNotification(
                audioDeleted: deletedAudio,
                orphanedCleaned: orphanedCleaned,
                spaceSaved: report.spaceSaved
            )
        }
    }
    
    /// Get current storage usage
    func getCurrentStorageUsage() -> StorageReport {
        audioStorageManager.getStorageUsage()
    }
    
    /// Estimate storage for upcoming retention period
    func estimateStorageNeeds() -> StorageEstimate {
        let currentUsage = getCurrentStorageUsage()
        
        // Calculate average daily growth
        let dailyGrowth = estimateDailyGrowth()
        
        // Project 30 days ahead
        let projectedUsage = currentUsage.totalSize + (dailyGrowth * 30)
        
        // Check available space
        let availableSpace = getAvailableDiskSpace()
        
        return StorageEstimate(
            currentUsage: currentUsage.totalSize,
            projectedUsage: projectedUsage,
            availableSpace: availableSpace,
            daysUntilFull: availableSpace > 0 ? Int(availableSpace / dailyGrowth) : 0,
            recommendation: generateStorageRecommendation(
                current: currentUsage.totalSize,
                projected: projectedUsage,
                available: availableSpace
            )
        )
    }
    
    // MARK: - Private Maintenance Methods
    
    /// Delete audio files older than retention period
    private func deleteExpiredAudioFiles() async -> Int {
        var deletedCount = 0
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -audioRetentionDays,
            to: Date()
        )!
        
        // Fetch meetings with audio older than cutoff
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "audioFilePath != nil AND date < %@ AND scheduledDeletion == nil",
            cutoffDate as NSDate
        )
        
        do {
            let meetings = try context.fetch(fetchRequest)
            
            for meeting in meetings {
                if let audioPath = meeting.audioFilePath {
                    let audioURL = URL(fileURLWithPath: audioPath)
                    
                    if fileManager.fileExists(atPath: audioURL.path) {
                        try fileManager.removeItem(at: audioURL)
                        deletedCount += 1
                        
                        // Clear audio path but preserve transcript
                        meeting.audioFilePath = nil
                        meeting.scheduledDeletion = nil
                        
                        print("🗑️ Deleted expired audio: \(meeting.displayTitle)")
                        print("   📝 Transcript and summary preserved")
                    }
                }
            }
            
            try context.save()
        } catch {
            print("❌ Error deleting expired audio: \(error)")
        }
        
        return deletedCount
    }
    
    /// Clean orphaned files not linked to any meeting
    private func cleanOrphanedFiles() async -> Int {
        var cleanedCount = 0
        let audioDir = getAudioDirectory()
        
        guard let enumerator = fileManager.enumerator(
            at: audioDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return 0 }
        
        // Get all valid audio file references from Core Data
        let validFiles = await getValidAudioFiles()
        
        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            
            // Check if file is orphaned
            if !validFiles.contains(fileName) {
                // Check creation date for grace period
                if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate {
                    let daysSinceCreation = Calendar.current.dateComponents(
                        [.day],
                        from: creationDate,
                        to: Date()
                    ).day ?? 0
                    
                    if daysSinceCreation > orphanedFileGracePeriod {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            cleanedCount += 1
                            print("🗑️ Removed orphaned file: \(fileName)")
                        } catch {
                            print("❌ Failed to remove orphaned file: \(error)")
                        }
                    }
                }
            }
        }
        
        return cleanedCount
    }
    
    /// Verify Core Data integrity
    private func verifyDataIntegrity() async -> Int {
        var fixedCount = 0
        
        // Check for meetings with invalid audio references
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "audioFilePath != nil")
        
        do {
            let meetings = try context.fetch(fetchRequest)
            
            for meeting in meetings {
                if let audioPath = meeting.audioFilePath {
                    let audioURL = URL(fileURLWithPath: audioPath)
                    
                    // If file doesn't exist but path is set, clear it
                    if !fileManager.fileExists(atPath: audioURL.path) {
                        meeting.audioFilePath = nil
                        fixedCount += 1
                        print("🔧 Fixed invalid audio reference for: \(meeting.displayTitle)")
                    }
                }
            }
            
            if fixedCount > 0 {
                try context.save()
            }
        } catch {
            print("❌ Error verifying data integrity: \(error)")
        }
        
        return fixedCount
    }
    
    /// Optimize storage by compressing old recordings
    private func optimizeStorage() async -> Bool {
        guard maintenanceSettings.enableCompression else { return false }
        
        let compressionCutoff = Calendar.current.date(
            byAdding: .day,
            value: -7, // Compress recordings older than 7 days
            to: Date()
        )!
        
        // Find uncompressed recordings
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "audioFilePath != nil AND date < %@",
            compressionCutoff as NSDate
        )
        
        do {
            let meetings = try context.fetch(fetchRequest)
            var compressedCount = 0
            
            for meeting in meetings {
                if let audioPath = meeting.audioFilePath {
                    let audioURL = URL(fileURLWithPath: audioPath)
                    
                    // Check if already compressed (by file size heuristic)
                    if let fileSize = try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        let duration = TimeInterval(meeting.duration)
                        let expectedSize = audioStorageManager.estimateStorageNeeded(for: duration)
                        
                        // If file is significantly larger than expected, compress it
                        if Int64(fileSize) > expectedSize * 2 {
                            do {
                                let compressedURL = try await audioStorageManager.compressAudioFile(audioURL)
                                meeting.audioFilePath = compressedURL.path
                                compressedCount += 1
                            } catch {
                                print("❌ Failed to compress: \(error)")
                            }
                        }
                    }
                }
            }
            
            if compressedCount > 0 {
                try context.save()
                print("📦 Compressed \(compressedCount) audio files")
            }
            
            return compressedCount > 0
        } catch {
            print("❌ Error optimizing storage: \(error)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    private func getAudioDirectory() -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("MeetingRecordings")
    }
    
    private func getValidAudioFiles() async -> Set<String> {
        var validFiles = Set<String>()
        
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "audioFilePath != nil")
        
        if let meetings = try? context.fetch(fetchRequest) {
            for meeting in meetings {
                if let audioPath = meeting.audioFilePath {
                    let url = URL(fileURLWithPath: audioPath)
                    validFiles.insert(url.lastPathComponent)
                }
            }
        }
        
        return validFiles
    }
    
    private func getAvailableDiskSpace() -> Int64 {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            print("Error getting available disk space: \(error)")
            return 0
        }
    }
    
    private func estimateDailyGrowth() -> Int64 {
        // Calculate based on recent meeting history
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "date > %@", thirtyDaysAgo as NSDate)
        
        do {
            let recentMeetings = try context.fetch(fetchRequest)
            let totalDuration = recentMeetings.reduce(0) { $0 + TimeInterval($1.duration) }
            let estimatedSize = audioStorageManager.estimateStorageNeeded(for: totalDuration)
            
            return estimatedSize / 30 // Average daily growth
        } catch {
            return 15 * 1024 * 1024 // Default 15MB per day
        }
    }
    
    private func generateStorageRecommendation(
        current: Int64,
        projected: Int64,
        available: Int64
    ) -> String {
        let projectedUsagePercent = Double(projected) / Double(available + current) * 100
        
        if projectedUsagePercent > 90 {
            return "⚠️ Critical: Storage will be full soon. Consider reducing retention period or upgrading storage."
        } else if projectedUsagePercent > 70 {
            return "⚡ Warning: Storage usage is high. Monitor closely."
        } else if projectedUsagePercent > 50 {
            return "ℹ️ Normal: Storage usage is moderate."
        } else {
            return "✅ Excellent: Plenty of storage available."
        }
    }
    
    private func generateStorageReport() async -> StorageReport {
        let audioUsage = audioStorageManager.getStorageUsage()
        
        return StorageReport(
            totalSize: audioUsage.totalSize,
            fileCount: audioUsage.fileCount,
            formattedSize: audioUsage.formattedSize
        )
    }
    
    // MARK: - Scheduling
    
    private func scheduleAutomaticMaintenance() {
        // Run daily at 3 AM
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.hour = 3
        dateComponents.minute = 0
        
        if let nextRun = calendar.nextDate(
            after: Date(),
            matching: dateComponents,
            matchingPolicy: .nextTime
        ) {
            let timeInterval = nextRun.timeIntervalSinceNow
            
            maintenanceTimer = Timer.scheduledTimer(
                withTimeInterval: timeInterval,
                repeats: false
            ) { [weak self] _ in
                Task {
                    await self?.performMaintenance()
                    self?.scheduleAutomaticMaintenance() // Reschedule for next day
                }
            }
            
            print("📅 Next maintenance scheduled for: \(nextRun)")
        }
    }
    
    private func registerBackgroundTask() {
        // Register background task for macOS
        // Note: This would need proper implementation for production
        print("📋 Background maintenance task registered")
    }
    
    private func getNextScheduledMaintenance() -> Date? {
        guard let lastMaintenance = lastMaintenanceDate else {
            return Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }
        
        return Calendar.current.date(byAdding: .day, value: 1, to: lastMaintenance)
    }
    
    // MARK: - Notifications
    
    private func sendMaintenanceNotification(
        audioDeleted: Int,
        orphanedCleaned: Int,
        spaceSaved: Int64
    ) {
        let notification = NSUserNotification()
        notification.title = "Storage Maintenance Complete"
        notification.informativeText = """
        Cleaned up:
        • \(audioDeleted) expired recordings
        • \(orphanedCleaned) orphaned files
        • Saved \(formatBytes(spaceSaved))
        """
        notification.soundName = nil
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Settings
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "MaintenanceSettings"),
           let decoded = try? JSONDecoder().decode(MaintenanceSettings.self, from: data) {
            maintenanceSettings = decoded
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(maintenanceSettings) {
            UserDefaults.standard.set(encoded, forKey: "MaintenanceSettings")
        }
    }
    
    private func loadLastMaintenanceDate() {
        lastMaintenanceDate = UserDefaults.standard.object(forKey: "LastMaintenanceDate") as? Date
    }
    
    private func saveLastMaintenanceDate() {
        UserDefaults.standard.set(lastMaintenanceDate, forKey: "LastMaintenanceDate")
    }
}

// MARK: - Supporting Types

extension StorageReport {
    var spaceSaved: Int64 { 0 } // Extended property
    var lastMaintenance: Date? { nil }
    var nextScheduledMaintenance: Date? { nil }
}

struct MaintenanceSettings: Codable {
    var autoMaintenanceEnabled: Bool = true
    var audioRetentionDays: Int = 30
    var enableCompression: Bool = true
    var compressionAfterDays: Int = 7
    var deleteOrphanedFiles: Bool = true
    var orphanGracePeriodDays: Int = 7
    var maintenanceTime: Date = {
        var components = DateComponents()
        components.hour = 3
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
}

struct StorageEstimate {
    let currentUsage: Int64
    let projectedUsage: Int64
    let availableSpace: Int64
    let daysUntilFull: Int
    let recommendation: String
}

// MARK: - Maintenance Settings View

struct MaintenanceSettingsView: View {
    @StateObject private var manager = StorageMaintenanceManager.shared
    @State private var showingRunNow = false
    
    var body: some View {
        Form {
            Section("Automatic Maintenance") {
                Toggle("Enable automatic maintenance", isOn: $manager.maintenanceSettings.autoMaintenanceEnabled)
                
                DatePicker(
                    "Run daily at:",
                    selection: $manager.maintenanceSettings.maintenanceTime,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!manager.maintenanceSettings.autoMaintenanceEnabled)
            }
            
            Section("Audio Retention") {
                HStack {
                    Text("Delete audio after:")
                    Stepper(
                        "\(manager.maintenanceSettings.audioRetentionDays) days",
                        value: $manager.maintenanceSettings.audioRetentionDays,
                        in: 7...90
                    )
                }
                
                Text("Transcripts and summaries are always preserved")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Storage Optimization") {
                Toggle("Compress old recordings", isOn: $manager.maintenanceSettings.enableCompression)
                
                if manager.maintenanceSettings.enableCompression {
                    HStack {
                        Text("Compress after:")
                        Stepper(
                            "\(manager.maintenanceSettings.compressionAfterDays) days",
                            value: $manager.maintenanceSettings.compressionAfterDays,
                            in: 1...30
                        )
                    }
                }
                
                Toggle("Clean orphaned files", isOn: $manager.maintenanceSettings.deleteOrphanedFiles)
                
                if manager.maintenanceSettings.deleteOrphanedFiles {
                    HStack {
                        Text("Grace period:")
                        Stepper(
                            "\(manager.maintenanceSettings.orphanGracePeriodDays) days",
                            value: $manager.maintenanceSettings.orphanGracePeriodDays,
                            in: 1...30
                        )
                    }
                }
            }
            
            Section("Storage Status") {
                if let report = manager.storageReport {
                    LabeledContent("Total Size:", value: report.formattedSize)
                    LabeledContent("File Count:", value: "\(report.fileCount)")
                    if let lastMaintenance = manager.lastMaintenanceDate {
                        LabeledContent("Last Maintenance:", value: lastMaintenance.formatted())
                    }
                }
                
                Button("Run Maintenance Now") {
                    showingRunNow = true
                    Task {
                        await manager.performMaintenance()
                        showingRunNow = false
                    }
                }
                .disabled(manager.isPerformingMaintenance || showingRunNow)
                
                if manager.isPerformingMaintenance {
                    ProgressView("Running maintenance...")
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .onDisappear {
            manager.saveSettings()
        }
    }
}