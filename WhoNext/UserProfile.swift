import Foundation
import Combine

/// App-wide user profile settings
/// Stores the current user's name and email to exclude them from attendee lists
/// and personalize the app experience
class UserProfile: ObservableObject {
    
    // MARK: - Singleton
    static let shared = UserProfile()
    
    // MARK: - Published Properties
    @Published var name: String {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var email: String {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var jobTitle: String {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var organization: String {
        didSet {
            saveToUserDefaults()
        }
    }
    
    // MARK: - User Defaults Keys
    private enum Keys {
        static let userName = "userProfileName"
        static let userEmail = "userProfileEmail"
        static let userJobTitle = "userProfileJobTitle"
        static let userOrganization = "userProfileOrganization"
    }
    
    // MARK: - Initialization
    private init() {
        // Load from UserDefaults
        self.name = UserDefaults.standard.string(forKey: Keys.userName) ?? ""
        self.email = UserDefaults.standard.string(forKey: Keys.userEmail) ?? ""
        self.jobTitle = UserDefaults.standard.string(forKey: Keys.userJobTitle) ?? ""
        self.organization = UserDefaults.standard.string(forKey: Keys.userOrganization) ?? ""
        
        // Try to auto-populate from system if empty
        if name.isEmpty {
            autoPopulateFromSystem()
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if a given attendee string matches the current user
    func isCurrentUser(_ attendee: String) -> Bool {
        // Check if it's empty
        guard !attendee.isEmpty else { return false }
        
        // Check email match
        if !email.isEmpty && attendee.localizedCaseInsensitiveContains(email) {
            return true
        }
        
        // Check name match
        if !name.isEmpty {
            // Direct match
            if attendee.localizedCaseInsensitiveCompare(name) == .orderedSame {
                return true
            }
            
            // Check if attendee contains all parts of the user's name
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
        name = ""
        email = ""
        jobTitle = ""
        organization = ""
        saveToUserDefaults()
    }
    
    // MARK: - Private Methods
    
    private func saveToUserDefaults() {
        UserDefaults.standard.set(name, forKey: Keys.userName)
        UserDefaults.standard.set(email, forKey: Keys.userEmail)
        UserDefaults.standard.set(jobTitle, forKey: Keys.userJobTitle)
        UserDefaults.standard.set(organization, forKey: Keys.userOrganization)
    }
    
    private func autoPopulateFromSystem() {
        // Try to get the user's full name from the system
        let fullName = NSFullUserName()
        if !fullName.isEmpty {
            self.name = fullName
        }
        
        // Try to get username and construct email (this is a guess)
        let username = NSUserName()
        if !username.isEmpty {
            // Don't auto-populate email as we can't know the domain
            // Users should set this manually
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
}