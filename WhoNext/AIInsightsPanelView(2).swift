import SwiftUI
import Down
import AppKit

struct AIInsightsPanelView: View {
    @Binding var chatInput: String
    @FocusState.Binding var isFocused: Bool

    @StateObject private var chatSession = ChatSessionHolder.shared.session
    @StateObject private var hybridAI = HybridAIService()
    @StateObject private var calendarService = CalendarService.shared
    @AppStorage("isChatExpanded") private var isExpanded = false
    @State private var chatWindow: NSWindow?

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    // Quick action prompts
    let quickPrompts = [
        (icon: "bubble.left", text: "Who should I talk to today?"),
        (icon: "calendar", text: "Prepare me for tomorrow's meetings"),
        (icon: "exclamationmark.triangle", text: "Show relationships needing attention"),
        (icon: "chart.line.uptrend.xyaxis", text: "How is my network health?")
    ]

    var body: some View {
        // Outer container with margins
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 18))
                    Text("AI Insights")
                        .font(.system(size: 18, weight: .semibold))

                    // Provider status
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
                    openChatWindow()
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Open in separate window")

                // Expand/Collapse button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse chat" : "Expand chat")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Chat messages - show last 3 in compact mode, all in expanded mode
            if !chatSession.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            let messagesToShow = isExpanded ? chatSession.messages : Array(chatSession.messages.suffix(3))
                            ForEach(messagesToShow) { message in
                                ChatMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .frame(height: isExpanded ? 300 : 140)
                    .frame(maxWidth: .infinity)
                    .onChange(of: chatSession.messages.count) { _ in
                        if let lastMessage = chatSession.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                // Empty state - show quick prompts
                VStack(spacing: 12) {
                    Text("Ask me about your network")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Quick action prompts - horizontal scrollable
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickPrompts, id: \.text) { prompt in
                                Button(action: {
                                    chatInput = prompt.text
                                    isFocused = true
                                    Task {
                                        await sendMessage()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: prompt.icon)
                                            .font(.caption)
                                        Text(prompt.text)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Ask about your network...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                Button(action: {
                    Task {
                        await sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(chatInput.isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(chatInput.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // Send message function
    private func sendMessage() async {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(
            content: chatInput,
            isUser: true,
            timestamp: Date()
        )

        chatSession.messages.append(userMessage)
        let currentInput = chatInput
        chatInput = ""

        do {
            // Build comprehensive context
            let context = buildContext(for: currentInput)

            let response = try await hybridAI.sendMessage(currentInput, context: context)
            let aiMessage = ChatMessage(
                content: response,
                isUser: false,
                timestamp: Date()
            )
            chatSession.messages.append(aiMessage)
        } catch {
            let errorMessage = ChatMessage(
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                isUser: false,
                timestamp: Date()
            )
            chatSession.messages.append(errorMessage)
        }
    }

    // Build context from people, conversations, and meetings
    private func buildContext(for message: String) -> String {
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

        // Get base context from ChatContextService
        let peopleArray = Array(people)
        let historicalContext = ChatContextService.generateContext(
            for: message,
            people: peopleArray,
            provider: hybridAI.preferredProvider
        )
        context += historicalContext

        // === FUTURE MEETINGS (Calendar Data) ===
        let meetingContext = buildMeetingContext(for: message)
        if !meetingContext.isEmpty {
            context += "\n\n" + String(repeating: "=", count: 80)
            context += "\n=== UPCOMING SCHEDULED MEETINGS (FUTURE EVENTS) ===\n"
            context += String(repeating: "=", count: 80)
            context += meetingContext
        }

        // === DATA QUALITY WARNINGS ===
        let validationWarnings = validateContextIntegrity(peopleArray)
        if !validationWarnings.isEmpty {
            context += "\n\n" + String(repeating: "=", count: 80)
            context += "\n=== DATA QUALITY NOTES ===\n"
            context += String(repeating: "=", count: 80) + "\n"
            context += validationWarnings
        }

        // Debug logging
        print("📝 [AI Context] Total context length: \(context.count) characters")
        print("📝 [AI Context] Full context being sent to AI:")
        print("=" + String(repeating: "=", count: 80))
        print(context)
        print("=" + String(repeating: "=", count: 80))

        if context.contains("Notes:") {
            print("✅ [AI Context] Context includes conversation notes")
        } else {
            print("❌ [AI Context] WARNING: No conversation notes found in context")
        }

        return context
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

    // Build meeting-specific context
    private func buildMeetingContext(for message: String) -> String {
        let lowercased = message.lowercased()
        let isMeetingQuery = lowercased.contains("meeting") ||
                            lowercased.contains("prepare") ||
                            lowercased.contains("tomorrow") ||
                            lowercased.contains("upcoming") ||
                            lowercased.contains("calendar")

        guard isMeetingQuery else { return "" }

        var context = """

        UPCOMING MEETINGS AND CALENDAR:

        """

        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: tomorrow)) ?? tomorrow

        // Get meetings for tomorrow
        let tomorrowMeetings = calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= calendar.startOfDay(for: tomorrow) && meeting.startDate < endOfTomorrow
        }

        // Get upcoming meetings (next 7 days)
        let upcomingMeetings = calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= now && meeting.startDate < calendar.date(byAdding: .day, value: 7, to: now)!
        }.sorted { $0.startDate < $1.startDate }

        if !tomorrowMeetings.isEmpty {
            context += "TOMORROW'S MEETINGS:\n"
            for meeting in tomorrowMeetings.sorted(by: { $0.startDate < $1.startDate }) {
                context += "\n- \(meeting.title)"
                context += "\n  Time: \(meeting.startDate.formatted(date: .omitted, time: .shortened))"

                if let attendees = meeting.attendees, !attendees.isEmpty {
                    context += "\n  Attendees: \(attendees.joined(separator: ", "))"

                    // Find matching people and their conversation history
                    for attendee in attendees {
                        if let matchedPerson = people.first(where: { person in
                            guard let personName = person.name else { return false }
                            return attendee.lowercased().contains(personName.lowercased()) ||
                                   personName.lowercased().contains(attendee.lowercased())
                        }) {
                            context += "\n\n  CONTEXT FOR \(matchedPerson.name ?? attendee):"
                            if let role = matchedPerson.role {
                                context += "\n    Role: \(role)"
                            }

                            // Recent conversations with detailed context
                            let conversations = matchedPerson.conversationsArray
                            if !conversations.isEmpty {
                                // Show more conversations (up to 4) for better context
                                let recentConvs = conversations.prefix(4)
                                context += "\n    Recent Conversation History:"
                                for conv in recentConvs {
                                    if let date = conv.date {
                                        let daysSince = calendar.dateComponents([.day], from: date, to: now).day ?? 0
                                        context += "\n      • \(date.formatted(date: .abbreviated, time: .omitted)) (\(daysSince) days ago)"

                                        // Include summary
                                        if let summary = conv.summary, !summary.isEmpty {
                                            context += "\n        Summary: \(summary)"
                                        }

                                        // Include key topics if available
                                        if let topics = conv.keyTopics, !topics.isEmpty {
                                            context += "\n        Topics: \(topics.joined(separator: ", "))"
                                        }

                                        // Include detailed notes if available (full content for better context)
                                        if let notes = conv.notes, !notes.isEmpty {
                                            context += "\n        Notes: \(notes)"
                                        }

                                        // Include sentiment/engagement if meaningful
                                        if let engagement = conv.engagementLevel, !engagement.isEmpty {
                                            context += "\n        Engagement: \(engagement)"
                                        }
                                    }
                                }
                            } else {
                                context += "\n    No recent conversations recorded"
                            }
                        }
                    }
                }
                context += "\n"
            }
        }

        if !upcomingMeetings.isEmpty && upcomingMeetings.count > tomorrowMeetings.count {
            context += "\n\nOTHER UPCOMING MEETINGS (Next 7 Days):\n"
            let otherMeetings = upcomingMeetings.filter { meeting in
                !tomorrowMeetings.contains(where: { $0.id == meeting.id })
            }
            for meeting in otherMeetings.prefix(5) {
                context += "\n- \(meeting.title)"
                context += " - \(meeting.startDate.formatted(date: .abbreviated, time: .shortened))"
                if let attendees = meeting.attendees, !attendees.isEmpty {
                    context += " (with \(attendees.joined(separator: ", ")))"
                }
            }
        }

        return context
    }

    // Open chat in separate window
    private func openChatWindow() {
        // Check if window already exists
        if let existingWindow = chatWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let window = PopoutChatWindow(context: viewContext)
        window.makeKeyAndOrderFront(nil)
        chatWindow = window
    }
}

// Simple chat message row component
struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(16)
                        .textSelection(.enabled)
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundColor(.purple)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    // Use custom markdown view that preserves formatting
                    MarkdownTextView(markdown: message.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 4)
    }
}

// Custom markdown renderer that preserves list indentation with proper sizing
struct MarkdownTextView: View {
    let markdown: String
    @State private var calculatedHeight: CGFloat = 0

    var body: some View {
        MarkdownTextViewRepresentable(markdown: markdown, calculatedHeight: $calculatedHeight)
            .frame(height: max(calculatedHeight, 30))
    }
}

struct MarkdownTextViewRepresentable: NSViewRepresentable {
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
            mutableString.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
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

#Preview {
    struct PreviewWrapper: View {
        @State private var chatInput = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            AIInsightsPanelView(
                chatInput: $chatInput,
                isFocused: $isFocused
            )
            .frame(height: 280)
        }
    }

    return PreviewWrapper()
}
