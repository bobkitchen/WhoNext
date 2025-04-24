import Foundation
import EventKit

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let calendarID: String
}

class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let eventStore = EKEventStore()
    private var targetCalendar: EKCalendar?

    @Published var upcomingMeetings: [UpcomingMeeting] = []

    private init() {}

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            print("[CalendarService] Using requestFullAccessToEvents API (macOS 14+)")
            eventStore.requestFullAccessToEvents { granted, error in
                print("[CalendarService] Calendar access granted: \(granted). Error: \(String(describing: error))")
                if granted {
                    self.logAvailableCalendars()
                    self.loadTargetCalendar()
                }
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            print("[CalendarService] Using deprecated requestAccess API (macOS <14)")
            eventStore.requestAccess(to: .event) { granted, error in
                print("[CalendarService] Calendar access granted: \(granted). Error: \(String(describing: error))")
                if granted {
                    self.logAvailableCalendars()
                    self.loadTargetCalendar()
                }
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    private func logAvailableCalendars() {
        let calendars = eventStore.calendars(for: .event)
        print("[CalendarService] Available calendars:")
        for cal in calendars {
            print("  - Title: \(cal.title), Source: \(cal.source.title), Type: \(cal.type.rawValue), ID: \(cal.calendarIdentifier)")
        }
    }

    private func loadTargetCalendar() {
        let calendars = eventStore.calendars(for: .event)
        if let exchangeCal = calendars.first(where: { $0.source.title.lowercased().contains("exchange") }) {
            targetCalendar = exchangeCal
            print("[CalendarService] Selected Exchange calendar: \(exchangeCal.title) (ID: \(exchangeCal.calendarIdentifier))")
        } else if let first = calendars.first {
            targetCalendar = first
            print("[CalendarService] Selected fallback calendar: \(first.title) (ID: \(first.calendarIdentifier))")
        } else {
            print("[CalendarService] No calendars found!")
        }
    }

    func fetchUpcomingMeetings(daysAhead: Int = 7) {
        guard let calendar = targetCalendar else {
            print("[CalendarService] No target calendar set, attempting to reload...")
            loadTargetCalendar()
            return
        }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let events = eventStore.events(matching: predicate)
            .filter { $0.title.localizedCaseInsensitiveContains("1:1") }
            .sorted { $0.startDate < $1.startDate }
        let meetings = events.map { event in
            UpcomingMeeting(
                id: event.eventIdentifier,
                title: event.title,
                startDate: event.startDate,
                calendarID: event.calendar.calendarIdentifier
            )
        }
        print("[CalendarService] Found \(meetings.count) upcoming 1:1 meetings in calendar \(calendar.title)")
        DispatchQueue.main.async {
            self.upcomingMeetings = meetings
        }
    }
}
