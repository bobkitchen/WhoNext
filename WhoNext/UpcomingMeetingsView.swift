import SwiftUI
import CoreData

struct UpcomingMeetingsView: View {
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    @StateObject private var calendarService = CalendarService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeaderView(
                icon: "calendar.badge.clock",
                title: "Upcoming Meetings",
                count: upcomingMeetingsThisWeek.count
            )
            
            if upcomingMeetingsThisWeek.isEmpty {
                EmptyStateCard(
                    icon: "calendar.badge.clock",
                    title: "No upcoming meetings",
                    subtitle: "Your calendar is clear for this week"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(upcomingMeetingsThisWeek, id: \.id) { meeting in
                        UpcomingMeetingCard(
                            meeting: meeting,
                            matchedPerson: people.first { person in
                                meeting.attendees?.contains { attendee in
                                    attendee.lowercased().contains(person.name?.lowercased() ?? "")
                                } ?? false
                            }
                        ) {
                            if let matchedPerson = people.first(where: { person in
                                meeting.attendees?.contains { attendee in
                                    attendee.lowercased().contains(person.name?.lowercased() ?? "")
                                } ?? false
                            }) {
                                selectedPerson = matchedPerson
                                selectedPersonID = matchedPerson.identifier
                                selectedTab = .people
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            calendarService.requestAccess { granted, error in
                if granted {
                    calendarService.fetchUpcomingMeetings()
                } else {
                    // Handle access denied or error
                    if let error = error {
                        print("Calendar access error: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Computed Properties
extension UpcomingMeetingsView {
    private var upcomingMeetingsThisWeek: [UpcomingMeeting] {
        let calendar = Calendar.current
        let now = Date()
        let endDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        return calendarService.upcomingMeetings.filter { meeting in
            meeting.startDate >= now && meeting.startDate < endDate
        }
    }
}

#Preview {
    UpcomingMeetingsView(
        selectedPersonID: .constant(nil),
        selectedPerson: .constant(nil),
        selectedTab: .constant(.meetings)
    )
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}