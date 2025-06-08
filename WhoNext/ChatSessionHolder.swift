import SwiftUI
import Foundation

// Chat message model
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// Chat session model
class ChatSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
}

// Shared chat session to maintain state between main view and popout
class ChatSessionHolder: ObservableObject {
    static let shared = ChatSessionHolder()
    
    @Published var session = ChatSession()
    
    private init() {}
}
