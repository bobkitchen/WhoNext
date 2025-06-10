import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct PersonDetailView: View {
    @ObservedObject var person: Person
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow

    @FetchRequest private var conversations: FetchedResults<Conversation>

    @State private var isGeneratingBrief = false
    @State private var preMeetingBrief: [UUID: String] = [:]
    @State private var briefError: String? = nil
    @AppStorage("openaiApiKey") private var apiKey: String = ""

    init(person: Person) {
        self.person = person
        _conversations = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)],
            predicate: NSPredicate(format: "person == %@", person),
            animation: .default
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                notesView
                sentimentAnalyticsView
                preMeetingBriefView
                conversationsView
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ConversationSaved"))) { _ in
            // Refresh the managed object context to pick up new conversations
            viewContext.refreshAllObjects()
        }
    }
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 20) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemGray).opacity(0.15))
                    .frame(width: 64, height: 64)
                
                if let data = person.photo, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                        .frame(width: 64, height: 64)
                } else {
                    Text(person.initials)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            // Person Info
            VStack(alignment: .leading, spacing: 6) {
                Text(person.name ?? "Unnamed")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if let timezone = person.timezone, !timezone.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(timezone)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                if (person.value(forKey: "isDirectReport") as? Bool) == true {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("Direct Report")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                // LinkedIn Search Button
                Button(action: searchLinkedIn) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                        Text("Find on LinkedIn")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Edit Button
                Button(action: openEditWindow) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                        Text("Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    @ViewBuilder
    private var notesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text("Profile Notes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                
                // Quick tip for LinkedIn info
                Text("💡 Tip: Use 'Find on LinkedIn' button above, then copy/paste profile info here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            if let notes = person.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No profile information available")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text("Click 'Find on LinkedIn' above to search for this person, then copy relevant details (job history, education, etc.) and paste them in the Edit view.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var sentimentAnalyticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Conversation Analytics")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("(\(conversations.count) conversations)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if conversations.isEmpty {
                // Show placeholder when no conversations
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No conversation data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Start a conversation to see analytics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                // Analytics Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    // Health Score Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundColor(healthScoreColor)
                            Text("Health Score")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(String(format: "%.1f", relationshipHealthScore))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(healthScoreColor)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Average Sentiment Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "face.smiling.fill")
                                .font(.system(size: 12))
                                .foregroundColor(averageSentimentColor)
                            Text("Avg Sentiment")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(averageSentimentLabel)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(averageSentimentColor)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Total Conversations Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                            Text("Conversations")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(conversations.count)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Detailed Analytics
                ConversationDurationView(person: person)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    private var relationshipHealthScore: Double {
        guard let metrics = ConversationMetricsCalculator.shared.calculateMetrics(for: person) else {
            return 0.0
        }
        return metrics.healthScore
    }
    
    private var healthScoreColor: Color {
        let score = relationshipHealthScore
        if score >= 0.7 { return .green }
        else if score >= 0.4 { return .orange }
        else { return .red }
    }
    
    private var averageSentiment: Double {
        let sentiments = conversations.compactMap { conversation in
            conversation.value(forKey: "sentimentScore") as? Double
        }
        guard !sentiments.isEmpty else { return 0.0 }
        return sentiments.reduce(0, +) / Double(sentiments.count)
    }
    
    private var averageSentimentLabel: String {
        let sentiment = averageSentiment
        if sentiment >= 0.6 { return "Positive" }
        else if sentiment >= 0.4 { return "Neutral" }
        else if sentiment >= 0.2 { return "Mixed" }
        else { return "Negative" }
    }
    
    private var averageSentimentColor: Color {
        let sentiment = averageSentiment
        if sentiment >= 0.6 { return .green }
        else if sentiment >= 0.4 { return .blue }
        else if sentiment >= 0.2 { return .orange }
        else { return .red }
    }
    
    @ViewBuilder
    private var preMeetingBriefView: some View {
        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Pre-Meeting Brief")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let brief = preMeetingBrief[person.identifier ?? UUID()], !brief.isEmpty {
                        Button(action: {
                            copyToClipboard(brief)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 10))
                                Text("Copy")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: generatePreMeetingBrief) {
                            HStack(spacing: 6) {
                                if isGeneratingBrief {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                }
                                Text(isGeneratingBrief ? "Generating..." : "Generate")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isGeneratingBrief)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var conversationsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Conversations")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: openNewConversationWindow) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("New")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if conversations.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    VStack(spacing: 8) {
                        Text("No conversations yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Start your first conversation to begin building insights")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(action: openNewConversationWindow) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                            Text("Add First Conversation")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Conversation List
                LazyVStack(spacing: 12) {
                    ForEach(conversations) { conversation in
                        ConversationRowView(conversation: conversation)
                    }
                }
            }
        }
    }
    
    private func openEditWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit \(person.name ?? "Person")"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PersonEditView(
                person: person,
                onSave: { window.close() },
                onCancel: { window.close() }
            )
            .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
    
    private func openNewConversationWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Conversation with \(person.name ?? "Person")"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: NewConversationWindowView(
                preselectedPerson: person,
                onSave: { window.close() },
                onCancel: { window.close() }
            )
            .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
    
    private func generatePreMeetingBrief() {
        guard !apiKey.isEmpty else {
            briefError = "OpenAI API key is required. Please set it in Settings."
            return
        }
        
        isGeneratingBrief = true
        preMeetingBrief[person.identifier ?? UUID()] = nil
        briefError = nil
        
        PreMeetingBriefService.generateBrief(for: person, apiKey: apiKey) { result in
            DispatchQueue.main.async {
                self.isGeneratingBrief = false
                switch result {
                case .success(let brief):
                    self.preMeetingBrief[self.person.identifier ?? UUID()] = brief
                case .failure(let error):
                    self.briefError = error.localizedDescription
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func searchLinkedIn() {
        // Construct LinkedIn search URL with person's name and role
        var searchQuery = person.name ?? ""
        
        if let role = person.role, !role.isEmpty {
            searchQuery += " " + role
        }
        
        // URL encode the search query
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // LinkedIn search URL
        let linkedInSearchURL = "https://www.linkedin.com/search/results/people/?keywords=\(encodedQuery)"
        
        // Open LinkedIn search in default browser
        if let url = URL(string: linkedInSearchURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dateIndicator
            conversationContent
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            openConversationWindow()
        }
        .contextMenu {
            Button(action: openConversationWindow) {
                Label("Open in Window", systemImage: "macwindow")
            }
            
            Divider()
            
            Button(action: deleteConversation) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var dateIndicator: some View {
        VStack(spacing: 4) {
            if let date = conversation.date {
                Text(dayFormatter.string(from: date))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(monthFormatter.string(from: date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 50)
        .padding(.vertical, 4)
    }
    
    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            durationAndEngagementInfo
            summaryOrNotes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var headerRow: some View {
        HStack {
            Text(conversationTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
            
            // Sentiment indicator
            if conversation.value(forKey: "lastSentimentAnalysis") != nil {
                sentimentIndicator
            }
            
            if let date = conversation.date {
                Text(timeFormatter.string(from: date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var durationAndEngagementInfo: some View {
        let duration = conversation.value(forKey: "duration") as? Int16 ?? 0
        if duration > 0 || conversation.value(forKey: "lastSentimentAnalysis") != nil {
            HStack(spacing: 12) {
                if duration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(duration)m")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let engagementLevel = conversation.value(forKey: "engagementLevel") as? String {
                    HStack(spacing: 4) {
                        Image(systemName: engagementIcon(engagementLevel))
                            .font(.system(size: 10))
                            .foregroundColor(engagementColor(engagementLevel))
                        Text(engagementLevel.capitalized)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var summaryOrNotes: some View {
        if let summary = conversation.summary, !summary.isEmpty {
            Text(summary)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
        } else if let notes = conversation.notes, !notes.isEmpty {
            Text(notes)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
    }
    
    private var conversationTitle: String {
        if let summary = conversation.summary, !summary.isEmpty {
            // Extract first line as title
            let firstLine = summary.components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty ? "Conversation" : firstLine
        } else if let notes = conversation.notes, !notes.isEmpty {
            let firstLine = notes.components(separatedBy: .newlines).first ?? ""
            return firstLine.isEmpty ? "Conversation" : firstLine
        }
        return "Conversation"
    }
    
    private var sentimentIndicator: some View {
        Circle()
            .fill(sentimentColor)
            .frame(width: 8, height: 8)
    }
    
    private var sentimentColor: Color {
        let score = conversation.value(forKey: "sentimentScore") as? Double ?? 0.0
        if score > 0.3 {
            return .green
        } else if score < -0.3 {
            return .red
        } else {
            return .orange
        }
    }
    
    private func openConversationWindow() {
        // Open conversation in new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Conversation - \(conversationTitle)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: conversation)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
    
    private func deleteConversation() {
        viewContext.delete(conversation)
        try? viewContext.save()
    }
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func engagementIcon(_ engagementLevel: String) -> String {
        switch engagementLevel.lowercased() {
        case "high":
            return "flame.fill"
        case "medium":
            return "circle.fill"
        case "low":
            return "circle"
        default:
            return "circle"
        }
    }
    
    private func engagementColor(_ engagementLevel: String) -> Color {
        switch engagementLevel.lowercased() {
        case "high":
            return .green
        case "medium":
            return .orange
        case "low":
            return .red
        default:
            return .secondary
        }
    }
}
