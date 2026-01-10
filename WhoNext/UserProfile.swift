import Foundation
import Combine
import CoreData

/// App-wide user profile settings
/// Stores the current user's name, email, photo, and voice profile
/// Syncs across devices via CloudKit through Core Data
class UserProfile: ObservableObject {

    // MARK: - Singleton
    static let shared = UserProfile()

    // MARK: - Core Data Context
    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // MARK: - Published Properties
    @Published var name: String = "" {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var email: String = "" {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var jobTitle: String = "" {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var organization: String = "" {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var photo: Data? = nil {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    // MARK: - Voice Profile
    @Published var voiceEmbedding: [Float]? = nil {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var voiceConfidence: Float = 0.0 {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var voiceSampleCount: Int = 0 {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    @Published var lastVoiceUpdate: Date? = nil {
        didSet {
            guard !isLoading else { return }
            saveToEntity()
        }
    }

    // MARK: - Private State
    private var isLoading = false
    private var cancellables = Set<AnyCancellable>()
    private var pendingReloadWorkItem: DispatchWorkItem?
    private var lastReloadTime: Date?
    private let reloadDebounceInterval: TimeInterval = 1.0  // Debounce reloads to 1 second

    // MARK: - Initial Sync State
    @Published var isInitialSyncComplete: Bool = false
    private var initialSyncContinuation: CheckedContinuation<Void, Never>?
    private var hasReceivedRemoteChange = false

    // MARK: - Onboarding State (stored in UserDefaults, not synced)
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: OnboardingKeys.hasCompletedOnboarding)
        }
    }

    private enum OnboardingKeys {
        static let hasCompletedOnboarding = "userProfileHasCompletedOnboarding"
    }

    // MARK: - User Defaults Keys (for migration)
    private enum LegacyKeys {
        static let userName = "userProfileName"
        static let userEmail = "userProfileEmail"
        static let userJobTitle = "userProfileJobTitle"
        static let userOrganization = "userProfileOrganization"
        static let userVoiceEmbedding = "userProfileVoiceEmbedding"
        static let userVoiceConfidence = "userProfileVoiceConfidence"
        static let userVoiceSampleCount = "userProfileVoiceSampleCount"
        static let userLastVoiceUpdate = "userProfileLastVoiceUpdate"
        static let migrationComplete = "userProfileMigratedToCoreData_v1"
    }

    // MARK: - Initialization
    private init() {
        // Load onboarding state from UserDefaults
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: OnboardingKeys.hasCompletedOnboarding)

        // Set up notification listener for remote changes
        setupRemoteChangeListener()

        // Load from Core Data (will also handle migration)
        loadFromEntity()
    }

    // MARK: - Remote Change Listening

    private func setupRemoteChangeListener() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: PersistenceController.shared.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.handleRemoteChange()
        }
    }

    private func handleRemoteChange() {
        // Signal initial sync completion if we were waiting
        if !hasReceivedRemoteChange {
            hasReceivedRemoteChange = true
            print("👤 [UserProfile] First remote change received - CloudKit sync is active")
            signalInitialSyncComplete()
        }
        scheduleReload()
    }

    private func signalInitialSyncComplete() {
        guard !isInitialSyncComplete else { return }
        isInitialSyncComplete = true
        initialSyncContinuation?.resume()
        initialSyncContinuation = nil
    }

    // MARK: - Initial Sync Waiting

    /// Wait for initial CloudKit sync to complete (or timeout after 5 seconds)
    /// Call this on app startup before relying on user profile data
    @MainActor
    func waitForInitialSync() async {
        // If already synced, return immediately
        if isInitialSyncComplete || hasReceivedRemoteChange {
            print("👤 [UserProfile] Initial sync already complete")
            loadFromEntity()  // Reload to pick up any remote data
            return
        }

        print("👤 [UserProfile] Waiting for initial CloudKit sync...")

        // Wait for either remote change or timeout
        await withCheckedContinuation { continuation in
            self.initialSyncContinuation = continuation

            // Timeout after 5 seconds - CloudKit might not have any data or be slow
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !self.isInitialSyncComplete {
                    print("👤 [UserProfile] Initial sync timeout (5s) - proceeding with local data")
                    self.signalInitialSyncComplete()
                }
            }
        }

        // Reload after sync completes
        loadFromEntity()
        print("👤 [UserProfile] Initial sync wait complete - profile loaded")
    }

    /// Debounced reload to prevent flooding during rapid CloudKit sync events
    private func scheduleReload() {
        // Cancel any pending reload
        pendingReloadWorkItem?.cancel()

        // Check if we've reloaded recently
        if let lastReload = lastReloadTime,
           Date().timeIntervalSince(lastReload) < reloadDebounceInterval {
            // Schedule a delayed reload instead
            let workItem = DispatchWorkItem { [weak self] in
                self?.performReload()
            }
            pendingReloadWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + reloadDebounceInterval, execute: workItem)
        } else {
            // Reload immediately
            performReload()
        }
    }

    private func performReload() {
        // Ensure we're on the main thread for @Published property updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [self] in
                performReload()
            }
            return
        }

        lastReloadTime = Date()
        print("👤 [UserProfile] Remote changes detected - checking for duplicates and reloading")

        // Re-run getOrCreate which will detect and merge any duplicates from other devices
        viewContext.perform { [self] in
            _ = UserProfileEntity.getOrCreate(in: viewContext)
        }

        loadFromEntity()
    }

    // MARK: - Core Data Operations

    private func loadFromEntity() {
        // Ensure we're on the main thread for @Published property updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [self] in
                loadFromEntity()
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        // First, check if we need to migrate from UserDefaults
        migrateFromUserDefaultsIfNeeded()

        // Fetch or create the entity
        let entity = UserProfileEntity.getOrCreate(in: viewContext)

        // Load values
        name = entity.name ?? ""
        email = entity.email ?? ""
        jobTitle = entity.jobTitle ?? ""
        organization = entity.organization ?? ""
        photo = entity.photo
        voiceEmbedding = entity.voiceEmbeddingArray
        voiceConfidence = entity.voiceConfidence
        voiceSampleCount = Int(entity.voiceSampleCount)
        lastVoiceUpdate = entity.lastVoiceUpdate

        print("👤 [UserProfile] Loaded from Core Data: \(name), \(email)")

        // Try to auto-populate from system if empty
        if name.isEmpty {
            autoPopulateFromSystem()
        }
    }

    private func saveToEntity() {
        viewContext.perform { [self] in
            let entity = UserProfileEntity.getOrCreate(in: viewContext)

            entity.name = name
            entity.email = email
            entity.jobTitle = jobTitle
            entity.organization = organization
            entity.photo = photo
            entity.voiceEmbeddingArray = voiceEmbedding
            entity.voiceConfidence = voiceConfidence
            entity.voiceSampleCount = Int32(voiceSampleCount)
            entity.lastVoiceUpdate = lastVoiceUpdate
            entity.modifiedAt = Date()

            do {
                if viewContext.hasChanges {
                    try viewContext.save()
                    print("👤 [UserProfile] Saved to Core Data (will sync via CloudKit)")
                }
            } catch {
                print("👤 [UserProfile] Error saving: \(error)")
            }
        }
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        // Check if already migrated
        guard !defaults.bool(forKey: LegacyKeys.migrationComplete) else {
            return
        }

        print("👤 [UserProfile] Migrating from UserDefaults to Core Data...")

        // Check if there's existing data in UserDefaults
        let legacyName = defaults.string(forKey: LegacyKeys.userName) ?? ""
        let legacyEmail = defaults.string(forKey: LegacyKeys.userEmail) ?? ""
        let legacyJobTitle = defaults.string(forKey: LegacyKeys.userJobTitle) ?? ""
        let legacyOrganization = defaults.string(forKey: LegacyKeys.userOrganization) ?? ""
        let legacyVoiceConfidence = defaults.float(forKey: LegacyKeys.userVoiceConfidence)
        let legacyVoiceSampleCount = defaults.integer(forKey: LegacyKeys.userVoiceSampleCount)
        let legacyLastVoiceUpdate = defaults.object(forKey: LegacyKeys.userLastVoiceUpdate) as? Date
        let legacyVoiceEmbedding = loadLegacyVoiceEmbedding()

        // Only migrate if there's data
        if !legacyName.isEmpty || !legacyEmail.isEmpty || legacyVoiceEmbedding != nil {
            let entity = UserProfileEntity.getOrCreate(in: viewContext)

            // Only set values if entity doesn't already have them (remote sync may have beaten us)
            if (entity.name ?? "").isEmpty { entity.name = legacyName }
            if (entity.email ?? "").isEmpty { entity.email = legacyEmail }
            if (entity.jobTitle ?? "").isEmpty { entity.jobTitle = legacyJobTitle }
            if (entity.organization ?? "").isEmpty { entity.organization = legacyOrganization }

            // Voice profile - only migrate if entity doesn't have one
            if entity.voiceSampleCount == 0 && legacyVoiceEmbedding != nil {
                entity.voiceEmbeddingArray = legacyVoiceEmbedding
                entity.voiceConfidence = legacyVoiceConfidence
                entity.voiceSampleCount = Int32(legacyVoiceSampleCount)
                entity.lastVoiceUpdate = legacyLastVoiceUpdate
            }

            entity.modifiedAt = Date()

            do {
                try viewContext.save()
                print("👤 [UserProfile] Migration complete!")
            } catch {
                print("👤 [UserProfile] Migration error: \(error)")
            }
        }

        // Mark migration complete
        defaults.set(true, forKey: LegacyKeys.migrationComplete)
    }

    private func loadLegacyVoiceEmbedding() -> [Float]? {
        guard let data = UserDefaults.standard.data(forKey: LegacyKeys.userVoiceEmbedding) else {
            return nil
        }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    // MARK: - Public Methods

    /// Check if a given attendee string matches the current user
    func isCurrentUser(_ attendee: String) -> Bool {
        guard !attendee.isEmpty else { return false }

        // Check email match
        if !email.isEmpty && attendee.localizedCaseInsensitiveContains(email) {
            return true
        }

        // Check name match
        if !name.isEmpty {
            if attendee.localizedCaseInsensitiveCompare(name) == .orderedSame {
                return true
            }

            let nameParts = name.split(separator: " ").map { String($0).lowercased() }
            let attendeeLower = attendee.lowercased()
            if nameParts.allSatisfy({ attendeeLower.contains($0) }) {
                return true
            }
        }

        return false
    }

    /// Extract name from email for comparison
    func extractName(from email: String) -> String {
        if email.contains("@") {
            let namePart = email.split(separator: "@").first ?? Substring(email)
            let name = String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            return name.split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        return email
    }

    /// Reset user profile
    func reset() {
        isLoading = true
        name = ""
        email = ""
        jobTitle = ""
        organization = ""
        photo = nil
        isLoading = false
        saveToEntity()
    }

    // MARK: - Private Methods

    private func autoPopulateFromSystem() {
        let fullName = NSFullUserName()
        if !fullName.isEmpty {
            isLoading = true
            self.name = fullName
            isLoading = false
            saveToEntity()
        }
    }

    // MARK: - Computed Properties

    var displayName: String {
        return name.isEmpty ? "User" : name
    }

    var hasProfile: Bool {
        return !name.isEmpty || !email.isEmpty
    }

    var profileSummary: String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if !jobTitle.isEmpty { parts.append(jobTitle) }
        if !organization.isEmpty { parts.append("at \(organization)") }
        return parts.joined(separator: " ")
    }

    var hasVoiceProfile: Bool {
        return voiceEmbedding != nil && voiceSampleCount > 0
    }

    var voiceProfileStatus: String {
        guard hasVoiceProfile else { return "Not trained" }

        if voiceConfidence >= 0.9 {
            return "Excellent (\(voiceSampleCount) samples)"
        } else if voiceConfidence >= 0.7 {
            return "Good (\(voiceSampleCount) samples)"
        } else if voiceConfidence >= 0.5 {
            return "Fair (\(voiceSampleCount) samples)"
        } else {
            return "Needs improvement (\(voiceSampleCount) samples)"
        }
    }

    var hasPhoto: Bool {
        return photo != nil
    }

    // MARK: - Voice Profile Management

    /// Add a new voice sample and update the user's voice embedding
    func addVoiceSample(_ embedding: [Float]) {
        if let existing = voiceEmbedding {
            let weight = min(0.2, 1.0 / Float(voiceSampleCount + 1))
            voiceEmbedding = zip(existing, embedding).map { old, new in
                old * (1 - weight) + new * weight
            }
        } else {
            voiceEmbedding = embedding
        }

        voiceSampleCount += 1
        lastVoiceUpdate = Date()
        updateVoiceConfidence()
    }

    /// Clear voice profile
    func clearVoiceProfile() {
        voiceEmbedding = nil
        voiceConfidence = 0.0
        voiceSampleCount = 0
        lastVoiceUpdate = nil
    }

    /// Match a given embedding against the user's voice profile
    func matchesUserVoice(_ embedding: [Float], threshold: Float = 0.7) -> (matches: Bool, confidence: Float) {
        guard let userEmbedding = voiceEmbedding else {
            return (false, 0.0)
        }

        let similarity = cosineSimilarity(userEmbedding, embedding)
        return (similarity >= threshold, similarity)
    }

    // MARK: - Private Voice Methods

    private func updateVoiceConfidence() {
        let sampleFactor = min(Float(voiceSampleCount) / 10.0, 1.0)
        voiceConfidence = 0.5 + (sampleFactor * 0.5)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Force refresh from Core Data (useful after sync)
    func refreshFromCoreData() {
        loadFromEntity()
    }

    /// Force sync user profile to CloudKit by touching modifiedAt
    /// Call this after completing voice training to ensure sync
    func forceSyncToCloud() {
        viewContext.perform { [self] in
            let entity = UserProfileEntity.getOrCreate(in: viewContext)
            entity.modifiedAt = Date()

            do {
                if viewContext.hasChanges {
                    try viewContext.save()
                    print("👤 [UserProfile] Force sync triggered - should upload to CloudKit")
                }
            } catch {
                print("👤 [UserProfile] Force sync error: \(error)")
            }
        }
    }

    /// Debug: Print current voice profile status
    func debugPrintVoiceProfile() {
        print("👤 ========== USER VOICE PROFILE STATUS ==========")
        print("👤 Has Voice Profile: \(hasVoiceProfile)")
        print("👤 Voice Sample Count: \(voiceSampleCount)")
        print("👤 Voice Confidence: \(voiceConfidence)")
        print("👤 Embedding Size: \(voiceEmbedding?.count ?? 0) floats")
        print("👤 Last Voice Update: \(lastVoiceUpdate?.description ?? "never")")
        print("👤 ================================================")
    }
}
