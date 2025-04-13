import SwiftUI
import CoreData

struct InsightsView: View {
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    )
    private var people: FetchedResults<Person>
    
    private var suggestedPeople: [Person] {
        people
            .filter { $0.name != nil }
            .sorted {
                ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast)
            }
            .prefix(2)
            .map { $0 }
    }
    
    private var comingUpTomorrow: [Person] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return people.filter {
            guard let scheduled = $0.scheduledConversationDate else { return false }
            return calendar.isDate(scheduled, inSameDayAs: tomorrow)
        }
    }
    
    @State private var showingCalendar: Person? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Insights")
                .font(.largeTitle)
                .bold()
            
            // Chat Interface
            ChatView()
                .frame(height: 300)
            
            // Suggested People Section
            if suggestedPeople.isEmpty {
                Text("No suggestions available yet.")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested People to Talk To Next")
                        .font(.title2)
                        .bold()
                    
                    HStack(spacing: 12) {
                        ForEach(suggestedPeople, id: \.self) { person in
                            PersonCardView(person: person, showingCalendar: $showingCalendar)
                        }
                    }
                }
            }
            
            // Coming Up Tomorrow Section
            if !comingUpTomorrow.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Coming Up Tomorrow")
                        .font(.title2)
                        .bold()
                    
                    HStack(spacing: 12) {
                        ForEach(comingUpTomorrow, id: \.self) { person in
                            Button(action: {
                                openConversationWindow(for: person)
                            }) {
                                PersonCardView(person: person, showingCalendar: $showingCalendar)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func openConversationWindow(for person: Person) {
        let newConversation = Conversation(context: viewContext)
        newConversation.date = Date()
        newConversation.person = person
        newConversation.uuid = UUID()
        
        person.scheduledConversationDate = nil
        try? viewContext.save()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ConversationDetailView.formattedWindowTitle(for: newConversation, person: person)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: newConversation, isInitiallyEditing: true)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
}

struct PersonCardView: View {
    let person: Person
    @Binding var showingCalendar: Person?
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .overlay(Text(person.initials).foregroundColor(.white).font(.subheadline))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name ?? "Unknown")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let role = person.role {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let lastDate = person.lastContactDate {
                Text("Last contacted on \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                Text("Never contacted")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            if let scheduled = person.scheduledConversationDate {
                Text("📅 Scheduled for \(scheduled.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            Button("📅 Schedule") {
                showingCalendar = person
            }
            .font(.caption2)
            .popover(item: $showingCalendar) { person in
                VStack {
                    DatePicker(
                        "Schedule Date",
                        selection: Binding(
                            get: { person.scheduledConversationDate ?? Date() },
                            set: { newDate in
                                person.scheduledConversationDate = newDate
                                try? viewContext.save()
                                showingCalendar = nil
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
                .frame(width: 220)
                .padding(12)
            }
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var role: String
            var content: String
            var refusal: String?
            var annotations: [String]?
        }
        var index: Int
        var message: Message
        var logprobs: String?
        var finish_reason: String
    }
    
    struct UsageDetails: Decodable {
        var cached_tokens: Int?
        var audio_tokens: Int?
    }
    
    struct CompletionDetails: Decodable {
        var reasoning_tokens: Int?
        var audio_tokens: Int?
        var accepted_prediction_tokens: Int?
        var rejected_prediction_tokens: Int?
    }
    
    struct Usage: Decodable {
        var prompt_tokens: Int
        var completion_tokens: Int
        var total_tokens: Int
        var prompt_tokens_details: UsageDetails?
        var completion_tokens_details: CompletionDetails?
    }
    
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [Choice]
    var usage: Usage
    var service_tier: String?
    var system_fingerprint: String?
}

extension Person {
    var conversationsArray: [Conversation] {
        let set = conversations as? Set<Conversation> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    var lastContactDate: Date? {
        conversationsArray.first?.date
    }
}

extension Person {
    var initials: String {
        let components = (name ?? "").split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined()
    }
}
