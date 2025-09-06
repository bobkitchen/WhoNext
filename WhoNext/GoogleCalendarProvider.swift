import Foundation
import AppKit
import AuthenticationServices

// MARK: - Google Calendar Provider
/// Implementation of CalendarProvider using Google Calendar API
class GoogleCalendarProvider: NSObject, CalendarProvider {
    
    // MARK: - Properties
    private var activeCalendarID: String?
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var userEmail: String?
    
    // OAuth session for handling the authentication flow
    private var authSession: ASWebAuthenticationSession?
    
    var providerName: String {
        return "Google Calendar"
    }
    
    var isAuthorized: Bool {
        get async {
            // Check if we have a valid token and it hasn't expired
            guard let token = loadTokenFromKeychain() else { return false }
            self.accessToken = token.accessToken
            self.refreshToken = token.refreshToken
            self.tokenExpiresAt = token.expiresAt
            self.userEmail = token.userEmail
            
            // Check if token needs refresh
            if let expiresAt = token.expiresAt, expiresAt < Date() {
                do {
                    try await refreshAccessToken()
                    return true
                } catch {
                    return false
                }
            }
            
            return true
        }
    }
    
    // MARK: - Public Methods
    
    func requestAccess() async throws -> Bool {
        // Check if we already have valid credentials
        if await isAuthorized {
            return true
        }
        
        // Perform OAuth 2.0 flow
        return try await performOAuthFlow()
    }
    
    func fetchUpcomingMeetings(daysAhead: Int) async throws -> [UpcomingMeeting] {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        guard let token = accessToken else {
            throw CalendarProviderError.notAuthorized
        }
        
        let calendar = Calendar.current
        let now = Date()
        let endDate = calendar.date(byAdding: .day, value: daysAhead, to: now)!
        
        let timeMin = ISO8601DateFormatter().string(from: now)
        let timeMax = ISO8601DateFormatter().string(from: endDate)
        
        var urlComponents = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        urlComponents?.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        
        if let calendarID = activeCalendarID, calendarID != "primary" {
            urlComponents?.path = "/calendar/v3/calendars/\(calendarID)/events"
        }
        
        guard let url = urlComponents?.url else {
            throw CalendarProviderError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarProviderError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token expired, try to refresh
            try await refreshAccessToken()
            // Retry with new token
            return try await fetchUpcomingMeetings(daysAhead: daysAhead)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CalendarProviderError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["items"] as? [[String: Any]] ?? []
        
        return items.compactMap { eventData in
            mapGoogleEventToMeeting(eventData)
        }
    }
    
    func getAvailableCalendars() async throws -> [CalendarInfo] {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        guard let token = accessToken else {
            throw CalendarProviderError.notAuthorized
        }
        
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarProviderError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            return try await getAvailableCalendars()
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CalendarProviderError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["items"] as? [[String: Any]] ?? []
        
        return items.compactMap { calendarData in
            mapGoogleCalendarToInfo(calendarData)
        }
    }
    
    func setActiveCalendar(calendarID: String) async throws {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        activeCalendarID = calendarID
        // Store in UserDefaults for persistence
        UserDefaults.standard.set(calendarID, forKey: "googleCalendarID")
    }
    
    func signOut() async throws {
        // Revoke the token if we have one
        if let token = accessToken {
            let url = URL(string: "https://oauth2.googleapis.com/revoke")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(token)".data(using: .utf8)
            
            _ = try? await URLSession.shared.data(for: request)
        }
        
        // Clear stored credentials
        deleteTokenFromKeychain()
        
        // Clear local state
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        userEmail = nil
        activeCalendarID = nil
        UserDefaults.standard.removeObject(forKey: "googleCalendarID")
    }
    
    // MARK: - OAuth Implementation
    
    @MainActor
    private func performOAuthFlow() async throws -> Bool {
        guard let authURL = GoogleOAuthConfig.authorizationURL else {
            throw CalendarProviderError.invalidConfiguration
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.bobk.whonext"
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: CalendarProviderError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: CalendarProviderError.invalidResponse)
                    return
                }
                
                // Exchange authorization code for tokens
                Task {
                    do {
                        let success = try await self.exchangeCodeForTokens(code)
                        continuation.resume(returning: success)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            
            if !authSession!.start() {
                continuation.resume(throwing: CalendarProviderError.authenticationFailed)
            }
        }
    }
    
    private func exchangeCodeForTokens(_ code: String) async throws -> Bool {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParameters = [
            "code": code,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri": GoogleOAuthConfig.redirectURI,
            "grant_type": "authorization_code"
        ]
        
        let bodyString = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CalendarProviderError.authenticationFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let accessToken = json?["access_token"] as? String else {
            throw CalendarProviderError.authenticationFailed
        }
        
        self.accessToken = accessToken
        self.refreshToken = json?["refresh_token"] as? String
        
        if let expiresIn = json?["expires_in"] as? Int {
            self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        
        // Fetch user email
        await fetchUserEmail()
        
        // Store in keychain
        let tokenData = GoogleTokenData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: tokenExpiresAt,
            userEmail: userEmail
        )
        try storeTokenInKeychain(tokenData)
        
        return true
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = self.refreshToken else {
            throw CalendarProviderError.notAuthorized
        }
        
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParameters = [
            "refresh_token": refreshToken,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Refresh failed, clear everything
            deleteTokenFromKeychain()
            throw CalendarProviderError.notAuthorized
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let accessToken = json?["access_token"] as? String else {
            throw CalendarProviderError.authenticationFailed
        }
        
        self.accessToken = accessToken
        
        if let expiresIn = json?["expires_in"] as? Int {
            self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        
        // Update keychain
        let tokenData = GoogleTokenData(
            accessToken: accessToken,
            refreshToken: self.refreshToken,
            expiresAt: tokenExpiresAt,
            userEmail: userEmail
        )
        try storeTokenInKeychain(tokenData)
    }
    
    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        
        let url = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            self.userEmail = json?["email"] as? String
        } catch {
            print("Failed to fetch user email: \(error)")
        }
    }
    
    // MARK: - Keychain Storage
    
    private struct GoogleTokenData: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let userEmail: String?
    }
    
    private func storeTokenInKeychain(_ tokenData: GoogleTokenData) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(tokenData)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bobk.whonext.google",
            kSecAttrAccount as String: "google_oauth_token",
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CalendarProviderError.keychainError(status)
        }
    }
    
    private func loadTokenFromKeychain() -> GoogleTokenData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bobk.whonext.google",
            kSecAttrAccount as String: "google_oauth_token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(GoogleTokenData.self, from: data)
    }
    
    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bobk.whonext.google",
            kSecAttrAccount as String: "google_oauth_token"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Google OAuth Configuration
struct GoogleOAuthConfig {
    // These will be configured with your Google Cloud Console credentials
    static let clientID = "654710857458-md2cpglkug04ah5ls0efn3oml7ev06gv.apps.googleusercontent.com"
    static let clientSecret = ""  // For native apps, this can be empty or use PKCE
    static let redirectURI = "com.bobk.whonext:/oauth2redirect"
    static let scope = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/userinfo.email"
    
    static var authorizationURL: URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }
}

// MARK: - Google Calendar Event Mapping
extension GoogleCalendarProvider {
    
    /// Map Google Calendar event to UpcomingMeeting
    private func mapGoogleEventToMeeting(_ eventData: [String: Any]) -> UpcomingMeeting? {
        guard let id = eventData["id"] as? String,
              let summary = eventData["summary"] as? String else {
            return nil
        }
        
        // Parse start date
        guard let start = eventData["start"] as? [String: Any],
              let startDateString = start["dateTime"] as? String ?? start["date"] as? String,
              let startDate = parseGoogleDate(startDateString) else {
            return nil
        }
        
        // Parse end date for duration calculation
        var duration: TimeInterval? = nil
        if let end = eventData["end"] as? [String: Any],
           let endDateString = end["dateTime"] as? String ?? end["date"] as? String,
           let endDate = parseGoogleDate(endDateString) {
            duration = endDate.timeIntervalSince(startDate)
        }
        
        let location = eventData["location"] as? String
        let description = eventData["description"] as? String
        
        // Extract attendees
        var attendeesList: [String]? = nil
        if let attendees = eventData["attendees"] as? [[String: Any]] {
            attendeesList = attendees.compactMap { attendee in
                attendee["email"] as? String
            }
        }
        
        return UpcomingMeeting(
            id: id,
            title: summary,
            startDate: startDate,
            calendarID: activeCalendarID ?? "primary",
            notes: description,
            location: location,
            attendees: attendeesList,
            duration: duration
        )
    }
    
    /// Map Google Calendar to CalendarInfo
    private func mapGoogleCalendarToInfo(_ calendarData: [String: Any]) -> CalendarInfo? {
        guard let id = calendarData["id"] as? String,
              let summary = calendarData["summary"] as? String else {
            return nil
        }
        
        let backgroundColor = calendarData["backgroundColor"] as? String
        let isPrimary = calendarData["primary"] as? Bool ?? false
        
        return CalendarInfo(
            id: id,
            title: summary,
            color: backgroundColor,
            isDefault: isPrimary,
            accountName: userEmail,
            metadata: calendarData
        )
    }
    
    private func parseGoogleDate(_ dateString: String) -> Date? {
        // Try RFC3339 format first (with timezone)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try date-only format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateString)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension GoogleCalendarProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Error Extensions
extension CalendarProviderError {
    static var userCancelled: CalendarProviderError {
        return CalendarProviderError.authenticationFailed
    }
    
    static var invalidConfiguration: CalendarProviderError {
        return CalendarProviderError.providerNotAvailable
    }
    
    static var invalidRequest: CalendarProviderError {
        return CalendarProviderError.providerNotAvailable  
    }
    
    static var invalidResponse: CalendarProviderError {
        return CalendarProviderError.providerNotAvailable
    }
    
    static func apiError(statusCode: Int) -> CalendarProviderError {
        return CalendarProviderError.providerNotAvailable
    }
    
    static func keychainError(_ status: OSStatus) -> CalendarProviderError {
        return CalendarProviderError.providerNotAvailable
    }
}