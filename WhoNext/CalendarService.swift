import Foundation
import EventKit

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let calendarID: String
    let notes: String?
    let location: String?
    let attendees: [String]?
}

class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let eventStore = EKEventStore()
    private var targetCalendar: EKCalendar?

    @Published var upcomingMeetings: [UpcomingMeeting] = []

    private init() {
        // Listen for calendar selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarSelectionChanged(_:)),
            name: Notification.Name("CalendarSelectionChanged"),
            object: nil
        )
    }
    
    @objc private func calendarSelectionChanged(_ notification: Notification) {
        if let calendarID = notification.object as? String, !calendarID.isEmpty {
            loadTargetCalendar(withID: calendarID)
        } else {
            let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
            loadTargetCalendar(withID: storedID)
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            print("[CalendarService] Using requestFullAccessToEvents API (macOS 14+)")
            eventStore.requestFullAccessToEvents { granted, error in
                print("[CalendarService] Calendar access granted: \(granted). Error: \(String(describing: error))")
                if granted {
                    self.logAvailableCalendars()
                    let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
                    self.loadTargetCalendar(withID: storedID)
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
                    let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
                    self.loadTargetCalendar(withID: storedID)
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

    private func loadTargetCalendar(withID id: String? = nil) {
        if let id = id, let exchangeCal = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) {
            targetCalendar = exchangeCal
            print("[CalendarService] Selected calendar with ID \(id): \(exchangeCal.title)")
        } else if let exchangeCal = eventStore.calendars(for: .event).first(where: { $0.source.title.lowercased().contains("exchange") }) {
            targetCalendar = exchangeCal
            print("[CalendarService] Selected Exchange calendar: \(exchangeCal.title) (ID: \(exchangeCal.calendarIdentifier))")
        } else if let first = eventStore.calendars(for: .event).first {
            targetCalendar = first
            print("[CalendarService] Selected fallback calendar: \(first.title) (ID: \(first.calendarIdentifier))")
        } else {
            print("[CalendarService] No calendars found!")
        }
    }

    func fetchUpcomingMeetings(daysAhead: Int = 7) {
        guard let calendar = targetCalendar else {
            print("[CalendarService] No target calendar set, attempting to reload...")
            let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
            loadTargetCalendar(withID: storedID)
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
                calendarID: event.calendar.calendarIdentifier,
                notes: event.notes,
                location: event.location,
                attendees: event.attendees?.compactMap { $0.name }
            )
        }
        print("[CalendarService] Found \(meetings.count) upcoming 1:1 meetings in calendar \(calendar.title)")
        DispatchQueue.main.async {
            self.upcomingMeetings = meetings
        }
    }
}
