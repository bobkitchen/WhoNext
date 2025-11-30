import SwiftUI
import CoreData
import AppKit

struct OverdueConversationsDetailView: View {
    let overdueRelationships: [PersonMetrics]
    @Environment(\.managedObjectContext) private var viewContext
    @State private var windowController: NSWindowController?
    @State private var showEmailInstructions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overdue Conversations")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(overdueRelationships.count) people haven't been contacted recently")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // Relationships List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(overdueRelationships, id: \.person.objectID) { personMetrics in
                        OverdueRelationshipRow(personMetrics: personMetrics)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.top)
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct OverdueRelationshipRow: View {
    let personMetrics: PersonMetrics
    @Environment(\.managedObjectContext) private var viewContext
    @State private var windowController: NSWindowController?
    @State private var showEmailInstructions = false
    
    private var daysSinceLastContact: Int {
        guard let lastDate = personMetrics.lastConversationDate else { return 999 }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 999
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            if let photoData = personMetrics.person.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(personMetrics.person.name?.prefix(1) ?? "?"))
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    )
            }
            
            // Person Info
            VStack(alignment: .leading, spacing: 4) {
                Text(personMetrics.person.name ?? "Unknown")
                    .font(.headline)
                    .fontWeight(.medium)
                
                if let role = personMetrics.person.role, !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("\(daysSinceLastContact) days ago")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(personMetrics.metrics.conversationCount) conversations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    openEmailDraft(for: personMetrics.person)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                        Text("Email")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    openPersonDetailWindow(for: personMetrics)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                        Text("View")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .alert(isPresented: $showEmailInstructions) {
            Alert(
                title: Text("Email Ready"),
                message: Text("The email content has been copied to your clipboard. Press Cmd+N in Outlook to create a new email, then paste (Cmd+V) the content."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func openEmailDraft(for person: Person) {
        // Get email templates from UserDefaults (AppStorage)
        let subjectTemplate = UserDefaults.standard.string(forKey: "emailSubjectTemplate") ?? "1:1 - {name} + BK"
        let bodyTemplate = UserDefaults.standard.string(forKey: "emailBodyTemplate") ?? """
        Hi {firstName},
        
        I wanted to follow up on our conversation and see how things are going.
        
        Would you have time for a quick chat this week?
        
        Best regards
        """
        
        let firstName = person.name?.components(separatedBy: " ").first ?? "there"
        let fullName = person.name ?? "Meeting"
        
        // Replace placeholders in templates
        let subject = subjectTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        let body = bodyTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        // Get email address
        let email = inferEmailFromName(person)
        
        // Open email using mailto (works with new Outlook)
        openEmailWithMailto(to: email, subject: subject, body: body)
    }
    
    private func openEmailWithMailto(to: String, subject: String, body: String) {
        // URL encode the components
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTo = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email parameters")
            fallbackToCopyPaste(subject: subject, body: body)
            return
        }
        
        let mailtoString = "mailto:\(encodedTo)?subject=\(encodedSubject)&body=\(encodedBody)"
        
        if let url = URL(string: mailtoString) {
            NSWorkspace.shared.open(url)
            print("✅ Email opened in default mail client for \(personMetrics.person.name ?? "person")")
        } else {
            fallbackToCopyPaste(subject: subject, body: body)
        }
    }
    
    private func inferEmailFromName(_ person: Person) -> String {
        // Simple email inference if not stored
        let nameParts = person.name?.components(separatedBy: " ") ?? []
        let firstName = nameParts.first?.lowercased() ?? "unknown"
        let lastName = nameParts.count > 1 ? nameParts[1].lowercased() : ""
        // Using organization domain
        return "\(firstName).\(lastName)@rescue.org"
    }
    
    private func fallbackToCopyPaste(subject: String, body: String) {
        let emailContent = "Subject: \(subject)\n\n\(body)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emailContent, forType: .string)
        
        DispatchQueue.main.async {
            self.showEmailInstructions = true
        }
    }
    
    private func openNewConversationWindow() {
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "New Conversation"
            window.center()
            
            let hostingView = NSHostingView(
                rootView: NewConversationWindowView(preselectedPerson: personMetrics.person)
                    .environment(\.managedObjectContext, viewContext)
            )
            window.contentView = hostingView
            
            // Create window controller to manage lifecycle
            let controller = NSWindowController(window: window)
            controller.showWindow(nil)
            
            // Store reference to keep window alive
            self.windowController = controller
            
            // Activate app to ensure window focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func openPersonDetailWindow(for personMetrics: PersonMetrics) {
        DispatchQueue.main.async {
            // Get the person's objectID to ensure we can fetch it in the new context
            let personObjectID = personMetrics.person.objectID
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = personMetrics.person.name ?? "Person Detail"
            window.center()
            
            // Use the shared view context
            let sharedContext = PersistenceController.shared.container.viewContext
            
            // Fetch the person in the shared context
            if let person = try? sharedContext.existingObject(with: personObjectID) as? Person {
                let hostingView = NSHostingView(
                    rootView: PersonDetailView(person: person)
                        .environment(\.managedObjectContext, sharedContext)
                )
                window.contentView = hostingView
                
                // Create window controller to manage lifecycle
                let controller = NSWindowController(window: window)
                controller.showWindow(nil)
                
                // Store reference to keep window alive
                self.windowController = controller
                
                // Activate app to ensure window focus
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

struct OverdueConversationsDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let person = Person(context: context)
        person.name = "Jane Smith"
        person.role = "Product Manager"
        
        let conversationMetrics = ConversationMetrics(
            averageDuration: 30.0,
            totalDuration: 90.0,
            conversationCount: 3,
            averageSentimentPerMinute: 0.6,
            optimalDurationRange: 25...45
        )
        
        let metrics = PersonMetrics(
            person: person,
            metrics: conversationMetrics,
            healthScore: 0.6,
            trendDirection: "stable",
            lastConversationDate: Calendar.current.date(byAdding: .day, value: -45, to: Date()),
            daysSinceLastConversation: 45,
            relationshipType: .directReport,
            isOverdue: true,
            contextualInsights: ["This is a sample overdue conversation insight"]
        )
        
        return OverdueConversationsDetailView(overdueRelationships: [metrics])
            .environment(\.managedObjectContext, context)
    }
}