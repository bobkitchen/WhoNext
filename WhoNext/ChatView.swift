import SwiftUI
import CoreData
import AppKit
import Down

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var people: [Person] = []
    @StateObject private var chatSession = ChatSessionHolder.shared.session
    @StateObject private var hybridAI = HybridAIService()
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
                        .frame(width: 24, height: 24)
                    Text("Chat Insights")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    
                    // AI Provider Status
                    Text(hybridAI.getProviderStatus())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
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
                    .padding(.horizontal, 12)
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
                .padding(.horizontal, 12)
                .padding(.top, 10)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
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
                .padding(12)
                .liquidGlassCard(
                    cornerRadius: 16,
                    elevation: .medium,
                    padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                    isInteractive: false
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
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
            InsightsOnboardingView()
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
            print("🔍 [Context] Generated context length: \(context.count) characters")
            print("🔍 [Context] Context preview: \(String(context.prefix(300)))...")
            let response = try await hybridAI.sendMessage(messageToSend, context: context)
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
        // Use centralized context service with current AI provider
        let context = ChatContextService.generateContext(
            for: message, 
            people: people, 
            provider: hybridAI.preferredProvider
        )
        
        // Optimize context for the current provider
        return ChatContextService.optimizeContextForProvider(context, provider: hybridAI.preferredProvider)
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
                    // Enhanced AI response bubble with proper markdown indentation
                    PopoutMarkdownTextView(markdown: message.content)
                        .frame(maxWidth: 400, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                                )
                        )
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

// Insights Onboarding View
struct InsightsOnboardingView: View {
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
                .padding(.horizontal, 12)
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

// Custom markdown renderer that preserves list indentation with proper sizing
struct PopoutMarkdownTextView: View {
    let markdown: String
    @State private var calculatedHeight: CGFloat = 0

    var body: some View {
        MarkdownTextViewWrapper(markdown: markdown, calculatedHeight: $calculatedHeight)
            .frame(height: max(calculatedHeight, 30))
    }
}

struct MarkdownTextViewWrapper: NSViewRepresentable {
    let markdown: String
    @Binding var calculatedHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        do {
            let down = try Down(markdownString: markdown)
            let attributedString = try down.toAttributedString()

            // Apply proper styling with indentation
            let mutableString = NSMutableAttributedString(attributedString: attributedString)
            let fullRange = NSRange(location: 0, length: mutableString.length)

            // Set base font
            mutableString.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: fullRange)
            mutableString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            // Configure paragraph styles for lists
            mutableString.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
                let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()

                // Get the text in this range to check if it's a list item
                let text = (mutableString.string as NSString).substring(with: range)

                // Detect and style numbered lists (1., 2., etc.)
                if text.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                    paragraphStyle.firstLineHeadIndent = 0
                    paragraphStyle.headIndent = 0
                    paragraphStyle.paragraphSpacing = 8
                    paragraphStyle.paragraphSpacingBefore = 4
                }
                // Detect and style bullet points with proper indentation
                else if text.hasPrefix("•") || text.hasPrefix("-") || text.hasPrefix("*") {
                    // Check indentation level based on leading whitespace
                    let leadingSpaces = text.prefix(while: { $0.isWhitespace }).count
                    let indentLevel = leadingSpaces / 2 // Assuming 2 spaces per indent level

                    let baseIndent: CGFloat = 20
                    let indentMultiplier: CGFloat = 20

                    paragraphStyle.firstLineHeadIndent = baseIndent + (CGFloat(indentLevel) * indentMultiplier)
                    paragraphStyle.headIndent = baseIndent + (CGFloat(indentLevel) * indentMultiplier) + 15
                    paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: paragraphStyle.headIndent)]
                    paragraphStyle.paragraphSpacing = 4
                }
                // Regular paragraph
                else {
                    paragraphStyle.paragraphSpacing = 8
                }

                mutableString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            }

            textView.textStorage?.setAttributedString(mutableString)

            // Calculate required height
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!)
            let height = (usedRect?.height ?? 0) + textView.textContainerInset.height * 2

            DispatchQueue.main.async {
                calculatedHeight = height
            }
        } catch {
            // Fallback to plain text
            textView.string = markdown

            // Calculate height for plain text
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!)
            let height = (usedRect?.height ?? 0) + textView.textContainerInset.height * 2

            DispatchQueue.main.async {
                calculatedHeight = height
            }
        }
    }
}
