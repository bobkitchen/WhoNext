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
    let id: String
    let identifier: String?
    let name: String?
    let role: String?
    let notes: String?
    let isDirectReport: Bool
    let timezone: String?
    let scheduledConversationDate: Date?
    let photoBase64: String? // Store as base64 string for Supabase
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, identifier, name, role, notes, timezone
        case isDirectReport = "is_direct_report"
        case scheduledConversationDate = "scheduled_conversation_date"
        case photoBase64 = "photo"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SupabaseConversation: Codable {
    let id: String
    let uuid: String
    let personId: String?
    let date: Date?
    let duration: Int?
    let engagementLevel: String?
    let notes: String?
    let summary: String?
    let analysisVersion: String?
    let keyTopics: [String]?
    let qualityScore: Double
    let sentimentLabel: String?
    let sentimentScore: Double
    let lastAnalyzed: Date?
    let lastSentimentAnalysis: Date?
    let legacyId: Date?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, date, duration, notes, summary
        case personId = "person_id"
        case engagementLevel = "engagement_level"
        case analysisVersion = "analysis_version"
        case keyTopics = "key_topics"
        case qualityScore = "quality_score"
        case sentimentLabel = "sentiment_label"
        case sentimentScore = "sentiment_score"
        case lastAnalyzed = "last_analyzed"
        case lastSentimentAnalysis = "last_sentiment_analysis"
        case legacyId = "legacy_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
