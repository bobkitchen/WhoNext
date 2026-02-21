import Foundation
import EventKit
import Combine
import WidgetKit
import CoreData

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let calendarID: String
    let notes: String?
    let location: String?
    let attendees: [String]?
    let duration: TimeInterval?  // Duration in seconds
}

class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    // MARK: - Published Properties
    @Published var upcomingMeetings: [UpcomingMeeting] = []
    @Published var currentProvider: CalendarProviderType = .apple
    @Published var isAuthorized: Bool = false
    @Published var availableCalendars: [CalendarInfo] = []
    @Published var selectedCalendarID: String?
    
    // MARK: - Provider Management
    private var activeProvider: CalendarProvider
    private let appleProvider = AppleCalendarProvider()
    private let googleProvider = GoogleCalendarProvider()
    
    // MARK: - User Defaults Keys
    private let providerTypeKey = "selectedCalendarProvider"
    private let appleCalendarIDKey = "selectedCalendarID"
    private let googleCalendarIDKey = "googleCalendarID"
    
    private init() {
        // Initialize with default provider first
        self.activeProvider = appleProvider
        
        // Load saved provider preference
        if let savedProvider = UserDefaults.standard.string(forKey: providerTypeKey),
           let provider = CalendarProviderType(rawValue: savedProvider) {
            currentProvider = provider
        }
        
        // Set the correct provider based on preference
        activeProvider = currentProvider == .apple ? appleProvider : googleProvider
        
        // Load saved calendar selection
        loadSavedCalendarSelection()
        
        // Listen for calendar selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarSelectionChanged(_:)),
            name: Notification.Name("CalendarSelectionChanged"),
            object: nil
        )
        
        // Check authorization status
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Switch to a different calendar provider
    func switchProvider(to provider: CalendarProviderType) async throws {
        currentProvider = provider
        activeProvider = provider == .apple ? appleProvider : googleProvider
        
        // Save preference
        UserDefaults.standard.set(provider.rawValue, forKey: providerTypeKey)
        
        // Clear current meetings
        await MainActor.run {
            self.upcomingMeetings = []
            self.availableCalendars = []
        }
        
        // Load saved calendar for new provider
        loadSavedCalendarSelection()
        
        // Check authorization for new provider
        await checkAuthorizationStatus()
        
        // If authorized, fetch calendars and meetings
        if isAuthorized {
            try await fetchAvailableCalendars()
            await fetchUpcomingMeetings()
        }
    }
    
    /// Request access to the current calendar provider
    func requestAccess(completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                let granted = try await activeProvider.requestAccess()
                await MainActor.run {
                    self.isAuthorized = granted
                }
                
                if granted {
                    // Fetch available calendars after authorization
                    try await fetchAvailableCalendars()
                    
                    // Load saved calendar selection
                    if let savedID = selectedCalendarID {
                        try await activeProvider.setActiveCalendar(calendarID: savedID)
                    }
                }
                
                await MainActor.run {
                    completion(granted, nil)
                }
            } catch {
                await MainActor.run {
                    completion(false, error)
                }
            }
        }
    }
    
    /// Fetch upcoming meetings from the current provider
    func fetchUpcomingMeetings(daysAhead: Int = 7) {
        Task {
            await fetchUpcomingMeetings(daysAhead: daysAhead)
        }
    }
    
    /// Async version of fetchUpcomingMeetings
    private func fetchUpcomingMeetings(daysAhead: Int = 7) async {
        do {
            let meetings = try await activeProvider.fetchUpcomingMeetings(daysAhead: daysAhead)
            await MainActor.run {
                self.upcomingMeetings = meetings
            }
            // Sync to widget after fetching
            syncToWidget()
        } catch {
            print("Error fetching meetings: \(error)")
            await MainActor.run {
                self.upcomingMeetings = []
            }
            // Clear widget data on error
            syncToWidget()
        }
    }

    // MARK: - Widget Integration

    /// Sync upcoming meetings to the desktop widget via App Groups
    func syncToWidget() {
        print("🔄 Widget Sync: Starting sync with \(upcomingMeetings.count) meetings")

        // Convert UpcomingMeeting to SharedMeeting format for widget
        let sharedMeetings = upcomingMeetings.map { meeting -> SharedMeeting in
            let attendeeCount = meeting.attendees?.count ?? 0
            let isOneOnOne = attendeeCount == 2

            // For 1:1 meetings, try to find the other participant's info
            var participantName: String? = nil
            var participantPhotoData: Data? = nil

            if isOneOnOne, let attendees = meeting.attendees {
                // Get the other participant (not the current user)
                let currentUserName = UserProfile.shared.name
                let currentUserEmail = UserProfile.shared.email
                let otherParticipant = attendees.first { attendee in
                    !attendee.localizedCaseInsensitiveContains(currentUserName) &&
                    !attendee.localizedCaseInsensitiveContains(currentUserEmail)
                }

                if let otherName = otherParticipant {
                    participantName = otherName
                    print("🔍 Widget: 1:1 meeting '\(meeting.title)' - other participant: '\(otherName)'")

                    // Try to find matching Person in Core Data and get their photo
                    if let person = findPerson(byName: otherName) {
                        print("✅ Widget: Found Person '\(person.name ?? "?")' for '\(otherName)'")
                        if person.photo != nil {
                            participantPhotoData = SharedMeeting.createThumbnail(from: person.photo)
                            print("📸 Widget: Found photo for '\(person.name ?? "?")'")
                        } else {
                            print("⚠️ Widget: Person '\(person.name ?? "?")' has no photo")
                        }
                    } else {
                        print("⚠️ Widget: No Person found for '\(otherName)'")
                    }
                }
            }

            return SharedMeeting(
                id: meeting.id,
                title: meeting.title,
                startDate: meeting.startDate,
                duration: meeting.duration ?? 0,
                attendeeCount: attendeeCount,
                isOneOnOne: isOneOnOne,
                teamsURL: extractTeamsURL(from: meeting.notes),
                participantName: participantName,
                participantPhotoData: participantPhotoData
            )
        }

        // Encode and save to shared UserDefaults
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(sharedMeetings)

            // Check if App Group is accessible
            guard let defaults = UserDefaults(suiteName: AppGroupConstants.groupIdentifier) else {
                print("❌ Widget Sync: FAILED - Cannot access App Group '\(AppGroupConstants.groupIdentifier)'")
                print("   → You need to add the App Group in Apple Developer portal")
                return
            }

            defaults.set(data, forKey: AppGroupConstants.meetingsKey)
            defaults.synchronize()  // Force immediate write

            print("✅ Widget Sync: Saved \(sharedMeetings.count) meetings to App Group")
            for meeting in sharedMeetings.prefix(3) {
                print("   → \(meeting.title) at \(meeting.startDate)")
            }

            // Verify data was written
            if let savedData = defaults.data(forKey: AppGroupConstants.meetingsKey) {
                print("✅ Widget Sync: Verified - \(savedData.count) bytes saved")
            } else {
                print("❌ Widget Sync: Verification FAILED - data not readable")
            }

        } catch {
            print("❌ Widget Sync: Encoding error - \(error)")
        }

        // Trigger widget refresh
        WidgetCenter.shared.reloadTimelines(ofKind: "WhoNextWidget")
        print("🔄 Widget Sync: Requested widget timeline reload")
    }

    /// Find a Person in Core Data by name or email (for widget participant photos)
    private func findPerson(byName name: String) -> Person? {
        let context = PersistenceController.shared.container.viewContext

        // First, try exact name match
        let exactRequest: NSFetchRequest<Person> = Person.fetchRequest()
        exactRequest.predicate = NSPredicate(format: "name ==[cd] %@", name)
        exactRequest.fetchLimit = 1

        if let exactMatch = try? context.fetch(exactRequest).first {
            return exactMatch
        }

        // If the input looks like an email, try matching by email
        if name.contains("@") {
            let emailRequest: NSFetchRequest<Person> = Person.fetchRequest()
            emailRequest.predicate = NSPredicate(format: "email ==[cd] %@", name)
            emailRequest.fetchLimit = 1

            if let emailMatch = try? context.fetch(emailRequest).first {
                return emailMatch
            }

            // Also try extracting the name part from email (before @) for partial matching
            let namePart = name.split(separator: "@").first.map(String.init) ?? ""
            if !namePart.isEmpty {
                let partialRequest: NSFetchRequest<Person> = Person.fetchRequest()
                // e.g., "alice.lastname" -> try matching Person names containing "alice" or "lastname"
                let nameParts = namePart.replacingOccurrences(of: ".", with: " ")
                    .split(separator: " ")
                    .map(String.init)

                if let firstName = nameParts.first, firstName.count >= 3 {
                    partialRequest.predicate = NSPredicate(format: "name CONTAINS[cd] %@", firstName)
                    partialRequest.fetchLimit = 1

                    if let partialMatch = try? context.fetch(partialRequest).first {
                        return partialMatch
                    }
                }
            }
        }

        // Try fuzzy/partial name match as last resort
        let fuzzyRequest: NSFetchRequest<Person> = Person.fetchRequest()
        fuzzyRequest.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        fuzzyRequest.fetchLimit = 1

        if let fuzzyMatch = try? context.fetch(fuzzyRequest).first {
            return fuzzyMatch
        }

        // Try matching first word of the name
        let firstName = name.split(separator: " ").first.map(String.init) ?? ""
        if firstName.count >= 3 && firstName != name {
            let firstNameRequest: NSFetchRequest<Person> = Person.fetchRequest()
            firstNameRequest.predicate = NSPredicate(format: "name BEGINSWITH[cd] %@", firstName)
            firstNameRequest.fetchLimit = 1

            return try? context.fetch(firstNameRequest).first
        }

        return nil
    }

    /// Extract Teams meeting URL from notes and convert to msteams:// scheme
    private func extractTeamsURL(from notes: String?) -> String? {
        guard let notes = notes else { return nil }

        let patterns = [
            "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s<>\"]+",
            "https://teams\\.live\\.com/meet/[^\\s<>\"]+",
            "msteams://[^\\s<>\"]+",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
               let range = Range(match.range, in: notes) {
                var urlString = String(notes[range])

                // Convert HTTPS to msteams:// for direct Teams app opening
                if urlString.lowercased().hasPrefix("https://") {
                    urlString = urlString.replacingOccurrences(
                        of: "https://",
                        with: "msteams://",
                        options: .caseInsensitive
                    )
                }

                return urlString
            }
        }
        return nil
    }
    
    /// Fetch available calendars from the current provider
    func fetchAvailableCalendars() async throws {
        let calendars = try await activeProvider.getAvailableCalendars()
        await MainActor.run {
            self.availableCalendars = calendars
        }
    }
    
    /// Set the active calendar for the current provider
    func setActiveCalendar(_ calendarID: String) async throws {
        try await activeProvider.setActiveCalendar(calendarID: calendarID)
        selectedCalendarID = calendarID
        
        // Save selection based on provider
        let key = currentProvider == .apple ? appleCalendarIDKey : googleCalendarIDKey
        UserDefaults.standard.set(calendarID, forKey: key)
        
        // Fetch meetings for the newly selected calendar
        await fetchUpcomingMeetings()
    }
    
    /// Sign out from Google Calendar (no-op for Apple Calendar)
    func signOutGoogle() async throws {
        if currentProvider == .google {
            try await googleProvider.signOut()
            await MainActor.run {
                self.isAuthorized = false
                self.upcomingMeetings = []
                self.availableCalendars = []
                self.selectedCalendarID = nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func checkAuthorizationStatus() async {
        let authorized = await activeProvider.isAuthorized
        await MainActor.run {
            self.isAuthorized = authorized
        }
    }
    
    private func loadSavedCalendarSelection() {
        let key = currentProvider == .apple ? appleCalendarIDKey : googleCalendarIDKey
        selectedCalendarID = UserDefaults.standard.string(forKey: key)
        
        // For Apple Calendar, also handle legacy migration
        if currentProvider == .apple, let appleProvider = activeProvider as? AppleCalendarProvider {
            appleProvider.loadTargetCalendar(withID: selectedCalendarID)
        }
    }
    
    @objc private func calendarSelectionChanged(_ notification: Notification) {
        if let calendarID = notification.object as? String, !calendarID.isEmpty {
            Task {
                try? await setActiveCalendar(calendarID)
            }
        }
    }
    
    // MARK: - Legacy Support
    // These methods maintain compatibility with existing code
    
    /// Legacy method for backwards compatibility
    func logAvailableCalendars() {
        Task {
            if let calendars = try? await activeProvider.getAvailableCalendars() {
                for calendar in calendars {
                    print("Calendar: \(calendar.title) (\(calendar.id))")
                }
            }
        }
    }
}
