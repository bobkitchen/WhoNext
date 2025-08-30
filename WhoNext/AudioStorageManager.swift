import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import CoreData

/// Manages audio file storage, compression, and lifecycle for recorded meetings
class AudioStorageManager {
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let documentsURL: URL
    private let audioDirectory = "MeetingRecordings"
    private let compressionSettings: [String: Any]
    
    // MARK: - Initialization
    
    init() {
        // Get documents directory
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Set up compression settings for voice (32kbps mono)
        compressionSettings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000, // 16kHz for speech
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderBitRateKey: 32000, // 32kbps
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        // Create audio directory if needed
        createAudioDirectory()
        
        // Schedule daily cleanup
        scheduleDailyCleanup()
    }
    
    // MARK: - Public Methods
    
    /// Create a new audio file for recording
    func createAudioFile(for meetingID: UUID) throws -> URL {
        let fileName = "\(meetingID.uuidString).m4a"
        let fileURL = getAudioDirectory().appendingPathComponent(fileName)
        
        // Create parent directory if needed
        try fileManager.createDirectory(at: getAudioDirectory(), withIntermediateDirectories: true)
        
        return fileURL
    }
    
    /// Compress an audio file after recording
    func compressAudioFile(_ fileURL: URL) async throws -> URL {
        print("🗜️ Compressing audio file: \(fileURL.lastPathComponent)")
        
        let inputFile = try AVAudioFile(forReading: fileURL)
        let format = inputFile.processingFormat
        
        // Create compressed output file
        let compressedURL = fileURL.deletingPathExtension().appendingPathExtension("compressed.m4a")
        let outputFile = try AVAudioFile(
            forWriting: compressedURL,
            settings: compressionSettings
        )
        
        // Read and write in chunks to avoid memory issues
        let frameCount = AVAudioFrameCount(8192)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        
        while inputFile.framePosition < inputFile.length {
            let framesToRead = min(frameCount, AVAudioFrameCount(inputFile.length - inputFile.framePosition))
            buffer.frameLength = framesToRead
            
            try inputFile.read(into: buffer)
            try outputFile.write(from: buffer)
        }
        
        // Replace original with compressed version
        try fileManager.removeItem(at: fileURL)
        try fileManager.moveItem(at: compressedURL, to: fileURL)
        
        let originalSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
        let compressedSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
        let compressionRatio = Double(originalSize) / Double(compressedSize)
        
        print("✅ Compression complete: \(formatBytes(originalSize)) → \(formatBytes(compressedSize)) (ratio: \(String(format: "%.1fx", compressionRatio)))")
        
        return fileURL
    }
    
    /// Schedule automatic deletion for a meeting (default 30 days)
    func scheduleAutoDelete(for meetingID: UUID, afterDays days: Int = 30) {
        let deleteDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        
        // Store deletion date in user defaults
        var scheduledDeletions = UserDefaults.standard.dictionary(forKey: "ScheduledAudioDeletions") as? [String: Date] ?? [:]
        scheduledDeletions[meetingID.uuidString] = deleteDate
        UserDefaults.standard.set(scheduledDeletions, forKey: "ScheduledAudioDeletions")
        
        // Also update Core Data if meeting exists
        updateMeetingAudioExpiration(meetingID: meetingID, expirationDate: deleteDate)
        
        print("🗓️ Scheduled audio deletion for \(meetingID.uuidString) on \(deleteDate) (in \(days) days)")
        print("📝 Note: Transcript and summary will be preserved permanently")
    }
    
    /// Update Core Data with audio expiration date
    private func updateMeetingAudioExpiration(meetingID: UUID, expirationDate: Date) {
        let context = PersistenceController.shared.container.viewContext
        
        // Try to find GroupMeeting with this ID
        let fetchRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", meetingID as CVarArg)
        
        do {
            let meetings = try context.fetch(fetchRequest)
            if let meeting = meetings.first {
                meeting.scheduledDeletion = expirationDate
                try context.save()
                print("✅ Updated Core Data with audio expiration date")
            }
        } catch {
            print("⚠️ Could not update Core Data with expiration: \(error)")
        }
    }
    
    /// Delete expired audio files (but preserve transcripts and summaries)
    func deleteExpiredFiles() {
        print("🧹 Checking for expired audio files (transcripts will be preserved)...")
        
        var scheduledDeletions = UserDefaults.standard.dictionary(forKey: "ScheduledAudioDeletions") as? [String: Date] ?? [:]
        let now = Date()
        var deletedCount = 0
        
        for (meetingID, deleteDate) in scheduledDeletions {
            if deleteDate <= now {
                // Delete the audio file only
                let fileURL = getAudioDirectory().appendingPathComponent("\(meetingID).m4a")
                
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        deletedCount += 1
                        print("🗑️ Deleted expired audio file: \(meetingID)")
                        
                        // Update Core Data to clear audio path but keep all other data
                        clearAudioPathInCoreData(meetingID: meetingID)
                        
                    } catch {
                        print("❌ Failed to delete file: \(error)")
                    }
                }
                
                // Remove from scheduled deletions
                scheduledDeletions.removeValue(forKey: meetingID)
            }
        }
        
        // Update user defaults
        UserDefaults.standard.set(scheduledDeletions, forKey: "ScheduledAudioDeletions")
        
        if deletedCount > 0 {
            print("✅ Deleted \(deletedCount) expired audio files")
            print("📝 All transcripts, summaries, and action items have been preserved")
        }
    }
    
    /// Clear audio file path in Core Data when audio is deleted
    private func clearAudioPathInCoreData(meetingID: String) {
        guard let uuid = UUID(uuidString: meetingID) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<GroupMeeting>(entityName: "GroupMeeting")
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", uuid as CVarArg)
        
        do {
            let meetings = try context.fetch(fetchRequest)
            if let meeting = meetings.first {
                meeting.audioFilePath = nil
                meeting.scheduledDeletion = nil
                try context.save()
                print("✅ Cleared audio path in Core Data, preserved transcript and summary")
            }
        } catch {
            print("⚠️ Could not update Core Data: \(error)")
        }
    }
    
    /// Get storage usage for audio files
    func getStorageUsage() -> StorageReport {
        let audioDir = getAudioDirectory()
        var totalSize: Int64 = 0
        var fileCount = 0
        
        if let enumerator = fileManager.enumerator(at: audioDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                    fileCount += 1
                }
            }
        }
        
        return StorageReport(
            totalSize: totalSize,
            fileCount: fileCount,
            formattedSize: formatBytes(Int(totalSize))
        )
    }
    
    /// Estimate storage needed for a duration
    func estimateStorageNeeded(for duration: TimeInterval) -> Int64 {
        // At 32kbps: 32,000 bits/sec = 4,000 bytes/sec = ~14.4 MB/hour
        let bytesPerSecond: Int64 = 4000
        return Int64(duration) * bytesPerSecond
    }
    
    /// Export audio file to user-selected location
    func exportAudioFile(for meetingID: UUID) throws -> URL? {
        let fileURL = getAudioDirectory().appendingPathComponent("\(meetingID).m4a")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw StorageError.fileNotFound
        }
        
        // Show save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Audio]
        savePanel.nameFieldStringValue = "Meeting_\(meetingID.uuidString).m4a"
        
        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            return destinationURL
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    private func createAudioDirectory() {
        let audioDir = getAudioDirectory()
        
        if !fileManager.fileExists(atPath: audioDir.path) {
            do {
                try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
                print("📁 Created audio directory: \(audioDir.path)")
            } catch {
                print("❌ Failed to create audio directory: \(error)")
            }
        }
    }
    
    private func getAudioDirectory() -> URL {
        return documentsURL.appendingPathComponent(audioDirectory)
    }
    
    private func scheduleDailyCleanup() {
        // Schedule daily cleanup at 3 AM
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.performDailyCleanup()
        }
        
        // Also perform cleanup on init
        performDailyCleanup()
    }
    
    private func performDailyCleanup() {
        print("🧹 Performing daily cleanup...")
        
        // Delete expired files
        deleteExpiredFiles()
        
        // Clean up orphaned files (older than 30 days without scheduled deletion)
        cleanupOrphanedFiles()
        
        // Log storage usage
        let usage = getStorageUsage()
        print("💾 Storage usage: \(usage.formattedSize) across \(usage.fileCount) files")
    }
    
    private func cleanupOrphanedFiles() {
        let audioDir = getAudioDirectory()
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        if let enumerator = fileManager.enumerator(at: audioDir, includingPropertiesForKeys: [.creationDateKey]) {
            for case let fileURL as URL in enumerator {
                if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate {
                    if creationDate < thirtyDaysAgo {
                        // Check if this file has a scheduled deletion
                        let fileName = fileURL.deletingPathExtension().lastPathComponent
                        let scheduledDeletions = UserDefaults.standard.dictionary(forKey: "ScheduledAudioDeletions") as? [String: Date] ?? [:]
                        
                        if scheduledDeletions[fileName] == nil {
                            // Orphaned file - delete it
                            do {
                                try fileManager.removeItem(at: fileURL)
                                print("🗑️ Deleted orphaned file: \(fileName)")
                            } catch {
                                print("❌ Failed to delete orphaned file: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Storage Report

struct StorageReport {
    let totalSize: Int64
    let fileCount: Int
    let formattedSize: String
}

// MARK: - Storage Errors

enum StorageError: LocalizedError {
    case fileNotFound
    case compressionFailed
    case deletionFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .compressionFailed:
            return "Failed to compress audio file"
        case .deletionFailed:
            return "Failed to delete audio file"
        }
    }
}