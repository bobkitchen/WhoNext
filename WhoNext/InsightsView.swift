import SwiftUI
import CoreData

struct InsightsView: View {
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    // Calendar integration
    @StateObject private var calendarService = CalendarService.shared
    
    @AppStorage("dismissedPeople") private var dismissedPeopleData: Data = Data()
    @State private var dismissedPeople: [UUID: Date] = [:]
    
    private var suggestedPeople: [Person] {
        let calendar = Calendar.current
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        
        // Get all non-direct reports, sorted alphabetically
        let nonDirectReports = people
            .filter { person in
                guard let name = person.name, !name.isEmpty else { return false }
                guard !person.isDirectReport else { return false }
                
                // Check if person was dismissed within the last month
                if let id = person.identifier,
                   let dismissedDate = dismissedPeople[id],
                   dismissedDate > oneMonthAgo {
                    return false
                }
                
                return true
            }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        
        // Sort by last contact date, putting people we haven't met with first
        return nonDirectReports
            .sorted { 
                let date1 = $0.lastContactDate ?? .distantPast
                let date2 = $1.lastContactDate ?? .distantPast
                return date1 < date2
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
        VStack(alignment: .leading, spacing: 24) {
            // Upcoming 1:1 Meetings
            VStack(alignment: .leading, spacing: 16) {
                Text("Upcoming 1:1s")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                if calendarService.upcomingMeetings.isEmpty {
                    Text("No upcoming 1:1s")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendarService.upcomingMeetings) { meeting in
                        HStack {
                            Text(meeting.title)
                            Spacer()
                            Text(meeting.startDate, style: .date)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .cardStyle()
            
            // Chat Interface
            ChatView()
                .frame(height: 300)
                .cardStyle()
            
            // Suggested People Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Follow-up Needed")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if suggestedPeople.isEmpty {
                    Text("No follow-ups needed")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .cardStyle()
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(suggestedPeople) { person in
                            PersonCardView(
                                person: person,
                                isFollowUp: true,
                                onDismiss: {
                                    if let id = person.identifier {
                                        dismissedPeople[id] = Date()
                                        if let encoded = try? JSONEncoder().encode(dismissedPeople) {
                                            dismissedPeopleData = encoded
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            // Coming Up Tomorrow Section
            if !comingUpTomorrow.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Coming Up Tomorrow")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(comingUpTomorrow) { person in
                            PersonCardView(
                                person: person,
                                isFollowUp: false,
                                onDismiss: nil
                            )
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(24)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let decoded = try? JSONDecoder().decode([UUID: Date].self, from: dismissedPeopleData) {
                dismissedPeople = decoded
            }
            calendarService.requestAccess { granted in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                }
            }
        }
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
    let isFollowUp: Bool
    let onDismiss: (() -> Void)?
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with avatar and name
            HStack(spacing: 12) {
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
                
                Spacer()
                
                if isFollowUp, let dismiss = onDismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Contact info
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
                Text("Meeting scheduled for \(scheduled.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .frame(width: 300, height: 120)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4)
    }
}
