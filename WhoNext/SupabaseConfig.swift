import Foundation
import Supabase

class SupabaseConfig {
    static let shared = SupabaseConfig()
    
    // Supabase project credentials
    private let supabaseURL = "https://iuaqpspmtwdweehldjng.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1YXFwc3BtdHdkd2VlaGxkam5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk0NzE5ODEsImV4cCI6MjA2NTA0Nzk4MX0.a1ovVTInLjBko4l8gbUIzNQ1LgUHT2w--1kN_zVb8Dc"
    
    lazy var client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseAnonKey
        )
    }()
    
    private init() {}
}

// MARK: - Supabase Data Models
struct SupabasePerson: Codable {
    let id: String?
    let identifier: String
    let name: String?
    let photoBase64: String?
    let notes: String?
    let createdAt: String?
    let updatedAt: String?
    let deviceId: String?
    let isDeleted: Bool?
    let deletedAt: String?
    let role: String?
    let timezone: String?
    let scheduledConversationDate: String?
    let isDirectReport: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case identifier
        case name
        case photoBase64 = "photo_base64"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deviceId = "device_id"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
        case role
        case timezone
        case scheduledConversationDate = "scheduled_conversation_date"
        case isDirectReport = "is_direct_report"
    }
}

struct SupabaseConversation: Codable {
    let id: String?
    let uuid: String
    let personIdentifier: String?
    let date: String?
    let notes: String?
    let summary: String?
    let createdAt: String?
    let updatedAt: String?
    let deviceId: String?
    let isDeleted: Bool?
    let deletedAt: String?
    let duration: Int?
    let engagementLevel: String?
    let analysisVersion: String?
    let keyTopics: [String]?
    let qualityScore: Double
    let sentimentLabel: String?
    let sentimentScore: Double
    let lastAnalyzed: String?
    let lastSentimentAnalysis: String?
    let legacyId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case personIdentifier = "person_identifier"
        case date
        case notes
        case summary
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deviceId = "device_id"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
        case duration
        case engagementLevel = "engagement_level"
        case analysisVersion = "analysis_version"
        case keyTopics = "key_topics"
        case qualityScore = "quality_score"
        case sentimentLabel = "sentiment_label"
        case sentimentScore = "sentiment_score"
        case lastAnalyzed = "last_analyzed"
        case lastSentimentAnalysis = "last_sentiment_analysis"
        case legacyId = "legacy_id"
    }
}
