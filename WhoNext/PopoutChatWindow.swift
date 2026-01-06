import SwiftUI
import AppKit
import CoreData

class PopoutChatWindow: NSWindow {
    init(context: NSManagedObjectContext) {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "WhoNext - Chat Insights"
        self.contentView = NSHostingView(rootView: PopoutChatView().environment(\.managedObjectContext, context))
        self.isReleasedWhenClosed = false
        self.center()
        
        // Set minimum size
        self.minSize = NSSize(width: 400, height: 500)
    }
}

struct PopoutChatView: View {
    @StateObject private var chatSession = ChatSessionHolder.shared.session
    @Environment(\.managedObjectContext) private var viewContext
    @State private var people: [Person] = []
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image("icon_lightbulb")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Chat Insights")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                Spacer()
                
                Button(action: {
                    if let window = NSApp.windows.first(where: { $0 is PopoutChatWindow }) {
                        window.close()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Messages area with fixed height
            if chatSession.messages.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Start a conversation")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Ask me anything about your network, meetings, or who you should connect with.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            
                            // Loading indicator
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
                    .onChange(of: chatSession.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = chatSession.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
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
                .padding()
            }
        }
        .onAppear {
            fetchPeople()
            isFocused = true
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
            let context = generateContext(for: messageToSend)
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
    
    private func generateContext(for message: String) -> String {
        // Add explicit instructions at the start with temporal clarity
        var context = """
        CRITICAL INSTRUCTIONS FOR AI ASSISTANT:

        You have access to TWO types of information:
        1. PAST CONVERSATION DATA (historical records from CoreData)
        2. FUTURE SCHEDULED MEETINGS (upcoming events from calendar)

        IMPORTANT RULES:
        - CLEARLY DISTINGUISH between past events and future events
        - NEVER invent or hallucinate dates, times, or locations not explicitly provided
        - NEVER mix past conversation data with future meeting metadata
        - If asked about "last meeting" or "previous meeting" → use ONLY past conversation data
        - If asked about "next meeting" or "upcoming meeting" → use ONLY future calendar data
        - If data looks suspicious or contradictory (e.g., meeting dated today with old content), MENTION this uncertainty
        - Use specific details from conversation notes and summaries, not generic responses
        - Quote or paraphrase actual meeting content when available

        """

        // === PAST CONVERSATIONS (Historical Data) ===
        context += "\n" + String(repeating: "=", count: 80)
        context += "\n=== HISTORICAL CONVERSATION DATA (PAST MEETINGS) ===\n"
        context += String(repeating: "=", count: 80) + "\n"

        // Use the same centralized context service as main chat
        let hybridAI = HybridAIService()
        let historicalContext = ChatContextService.generateContext(
            for: message,
            people: people,
            provider: hybridAI.preferredProvider
        )
        context += historicalContext

        // === DATA QUALITY WARNINGS ===
        let validationWarnings = validateContextIntegrity(people)
        if !validationWarnings.isEmpty {
            context += "\n\n" + String(repeating: "=", count: 80)
            context += "\n=== DATA QUALITY NOTES ===\n"
            context += String(repeating: "=", count: 80) + "\n"
            context += validationWarnings
        }

        // Optimize context for the current provider
        return ChatContextService.optimizeContextForProvider(context, provider: hybridAI.preferredProvider)
    }

    // Validate data integrity and flag suspicious dates
    private func validateContextIntegrity(_ people: [Person]) -> String {
        var warnings = ""
        let now = Date()
        let calendar = Calendar.current

        for person in people {
            if let conversations = person.conversations as? Set<Conversation> {
                for conv in conversations {
                    // Check for future dates
                    if let date = conv.date, date > now {
                        let daysFuture = calendar.dateComponents([.day], from: now, to: date).day ?? 0
                        warnings += "⚠️ SUSPICIOUS: Conversation with \(person.name ?? "Unknown") is dated \(daysFuture) days in the FUTURE (\(date.formatted())) - likely a data error\n"
                    }

                    // Check for today's date with extensive content
                    if let date = conv.date, calendar.isDateInToday(date),
                       let notes = conv.notes, notes.count > 1000 {
                        warnings += "⚠️ VERIFY: Conversation with \(person.name ?? "Unknown") is dated today but has extensive notes (\(notes.count) chars) - may be misdated\n"
                    }

                    // Check for major discrepancy between created date and meeting date
                    if let meetingDate = conv.date, let createdDate = conv.createdAt {
                        let daysDiff = abs(calendar.dateComponents([.day], from: meetingDate, to: createdDate).day ?? 0)
                        if daysDiff > 7 {
                            warnings += "⚠️ DATE MISMATCH: Conversation with \(person.name ?? "Unknown") dated \(meetingDate.formatted()) but created \(createdDate.formatted()) - \(daysDiff) day difference\n"
                        }
                    }
                }
            }
        }

        return warnings
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
}
