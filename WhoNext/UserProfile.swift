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

    // MARK: - Voice Profile

    /// User's voice embedding for speaker identification
    @Published var voiceEmbedding: [Float]? {
        didSet {
            saveVoiceEmbedding()
        }
    }

    /// Confidence level in user's voice profile (0.0 - 1.0)
    @Published var voiceConfidence: Float {
        didSet {
            UserDefaults.standard.set(voiceConfidence, forKey: Keys.userVoiceConfidence)
        }
    }

    /// Number of voice samples collected
    @Published var voiceSampleCount: Int {
        didSet {
            UserDefaults.standard.set(voiceSampleCount, forKey: Keys.userVoiceSampleCount)
        }
    }

    /// Last time voice profile was updated
    @Published var lastVoiceUpdate: Date? {
        didSet {
            if let date = lastVoiceUpdate {
                UserDefaults.standard.set(date, forKey: Keys.userLastVoiceUpdate)
            }
        }
    }

    // MARK: - User Defaults Keys
    private enum Keys {
        static let userName = "userProfileName"
        static let userEmail = "userProfileEmail"
        static let userJobTitle = "userProfileJobTitle"
        static let userOrganization = "userProfileOrganization"
        static let userVoiceEmbedding = "userProfileVoiceEmbedding"
        static let userVoiceConfidence = "userProfileVoiceConfidence"
        static let userVoiceSampleCount = "userProfileVoiceSampleCount"
        static let userLastVoiceUpdate = "userProfileLastVoiceUpdate"
    }
    
    // MARK: - Initialization
    private init() {
        // Load from UserDefaults
        self.name = UserDefaults.standard.string(forKey: Keys.userName) ?? ""
        self.email = UserDefaults.standard.string(forKey: Keys.userEmail) ?? ""
        self.jobTitle = UserDefaults.standard.string(forKey: Keys.userJobTitle) ?? ""
        self.organization = UserDefaults.standard.string(forKey: Keys.userOrganization) ?? ""

        // Load voice profile
        self.voiceConfidence = UserDefaults.standard.float(forKey: Keys.userVoiceConfidence)
        self.voiceSampleCount = UserDefaults.standard.integer(forKey: Keys.userVoiceSampleCount)
        self.lastVoiceUpdate = UserDefaults.standard.object(forKey: Keys.userLastVoiceUpdate) as? Date
        self.voiceEmbedding = loadVoiceEmbedding()

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

    // MARK: - Voice Profile Management

    /// Add a new voice sample and update the user's voice embedding
    func addVoiceSample(_ embedding: [Float]) {
        if let existing = voiceEmbedding {
            // Weighted average: give more weight to existing profile
            let weight = min(0.2, 1.0 / Float(voiceSampleCount + 1))
            voiceEmbedding = zip(existing, embedding).map { old, new in
                old * (1 - weight) + new * weight
            }
        } else {
            voiceEmbedding = embedding
        }

        voiceSampleCount += 1
        lastVoiceUpdate = Date()

        // Update confidence based on sample count
        updateVoiceConfidence()
    }

    /// Clear voice profile
    func clearVoiceProfile() {
        voiceEmbedding = nil
        voiceConfidence = 0.0
        voiceSampleCount = 0
        lastVoiceUpdate = nil

        UserDefaults.standard.removeObject(forKey: Keys.userVoiceEmbedding)
        UserDefaults.standard.removeObject(forKey: Keys.userVoiceConfidence)
        UserDefaults.standard.removeObject(forKey: Keys.userVoiceSampleCount)
        UserDefaults.standard.removeObject(forKey: Keys.userLastVoiceUpdate)
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

    private func saveVoiceEmbedding() {
        guard let embedding = voiceEmbedding else {
            UserDefaults.standard.removeObject(forKey: Keys.userVoiceEmbedding)
            return
        }

        let data = embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        UserDefaults.standard.set(data, forKey: Keys.userVoiceEmbedding)
    }

    private func loadVoiceEmbedding() -> [Float]? {
        guard let data = UserDefaults.standard.data(forKey: Keys.userVoiceEmbedding) else {
            return nil
        }

        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    private func updateVoiceConfidence() {
        // Confidence improves with more samples, plateaus around 10 samples
        let sampleFactor = min(Float(voiceSampleCount) / 10.0, 1.0)
        voiceConfidence = 0.5 + (sampleFactor * 0.5) // Range: 0.5 - 1.0
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
}