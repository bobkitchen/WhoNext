import Foundation
import CoreData
import SwiftUI

/// Manages automated pre-meeting brief generation for today's 1:1 meetings
/// Generates briefs in the morning and caches them for display in meeting cards
class PreMeetingBriefManager: ObservableObject {
    static let shared = PreMeetingBriefManager()

    // MARK: - Published Properties

    /// Cached briefs keyed by meeting ID
    @Published var briefCache: [String: CachedBrief] = [:]

    /// Whether briefs are currently being generated
    @Published var isGenerating: Bool = false

    /// Meetings that are pending brief generation
    @Published var pendingMeetings: [String] = []

    /// Last time briefs were generated
    @Published var lastGenerationTime: Date?

    // MARK: - Types

    struct CachedBrief {
        let meetingID: String
        let personID: UUID?
        let personName: String
        let briefContent: String
        let generatedAt: Date
        var isStale: Bool {
            // Briefs are stale after 4 hours
            Date().timeIntervalSince(generatedAt) > 14400
        }
    }

    enum BriefGenerationError: Error {
        case noPersonFound
        case personHasNoConversations
        case aiServiceError(String)
        case notA1on1Meeting
    }

    // MARK: - Initialization

    private init() {
        // Check if we should generate briefs on app launch
        checkAndGenerateMorningBriefs()
    }

    // MARK: - Morning Brief Generation

    /// Check if it's time to generate morning briefs and do so if needed
    func checkAndGenerateMorningBriefs() {
        let calendar = Calendar.current
        let now = Date()

        // Check if we've already generated briefs today
        if let lastGen = lastGenerationTime,
           calendar.isDate(lastGen, inSameDayAs: now) {
            print("📋 Briefs already generated today at \(lastGen)")
            return
        }

        // Generate briefs for today's 1:1 meetings
        Task { @MainActor in
            await generateBriefsForTodaysMeetings()
        }
    }

    /// Generate briefs for all 1:1 meetings scheduled for today
    @MainActor
    func generateBriefsForTodaysMeetings() async {
        guard !isGenerating else {
            print("⏳ Brief generation already in progress")
            return
        }

        isGenerating = true
        print("🌅 Starting morning brief generation...")

        let todaysMeetings = getTodaysOneOnOneMeetings()
        print("📅 Found \(todaysMeetings.count) 1:1 meetings for today")

        pendingMeetings = todaysMeetings.map { $0.id }

        for meeting in todaysMeetings {
            await generateBriefForMeeting(meeting)
            pendingMeetings.removeAll { $0 == meeting.id }
        }

        lastGenerationTime = Date()
        isGenerating = false
        print("✅ Morning brief generation complete")
    }

    /// Get all 1:1 meetings scheduled for today
    private func getTodaysOneOnOneMeetings() -> [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()

        return CalendarService.shared.upcomingMeetings.filter { meeting in
            // Must be today
            guard calendar.isDate(meeting.startDate, inSameDayAs: now) else { return false }
            // Must not have passed
            guard meeting.startDate >= now else { return false }
            // Must be 1:1 (exactly 2 attendees)
            guard (meeting.attendees?.count ?? 0) == 2 else { return false }

            return true
        }
    }

    // MARK: - Individual Brief Generation

    /// Generate a brief for a specific meeting
    @MainActor
    func generateBriefForMeeting(_ meeting: UpcomingMeeting) async {
        print("📝 Generating brief for: \(meeting.title)")

        // Find the other attendee (not the user)
        guard let attendees = meeting.attendees, attendees.count == 2 else {
            print("⚠️ Meeting doesn't have exactly 2 attendees")
            return
        }

        // Find Person record for the other attendee
        guard let person = findPersonForMeeting(attendees: attendees) else {
            print("⚠️ No Person record found for attendees: \(attendees)")
            // Cache a placeholder indicating no Person found
            briefCache[meeting.id] = CachedBrief(
                meetingID: meeting.id,
                personID: nil,
                personName: extractBestName(from: attendees),
                briefContent: "",  // Empty content signals to show calendar notes
                generatedAt: Date()
            )
            return
        }

        // Check if person has any conversations
        let conversationCount = person.conversations?.count ?? 0
        if conversationCount == 0 {
            print("ℹ️ \(person.wrappedName) has no conversation history")
            briefCache[meeting.id] = CachedBrief(
                meetingID: meeting.id,
                personID: person.id,
                personName: person.wrappedName,
                briefContent: "First meeting with \(person.wrappedName). No previous conversation history available.",
                generatedAt: Date()
            )
            return
        }

        // Generate brief using PreMeetingBriefService
        do {
            let brief = try await generateBriefAsync(for: person)
            briefCache[meeting.id] = CachedBrief(
                meetingID: meeting.id,
                personID: person.id,
                personName: person.wrappedName,
                briefContent: brief,
                generatedAt: Date()
            )
            print("✅ Brief generated for \(person.wrappedName)")
        } catch {
            print("❌ Failed to generate brief: \(error)")
            briefCache[meeting.id] = CachedBrief(
                meetingID: meeting.id,
                personID: person.id,
                personName: person.wrappedName,
                briefContent: "Unable to generate brief: \(error.localizedDescription)",
                generatedAt: Date()
            )
        }
    }

    /// Generate brief asynchronously
    private func generateBriefAsync(for person: Person) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let apiKey = UserDefaults.standard.string(forKey: "openAIKey") ?? ""
            PreMeetingBriefService.generateBrief(for: person, apiKey: apiKey) { result in
                switch result {
                case .success(let brief):
                    continuation.resume(returning: brief)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Person Matching

    /// Find Person record matching meeting attendees
    private func findPersonForMeeting(attendees: [String]) -> Person? {
        let context = PersistenceController.shared.container.viewContext

        for attendee in attendees {
            // Skip if this looks like the user's own email (common patterns)
            if isLikelyCurrentUser(attendee) {
                continue
            }

            // Try to find Person by name or email
            if let person = findPerson(matching: attendee, in: context) {
                return person
            }
        }

        return nil
    }

    /// Check if attendee is likely the current user
    private func isLikelyCurrentUser(_ attendee: String) -> Bool {
        // Get user's profile name if available
        let userName = UserProfile.shared.name.lowercased()
        let userEmail = UserDefaults.standard.string(forKey: "userEmail")?.lowercased() ?? ""

        let attendeeLower = attendee.lowercased()

        // Check email match
        if !userEmail.isEmpty && attendeeLower.contains(userEmail) {
            return true
        }

        // Check name match
        if !userName.isEmpty {
            let nameParts = userName.split(separator: " ")
            for part in nameParts {
                if attendeeLower.contains(String(part)) && part.count > 2 {
                    return true
                }
            }
        }

        return false
    }

    /// Find Person by name (extracted from email or display name)
    private func findPerson(matching attendee: String, in context: NSManagedObjectContext) -> Person? {
        let request: NSFetchRequest<Person> = Person.fetchRequest()

        // Extract clean name from email or display name
        let cleanName = extractCleanName(from: attendee)

        // Try full name match first
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", cleanName)
        if let results = try? context.fetch(request), let person = results.first {
            return person
        }

        // Try matching individual name parts (for partial matches)
        let nameParts = cleanName.split(separator: " ")
        for part in nameParts where part.count > 2 {
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", String(part))
            if let results = try? context.fetch(request), let person = results.first {
                return person
            }
        }

        return nil
    }

    /// Extract clean name from email or attendee string
    private func extractCleanName(from attendee: String) -> String {
        if attendee.contains("@") {
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            return String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        return attendee
    }

    /// Extract best name from attendees list
    private func extractBestName(from attendees: [String]) -> String {
        for attendee in attendees {
            if !isLikelyCurrentUser(attendee) {
                return extractCleanName(from: attendee)
            }
        }
        return attendees.first.map { extractCleanName(from: $0) } ?? "Unknown"
    }

    // MARK: - Brief Access

    /// Get cached brief for a meeting
    func getBrief(for meetingID: String) -> CachedBrief? {
        return briefCache[meetingID]
    }

    /// Check if a brief exists and is valid for a meeting
    func hasBrief(for meetingID: String) -> Bool {
        guard let brief = briefCache[meetingID] else { return false }
        return !brief.briefContent.isEmpty && !brief.isStale
    }

    /// Regenerate brief for a specific meeting
    @MainActor
    func regenerateBrief(for meeting: UpcomingMeeting) async {
        // Remove cached brief
        briefCache.removeValue(forKey: meeting.id)

        // Regenerate
        await generateBriefForMeeting(meeting)
    }

    /// Clear all cached briefs
    func clearCache() {
        briefCache.removeAll()
        lastGenerationTime = nil
    }
}
