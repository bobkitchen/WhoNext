import Foundation
import AppKit

/// Lightweight meeting model shared between main app and widget via App Groups
struct SharedMeeting: Codable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendeeCount: Int
    let isOneOnOne: Bool
    let teamsURL: String?  // Pre-extracted msteams:// URL
    let participantName: String?      // For 1:1s - the other participant's name
    let participantPhotoData: Data?   // Small thumbnail (32x32) for 1:1 participant

    /// Placeholder for widget preview
    static let placeholder = SharedMeeting(
        id: "placeholder",
        title: "Weekly 1:1 with Sarah",
        startDate: Date(),
        duration: 1800,
        attendeeCount: 2,
        isOneOnOne: true,
        teamsURL: "msteams://teams.microsoft.com/l/meetup-join/example",
        participantName: "Sarah",
        participantPhotoData: nil
    )

    /// Sample meetings for previews
    static let sampleMeetings: [SharedMeeting] = [
        SharedMeeting(
            id: "1",
            title: "Weekly 1:1 with Sarah",
            startDate: Date().addingTimeInterval(3600),
            duration: 1500,
            attendeeCount: 2,
            isOneOnOne: true,
            teamsURL: "msteams://teams.microsoft.com/l/meetup-join/example1",
            participantName: "Sarah",
            participantPhotoData: nil
        ),
        SharedMeeting(
            id: "2",
            title: "Team Standup",
            startDate: Date().addingTimeInterval(7200),
            duration: 1800,
            attendeeCount: 5,
            isOneOnOne: false,
            teamsURL: "msteams://teams.microsoft.com/l/meetup-join/example2",
            participantName: nil,
            participantPhotoData: nil
        ),
        SharedMeeting(
            id: "3",
            title: "Project Review",
            startDate: Date().addingTimeInterval(14400),
            duration: 3600,
            attendeeCount: 4,
            isOneOnOne: false,
            teamsURL: "msteams://teams.microsoft.com/l/meetup-join/example3",
            participantName: nil,
            participantPhotoData: nil
        )
    ]

    /// Create a small thumbnail from an image for widget display
    static func createThumbnail(from imageData: Data?, targetSize: CGFloat = 64) -> Data? {
        guard let data = imageData,
              let image = NSImage(data: data) else { return nil }

        let newSize = NSSize(width: targetSize, height: targetSize)
        let newImage = NSImage(size: newSize)

        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        return jpegData
    }

    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
    }

    /// Meeting type description
    var meetingTypeLabel: String {
        isOneOnOne ? "1:1" : "\(attendeeCount) people"
    }
}

// MARK: - App Group Constants

enum AppGroupConstants {
    // Note: macOS 15+ requires Team ID prefix instead of "group." for widgets
    static let groupIdentifier = "ZW6EQ2JWKC.com.bobk.WhoNext"
    static let meetingsKey = "upcomingMeetings"

    /// Get shared UserDefaults for App Group
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }
}
