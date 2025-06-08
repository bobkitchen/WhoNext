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
    
    // Email functionality
    func openEmailDraft(for person: Person) {
        // Get email templates from settings
        @AppStorage("emailSubjectTemplate") var subjectTemplate = "1:1 - {name} + BK"
        @AppStorage("emailBodyTemplate") var bodyTemplate = """
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
        
        print("Email button clicked - trying to open Outlook")
        
        // Launch Outlook and use keyboard automation
        launchOutlookAndAutomate(person: person, subject: subject, body: body)
    }
    
    private func launchOutlookAndAutomate(person: Person, subject: String, body: String) {
        let outlookBundleID = "com.microsoft.Outlook"
        let workspace = NSWorkspace.shared
        
        guard let outlookURL = workspace.urlForApplication(withBundleIdentifier: outlookBundleID) else {
            print("Outlook not found")
            return
        }
        
        workspace.openApplication(at: outlookURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            if let error = error {
                print("Error opening Outlook: \(error)")
                return
            }
            
            print("Successfully opened Outlook, waiting for it to be ready...")
            
            // Wait for Outlook to be ready, then automate
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.automateEmailCreation(person: person, subject: subject, body: body)
            }
        }
    }
    
    private func automateEmailCreation(person: Person, subject: String, body: String) {
        print("Starting keyboard automation")
        
        // Create CGEventSource
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            print("Failed to create event source")
            fallbackToCopyPaste(subject: subject, body: body)
            return
        }
        
        // Helper function to type text
        func typeText(_ text: String) {
            for char in text {
                let keyCode = keyCodeForCharacter(char)
                if keyCode != 0 {
                    let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
                    let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
                    keyDownEvent?.post(tap: .cghidEventTap)
                    keyUpEvent?.post(tap: .cghidEventTap)
                    usleep(10000) // Small delay between keystrokes
                }
            }
        }
        
        // Send Cmd+N to create new email
        print("Sending Cmd+N to create new email")
        sendKeyCombo(keyCode: 45, modifiers: .maskCommand) // Cmd+N
        
        // Wait for new email window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Generate email address from person's name
            let nameParts = person.name?.components(separatedBy: " ") ?? []
            let firstName = nameParts.first?.lowercased() ?? "unknown"
            let lastName = nameParts.count > 1 ? nameParts[1].lowercased() : "user"
            let emailAddress = "\(firstName).\(lastName)@rescue.org"
            
            // Type email address in To: field (cursor starts there)
            print("Typing email address: \(emailAddress)")
            typeText(emailAddress)
            
            // Tab to subject field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sendKeyCombo(keyCode: 48, modifiers: []) // Tab
                
                // Type subject
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("Typing subject: \(subject)")
                    typeText(subject)
                    
                    // Tab to body field
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.sendKeyCombo(keyCode: 48, modifiers: []) // Tab
                        
                        // Type body
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("Typing body: \(body)")
                            typeText(body)
                            print("Email automation completed")
                        }
                    }
                }
            }
        }
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
    
    private func sendKeyCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else { return }
        
        let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        
        keyDownEvent?.flags = modifiers
        keyUpEvent?.flags = modifiers
        
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
    }
    
    private func keyCodeForCharacter(_ character: Character) -> CGKeyCode {
        // Basic character to key code mapping
        switch character.lowercased().first {
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        case " ": return 49
        case ".": return 47
        case "@": return 22 // This is actually "2" with shift
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        default: return 0
        }
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
                message: Text("Press Cmd+N to create a new email, then paste (Cmd+V) the pre-filled content."),
                dismissButton: .default(Text("OK"))
            )
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
