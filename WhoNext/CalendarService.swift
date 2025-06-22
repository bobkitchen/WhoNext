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

    func requestAccess(completion: @escaping (Bool, Error?) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                if granted {
                    self.logAvailableCalendars()
                    let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
                    self.loadTargetCalendar(withID: storedID)
                }
                DispatchQueue.main.async {
                    completion(granted, error)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                if granted {
                    self.logAvailableCalendars()
                    let storedID = UserDefaults.standard.string(forKey: "selectedCalendarID")
                    self.loadTargetCalendar(withID: storedID)
                }
                DispatchQueue.main.async {
                    completion(granted, error)
                }
            }
        }
    }

    private func logAvailableCalendars() {
        let calendars = eventStore.calendars(for: .event)
        for _ in calendars {
        }
    }

    private func loadTargetCalendar(withID id: String? = nil) {
        if let id = id, let exchangeCal = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) {
            targetCalendar = exchangeCal
        } else if let exchangeCal = eventStore.calendars(for: .event).first(where: { $0.source.title.lowercased().contains("exchange") }) {
            targetCalendar = exchangeCal
        } else if let first = eventStore.calendars(for: .event).first {
            targetCalendar = first
        } else {
        }
    }

    func fetchUpcomingMeetings(daysAhead: Int = 7) {
        guard let calendar = targetCalendar else {
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
        DispatchQueue.main.async {
            self.upcomingMeetings = meetings
        }
    }
}
