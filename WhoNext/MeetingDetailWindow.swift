import SwiftUI
import CoreData
import AppKit

/// A detail window that opens when a meeting card is clicked
/// Shows differentiated content for 1:1 vs group meetings
struct MeetingDetailWindow: View {
    let meeting: UpcomingMeeting
    let isOneOnOne: Bool
    let matchedPerson: Person?
    var onClose: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var briefManager = PreMeetingBriefManager.shared
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared

    @State private var isGeneratingBrief = false

    // MARK: - Computed Properties

    /// Get cached brief for this meeting
    private var cachedBrief: PreMeetingBriefManager.CachedBrief? {
        briefManager.getBrief(for: meeting.id)
    }

    /// Check if we have a valid AI brief
    private var hasValidBrief: Bool {
        guard let brief = cachedBrief else { return false }
        return !brief.briefContent.isEmpty
    }

    /// Pending action items for the matched person
    private var pendingActionItems: [ActionItem] {
        guard let person = matchedPerson else { return [] }
        return ActionItem.fetchForPerson(person, in: viewContext)
            .filter { !$0.isCompleted }
    }

    /// Extract Teams meeting URL from notes
    private var teamsURL: URL? {
        extractTeamsURL(from: meeting.notes)
    }

    /// Check if Teams URL exists
    private var hasTeamsURL: Bool {
        teamsURL != nil
    }

    // Format duration nicely
    private var formattedDuration: String {
        let minutes = Int(meeting.duration ?? 0) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()

            // Content (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Pre-Meeting Brief (both meeting types)
                    briefSection

                    if isOneOnOne {
                        // Action Items (1:1 only)
                        actionItemsSection
                    } else {
                        // Calendar Notes (group only)
                        calendarNotesSection
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Meeting type badge
                    HStack(spacing: 8) {
                        if isOneOnOne {
                            MeetingTypeBadge(type: .oneOnOne)
                        } else {
                            MeetingTypeBadge(type: .group)
                        }

                        if recordingEngine.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text("Recording")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }

                    // Title
                    Text(meeting.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    // Time and duration
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                            Text(meeting.startDate, style: .time)
                        }
                        .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.system(size: 12))
                            Text(formattedDuration)
                        }
                        .foregroundColor(.secondary)
                    }
                    .font(.system(size: 13))

                    // Matched person (for 1:1)
                    if isOneOnOne, let person = matchedPerson {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            Text(person.name ?? "Unknown")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    }
                }

                Spacer()

                // Join button
                if hasTeamsURL {
                    joinButton
                }
            }

            // Participants
            if let attendees = meeting.attendees, !attendees.isEmpty {
                HStack(spacing: 8) {
                    ParticipantAvatarStack(
                        participants: attendees.map { extractName(from: $0) }
                    )

                    Text(attendees.map { extractName(from: $0) }.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Join Button

    private var joinButton: some View {
        Button(action: joinMeeting) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                Text("Join")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help("Join Teams meeting and start recording")
    }

    private func joinMeeting() {
        // 1. Launch Teams meeting URL
        if let url = teamsURL {
            NSWorkspace.shared.open(url)
        }

        // 2. Start recording after brief delay (allow Teams to open)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MeetingRecordingEngine.shared.manualStartRecording()
        }
    }

    // MARK: - Brief Section

    private var briefSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Pre-Meeting Brief")
                    .font(.headline)

                Spacer()

                if hasValidBrief {
                    Button(action: regenerateBrief) {
                        if isGeneratingBrief || briefManager.pendingMeetings.contains(meeting.id) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isGeneratingBrief || briefManager.pendingMeetings.contains(meeting.id))
                    .help("Regenerate brief")
                }
            }

            if let brief = cachedBrief, !brief.briefContent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(brief.briefContent)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    if brief.isStale {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11))
                            Text("Brief may be outdated")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    }
                }
            } else if briefManager.pendingMeetings.contains(meeting.id) || isGeneratingBrief {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating brief...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if isOneOnOne && matchedPerson != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No brief generated yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Button(action: generateBrief) {
                        Label("Generate Brief", systemImage: "sparkles")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if isOneOnOne {
                Text("No Person record found for this meeting")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Text("Pre-meeting briefs are available for 1:1 meetings with known contacts")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Action Items Section (1:1 only)

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Outstanding Action Items")
                    .font(.headline)

                if !pendingActionItems.isEmpty {
                    Text("\(pendingActionItems.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }

            if pendingActionItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text("No pending action items")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 13))
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pendingActionItems) { item in
                        actionItemRow(item)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Priority indicator
            Circle()
                .fill(priorityColor(for: item))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "Untitled")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    // Due date
                    if let dueDate = item.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(dueDate, style: .date)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(item.isOverdue ? .red : .secondary)
                    }

                    // Owner
                    if item.isMyTask {
                        Text("My task")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }

    private func priorityColor(for item: ActionItem) -> Color {
        switch item.priorityEnum {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .green
        }
    }

    // MARK: - Calendar Notes Section (Group only)

    private var calendarNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text("Meeting Notes")
                    .font(.headline)
            }

            if let notes = meeting.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            } else {
                Text("No meeting notes available")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Helper Methods

    /// Extract Teams meeting URL from notes and convert to msteams:// scheme for direct opening
    private func extractTeamsURL(from notes: String?) -> URL? {
        guard let notes = notes else { return nil }

        // Match Teams meeting URLs
        let patterns = [
            "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s<>\"]+",
            "https://teams\\.live\\.com/meet/[^\\s<>\"]+",
            "msteams://[^\\s<>\"]+",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
               let range = Range(match.range, in: notes) {
                var urlString = String(notes[range])

                // Convert HTTPS to msteams:// for direct Teams app opening
                // This bypasses Safari and the "Allow website" dialog
                if urlString.lowercased().hasPrefix("https://") {
                    urlString = urlString.replacingOccurrences(
                        of: "https://",
                        with: "msteams://",
                        options: .caseInsensitive
                    )
                }

                return URL(string: urlString)
            }
        }
        return nil
    }

    /// Extract clean name from email
    private func extractName(from attendee: String) -> String {
        if attendee.contains("@") {
            let namePart = attendee.split(separator: "@").first ?? Substring(attendee)
            return String(namePart)
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
        return attendee
    }

    /// Generate brief for this meeting
    private func generateBrief() {
        isGeneratingBrief = true
        Task { @MainActor in
            await briefManager.generateBriefForMeeting(meeting)
            isGeneratingBrief = false
        }
    }

    /// Regenerate brief for this meeting
    private func regenerateBrief() {
        isGeneratingBrief = true
        Task { @MainActor in
            await briefManager.regenerateBrief(for: meeting)
            isGeneratingBrief = false
        }
    }
}

// MARK: - Window Helper

/// Opens a meeting detail window
func openMeetingDetailWindow(
    for meeting: UpcomingMeeting,
    isOneOnOne: Bool,
    matchedPerson: Person?,
    context: NSManagedObjectContext
) {
    let contentView = MeetingDetailWindow(
        meeting: meeting,
        isOneOnOne: isOneOnOne,
        matchedPerson: matchedPerson
    )
    .environment(\.managedObjectContext, context)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )

    window.title = meeting.title
    window.center()
    window.contentView = NSHostingView(rootView: contentView)
    window.makeKeyAndOrderFront(nil)

    // Keep window alive
    window.isReleasedWhenClosed = false
}

// MARK: - Preview

struct MeetingDetailWindow_Previews: PreviewProvider {
    static var previews: some View {
        MeetingDetailWindow(
            meeting: UpcomingMeeting(
                id: "preview",
                title: "Weekly 1:1 with Sarah",
                startDate: Date(),
                calendarID: "primary",
                notes: "Join Microsoft Teams Meeting: https://teams.microsoft.com/l/meetup-join/123456",
                location: nil,
                attendees: ["sarah.jones@company.com", "me@company.com"],
                duration: 1800
            ),
            isOneOnOne: true,
            matchedPerson: nil
        )
    }
}
