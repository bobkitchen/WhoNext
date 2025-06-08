import SwiftUI
import CoreData
import AppKit

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var people: [Person] = []
    @StateObject private var chatSession = ChatSessionHolder.shared.session
    @FocusState private var isFocused: Bool
    @AppStorage("hasSeenChatOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    
    // Suggested prompts for empty state
    let suggestedPrompts = [
        "Who should I connect with this week?",
        "Show me people I haven't talked to recently",
        "Who are my key stakeholders?",
        "Suggest someone for a coffee chat",
        "Who should I follow up with?"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Listen for PeopleDidImport notification and refresh the FetchRequest
            EmptyView()
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PeopleDidImport"))) { _ in
                    fetchPeople()
                }
            
            // Title section - left aligned
            HStack {
                HStack(spacing: 8) {
                    Image("icon_lightbulb")
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Insights")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                Spacer()
                
                // Pop-out button
                Button(action: {
                    openPopoutChat()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 16, weight: .medium))
                        Text("Pop Out")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Messages or Empty State
            if chatSession.messages.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    // Header with dismiss button
                    HStack {
                        Spacer()
                        Button(action: { 
                            // Add a welcome message to dismiss the empty state
                            let welcomeMessage = ChatMessage(
                                content: "Hello! I'm here to help you stay connected with your network. Feel free to ask me anything about your contacts, meetings, or networking strategies.",
                                isUser: false,
                                timestamp: Date()
                            )
                            chatSession.messages.append(welcomeMessage)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("Ask me about your network")
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        
                        Text("I can help you stay connected")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Try asking:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        // Show only 3 prompts to save space
                        ForEach(Array(suggestedPrompts.prefix(3)), id: \.self) { prompt in
                            Button(action: { 
                                chatSession.inputText = prompt
                                isFocused = true
                                Task {
                                    await sendMessage()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "sparkle")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                    Text(prompt)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 300)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            } else {
                // Messages ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatSession.messages) { message in
                                MessageBubble(message: message)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            
                            // Enhanced loading indicator
                            if chatSession.isLoading {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        HStack(spacing: 6) {
                                            ForEach(0..<3) { index in
                                                Circle()
                                                    .fill(Color.accentColor.opacity(0.6))
                                                    .frame(width: 8, height: 8)
                                                    .scaleEffect(chatSession.isLoading ? 1.2 : 0.8)
                                                    .animation(
                                                        Animation.easeInOut(duration: 0.6)
                                                            .repeatForever()
                                                            .delay(Double(index) * 0.2),
                                                        value: chatSession.isLoading
                                                    )
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color(NSColor.controlBackgroundColor))
                                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                        )
                                        
                                        Text("AI is thinking...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .opacity(0.8)
                                    }
                                    .padding(.trailing, 16)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: chatSession.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = chatSession.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                if let error = chatSession.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                
                HStack(spacing: 12) {
                    HStack {
                        TextField("Ask about your network...", text: $chatSession.inputText)
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .disabled(chatSession.isLoading)
                            .onSubmit {
                                guard !chatSession.inputText.isEmpty && !chatSession.isLoading else { return }
                                Task {
                                    await sendMessage()
                                }
                            }
                        
                        if !chatSession.inputText.isEmpty {
                            Button(action: { chatSession.inputText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    
                    Button(action: {
                        Task {
                            await sendMessage()
                        }
                    }) {
                        if chatSession.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(chatSession.inputText.isEmpty ? .gray : .accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(chatSession.inputText.isEmpty || chatSession.isLoading)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: -2)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .alert("Error", isPresented: $chatSession.showError) {
            Button("OK") { }
        } message: {
            Text(chatSession.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            isFocused = true
            fetchPeople()
            if !hasSeenOnboarding {
                showOnboarding = true
                hasSeenOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
    
    private func sendMessage() async {
        guard !chatSession.inputText.isEmpty else { return }
        
        let userMessage = ChatMessage(content: chatSession.inputText, isUser: true, timestamp: Date())
        chatSession.messages.append(userMessage)
        
        let messageToSend = chatSession.inputText
        chatSession.inputText = ""
        chatSession.isLoading = true
        chatSession.errorMessage = nil
        
        do {
            let context = generateContext()
            let response = try await AIService.shared.sendMessage(messageToSend, context: context)
            let aiMessage = ChatMessage(content: response, isUser: false, timestamp: Date())
            chatSession.messages.append(aiMessage)
            isFocused = true
        } catch {
            chatSession.errorMessage = error.localizedDescription
            chatSession.showError = true
        }
        
        chatSession.isLoading = false
    }
    
    private func generateContext() -> String {
        var context = "Team Members and Conversations:\n\n"
        
        for person in people {
            let name = person.name ?? "Unknown"
            let role = person.role ?? "Unknown"
            let isDirectReport = person.isDirectReport
            let timezone = person.timezone ?? "Unknown"
            let scheduledDate = person.scheduledConversationDate
            let conversations = person.conversations as? Set<Conversation> ?? []
            
            context += "Person: \(name)\n"
            context += "Role: \(role)\n"
            context += "Direct Report: \(isDirectReport)\n"
            context += "Timezone: \(timezone)\n"
            
            // Add person's background notes
            if let personNotes = person.notes, !personNotes.isEmpty {
                context += "Background Notes: \(personNotes)\n"
            }
            
            if let scheduledDate = scheduledDate {
                context += "Next Scheduled Conversation: \(scheduledDate.formatted())\n"
            }
            
            context += "Number of Past Conversations: \(conversations.count)\n"
            
            if !conversations.isEmpty {
                context += "Recent Conversations:\n"
                let sortedConversations = conversations.sorted { 
                    ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
                }
                for conversation in sortedConversations.prefix(3) {
                    if let date = conversation.date {
                        context += "- Date: \(date.formatted())\n"
                        if let summary = conversation.summary {
                            context += "  Summary: \(summary)\n"
                        }
                        if let notes = conversation.notes {
                            context += "  Notes: \(notes)\n"
                        }
                    }
                }
            }
            context += "\n"
        }
        
        return context
    }
    
    private func fetchPeople() {
        let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
        do {
            people = try viewContext.fetch(fetchRequest)
        } catch {
            print("Failed to fetch people: \(error)")
            people = []
        }
    }
    
    private func openPopoutChat() {
        // Check if popout window already exists
        if let existingWindow = NSApp.windows.first(where: { $0 is PopoutChatWindow }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create new popout window with Core Data context
        let popoutWindow = PopoutChatWindow(context: viewContext)
        popoutWindow.makeKeyAndOrderFront(nil)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(message.content)
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)], 
                                startPoint: .topLeading, 
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: isHovered ? 8 : 4, x: 0, y: 2)
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                } else {
                    // Enhanced AI response bubble
                    Text(message.content)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 400, alignment: .leading)
                        .shadow(color: .black.opacity(0.08), radius: isHovered ? 6 : 3, x: 0, y: 1)
                        .scaleEffect(isHovered ? 1.01 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
                
                // Enhanced timestamp with better styling
                HStack(spacing: 4) {
                    if !message.isUser {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor.opacity(0.7))
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(isHovered ? 1.0 : 0.6)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
                .padding(.horizontal, 4)
            }
            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .onHover { hovering in
            isHovered = hovering
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

// Onboarding View
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Welcome to Insights")
                    .font(.title.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                OnboardingRow(
                    icon: "person.2.fill",
                    title: "Stay Connected",
                    description: "Get suggestions on who to reach out to based on your interaction history"
                )
                
                OnboardingRow(
                    icon: "calendar",
                    title: "Smart Scheduling",
                    description: "Find the best times to connect with team members"
                )
                
                OnboardingRow(
                    icon: "sparkles",
                    title: "AI-Powered Insights",
                    description: "Ask questions about your network and get personalized recommendations"
                )
                
                OnboardingRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Progress",
                    description: "Monitor your networking goals and maintain consistent connections"
                )
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(width: 500, height: 400)
    }
}

struct OnboardingRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
}
