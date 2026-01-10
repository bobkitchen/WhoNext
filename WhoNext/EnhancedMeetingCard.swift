import SwiftUI
import CoreData

struct EnhancedMeetingCard: View {
    let meeting: UpcomingMeeting
    @ObservedObject var recordingEngine: MeetingRecordingEngine
    @Binding var selectedPersonID: UUID?
    @Binding var selectedPerson: Person?
    @Binding var selectedTab: SidebarItem
    let isCurrentlyRecording: Bool

    @State private var isHovered = false
    @State private var showingBrief = false

    @ObservedObject private var briefManager = PreMeetingBriefManager.shared
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Computed Properties

    /// Check if this is a 1:1 meeting
    private var isOneOnOne: Bool {
        (meeting.attendees?.count ?? 0) == 2
    }

    /// Get matched Person for 1:1 meetings
    private var matchedPerson: Person? {
        findMatchedPerson()
    }

    /// Pending action items count for matched person (1:1 only)
    private var pendingActionItemsCount: Int {
        guard let person = matchedPerson else { return 0 }
        let items = ActionItem.fetchForPerson(person, in: viewContext)
        return items.filter { !$0.isCompleted }.count
    }

    /// Participant count (excluding self for display)
    private var participantCount: Int {
        meeting.attendees?.count ?? 0
    }

    /// Check if meeting has calendar notes
    private var hasNotes: Bool {
        guard let notes = meeting.notes else { return false }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if meeting has a Teams URL
    private var teamsURL: URL? {
        extractTeamsURL(from: meeting.notes)
    }

    /// Format duration nicely
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

    /// Get the other person's name for 1:1 meetings
    private var otherPersonName: String? {
        guard isOneOnOne, let attendees = meeting.attendees else { return nil }

        let userEmail = UserProfile.shared.email.lowercased().trimmingCharacters(in: .whitespaces)
        let userName = UserProfile.shared.name.lowercased().trimmingCharacters(in: .whitespaces)

        for attendee in attendees {
            let attendeeLower = attendee.lowercased()
            let attendeeName = extractName(from: attendee).lowercased()

            let isUser = (!userEmail.isEmpty && attendeeLower.contains(userEmail)) ||
                         (!userName.isEmpty && (attendeeLower.contains(userName) || attendeeName == userName))

            if !isUser {
                return extractName(from: attendee)
            }
        }

        // Fallback to first attendee if can't determine
        if let first = attendees.first {
            return extractName(from: first)
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Meeting type badge + Duration + Time
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    if isOneOnOne {
                        MeetingTypeBadge(type: .oneOnOne)
                    } else if participantCount > 2 {
                        MeetingTypeBadge(type: .group)
                    }

                    // Recording indicator
                    if isCurrentlyRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .modifier(GlowingPulse(color: .red))
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

                Spacer()

                // Duration & Time
                HStack(spacing: 8) {
                    Text(formattedDuration)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.separatorColor).opacity(0.2))
                        .cornerRadius(4)

                    Text(meeting.startDate, style: .time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Row 2: Title
            Text(meeting.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Row 3: Person name (1:1) or Participant count (group)
            if isOneOnOne {
                // For 1:1: Show person name prominently
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text(otherPersonName ?? "Unknown")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
            } else {
                // For groups: Show participant count
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("\(participantCount) participants")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            // Row 4: Action items/Notes indicator + Join button
            HStack {
                if isOneOnOne {
                    // For 1:1: Show action items count
                    if pendingActionItemsCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.system(size: 11))
                            Text("\(pendingActionItemsCount) task\(pendingActionItemsCount == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                } else {
                    // For groups: Show notes indicator
                    if hasNotes {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                            Text("Notes")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Spacer()

                // Join button (always visible if Teams URL exists)
                if teamsURL != nil {
                    Button(action: joinMeeting) {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11))
                            Text("Join")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Join Teams meeting and start recording")
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.borderSubtle, lineWidth: 1)
        )
        .shadow(color: isHovered ? Color.black.opacity(0.08) : Color.black.opacity(0.04), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openMeetingDetailWindowAction()
        }
        .contextMenu {
            Button(action: copyMeetingDetails) {
                Label("Copy Details", systemImage: "doc.on.doc")
            }

            Divider()

            Button(action: deleteMeeting) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingBrief) {
            PreMeetingBriefWindow(
                personName: meeting.title ?? "Meeting",
                briefContent: meeting.notes ?? "No meeting notes available",
                onClose: { showingBrief = false }
            )
        }
    }

    // MARK: - Actions

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

    private func copyMeetingDetails() {
        let details = """
        Meeting: \(meeting.title)
        Time: \(meeting.startDate.formatted())
        Duration: \(formattedDuration)
        Attendees: \((meeting.attendees ?? []).joined(separator: ", "))
        \(meeting.notes ?? "")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }

    private func deleteMeeting() {
        // TODO: Implement meeting deletion
    }

    private func openMeetingDetailWindowAction() {
        openMeetingDetailWindow(
            for: meeting,
            isOneOnOne: isOneOnOne,
            matchedPerson: matchedPerson,
            context: viewContext
        )
    }

    // MARK: - Helper Methods

    /// Extract Teams meeting URL from notes and convert to msteams:// scheme for direct opening
    private func extractTeamsURL(from notes: String?) -> URL? {
        guard let notes = notes else { return nil }

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

    /// Find Person record from meeting attendee
    private func findMatchedPerson() -> Person? {
        guard isOneOnOne,
              let attendees = meeting.attendees,
              attendees.count == 2 else { return nil }

        let userEmail = UserProfile.shared.email.lowercased().trimmingCharacters(in: .whitespaces)
        let userName = UserProfile.shared.name.lowercased().trimmingCharacters(in: .whitespaces)

        var otherAttendee: String?
        for attendee in attendees {
            let attendeeLower = attendee.lowercased()
            let attendeeName = extractName(from: attendee).lowercased()

            let isUser = (!userEmail.isEmpty && attendeeLower.contains(userEmail)) ||
                         (!userName.isEmpty && (attendeeLower.contains(userName) || attendeeName == userName))

            if !isUser {
                otherAttendee = attendee
                break
            }
        }

        let attendeeToMatch = otherAttendee ?? attendees.first ?? ""
        guard !attendeeToMatch.isEmpty else { return nil }

        return searchForPerson(matching: attendeeToMatch)
    }

    /// Search for a Person matching the given attendee string
    private func searchForPerson(matching attendee: String) -> Person? {
        let trimmedAttendee = attendee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAttendee.count >= 2 else { return nil }

        let searchName = extractName(from: trimmedAttendee)
        guard searchName.count >= 2 else { return nil }

        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", searchName)
        request.fetchLimit = 1

        do {
            let results = try viewContext.fetch(request)
            return results.first
        } catch {
            print("Error searching for person: \(error)")
            return nil
        }
    }
}

// MARK: - Preview Provider
struct EnhancedMeetingCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // 1:1 Meeting Preview
            EnhancedMeetingCard(
                meeting: UpcomingMeeting(
                    id: "preview-1on1",
                    title: "Quick chat re AA fund management",
                    startDate: Date(),
                    calendarID: "primary",
                    notes: "Join Microsoft Teams Meeting: https://teams.microsoft.com/l/meetup-join/123456",
                    location: nil,
                    attendees: ["alyoscia.donofrio@company.com", "me@company.com"],
                    duration: 1500
                ),
                recordingEngine: MeetingRecordingEngine.shared,
                selectedPersonID: .constant(nil),
                selectedPerson: .constant(nil),
                selectedTab: .constant(.meetings),
                isCurrentlyRecording: false
            )

            // Group Meeting Preview
            EnhancedMeetingCard(
                meeting: UpcomingMeeting(
                    id: "preview-group",
                    title: "EMU SMT Staff Rep + BK check in",
                    startDate: Date().addingTimeInterval(3600),
                    calendarID: "primary",
                    notes: "Weekly sync meeting notes here. Join: https://teams.microsoft.com/l/meetup-join/789",
                    location: nil,
                    attendees: ["john@company.com", "jane@company.com", "bob@company.com"],
                    duration: 3600
                ),
                recordingEngine: MeetingRecordingEngine.shared,
                selectedPersonID: .constant(nil),
                selectedPerson: .constant(nil),
                selectedTab: .constant(.meetings),
                isCurrentlyRecording: false
            )
        }
        .frame(width: 400)
        .padding()
    }
}
