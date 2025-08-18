import Foundation

// MARK: - Calendar Provider Protocol
/// Common interface for calendar providers (Apple Calendar, Google Calendar, etc.)
protocol CalendarProvider {
    /// The name of the provider for display purposes
    var providerName: String { get }
    
    /// Whether the provider is currently authorized
    var isAuthorized: Bool { get async }
    
    /// Request access/authorization for the calendar provider
    func requestAccess() async throws -> Bool
    
    /// Fetch upcoming meetings from the calendar
    func fetchUpcomingMeetings(daysAhead: Int) async throws -> [UpcomingMeeting]
    
    /// Get list of available calendars from this provider
    func getAvailableCalendars() async throws -> [CalendarInfo]
    
    /// Set the active calendar to use for fetching events
    func setActiveCalendar(calendarID: String) async throws
    
    /// Sign out / revoke access (if applicable)
    func signOut() async throws
}

// MARK: - Calendar Info Model
/// Information about a calendar from any provider
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let color: String?
    let isDefault: Bool
    let accountName: String?
    
    /// Provider-specific metadata
    let metadata: [String: Any]?
}

// MARK: - Calendar Provider Type
enum CalendarProviderType: String, CaseIterable {
    case apple = "Apple Calendar"
    case google = "Google Calendar"
    
    var icon: String {
        switch self {
        case .apple:
            return "applelogo"
        case .google:
            return "globe" // Will use custom Google icon if available
        }
    }
    
    var description: String {
        switch self {
        case .apple:
            return "Use calendars from your Mac's Calendar app"
        case .google:
            return "Connect to your Google Calendar account"
        }
    }
}

// MARK: - Calendar Provider Error
enum CalendarProviderError: LocalizedError {
    case notAuthorized
    case authenticationFailed
    case networkError(Error)
    case invalidCalendarID
    case providerNotAvailable
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized. Please grant permission in Settings."
        case .authenticationFailed:
            return "Failed to authenticate with calendar provider."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidCalendarID:
            return "The selected calendar is no longer available."
        case .providerNotAvailable:
            return "Google Calendar integration is coming soon. This feature requires additional configuration including Google API setup and OAuth credentials."
        case .tokenExpired:
            return "Authentication expired. Please sign in again."
        }
    }
}