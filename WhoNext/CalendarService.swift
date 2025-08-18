import Foundation
import EventKit
import Combine

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let calendarID: String
    let notes: String?
    let location: String?
    let attendees: [String]?
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
        } catch {
            print("Error fetching meetings: \(error)")
            await MainActor.run {
                self.upcomingMeetings = []
            }
        }
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