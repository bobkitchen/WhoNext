import SwiftUI

enum SentimentColors {
    static func color(for sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive", "happy", "excited": return .green
        case "negative", "sad", "angry", "frustrated": return .red
        case "concerned", "worried", "neutral": return .orange
        default: return .gray
        }
    }

    static func relationshipHealth(_ health: String) -> Color {
        switch health.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "poor": return .red
        default: return .gray
        }
    }

    static func engagement(_ level: String) -> Color {
        switch level.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    static func energy(_ level: String) -> Color {
        switch level.lowercased() {
        case "high": return .green
        case "medium": return .blue
        case "low": return .orange
        default: return .gray
        }
    }
}
