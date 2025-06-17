import Foundation
import CoreData
import Supabase

// MARK: - Sync Configuration
struct SyncConfig {
    static let batchSize = 50
    static let maxRetries = 3
    static let syncTimeout: TimeInterval = 120
    static let minSyncInterval: TimeInterval = 30
    
    // Network resilience configuration
    static let baseRetryDelay: TimeInterval = 1.0
    static let maxRetryDelay: TimeInterval = 32.0
    static let connectionPoolSize = 5
    static let requestTimeout: TimeInterval = 30.0
    
    // Real-time sync configuration
    static let realtimeReconnectDelay: TimeInterval = 5.0
    static let maxRealtimeReconnectAttempts = 10
}

// MARK: - Sync Result Types
enum SyncResult {
    case success(SyncStats)
    case failure(SyncError)
    case partial(SyncStats, [SyncError])
}

// MARK: - Conflict Resolution
enum ConflictResolutionStrategy {
    case localWins        // Local changes take precedence
    case remoteWins       // Remote changes take precedence  
    case mergeChanges     // Attempt to merge non-conflicting fields
    case mostRecent       // Use most recently modified version
}

struct SyncConflict {
    let entityType: String
    let entityId: String
    let localVersion: Any?
    let remoteVersion: Any?
    let conflictingFields: [String]
    let localModifiedAt: Date?
    let remoteModifiedAt: Date?
}

struct SyncStats {
    let peopleInserted: Int
    let peopleUpdated: Int
    let peopleDeleted: Int
    let conversationsInserted: Int
    let conversationsUpdated: Int
    let conversationsDeleted: Int
    let startTime: Date
    let endTime: Date
    
    // Performance metrics
    let networkLatency: TimeInterval
    let databaseSaveTime: TimeInterval
    let conflictsDetected: Int
    let conflictsResolved: Int
    let bytesTransferred: Int64
    let retryAttempts: Int
    
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    var totalOperations: Int { 
        peopleInserted + peopleUpdated + peopleDeleted + 
        conversationsInserted + conversationsUpdated + conversationsDeleted 
    }
    var operationsPerSecond: Double {
        duration > 0 ? Double(totalOperations) / duration : 0
    }
    var averageLatency: TimeInterval {
        totalOperations > 0 ? networkLatency / Double(totalOperations) : 0
    }
}

enum SyncError: Error, LocalizedError {
    case networkUnavailable
    case authenticationFailed
    case dataValidationFailed(String)
    case databaseError(String)
    case contextSaveFailed(String)
    case relationshipIntegrityViolation(String)
    case concurrentModification
    case timeout
    case rateLimited
    case serverError(Int)
    case connectionPoolExhausted
    case retryExhausted
    case realtimeConnectionFailed
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "Network connection unavailable"
        case .authenticationFailed: return "Authentication failed"
        case .dataValidationFailed(let msg): return "Data validation failed: \(msg)"
        case .databaseError(let msg): return "Database error: \(msg)"
        case .contextSaveFailed(let msg): return "Failed to save changes: \(msg)"
        case .relationshipIntegrityViolation(let msg): return "Relationship integrity violation: \(msg)"
        case .concurrentModification: return "Concurrent modification detected"
        case .timeout: return "Sync operation timed out"
        case .rateLimited: return "Rate limit exceeded"
        case .serverError(let code): return "Server error: HTTP \(code)"
        case .connectionPoolExhausted: return "Connection pool exhausted"
        case .retryExhausted: return "Maximum retry attempts exceeded"
        case .realtimeConnectionFailed: return "Real-time connection failed"
        case .unknown(let error): return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Thread-Safe Sync Manager
@MainActor
class RobustSyncManager: ObservableObject {
    static let shared = RobustSyncManager()
    
    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var syncStatus = "Ready"
    @Published var syncProgress: Double = 0.0
    @Published var lastSyncResult: SyncResult?
    @Published var lastSuccessfulSync: Date?
    
    // MARK: - Private Properties
    private let supabase = SupabaseConfig.shared.client
    private let deviceId: String
    private let dateFormatter: ISO8601DateFormatter
    private let operationQueue = OperationQueue()
    
    // Real-time sync properties (temporarily disabled for compatibility)
    private var peopleChannel: RealtimeChannel?
    private var conversationsChannel: RealtimeChannel?
    private var isRealtimeEnabled = false
    
    // Conflict resolution
    private var conflictResolutionStrategy: ConflictResolutionStrategy = .mostRecent
    private var detectedConflicts: [SyncConflict] = []
    
    // Performance metrics tracking
    private var currentSyncNetworkLatency: TimeInterval = 0
    private var currentSyncDatabaseTime: TimeInterval = 0
    private var currentSyncBytesTransferred: Int64 = 0
    private var currentSyncRetryAttempts: Int = 0
    private var networkOperationCount: Int = 0
    
    // Sync timestamps with atomic access
    private let userDefaults = UserDefaults.standard
    private var lastPeopleSync: Date {
        get { userDefaults.object(forKey: "robust_lastPeopleSync") as? Date ?? Date.distantPast }
        set { userDefaults.set(newValue, forKey: "robust_lastPeopleSync") }
    }
    
    private var lastConversationsSync: Date {
        get { userDefaults.object(forKey: "robust_lastConversationsSync") as? Date ?? Date.distantPast }
        set { userDefaults.set(newValue, forKey: "robust_lastConversationsSync") }
    }
    
    private init() {
        // Generate stable device ID
        #if os(macOS)
        self.deviceId = Self.generateStableDeviceId()
        #else
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? Self.generateStableDeviceId()
        #endif
        
        // Configure shared date formatter
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Force UTC
        
        // Configure operation queue
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInitiated
        
        // Initialize real-time sync (temporarily disabled for compatibility)
        // Task {
        //     await initializeRealtimeSync()
        // }
    }
    
    private static func generateStableDeviceId() -> String {
        let key = "stable_device_id"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    // MARK: - Real-time Sync Implementation (temporarily disabled for compatibility)
    private func initializeRealtimeSync() async {
        // Temporarily disabled for Supabase API compatibility
        isRealtimeEnabled = false
        await updateSyncStatus("Real-time sync disabled (compatibility mode)")
    }
    
    /*
    private func setupPeopleRealtimeSync() async {
        // Temporarily disabled for Supabase API compatibility
    }
    */
    
    /*
    private func setupConversationsRealtimeSync() async {
        // Temporarily disabled for Supabase API compatibility
    }
    */
    
    /*
    // MARK: - Real-time Event Handlers (temporarily disabled for compatibility)
    private func handleRealtimePeopleInsert(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func handleRealtimePeopleUpdate(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func handleRealtimePeopleDelete(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func handleRealtimeConversationInsert(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func handleRealtimeConversationUpdate(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func handleRealtimeConversationDelete(_ payload: RealtimeMessage) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    // MARK: - Real-time Processing (temporarily disabled for compatibility)
    private func processRealtimePersonChange(_ remotePerson: SupabasePerson, operation: SyncOperation) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func processRealtimePersonDeletion(_ identifier: String) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func processRealtimeConversationChange(_ remoteConversation: SupabaseConversation, operation: SyncOperation) async {
        // Temporarily disabled for Supabase API compatibility
    }
    
    private func processRealtimeConversationDeletion(_ uuid: String) async {
        // Temporarily disabled for Supabase API compatibility
    }
    */
    
    private func updateSyncStatus(_ status: String) async {
        await MainActor.run {
            self.syncStatus = status
        }
    }
    
    // MARK: - Performance Metrics Tracking
    private func createEmptyStats() -> SyncStats {
        return SyncStats(
            peopleInserted: 0, peopleUpdated: 0, peopleDeleted: 0,
            conversationsInserted: 0, conversationsUpdated: 0, conversationsDeleted: 0,
            startTime: Date(), endTime: Date(),
            networkLatency: 0, databaseSaveTime: 0,
            conflictsDetected: 0, conflictsResolved: 0,
            bytesTransferred: 0, retryAttempts: 0
        )
    }
    
    private func incrementPeopleStats(_ stats: SyncStats, operation: SyncOperation) -> SyncStats {
        switch operation {
        case .inserted:
            return SyncStats(
                peopleInserted: stats.peopleInserted + 1, peopleUpdated: stats.peopleUpdated, peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted, conversationsUpdated: stats.conversationsUpdated, conversationsDeleted: stats.conversationsDeleted,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        case .updated:
            return SyncStats(
                peopleInserted: stats.peopleInserted, peopleUpdated: stats.peopleUpdated + 1, peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted, conversationsUpdated: stats.conversationsUpdated, conversationsDeleted: stats.conversationsDeleted,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        case .deleted:
            return SyncStats(
                peopleInserted: stats.peopleInserted, peopleUpdated: stats.peopleUpdated, peopleDeleted: stats.peopleDeleted + 1,
                conversationsInserted: stats.conversationsInserted, conversationsUpdated: stats.conversationsUpdated, conversationsDeleted: stats.conversationsDeleted,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        }
    }
    
    private func incrementConversationStats(_ stats: SyncStats, operation: SyncOperation) -> SyncStats {
        switch operation {
        case .inserted:
            return SyncStats(
                peopleInserted: stats.peopleInserted, peopleUpdated: stats.peopleUpdated, peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted + 1, conversationsUpdated: stats.conversationsUpdated, conversationsDeleted: stats.conversationsDeleted,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        case .updated:
            return SyncStats(
                peopleInserted: stats.peopleInserted, peopleUpdated: stats.peopleUpdated, peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted, conversationsUpdated: stats.conversationsUpdated + 1, conversationsDeleted: stats.conversationsDeleted,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        case .deleted:
            return SyncStats(
                peopleInserted: stats.peopleInserted, peopleUpdated: stats.peopleUpdated, peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted, conversationsUpdated: stats.conversationsUpdated, conversationsDeleted: stats.conversationsDeleted + 1,
                startTime: stats.startTime, endTime: stats.endTime,
                networkLatency: stats.networkLatency, databaseSaveTime: stats.databaseSaveTime,
                conflictsDetected: stats.conflictsDetected, conflictsResolved: stats.conflictsResolved,
                bytesTransferred: stats.bytesTransferred, retryAttempts: stats.retryAttempts
            )
        }
    }
    
    private func resetPerformanceMetrics() {
        currentSyncNetworkLatency = 0
        currentSyncDatabaseTime = 0
        currentSyncBytesTransferred = 0
        currentSyncRetryAttempts = 0
        networkOperationCount = 0
    }
    
    private func trackNetworkOperation<T>(operation: () async throws -> T) async throws -> T {
        let startTime = Date()
        networkOperationCount += 1
        
        do {
            let result = try await operation()
            let latency = Date().timeIntervalSince(startTime)
            currentSyncNetworkLatency += latency
            
            // Estimate bytes transferred (simplified)
            currentSyncBytesTransferred += 1024 // Base estimate per operation
            
            return result
        } catch {
            let latency = Date().timeIntervalSince(startTime)
            currentSyncNetworkLatency += latency
            throw error
        }
    }
    
    private func trackDatabaseOperation<T>(operation: () throws -> T) throws -> T {
        let startTime = Date()
        let result = try operation()
        let saveTime = Date().timeIntervalSince(startTime)
        currentSyncDatabaseTime += saveTime
        return result
    }
    
    // MARK: - Conflict Detection and Resolution
    private func detectPersonConflict(
        local: Person,
        remote: SupabasePerson
    ) -> SyncConflict? {
        var conflictingFields: [String] = []
        
        let localModified = local.modifiedAt ?? local.createdAt ?? Date.distantPast
        let remoteModified = dateFormatter.date(from: remote.updatedAt ?? remote.createdAt ?? "") ?? Date.distantPast
        
        // Only check for conflicts if both versions have been modified recently
        if abs(localModified.timeIntervalSince(remoteModified)) < 5.0 { // Within 5 seconds
            return nil // Too close to be a real conflict
        }
        
        // Check individual fields for conflicts
        if local.name != remote.name && local.name != nil && remote.name != nil {
            conflictingFields.append("name")
        }
        
        if local.role != remote.role && local.role != nil && remote.role != nil {
            conflictingFields.append("role")
        }
        
        if local.notes != remote.notes && local.notes != nil && remote.notes != nil {
            conflictingFields.append("notes")
        }
        
        if local.timezone != remote.timezone && local.timezone != nil && remote.timezone != nil {
            conflictingFields.append("timezone")
        }
        
        if local.isDirectReport != (remote.isDirectReport ?? false) {
            conflictingFields.append("isDirectReport")
        }
        
        // Check photo conflicts (simplified - just check if both exist and are different)
        if local.photo != nil && remote.photoBase64 != nil && local.photo?.base64EncodedString() != remote.photoBase64 {
            conflictingFields.append("photo")
        }
        
        if !conflictingFields.isEmpty {
            return SyncConflict(
                entityType: "Person",
                entityId: local.identifier?.uuidString ?? "",
                localVersion: local,
                remoteVersion: remote,
                conflictingFields: conflictingFields,
                localModifiedAt: localModified,
                remoteModifiedAt: remoteModified
            )
        }
        
        return nil
    }
    
    private func detectConversationConflict(
        local: Conversation,
        remote: SupabaseConversation
    ) -> SyncConflict? {
        var conflictingFields: [String] = []
        
        let localModified = local.modifiedAt ?? local.createdAt ?? Date.distantPast
        let remoteModified = dateFormatter.date(from: remote.updatedAt ?? remote.createdAt ?? "") ?? Date.distantPast
        
        // Only check for conflicts if both versions have been modified recently
        if abs(localModified.timeIntervalSince(remoteModified)) < 5.0 { // Within 5 seconds
            return nil // Too close to be a real conflict
        }
        
        // Check individual fields for conflicts
        if local.notes != remote.notes && local.notes != nil && remote.notes != nil {
            conflictingFields.append("notes")
        }
        
        if local.summary != remote.summary && local.summary != nil && remote.summary != nil {
            conflictingFields.append("summary")
        }
        
        if local.engagementLevel != remote.engagementLevel && local.engagementLevel != nil && remote.engagementLevel != nil {
            conflictingFields.append("engagementLevel")
        }
        
        if local.duration != Int32(remote.duration ?? 0) && remote.duration != nil {
            conflictingFields.append("duration")
        }
        
        if local.qualityScore != remote.qualityScore {
            conflictingFields.append("qualityScore")
        }
        
        if local.sentimentScore != remote.sentimentScore {
            conflictingFields.append("sentimentScore")
        }
        
        if local.sentimentLabel != remote.sentimentLabel && local.sentimentLabel != nil && remote.sentimentLabel != nil {
            conflictingFields.append("sentimentLabel")
        }
        
        if !conflictingFields.isEmpty {
            return SyncConflict(
                entityType: "Conversation",
                entityId: local.uuid?.uuidString ?? "",
                localVersion: local,
                remoteVersion: remote,
                conflictingFields: conflictingFields,
                localModifiedAt: localModified,
                remoteModifiedAt: remoteModified
            )
        }
        
        return nil
    }
    
    private func resolveConflict(_ conflict: SyncConflict, context: NSManagedObjectContext) async throws {
        switch conflictResolutionStrategy {
        case .localWins:
            // Keep local version, don't update from remote
            print("🔄 Conflict resolved: Local wins for \(conflict.entityType) \(conflict.entityId)")
            
        case .remoteWins:
            // Use remote version, overwrite local
            if conflict.entityType == "Person", let remotePerson = conflict.remoteVersion as? SupabasePerson {
                try await forceUpdatePerson(remotePerson, context: context)
            } else if conflict.entityType == "Conversation", let remoteConversation = conflict.remoteVersion as? SupabaseConversation {
                try await forceUpdateConversation(remoteConversation, context: context)
            }
            print("🔄 Conflict resolved: Remote wins for \(conflict.entityType) \(conflict.entityId)")
            
        case .mostRecent:
            // Use the most recently modified version
            let localIsNewer = (conflict.localModifiedAt ?? Date.distantPast) > (conflict.remoteModifiedAt ?? Date.distantPast)
            if localIsNewer {
                print("🔄 Conflict resolved: Local is newer for \(conflict.entityType) \(conflict.entityId)")
            } else {
                if conflict.entityType == "Person", let remotePerson = conflict.remoteVersion as? SupabasePerson {
                    try await forceUpdatePerson(remotePerson, context: context)
                } else if conflict.entityType == "Conversation", let remoteConversation = conflict.remoteVersion as? SupabaseConversation {
                    try await forceUpdateConversation(remoteConversation, context: context)
                }
                print("🔄 Conflict resolved: Remote is newer for \(conflict.entityType) \(conflict.entityId)")
            }
            
        case .mergeChanges:
            // Attempt to merge non-conflicting fields (advanced implementation)
            try await attemptMerge(conflict, context: context)
            print("🔄 Conflict resolved: Merged changes for \(conflict.entityType) \(conflict.entityId)")
        }
    }
    
    private func forceUpdatePerson(_ remotePerson: SupabasePerson, context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "identifier == %@", remotePerson.identifier as CVarArg)
        
        if let person = try context.fetch(request).first {
            // Force update all fields from remote
            person.name = remotePerson.name
            person.role = remotePerson.role
            person.notes = remotePerson.notes
            person.isDirectReport = remotePerson.isDirectReport ?? false
            person.timezone = remotePerson.timezone
            
            if let photoBase64 = remotePerson.photoBase64, !photoBase64.isEmpty {
                person.photo = Data(base64Encoded: photoBase64)
            }
            
            if let dateString = remotePerson.scheduledConversationDate {
                person.scheduledConversationDate = dateFormatter.date(from: dateString)
            }
            
            if let updatedAtString = remotePerson.updatedAt {
                person.modifiedAt = dateFormatter.date(from: updatedAtString)
            }
        }
    }
    
    private func forceUpdateConversation(_ remoteConversation: SupabaseConversation, context: NSManagedObjectContext) async throws {
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.predicate = NSPredicate(format: "uuid == %@", remoteConversation.uuid as CVarArg)
        
        if let conversation = try context.fetch(request).first {
            // Force update all fields from remote
            conversation.notes = remoteConversation.notes
            conversation.summary = remoteConversation.summary
            conversation.duration = Int32(remoteConversation.duration ?? 0)
            conversation.engagementLevel = remoteConversation.engagementLevel
            conversation.qualityScore = remoteConversation.qualityScore
            conversation.sentimentScore = remoteConversation.sentimentScore
            conversation.sentimentLabel = remoteConversation.sentimentLabel
            
            if let dateString = remoteConversation.date {
                conversation.date = dateFormatter.date(from: dateString)
            }
            
            if let updatedAtString = remoteConversation.updatedAt {
                conversation.modifiedAt = dateFormatter.date(from: updatedAtString)
            }
        }
    }
    
    private func attemptMerge(_ conflict: SyncConflict, context: NSManagedObjectContext) async throws {
        // Advanced merge logic - for now, fallback to mostRecent strategy
        // In a full implementation, this would intelligently merge non-conflicting fields
        let localIsNewer = (conflict.localModifiedAt ?? Date.distantPast) > (conflict.remoteModifiedAt ?? Date.distantPast)
        if !localIsNewer {
            if conflict.entityType == "Person", let remotePerson = conflict.remoteVersion as? SupabasePerson {
                try await forceUpdatePerson(remotePerson, context: context)
            } else if conflict.entityType == "Conversation", let remoteConversation = conflict.remoteVersion as? SupabaseConversation {
                try await forceUpdateConversation(remoteConversation, context: context)
            }
        }
    }
    
    // MARK: - Public API
    func performSync() async -> SyncResult {
        // Prevent concurrent syncs
        guard !isSyncing else {
            return .failure(.concurrentModification)
        }
        
        // Start sync task
        return await withTaskCancellation { [self] in
            self.isSyncing = true
            self.syncStatus = "Initializing sync..."
            self.syncProgress = 0.0
            
            let result = await self.performSyncInternal()
            
            self.isSyncing = false
            self.syncProgress = 1.0
            self.lastSyncResult = result
            
            switch result {
            case .success:
                self.lastSuccessfulSync = Date()
                self.syncStatus = "Sync completed successfully"
            case .failure(let error):
                self.syncStatus = "Sync failed: \(error.errorDescription ?? "Unknown error")"
            case .partial(let stats, let errors):
                self.syncStatus = "Sync partially completed (\(stats.totalOperations) operations, \(errors.count) errors)"
            }
            
            return result
        }
    }
    
    func resetSyncState() {
        lastPeopleSync = Date.distantPast
        lastConversationsSync = Date.distantPast
        lastSuccessfulSync = nil
        syncStatus = "Sync state reset - next sync will be full"
    }
    
    func cancelSync() {
        isSyncing = false
        syncStatus = "Sync cancelled"
    }
    
    // MARK: - Real-time Sync Control
    func enableRealTimeSync() async {
        if !isRealtimeEnabled {
            await initializeRealtimeSync()
        }
    }
    
    func disableRealTimeSync() async {
        isRealtimeEnabled = false
        
        if let peopleChannel = peopleChannel {
            try? await peopleChannel.unsubscribe()
        }
        
        if let conversationsChannel = conversationsChannel {
            try? await conversationsChannel.unsubscribe()
        }
        
        await updateSyncStatus("Real-time sync disabled")
    }
    
    var isRealTimeSyncEnabled: Bool {
        return isRealtimeEnabled
    }
    
    // MARK: - Conflict Resolution Control
    func setConflictResolutionStrategy(_ strategy: ConflictResolutionStrategy) {
        conflictResolutionStrategy = strategy
    }
    
    func getDetectedConflicts() -> [SyncConflict] {
        return detectedConflicts
    }
    
    func clearConflictHistory() {
        detectedConflicts.removeAll()
    }
    
    // MARK: - Performance Metrics
    func getCurrentSyncMetrics() -> (
        networkLatency: TimeInterval,
        databaseTime: TimeInterval,
        bytesTransferred: Int64,
        retryAttempts: Int,
        operationCount: Int
    ) {
        return (
            networkLatency: currentSyncNetworkLatency,
            databaseTime: currentSyncDatabaseTime,
            bytesTransferred: currentSyncBytesTransferred,
            retryAttempts: currentSyncRetryAttempts,
            operationCount: networkOperationCount
        )
    }
    
    // MARK: - Core Sync Implementation
    private func performSyncInternal() async -> SyncResult {
        let startTime = Date()
        
        // Reset performance metrics for this sync
        resetPerformanceMetrics()
        
        var stats = SyncStats(
            peopleInserted: 0, peopleUpdated: 0, peopleDeleted: 0,
            conversationsInserted: 0, conversationsUpdated: 0, conversationsDeleted: 0,
            startTime: startTime, endTime: startTime,
            networkLatency: 0, databaseSaveTime: 0,
            conflictsDetected: 0, conflictsResolved: 0,
            bytesTransferred: 0, retryAttempts: 0
        )
        var errors: [SyncError] = []
        
        do {
            // Validate network connectivity
            try await validateConnectivity()
            
            // Create background context for sync operations
            let container = PersistenceController.shared.container
            let backgroundContext = container.newBackgroundContext()
            backgroundContext.automaticallyMergesChangesFromParent = true
            backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            // Phase 1: Sync People (30% of progress)
            updateProgress(0.1, status: "Syncing people...")
            let peopleResult = try await syncPeople(context: backgroundContext)
            stats = mergePeopleStats(stats, peopleResult.stats)
            errors.append(contentsOf: peopleResult.errors)
            
            // Phase 2: Sync Conversations (60% of progress)  
            updateProgress(0.4, status: "Syncing conversations...")
            let conversationsResult = try await syncConversations(context: backgroundContext)
            stats = mergeConversationStats(stats, conversationsResult.stats)
            errors.append(contentsOf: conversationsResult.errors)
            
            // Phase 3: Validate relationships (10% of progress)
            updateProgress(0.9, status: "Validating relationships...")
            let relationshipErrors = try await validateRelationships(context: backgroundContext)
            errors.append(contentsOf: relationshipErrors)
            
            // Final save with error handling
            try await backgroundContext.perform {
                try self.saveContextWithRetry(backgroundContext)
            }
            
            stats = SyncStats(
                peopleInserted: stats.peopleInserted,
                peopleUpdated: stats.peopleUpdated,
                peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted,
                conversationsUpdated: stats.conversationsUpdated,
                conversationsDeleted: stats.conversationsDeleted,
                startTime: startTime,
                endTime: Date(),
                networkLatency: currentSyncNetworkLatency,
                databaseSaveTime: currentSyncDatabaseTime,
                conflictsDetected: detectedConflicts.count,
                conflictsResolved: detectedConflicts.count, // Assuming all detected conflicts are resolved
                bytesTransferred: currentSyncBytesTransferred,
                retryAttempts: currentSyncRetryAttempts
            )
            
            // Update sync timestamps only on success
            if errors.isEmpty {
                lastPeopleSync = Date()
                lastConversationsSync = Date()
                return .success(stats)
            } else {
                return .partial(stats, errors)
            }
            
        } catch {
            stats = SyncStats(
                peopleInserted: stats.peopleInserted,
                peopleUpdated: stats.peopleUpdated,
                peopleDeleted: stats.peopleDeleted,
                conversationsInserted: stats.conversationsInserted,
                conversationsUpdated: stats.conversationsUpdated,
                conversationsDeleted: stats.conversationsDeleted,
                startTime: startTime,
                endTime: Date(),
                networkLatency: currentSyncNetworkLatency,
                databaseSaveTime: currentSyncDatabaseTime,
                conflictsDetected: detectedConflicts.count,
                conflictsResolved: 0, // No conflicts resolved due to error
                bytesTransferred: currentSyncBytesTransferred,
                retryAttempts: currentSyncRetryAttempts
            )
            
            let syncError = self.mapError(error)
            return .failure(syncError)
        }
    }
    
    // MARK: - People Sync
    private func syncPeople(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Upload local changes
        let uploadResult = try await uploadPeopleChanges(context: context)
        stats = mergePeopleStats(stats, uploadResult.stats)
        errors.append(contentsOf: uploadResult.errors)
        
        // Download remote changes
        let downloadResult = try await downloadPeopleChanges(context: context)
        stats = mergePeopleStats(stats, downloadResult.stats)
        errors.append(contentsOf: downloadResult.errors)
        
        return (stats: stats, errors: errors)
    }
    
    private func uploadPeopleChanges(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Get people that need syncing
        let localPeople: [Person] = try await context.perform {
            let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            let modifiedAfter = self.lastPeopleSync
            request.predicate = NSPredicate(format: "modifiedAt > %@ OR createdAt > %@", modifiedAfter as NSDate, modifiedAfter as NSDate)
            request.fetchLimit = SyncConfig.batchSize
            
            return try context.fetch(request)
        }
        
        for person in localPeople {
            do {
                let result = try await uploadPerson(person, context: context)
                stats = incrementPeopleStats(stats, operation: result)
            } catch {
                errors.append(mapError(error))
            }
        }
        
        return (stats: stats, errors: errors)
    }
    
    private func downloadPeopleChanges(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Step 1: Get all remote people (for deletion detection) - exclude soft-deleted
        let allRemotePeople: [SupabasePerson] = try await supabase
            .from("people")
            .select()
            .is("is_deleted", value: false)
            .execute()
            .value
        
        let remoteIdentifiers = Set(allRemotePeople.compactMap { UUID(uuidString: $0.identifier) })
        
        // Step 2: Handle deletions - remove local people not in remote  
        // BUT only delete people that existed before the last sync (not new ones)
        do {
            let localPeople: [Person] = try await context.perform {
                let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
                return try context.fetch(request)
            }
            
            for localPerson in localPeople {
                if let localId = localPerson.identifier, !remoteIdentifiers.contains(localId) {
                    // Only delete people that have been successfully synced to remote before
                    // We can tell because they would have been created before the current sync started
                    let syncStartTime = Date().addingTimeInterval(-300) // 5 minutes ago as buffer
                    let personDate = localPerson.createdAt ?? localPerson.modifiedAt ?? Date()
                    
                    if personDate < syncStartTime && lastPeopleSync != Date.distantPast {
                        // This person was created more than 5 minutes ago and we've synced before - safe to delete
                        print("🗑️ Removing remotely deleted person: \(localPerson.name ?? "Unknown")")
                        try await context.perform {
                            context.delete(localPerson)
                        }
                        stats = incrementPeopleStats(stats, operation: .deleted)
                    } else {
                        // This is a recent person - don't delete them (might be new or sync failed)
                        print("⏳ Skipping recent person (might be new): \(localPerson.name ?? "Unknown")")
                    }
                }
            }
        } catch {
            errors.append(mapError(error))
        }
        
        // Step 3: Handle inserts/updates
        let response: [SupabasePerson]
        if lastPeopleSync == Date.distantPast {
            // Initial sync - use all people we already fetched
            response = allRemotePeople
        } else {
            // Incremental sync - only changes since last sync (exclude soft-deleted)
            let lastSyncISO = dateFormatter.string(from: lastPeopleSync)
            response = try await supabase
                .from("people")
                .select()
                .gte("updated_at", value: lastSyncISO)
                .is("is_deleted", value: false)
                .execute()
                .value
        }
        
        for remotePerson in response {
            do {
                let result = try await downloadPerson(remotePerson, context: context)
                stats = incrementPeopleStats(stats, operation: result)
            } catch {
                errors.append(mapError(error))
            }
        }
        
        return (stats: stats, errors: errors)
    }
    
    // MARK: - Conversation Sync
    private func syncConversations(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Upload local changes
        let uploadResult = try await uploadConversationChanges(context: context)
        stats = mergeConversationStats(stats, uploadResult.stats)
        errors.append(contentsOf: uploadResult.errors)
        
        // Download remote changes
        let downloadResult = try await downloadConversationChanges(context: context)
        stats = mergeConversationStats(stats, downloadResult.stats)
        errors.append(contentsOf: downloadResult.errors)
        
        return (stats: stats, errors: errors)
    }
    
    private func uploadConversationChanges(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Get conversations that need syncing
        let localConversations: [Conversation] = try await context.perform {
            let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
            let modifiedAfter = self.lastConversationsSync
            request.predicate = NSPredicate(format: "modifiedAt > %@ OR createdAt > %@", modifiedAfter as NSDate, modifiedAfter as NSDate)
            request.fetchLimit = SyncConfig.batchSize
            
            return try context.fetch(request)
        }
        
        for conversation in localConversations {
            do {
                let result = try await uploadConversation(conversation, context: context)
                stats = incrementConversationStats(stats, operation: result)
            } catch {
                errors.append(mapError(error))
            }
        }
        
        return (stats: stats, errors: errors)
    }
    
    private func downloadConversationChanges(context: NSManagedObjectContext) async throws -> (stats: SyncStats, errors: [SyncError]) {
        var stats = createEmptyStats()
        var errors: [SyncError] = []
        
        // Step 1: Get all remote conversations (for deletion detection) - exclude soft-deleted
        let allRemoteConversations: [SupabaseConversation] = try await supabase
            .from("conversations")
            .select()
            .is("is_deleted", value: false)
            .execute()
            .value
        
        let remoteUUIDs = Set(allRemoteConversations.compactMap { UUID(uuidString: $0.uuid) })
        
        // Step 2: Handle deletions - remove local conversations not in remote
        // BUT only delete conversations that existed before the last sync (not new ones)
        do {
            let localConversations: [Conversation] = try await context.perform {
                let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
                return try context.fetch(request)
            }
            
            for localConversation in localConversations {
                if let localUUID = localConversation.uuid, !remoteUUIDs.contains(localUUID) {
                    // Only delete conversations that have been successfully synced to remote before
                    // We can tell because they would have been created before the current sync started
                    let syncStartTime = Date().addingTimeInterval(-300) // 5 minutes ago as buffer
                    let conversationDate = localConversation.createdAt ?? localConversation.modifiedAt ?? Date()
                    
                    if conversationDate < syncStartTime && lastConversationsSync != Date.distantPast {
                        // This conversation was created more than 5 minutes ago and we've synced before - safe to delete
                        print("🗑️ Removing remotely deleted conversation: \(localUUID)")
                        try await context.perform {
                            context.delete(localConversation)
                        }
                        stats = incrementConversationStats(stats, operation: .deleted)
                    } else {
                        // This is a recent conversation - don't delete it (might be new or sync failed)
                        print("⏳ Skipping recent conversation (might be new): \(localUUID)")
                    }
                }
            }
        } catch {
            errors.append(mapError(error))
        }
        
        // Step 3: Handle inserts/updates
        let response: [SupabaseConversation]
        if lastConversationsSync == Date.distantPast {
            // Initial sync - use all conversations we already fetched
            response = allRemoteConversations
        } else {
            // Incremental sync - only changes since last sync (exclude soft-deleted)
            let lastSyncISO = dateFormatter.string(from: lastConversationsSync)
            response = try await supabase
                .from("conversations")
                .select()
                .gte("updated_at", value: lastSyncISO)
                .is("is_deleted", value: false)
                .execute()
                .value
        }
        
        for remoteConversation in response {
            do {
                let result = try await downloadConversation(remoteConversation, context: context)
                stats = incrementConversationStats(stats, operation: result)
            } catch {
                errors.append(mapError(error))
            }
        }
        
        return (stats: stats, errors: errors)
    }
    
    // MARK: - Individual Record Operations
    enum SyncOperation {
        case inserted
        case updated
        case deleted
    }
    
    private func uploadPerson(_ person: Person, context: NSManagedObjectContext) async throws -> SyncOperation {
        let (identifier, name, photoData, notes, createdAt, role, timezone, scheduledDate, isDirectReport) = try await context.perform {
            guard let identifier = person.identifier?.uuidString else {
                throw SyncError.dataValidationFailed("Person missing identifier")
            }
            
            // Validate required fields
            guard let name = person.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SyncError.dataValidationFailed("Person missing required name")
            }
            
            return (
                identifier,
                name,
                person.photo,
                person.notes,
                person.createdAt,
                person.role,
                person.timezone,
                person.scheduledConversationDate,
                person.isDirectReport
            )
        }
        
        let now = Date()
        let supabasePerson = SupabasePerson(
            id: nil,
            identifier: identifier,
            name: name,
            photoBase64: photoData?.base64EncodedString(),
            notes: notes?.isEmpty == true ? nil : notes,
            createdAt: dateFormatter.string(from: createdAt ?? now),
            updatedAt: dateFormatter.string(from: now),
            deviceId: deviceId,
            isSoftDeleted: false,
            deletedAt: nil,
            role: role?.isEmpty == true ? nil : role,
            timezone: timezone?.isEmpty == true ? nil : timezone,
            scheduledConversationDate: scheduledDate.map(dateFormatter.string),
            isDirectReport: isDirectReport
        )
        
        // Check if exists
        let existingPeople: [SupabasePerson] = try await supabase
            .from("people")
            .select()
            .eq("identifier", value: identifier)
            .execute()
            .value
        
        if existingPeople.isEmpty {
            try await supabase
                .from("people")
                .insert([supabasePerson])
                .execute()
            return .inserted
        } else {
            try await supabase
                .from("people")
                .update(supabasePerson)
                .eq("identifier", value: identifier)
                .execute()
            return .updated
        }
    }
    
    private func downloadPerson(_ remotePerson: SupabasePerson, context: NSManagedObjectContext) async throws -> SyncOperation {
        guard let identifierUUID = UUID(uuidString: remotePerson.identifier) else {
            throw SyncError.dataValidationFailed("Invalid person identifier: \(remotePerson.identifier)")
        }
        
        let request: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "identifier == %@", identifierUUID as CVarArg)
        
        let person = try await context.perform {
            try context.fetch(request).first ?? Person(context: context)
        }
        let isNew = person.identifier == nil
        
        // Check for conflicts before updating
        if !isNew {
            if let conflict = self.detectPersonConflict(local: person, remote: remotePerson) {
                self.detectedConflicts.append(conflict)
                try await self.resolveConflict(conflict, context: context)
                return .updated
            }
        }
        
        return try await context.perform {
            
            // Update person with remote data
            person.identifier = identifierUUID
            person.name = remotePerson.name
            person.role = remotePerson.role
            person.notes = remotePerson.notes
            person.isDirectReport = remotePerson.isDirectReport ?? false
            person.timezone = remotePerson.timezone
            
            if let photoBase64 = remotePerson.photoBase64, !photoBase64.isEmpty {
                person.photo = Data(base64Encoded: photoBase64)
            }
            
            if let dateString = remotePerson.scheduledConversationDate {
                person.scheduledConversationDate = self.dateFormatter.date(from: dateString)
            }
            
            if let createdAtString = remotePerson.createdAt {
                person.createdAt = self.dateFormatter.date(from: createdAtString)
            }
            
            if let updatedAtString = remotePerson.updatedAt {
                person.modifiedAt = self.dateFormatter.date(from: updatedAtString)
            }
            
            return isNew ? .inserted : .updated
        }
    }
    
    private func uploadConversation(_ conversation: Conversation, context: NSManagedObjectContext) async throws -> SyncOperation {
        guard let uuid = conversation.uuid?.uuidString else {
            throw SyncError.dataValidationFailed("Conversation missing UUID")
        }
        
        let now = Date()
        
        // Serialize key topics properly
        let keyTopicsJson: [String]?
        if let keyTopics = conversation.keyTopics, !keyTopics.isEmpty {
            keyTopicsJson = keyTopics
        } else {
            keyTopicsJson = nil
        }
        
        let supabaseConversation = SupabaseConversation(
            id: nil,
            uuid: uuid,
            personIdentifier: conversation.person?.identifier?.uuidString,
            date: conversation.date.map(dateFormatter.string),
            notes: conversation.notes?.isEmpty == true ? nil : conversation.notes,
            summary: conversation.summary?.isEmpty == true ? nil : conversation.summary,
            createdAt: dateFormatter.string(from: conversation.createdAt ?? now),
            updatedAt: dateFormatter.string(from: now),
            deviceId: deviceId,
            isSoftDeleted: false,
            deletedAt: nil,
            duration: conversation.duration > 0 ? Int(conversation.duration) : nil,
            engagementLevel: conversation.engagementLevel?.isEmpty == true ? nil : conversation.engagementLevel,
            analysisVersion: conversation.analysisVersion?.isEmpty == true ? nil : conversation.analysisVersion,
            keyTopics: keyTopicsJson,
            qualityScore: conversation.qualityScore,
            sentimentLabel: conversation.sentimentLabel?.isEmpty == true ? nil : conversation.sentimentLabel,
            sentimentScore: conversation.sentimentScore,
            lastAnalyzed: conversation.lastAnalyzed.map(dateFormatter.string),
            lastSentimentAnalysis: conversation.lastSentimentAnalysis.map(dateFormatter.string),
            legacyId: conversation.legacyId.map(dateFormatter.string)
        )
        
        // Check if exists
        let existingConversations: [SupabaseConversation] = try await supabase
            .from("conversations")
            .select()
            .eq("uuid", value: uuid)
            .execute()
            .value
        
        if existingConversations.isEmpty {
            try await supabase
                .from("conversations")
                .insert([supabaseConversation])
                .execute()
            return .inserted
        } else {
            try await supabase
                .from("conversations")
                .update(supabaseConversation)
                .eq("uuid", value: uuid)
                .execute()
            return .updated
        }
    }
    
    private func downloadConversation(_ remoteConversation: SupabaseConversation, context: NSManagedObjectContext) async throws -> SyncOperation {
        guard let conversationUUID = UUID(uuidString: remoteConversation.uuid) else {
            throw SyncError.dataValidationFailed("Invalid conversation UUID: \(remoteConversation.uuid)")
        }
        
        let request: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.predicate = NSPredicate(format: "uuid == %@", conversationUUID as CVarArg)
        
        let conversation = try context.fetch(request).first ?? Conversation(context: context)
        let isNew = conversation.uuid == nil
        
        // Check for conflicts before updating
        if !isNew {
            if let conflict = detectConversationConflict(local: conversation, remote: remoteConversation) {
                detectedConflicts.append(conflict)
                try await resolveConflict(conflict, context: context)
                return .updated
            }
        }
        
        // Update conversation with remote data
        conversation.uuid = conversationUUID
        conversation.notes = remoteConversation.notes
        conversation.summary = remoteConversation.summary
        conversation.duration = Int32(remoteConversation.duration ?? 0)
        conversation.engagementLevel = remoteConversation.engagementLevel
        conversation.analysisVersion = remoteConversation.analysisVersion
        conversation.keyTopics = remoteConversation.keyTopics
        conversation.qualityScore = remoteConversation.qualityScore
        conversation.sentimentLabel = remoteConversation.sentimentLabel
        conversation.sentimentScore = remoteConversation.sentimentScore
        
        if let dateString = remoteConversation.date {
            conversation.date = dateFormatter.date(from: dateString)
        }
        
        if let createdAtString = remoteConversation.createdAt {
            conversation.createdAt = dateFormatter.date(from: createdAtString)
        }
        
        if let updatedAtString = remoteConversation.updatedAt {
            conversation.modifiedAt = dateFormatter.date(from: updatedAtString)
        }
        
        if let lastAnalyzedString = remoteConversation.lastAnalyzed {
            conversation.lastAnalyzed = dateFormatter.date(from: lastAnalyzedString)
        }
        
        if let lastSentimentString = remoteConversation.lastSentimentAnalysis {
            conversation.lastSentimentAnalysis = dateFormatter.date(from: lastSentimentString)
        }
        
        if let legacyIdString = remoteConversation.legacyId {
            conversation.legacyId = dateFormatter.date(from: legacyIdString)
        }
        
        // Link to person if identifier provided (deferred if person doesn't exist yet)
        if let personIdentifier = remoteConversation.personIdentifier,
           let personUUID = UUID(uuidString: personIdentifier) {
            let personRequest: NSFetchRequest<Person> = NSFetchRequest<Person>(entityName: "Person")
            personRequest.predicate = NSPredicate(format: "identifier == %@", personUUID as CVarArg)
            if let associatedPerson = try context.fetch(personRequest).first {
                conversation.person = associatedPerson
            }
            // Note: If person doesn't exist, relationship will be resolved in validation phase
        }
        
        return isNew ? .inserted : .updated
    }
    
    // MARK: - Network Resilience Utilities
    private func withExponentialBackoff<T>(
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...SyncConfig.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if we should retry this error
                if !shouldRetry(error) {
                    throw error
                }
                
                // Don't wait after the last attempt
                if attempt == SyncConfig.maxRetries {
                    break
                }
                
                // Calculate exponential backoff delay
                let delay = min(
                    SyncConfig.baseRetryDelay * pow(2.0, Double(attempt - 1)),
                    SyncConfig.maxRetryDelay
                )
                
                print("🔄 Retry attempt \(attempt)/\(SyncConfig.maxRetries) after \(delay)s delay")
                currentSyncRetryAttempts += 1
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw SyncError.retryExhausted
    }
    
    private func shouldRetryError(_ error: Error) -> Bool {
        // Determine if an error is retryable
        if let syncError = error as? SyncError {
            switch syncError {
            case .networkUnavailable, .timeout:
                return true
            case .serverError(let code):
                // Retry network and server errors, but not client errors (4xx)
                return code >= 500 || code == 0
            case .rateLimited:
                return true
            case .authenticationFailed, .dataValidationFailed, .concurrentModification:
                return false
            default:
                return true
            }
        }
        
        // For unknown errors, attempt retry
        return true
    }
    
    // MARK: - Utility Methods
    private func validateConnectivity() async throws {
        try await withExponentialBackoff(
            operation: {
                let _ = try await self.supabase
                    .from("people")
                    .select("id")
                    .limit(1)
                    .execute()
            },
            shouldRetry: shouldRetryError
        )
    }
    
    private func validateRelationships(context: NSManagedObjectContext) async throws -> [SyncError] {
        var errors: [SyncError] = []
        
        // Find orphaned conversations
        let orphanedRequest: NSFetchRequest<Conversation> = NSFetchRequest<Conversation>(entityName: "Conversation")
        orphanedRequest.predicate = NSPredicate(format: "person == nil")
        
        let orphanedConversations = try context.fetch(orphanedRequest)
        
        for conversation in orphanedConversations {
            let error = SyncError.relationshipIntegrityViolation("Conversation \(conversation.uuid?.uuidString ?? "unknown") has no associated person")
            errors.append(error)
        }
        
        return errors
    }
    
    private func saveContextWithRetry(_ context: NSManagedObjectContext, retries: Int = SyncConfig.maxRetries) throws {
        var lastError: Error?
        
        for attempt in 1...retries {
            do {
                try context.save()
                return
            } catch {
                lastError = error
                if attempt < retries {
                    Thread.sleep(forTimeInterval: 0.1 * Double(attempt)) // Exponential backoff
                }
            }
        }
        
        throw SyncError.contextSaveFailed(lastError?.localizedDescription ?? "Unknown save error")
    }
    
    private func updateProgress(_ progress: Double, status: String) {
        Task { @MainActor in
            self.syncProgress = progress
            self.syncStatus = status
        }
    }
    
    private func mapError(_ error: Error) -> SyncError {
        if let syncError = error as? SyncError {
            return syncError
        }
        
        return .unknown(error)
    }
    
    private func mergePeopleStats(_ stats: SyncStats, _ other: SyncStats) -> SyncStats {
        return SyncStats(
            peopleInserted: stats.peopleInserted + other.peopleInserted,
            peopleUpdated: stats.peopleUpdated + other.peopleUpdated,
            peopleDeleted: stats.peopleDeleted + other.peopleDeleted,
            conversationsInserted: stats.conversationsInserted,
            conversationsUpdated: stats.conversationsUpdated,
            conversationsDeleted: stats.conversationsDeleted,
            startTime: stats.startTime,
            endTime: other.endTime,
            networkLatency: stats.networkLatency + other.networkLatency,
            databaseSaveTime: stats.databaseSaveTime + other.databaseSaveTime,
            conflictsDetected: stats.conflictsDetected + other.conflictsDetected,
            conflictsResolved: stats.conflictsResolved + other.conflictsResolved,
            bytesTransferred: stats.bytesTransferred + other.bytesTransferred,
            retryAttempts: stats.retryAttempts + other.retryAttempts
        )
    }
    
    private func mergeConversationStats(_ stats: SyncStats, _ other: SyncStats) -> SyncStats {
        return SyncStats(
            peopleInserted: stats.peopleInserted,
            peopleUpdated: stats.peopleUpdated,
            peopleDeleted: stats.peopleDeleted,
            conversationsInserted: stats.conversationsInserted + other.conversationsInserted,
            conversationsUpdated: stats.conversationsUpdated + other.conversationsUpdated,
            conversationsDeleted: stats.conversationsDeleted + other.conversationsDeleted,
            startTime: stats.startTime,
            endTime: other.endTime,
            networkLatency: stats.networkLatency + other.networkLatency,
            databaseSaveTime: stats.databaseSaveTime + other.databaseSaveTime,
            conflictsDetected: stats.conflictsDetected + other.conflictsDetected,
            conflictsResolved: stats.conflictsResolved + other.conflictsResolved,
            bytesTransferred: stats.bytesTransferred + other.bytesTransferred,
            retryAttempts: stats.retryAttempts + other.retryAttempts
        )
    }
    
    // MARK: - Public Deletion API
    func deletePerson(_ person: Person, context: NSManagedObjectContext) async {
        guard let identifier = person.identifier?.uuidString else { return }
        
        print("🗑️ Deleting person: \(person.name ?? "Unknown")")
        
        do {
            // Soft delete in Supabase (mark as deleted instead of hard delete)
            let now = Date()
            try await supabase
                .from("people")
                .update([
                    "is_deleted": "true",
                    "deleted_at": dateFormatter.string(from: now),
                    "updated_at": dateFormatter.string(from: now)
                ])
                .eq("identifier", value: identifier)
                .execute()
            
            // Delete locally
            context.delete(person)
            try context.save()
            
            print("✅ Person soft-deleted successfully")
            
        } catch {
            print("❌ Failed to delete person: \(error)")
        }
    }
    
    func deleteConversation(_ conversation: Conversation, context: NSManagedObjectContext) async {
        guard let uuid = conversation.uuid?.uuidString else { return }
        
        print("🗑️ Deleting conversation: \(uuid)")
        
        do {
            // Soft delete in Supabase (mark as deleted instead of hard delete)
            let now = Date()
            try await supabase
                .from("conversations")
                .update([
                    "is_deleted": "true",
                    "deleted_at": dateFormatter.string(from: now),
                    "updated_at": dateFormatter.string(from: now)
                ])
                .eq("uuid", value: uuid)
                .execute()
            
            // Delete locally
            context.delete(conversation)
            try context.save()
            
            print("✅ Conversation soft-deleted successfully")
            
        } catch {
            print("❌ Failed to delete conversation: \(error)")
        }
    }
    
    // Public trigger sync method for compatibility
    func triggerSync() {
        Task {
            await performSync()
        }
    }
}

// MARK: - Task Cancellation Support
extension RobustSyncManager {
    private func withTaskCancellation<T>(_ operation: @escaping () async -> T) async -> T {
        return await operation()
    }
}