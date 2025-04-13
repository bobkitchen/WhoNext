import SwiftUI
import CoreData

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default)
    private var people: FetchedResults<Person>
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var scrollToBottom = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    // Scroll to the last message with animation
                    withAnimation {
                        if let lastMessage = messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 8) {
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                HStack {
                    TextField("Type your message...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(isLoading)
                        .focused($isFocused)
                        .onSubmit {
                            guard !inputText.isEmpty && !isLoading else { return }
                            Task {
                                await sendMessage()
                            }
                        }
                    
                    Button(action: {
                        Task {
                            await sendMessage()
                        }
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(inputText.isEmpty || isLoading)
                }
                .padding()
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            isFocused = true // Focus the text field when view appears
        }
    }
    
    private func sendMessage() async {
        guard !inputText.isEmpty else { return }
        
        let userMessage = ChatMessage(content: inputText, isUser: true, timestamp: Date())
        messages.append(userMessage)
        
        let messageToSend = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil
        
        do {
            // Create context about the data
            let context = generateContext()
            let response = try await AIService.shared.sendMessage(messageToSend, context: context)
            let aiMessage = ChatMessage(content: response, isUser: false, timestamp: Date())
            messages.append(aiMessage)
            isFocused = true // Refocus the text field after receiving response
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    private func generateContext() -> String {
        var context = "Current data in the system:\n"
        
        // Add information about people
        context += "\nPeople (\(people.count) total):\n"
        for person in people {
            context += "- \(person.name ?? "Unknown")"
            if let role = person.role {
                context += " (\(role))"
            }
            if let lastContact = person.lastContactDate {
                context += ", Last contacted: \(lastContact.formatted())"
            }
            if let scheduled = person.scheduledConversationDate {
                context += ", Next scheduled: \(scheduled.formatted())"
            }
            context += "\n"
            
            // Add recent conversations
            let conversations = person.conversationsArray.prefix(3)
            if !conversations.isEmpty {
                context += "  Recent conversations:\n"
                for conversation in conversations {
                    context += "  - \(conversation.date?.formatted() ?? "Unknown date"): \(conversation.notes?.prefix(100) ?? "No notes")\n"
                }
            }
        }
        
        return context
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
} 