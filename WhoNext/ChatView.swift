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
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Insights")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 4)
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.spring()),
                                    removal: .opacity.animation(.easeOut(duration: 0.2))
                                ))
                        }
                        
                        if isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .transition(.opacity)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
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
                
                HStack(spacing: 12) {
                    TextField("Type your message...", text: $inputText)
                        .textFieldStyle(CustomTextFieldStyle())
                        .focused($isFocused)
                        .disabled(isLoading)
                        .overlay(
                            HStack {
                                Spacer()
                                if !inputText.isEmpty {
                                    Button(action: { inputText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .imageScale(.small)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                }
                            }
                        )
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
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
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
            isFocused = true
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
            let context = generateContext()
            let response = try await AIService.shared.sendMessage(messageToSend, context: context)
            let aiMessage = ChatMessage(content: response, isUser: false, timestamp: Date())
            messages.append(aiMessage)
            isFocused = true
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
                    .background(
                        Group {
                            if message.isUser {
                                LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                Color(NSColor.controlBackgroundColor)
                            }
                        }
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(BubbleShape(isUser: message.isUser))
                
                HStack(spacing: 4) {
                    if !message.isUser {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

struct BubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path()
        
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        
        path.move(to: CGPoint(x: topLeft.x + radius, y: topLeft.y))
        
        // Top edge
        path.addLine(to: CGPoint(x: topRight.x - radius, y: topRight.y))
        path.addArc(center: CGPoint(x: topRight.x - radius, y: topRight.y + radius),
                   radius: radius,
                   startAngle: Angle(degrees: -90),
                   endAngle: Angle(degrees: 0),
                   clockwise: false)
        
        // Right edge
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - radius))
        path.addArc(center: CGPoint(x: bottomRight.x - radius, y: bottomRight.y - radius),
                   radius: radius,
                   startAngle: Angle(degrees: 0),
                   endAngle: Angle(degrees: 90),
                   clockwise: false)
        
        // Bottom edge
        if isUser {
            path.addLine(to: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y))
            path.addArc(center: CGPoint(x: bottomLeft.x + radius, y: bottomLeft.y - radius),
                       radius: radius,
                       startAngle: Angle(degrees: 90),
                       endAngle: Angle(degrees: 180),
                       clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y))
        }
        
        // Left edge
        path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + radius))
        path.addArc(center: CGPoint(x: topLeft.x + radius, y: topLeft.y + radius),
                   radius: radius,
                   startAngle: Angle(degrees: 180),
                   endAngle: Angle(degrees: 270),
                   clockwise: false)
        
        return path
    }
} 
