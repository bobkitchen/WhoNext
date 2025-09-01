import Foundation
import EventKit
import AppKit

// MARK: - Apple Calendar Provider
/// Implementation of CalendarProvider using EventKit for Apple Calendar
class AppleCalendarProvider: CalendarProvider {
    
    // MARK: - Properties
    private let eventStore = EKEventStore()
    private var targetCalendar: EKCalendar?
    
    var providerName: String {
        return "Apple Calendar"
    }
    
    var isAuthorized: Bool {
        get async {
            if #available(macOS 14.0, *) {
                return EKEventStore.authorizationStatus(for: .event) == .fullAccess
            } else {
                return EKEventStore.authorizationStatus(for: .event) == .authorized
            }
        }
    }
    
    // MARK: - Public Methods
    
    func requestAccess() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    func fetchUpcomingMeetings(daysAhead: Int) async throws -> [UpcomingMeeting] {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        // Use all calendars if no specific calendar is selected
        let calendarsToSearch = targetCalendar != nil ? [targetCalendar!] : eventStore.calendars(for: .event)
        
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start)!
        
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendarsToSearch
        )
        
        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        
        return events.map { event in
            // Extract attendee information including emails
            let attendeeInfo = event.attendees?.compactMap { attendee in
                // Try to extract email from URL (mailto:)
                let urlString = attendee.url.absoluteString
                if urlString.hasPrefix("mailto:") {
                    let email = String(urlString.dropFirst(7)) // Remove "mailto:"
                    return email
                }
                // Fall back to name if no email
                if let name = attendee.name, !name.isEmpty {
                    return name
                }
                return nil
            }
            
            return UpcomingMeeting(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                calendarID: event.calendar.calendarIdentifier,
                notes: event.notes,
                location: event.location,
                attendees: attendeeInfo
            )
        }
    }
    
    func getAvailableCalendars() async throws -> [CalendarInfo] {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        let calendars = eventStore.calendars(for: .event)
        
        return calendars.map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: calendar.color?.hexString,
                isDefault: calendar.isSubscribed == false && calendar.type == .local,
                accountName: calendar.source.title,
                metadata: [
                    "sourceType": calendar.source.sourceType.rawValue,
                    "allowsModification": calendar.allowsContentModifications
                ]
            )
        }
    }
    
    func setActiveCalendar(calendarID: String) async throws {
        guard await isAuthorized else {
            throw CalendarProviderError.notAuthorized
        }
        
        if let calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarID }) {
            targetCalendar = calendar
        } else {
            throw CalendarProviderError.invalidCalendarID
        }
    }
    
    func signOut() async throws {
        // Not applicable for Apple Calendar - it uses system permissions
        // Just clear the selected calendar
        targetCalendar = nil
    }
    
    // MARK: - Helper Methods
    
    /// Load a specific calendar by ID or fall back to defaults
    func loadTargetCalendar(withID id: String? = nil) {
        if let id = id, 
           let calendar = eventStore.calendars(for: .event).first(where: { $0.calendarIdentifier == id }) {
            targetCalendar = calendar
        } else if let exchangeCal = eventStore.calendars(for: .event).first(where: { 
            $0.source.title.lowercased().contains("exchange") 
        }) {
            // Prefer Exchange calendar if available
            targetCalendar = exchangeCal
        } else if let first = eventStore.calendars(for: .event).first {
            // Fall back to first available calendar
            targetCalendar = first
        }
    }
}

// MARK: - Extensions

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "#000000" }
        
        let red = Int(rgbColor.redComponent * 255)
        let green = Int(rgbColor.greenComponent * 255)
        let blue = Int(rgbColor.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}