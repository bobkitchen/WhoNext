import Foundation
import CoreData
import AppKit
import Combine

/// Singleton service that syncs WhoNext meeting data to an Obsidian vault as markdown files.
/// Follows the `StorageMaintenanceManager.shared` pattern.
class ObsidianSyncService: ObservableObject {

    // MARK: - Singleton

    static let shared = ObsidianSyncService()

    // MARK: - Published Properties

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var vaultPath: URL?
    @Published var lastSyncDate: Date? {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: Keys.lastSyncDate) }
    }
    @Published var lastError: String?
    @Published var syncInProgress = false

    // MARK: - Private Properties

    private let formatter = ObsidianNoteFormatter()
    private let fileManager = FileManager.default
    private var observers: [NSObjectProtocol] = []
    private let context = PersistenceController.shared.container.viewContext

    private enum Keys {
        static let isEnabled = "ObsidianSyncEnabled"
        static let lastSyncDate = "ObsidianLastSyncDate"
        static let bookmarkData = "ObsidianVaultBookmark"
    }

    // MARK: - Initialization

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Keys.isEnabled)
        lastSyncDate = UserDefaults.standard.object(forKey: Keys.lastSyncDate) as? Date
        vaultPath = resolveBookmark()

        if isEnabled {
            registerObservers()
        }
    }

    // MARK: - Vault Selection (Security-Scoped Bookmark)

    /// Present a folder picker for the user to choose their Obsidian vault.
    @MainActor
    func selectVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your Obsidian vault folder"
        panel.prompt = "Select Vault"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.storeBookmark(for: url)
        }
    }

    private func storeBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Keys.bookmarkData)
            vaultPath = url
            isEnabled = true
            lastError = nil
            registerObservers()
            debugLog("📓 Obsidian: Vault set to \(url.path)")
        } catch {
            lastError = "Failed to save vault access: \(error.localizedDescription)"
            print("❌ Obsidian: Bookmark error - \(error)")
        }
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.bookmarkData) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-create the bookmark
                debugLog("📓 Obsidian: Refreshing stale bookmark")
                storeBookmark(for: url)
            }

            return url
        } catch {
            print("❌ Obsidian: Failed to resolve bookmark - \(error)")
            return nil
        }
    }

    /// Access the vault URL with security scope, execute a block, then release access.
    private func withVaultAccess<T>(_ block: (URL) throws -> T) rethrows -> T? {
        guard let url = vaultPath else {
            lastError = "No vault configured"
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Cannot access vault folder (permission denied)"
            return nil
        }

        defer { url.stopAccessingSecurityScopedResource() }
        return try block(url)
    }

    // MARK: - Directory Structure

    private func meetingsDir(in vault: URL) -> URL {
        vault.appendingPathComponent("WhoNext/Meetings")
    }

    private func peopleDir(in vault: URL) -> URL {
        vault.appendingPathComponent("WhoNext/People")
    }

    private func ensureDirectories(in vault: URL) throws {
        try fileManager.createDirectory(at: meetingsDir(in: vault), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: peopleDir(in: vault), withIntermediateDirectories: true)
    }

    // MARK: - Full Sync

    /// Sync ALL non-deleted conversations, group meetings, and people to the vault.
    func fullSync() async {
        guard isEnabled, !syncInProgress else { return }

        await MainActor.run { syncInProgress = true; lastError = nil }
        debugLog("📓 Obsidian: Starting full sync...")

        guard let vault = vaultPath else {
            await MainActor.run { syncInProgress = false; lastError = "No vault configured" }
            return
        }

        guard vault.startAccessingSecurityScopedResource() else {
            await MainActor.run { syncInProgress = false; lastError = "Cannot access vault folder (permission denied)" }
            return
        }

        defer { vault.stopAccessingSecurityScopedResource() }

        do {
            try ensureDirectories(in: vault)
        } catch {
            await MainActor.run { syncInProgress = false; lastError = "Failed to create vault directories: \(error.localizedDescription)" }
            return
        }

        // Conversations
        let convRequest: NSFetchRequest<Conversation> = NSFetchRequest(entityName: "Conversation")
        convRequest.predicate = NSPredicate(format: "isSoftDeleted == false")
        let conversations = (try? context.fetch(convRequest)) ?? []

        var totalErrors = 0
        for conv in conversations {
            do {
                try writeConversation(conv, to: vault)
            } catch {
                totalErrors += 1
                print("❌ Obsidian: Failed to write conversation - \(error)")
            }
        }

        // Group Meetings
        let gmRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        gmRequest.predicate = NSPredicate(format: "isSoftDeleted == false")
        let groupMeetings = (try? context.fetch(gmRequest)) ?? []

        for meeting in groupMeetings {
            do {
                try writeGroupMeeting(meeting, to: vault)
            } catch {
                totalErrors += 1
                print("❌ Obsidian: Failed to write group meeting - \(error)")
            }
        }

        // People
        let personRequest = Person.fetchRequest()
        personRequest.predicate = NSPredicate(format: "isSoftDeleted == false")
        let people = (try? context.fetch(personRequest)) ?? []

        for case let person as Person in people {
            guard !person.isCurrentUser else { continue }
            guard let name = person.name, !name.isEmpty else { continue }
            guard !name.hasPrefix("Speaker ") else { continue }

            do {
                try writePersonNote(person, to: vault)
            } catch {
                totalErrors += 1
                print("❌ Obsidian: Failed to write person - \(error)")
            }
        }

        print("📓 Obsidian: Full sync complete - \(conversations.count) convs, \(groupMeetings.count) group meetings, \(people.count) people (\(totalErrors) errors)")

        await MainActor.run {
            syncInProgress = false
            if totalErrors > 0 {
                lastError = "\(totalErrors) file(s) failed to sync"
            } else {
                lastSyncDate = Date()
            }
        }
    }

    // MARK: - Incremental Sync

    /// Sync conversations modified since last sync.
    func syncRecentConversations() {
        guard isEnabled, !syncInProgress else { return }

        withVaultAccess { vault in
            do {
                try ensureDirectories(in: vault)
            } catch {
                print("❌ Obsidian: Directory creation failed - \(error)")
                return
            }

            let request: NSFetchRequest<Conversation> = NSFetchRequest(entityName: "Conversation")
            var predicates = [NSPredicate(format: "isSoftDeleted == false")]
            if let lastSync = lastSyncDate {
                predicates.append(NSPredicate(format: "modifiedAt > %@", lastSync as NSDate))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            guard let conversations = try? context.fetch(request) else { return }

            for conv in conversations {
                do {
                    try writeConversation(conv, to: vault)
                    // Update the person note too
                    if let person = conv.person, !person.isCurrentUser {
                        try writePersonNote(person, to: vault)
                    }
                } catch {
                    print("❌ Obsidian: Incremental conv sync error - \(error)")
                }
            }

            if !conversations.isEmpty {
                DispatchQueue.main.async { self.lastSyncDate = Date() }
                debugLog("📓 Obsidian: Synced \(conversations.count) recent conversation(s)")
            }
        }
    }

    /// Sync group meetings modified since last sync.
    func syncRecentGroupMeetings() {
        guard isEnabled, !syncInProgress else { return }

        withVaultAccess { vault in
            do {
                try ensureDirectories(in: vault)
            } catch {
                print("❌ Obsidian: Directory creation failed - \(error)")
                return
            }

            let request: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
            var predicates = [NSPredicate(format: "isSoftDeleted == false")]
            if let lastSync = lastSyncDate {
                predicates.append(NSPredicate(format: "modifiedAt > %@", lastSync as NSDate))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            guard let meetings = try? context.fetch(request) else { return }

            for meeting in meetings {
                do {
                    try writeGroupMeeting(meeting, to: vault)
                    // Update attendee person notes too
                    for person in meeting.sortedAttendees where !person.isCurrentUser {
                        try writePersonNote(person, to: vault)
                    }
                } catch {
                    print("❌ Obsidian: Incremental group meeting sync error - \(error)")
                }
            }

            if !meetings.isEmpty {
                DispatchQueue.main.async { self.lastSyncDate = Date() }
                debugLog("📓 Obsidian: Synced \(meetings.count) recent group meeting(s)")
            }
        }
    }

    // MARK: - File Writing

    /// Write content to a file only if it differs from the existing file.
    /// Avoids unnecessary Obsidian Sync traffic when multiple Macs run the sync.
    private func writeIfChanged(_ content: String, to fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path),
           let existing = try? String(contentsOf: fileURL, encoding: .utf8),
           existing == content {
            return // File is identical, skip write
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeConversation(_ conversation: Conversation, to vault: URL) throws {
        let content = formatter.meetingNote(from: conversation)
        let filename = formatter.filenameForConversation(conversation)
        let fileURL = meetingsDir(in: vault).appendingPathComponent(filename)
        try writeIfChanged(content, to: fileURL)
    }

    private func writeGroupMeeting(_ meeting: GroupMeeting, to vault: URL) throws {
        let content = formatter.meetingNote(from: meeting)
        let filename = formatter.filenameForGroupMeeting(meeting)
        let fileURL = meetingsDir(in: vault).appendingPathComponent(filename)
        try writeIfChanged(content, to: fileURL)
    }

    private func writePersonNote(_ person: Person, to vault: URL) throws {
        let conversations = person.conversationsArray
        let groupMeetings = person.groupMeetingsArray
        let content = formatter.personNote(from: person, conversations: conversations, groupMeetings: groupMeetings)
        let filename = formatter.filenameForPerson(person)
        let fileURL = peopleDir(in: vault).appendingPathComponent(filename)
        try writeIfChanged(content, to: fileURL)
    }

    // MARK: - Notification Observers

    private func registerObservers() {
        // Remove any existing observers first
        unregisterObservers()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .conversationSaved, object: nil, queue: .main
            ) { [weak self] _ in
                self?.syncRecentConversations()
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .conversationUpdated, object: nil, queue: .main
            ) { [weak self] _ in
                self?.syncRecentConversations()
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .groupMeetingSaved, object: nil, queue: .main
            ) { [weak self] _ in
                self?.syncRecentGroupMeetings()
            }
        )

        debugLog("📓 Obsidian: Registered notification observers")
    }

    private func unregisterObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Disable

    /// Disable Obsidian sync. Does NOT delete existing vault files.
    func disable() {
        unregisterObservers()
        UserDefaults.standard.removeObject(forKey: Keys.bookmarkData)
        isEnabled = false
        vaultPath = nil
        lastError = nil
        debugLog("📓 Obsidian: Sync disabled")
    }
}
