//
//  WhoNextWidget.swift
//  WhoNextWidget
//
//  Created by Bob Kitchen on 1/10/26.
//

import WidgetKit
import SwiftUI

// MARK: - Shared Meeting Model

/// Lightweight meeting model shared between main app and widget via App Groups
struct SharedMeeting: Codable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let duration: TimeInterval
    let attendeeCount: Int
    let isOneOnOne: Bool
    let teamsURL: String?
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

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }
}

// MARK: - Timeline Entry

struct MeetingEntry: TimelineEntry {
    let date: Date
    let meetings: [SharedMeeting]

    var hasMeetings: Bool { !meetings.isEmpty }
    var nextMeeting: SharedMeeting? { meetings.first }

    static let placeholder = MeetingEntry(date: Date(), meetings: [.placeholder])
    static let sample = MeetingEntry(date: Date(), meetings: SharedMeeting.sampleMeetings)
}

// MARK: - Timeline Provider

struct MeetingTimelineProvider: TimelineProvider {
    typealias Entry = MeetingEntry

    func placeholder(in context: Context) -> MeetingEntry {
        MeetingEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MeetingEntry) -> Void) {
        let entry: MeetingEntry
        if context.isPreview {
            entry = MeetingEntry.sample
        } else {
            entry = MeetingEntry(date: Date(), meetings: loadMeetings())
        }
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MeetingEntry>) -> Void) {
        let meetings = loadMeetings()
        let currentDate = Date()
        var entries: [MeetingEntry] = []

        entries.append(MeetingEntry(date: currentDate, meetings: meetings))

        for meeting in meetings.prefix(5) {
            if meeting.startDate > currentDate {
                entries.append(MeetingEntry(date: meeting.startDate, meetings: meetings))
            }
        }

        let refreshInterval: TimeInterval = 15 * 60
        var nextRefresh = currentDate.addingTimeInterval(refreshInterval)

        if let nextMeeting = meetings.first,
           nextMeeting.startDate > currentDate,
           nextMeeting.startDate < nextRefresh {
            nextRefresh = nextMeeting.startDate
        }

        let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadMeetings() -> [SharedMeeting] {
        print("📱 Widget: loadMeetings() called")

        guard let defaults = AppGroupConstants.sharedDefaults else {
            print("❌ Widget: FAILED - Cannot access App Group '\(AppGroupConstants.groupIdentifier)'")
            print("   → App Group may not be configured in Apple Developer portal")
            return []
        }

        print("✅ Widget: App Group accessible")

        guard let data = defaults.data(forKey: AppGroupConstants.meetingsKey) else {
            print("⚠️ Widget: No data found for key '\(AppGroupConstants.meetingsKey)'")
            print("   → Main app may not have synced yet")
            return []
        }

        print("✅ Widget: Found \(data.count) bytes of meeting data")

        do {
            let decoder = JSONDecoder()
            let meetings = try decoder.decode([SharedMeeting].self, from: data)
            print("✅ Widget: Decoded \(meetings.count) meetings")

            let now = Date()
            let filteredMeetings = meetings
                .filter { $0.startDate > now.addingTimeInterval(-300) }
                .sorted { $0.startDate < $1.startDate }

            print("✅ Widget: Returning \(filteredMeetings.count) upcoming meetings")
            for meeting in filteredMeetings.prefix(3) {
                print("   → \(meeting.title) at \(meeting.startDate)")
            }

            return filteredMeetings
        } catch {
            print("❌ Widget: Failed to decode meetings: \(error)")
            return []
        }
    }
}

// MARK: - App Intents

import AppIntents

struct JoinMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Join Meeting"
    static var description = IntentDescription("Join a Teams meeting and start recording")

    @Parameter(title: "Meeting ID")
    var meetingId: String

    @Parameter(title: "Teams URL")
    var teamsURL: String?

    init() {
        self.meetingId = ""
        self.teamsURL = nil
    }

    init(meetingId: String, teamsURL: String?) {
        self.meetingId = meetingId
        self.teamsURL = teamsURL
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let urlString = teamsURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        try? await Task.sleep(for: .milliseconds(500))

        if let appURL = URL(string: "whonext://join?meetingId=\(meetingId)") {
            NSWorkspace.shared.open(appURL)
        }

        return .result()
    }
}

struct OpenWhoNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Open WhoNext"
    static var description = IntentDescription("Open the WhoNext app")

    @MainActor
    func perform() async throws -> some IntentResult {
        if let appURL = URL(string: "whonext://open") {
            NSWorkspace.shared.open(appURL)
        }
        return .result()
    }
}

// MARK: - Widget Views

struct MeetingWidgetView: View {
    let entry: MeetingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallMeetingView(meeting: entry.nextMeeting)
        case .systemMedium:
            MediumMeetingView(meetings: Array(entry.meetings.prefix(3)))
        case .systemLarge:
            LargeMeetingView(meetings: Array(entry.meetings.prefix(4)))  // Reduced from 6 to 4
        default:
            MediumMeetingView(meetings: Array(entry.meetings.prefix(3)))
        }
    }
}

// MARK: - Participant Avatar View

struct ParticipantAvatar: View {
    let meeting: SharedMeeting
    let size: CGFloat

    var body: some View {
        if meeting.isOneOnOne {
            // 1:1 meeting - show participant photo or initials
            if let photoData = meeting.participantPhotoData,
               let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback to initials
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials(from: meeting.participantName ?? meeting.title))
                            .font(.system(size: size * 0.4, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
        } else {
            // Group meeting - show group icon
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.green)
                )
        }
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

struct SmallMeetingView: View {
    let meeting: SharedMeeting?

    var body: some View {
        if let meeting = meeting {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ParticipantAvatar(meeting: meeting, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.startDate, style: .time)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(meeting.isOneOnOne ? "1:1" : "\(meeting.attendeeCount) people")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(meeting.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer()

                if meeting.teamsURL != nil {
                    Button(intent: JoinMeetingIntent(meetingId: meeting.id, teamsURL: meeting.teamsURL)) {
                        Text("Join")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
        } else {
            EmptyMeetingsView(isCompact: true)
        }
    }
}

struct MediumMeetingView: View {
    let meetings: [SharedMeeting]

    var body: some View {
        if meetings.isEmpty {
            EmptyMeetingsView(isCompact: false)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Upcoming Meetings")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                ForEach(meetings) { meeting in
                    MeetingRow(meeting: meeting, isCompact: true)
                    if meeting.id != meetings.last?.id {
                        Divider()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
    }
}

struct LargeMeetingView: View {
    let meetings: [SharedMeeting]

    var body: some View {
        if meetings.isEmpty {
            EmptyMeetingsView(isCompact: false)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("Upcoming Meetings")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(meetings.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 4)

                ForEach(meetings) { meeting in
                    MeetingRow(meeting: meeting, isCompact: false)
                    if meeting.id != meetings.last?.id {
                        Divider()
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Button(intent: OpenWhoNextIntent()) {
                        Label("Open WhoNext", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

struct MeetingRow: View {
    let meeting: SharedMeeting
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 8) {
            ParticipantAvatar(meeting: meeting, size: isCompact ? 24 : 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meeting.startDate, style: .time)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text(meeting.title)
                        .font(isCompact ? .caption : .subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                if !isCompact {
                    HStack(spacing: 8) {
                        Text(meeting.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(meeting.meetingTypeLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if meeting.teamsURL != nil {
                Button(intent: JoinMeetingIntent(meetingId: meeting.id, teamsURL: meeting.teamsURL)) {
                    Text("Join")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, isCompact ? 2 : 4)
    }
}

struct EmptyMeetingsView: View {
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(isCompact ? .title3 : .largeTitle)
                .foregroundStyle(.secondary)

            Text("No upcoming meetings")
                .font(isCompact ? .caption : .subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if !isCompact {
                Text("Enjoy your focus time!")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button(intent: OpenWhoNextIntent()) {
                    Label("Open WhoNext", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Widget Configuration

struct WhoNextWidget: Widget {
    let kind: String = "WhoNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeetingTimelineProvider()) { entry in
            MeetingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Meetings")
        .description("View and join your upcoming meetings")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    WhoNextWidget()
} timeline: {
    MeetingEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    WhoNextWidget()
} timeline: {
    MeetingEntry.sample
}

#Preview("Large", as: .systemLarge) {
    WhoNextWidget()
} timeline: {
    MeetingEntry.sample
}

#Preview("Empty", as: .systemMedium) {
    WhoNextWidget()
} timeline: {
    MeetingEntry(date: Date(), meetings: [])
}
