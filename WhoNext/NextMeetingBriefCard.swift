import SwiftUI
import CoreData

/// Full-width card showing the user's next meeting with person context,
/// relationship health, action items, and last conversation summary.
/// Replaces the three old statistics cards (Momentum, Focus Next, This Week).
struct NextMeetingBriefCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var calendarService = CalendarService.shared
    @ObservedObject private var briefManager = PreMeetingBriefManager.shared

    var onPersonTap: ((Person) -> Void)?

    @State private var isHovered = false
    @State private var isRegenerating = false
    @State private var showFullBrief = false

    private let calculator = ConversationMetricsCalculator.shared

    // MARK: - Body

    var body: some View {
        SwiftUI.Group {
            if let meeting = nextMeeting {
                meetingCard(for: meeting, isTomorrow: !isToday(meeting.startDate))
            } else if let futureMeeting = nextMeetingWithin7Days {
                emptyTodayCard(nextDate: futureMeeting.startDate)
            } else {
                emptyCard
            }
        }
    }

    // MARK: - Meeting Resolution

    /// Next meeting that hasn't started yet — always forward-looking for prep.
    /// Once a meeting starts, skip it and show what's next.
    private var nextMeeting: UpcomingMeeting? {
        let now = Date()
        let calendar = Calendar.current

        // Future meetings today (strictly not yet started)
        let todayFuture = calendarService.upcomingMeetings.filter { meeting in
            calendar.isDateInToday(meeting.startDate) && meeting.startDate > now
        }.sorted { $0.startDate < $1.startDate }

        if let first = todayFuture.first {
            return first
        }

        // Tomorrow's first meeting
        let tomorrowMeetings = calendarService.upcomingMeetings.filter { meeting in
            calendar.isDateInTomorrow(meeting.startDate)
        }.sorted { $0.startDate < $1.startDate }

        return tomorrowMeetings.first
    }

    /// Next meeting within 7 days (for the "no meetings today/tomorrow" state)
    private var nextMeetingWithin7Days: UpcomingMeeting? {
        let now = Date()
        return calendarService.upcomingMeetings
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    // MARK: - Card States

    @ViewBuilder
    private func meetingCard(for meeting: UpcomingMeeting, isTomorrow: Bool) -> some View {
        let isOneOnOne = (meeting.attendees?.count ?? 0) == 2
        let person = isOneOnOne ? findMatchedPerson(for: meeting) : nil
        let metrics = person.flatMap { calculator.calculateMetrics(for: $0) }

        VStack(alignment: .leading, spacing: 12) {
            // Header row
            headerRow(meeting: meeting, isTomorrow: isTomorrow)

            if isOneOnOne {
                oneOnOneContent(meeting: meeting, person: person, metrics: metrics, isTomorrow: isTomorrow)
            } else {
                groupContent(meeting: meeting)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    // MARK: - Header Row

    @ViewBuilder
    private func headerRow(meeting: UpcomingMeeting, isTomorrow: Bool) -> some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack {
                if isTomorrow {
                    Text("TOMORROW")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Text(meeting.startDate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("NEXT MEETING")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    countdownText(to: meeting.startDate)
                }

                Spacer()

                // Join Teams button
                if let teamsURL = extractTeamsURL(from: meeting.notes) {
                    Button(action: { NSWorkspace.shared.open(teamsURL) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11))
                            Text("Join")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 1:1 Content

    @ViewBuilder
    private func oneOnOneContent(meeting: UpcomingMeeting, person: Person?, metrics: PersonMetrics?, isTomorrow: Bool) -> some View {
        // Person identity row
        HStack(spacing: 12) {
            personAvatar(person: person, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(person?.wrappedName ?? otherAttendeeName(for: meeting))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    if person == nil {
                        Text("Not linked")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 6) {
                    if let role = person?.role, !role.isEmpty {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if person?.isDirectReport == true {
                        Text("Direct Report")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                if let metrics = metrics {
                    HStack(spacing: 8) {
                        Text("Last met \(metrics.daysSinceLastConversation) days ago")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        healthDots(score: metrics.healthScore)

                        trendArrow(direction: metrics.trendDirection)
                    }
                } else if person != nil {
                    Text("First meeting")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let person = person {
                onPersonTap?(person)
            }
        }

        // Detail panels (not shown in tomorrow/compact mode)
        if !isTomorrow, let person = person {
            detailPanels(person: person, meeting: meeting)
        }
    }

    // MARK: - Detail Panels (Action Items + Last Conversation)

    @ViewBuilder
    private func detailPanels(person: Person, meeting: UpcomingMeeting) -> some View {
        let actionItems = ActionItem.fetchForPerson(person, in: viewContext).filter { !$0.isCompleted }
        let lastConversation = person.conversationsArray.first

        let hasActionItems = !actionItems.isEmpty
        let hasConversation = lastConversation != nil

        if hasActionItems || hasConversation {
            HStack(alignment: .top, spacing: 12) {
                // Action items panel
                if hasActionItems {
                    actionItemsPanel(items: actionItems)
                        .frame(maxWidth: hasConversation ? .infinity : .infinity)
                }

                // Last conversation panel
                if let conversation = lastConversation {
                    lastConversationPanel(conversation: conversation)
                        .frame(maxWidth: hasActionItems ? .infinity : .infinity)
                }
            }
        }

        // Inline AI brief section
        inlineBriefSection(meeting: meeting, person: person)
    }

    @ViewBuilder
    private func actionItemsPanel(items: [ActionItem]) -> some View {
        let overdueCount = items.filter { $0.isOverdue }.count

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ACTION ITEMS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.3)
                Spacer()
                Text("\(items.count) open\(overdueCount > 0 ? " (\(overdueCount) overdue)" : "")")
                    .font(.caption2)
                    .foregroundColor(overdueCount > 0 ? .red : .secondary)
            }

            ForEach(items.prefix(3), id: \.identifier) { item in
                HStack(spacing: 6) {
                    if item.isOverdue {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                            .frame(width: 8, height: 8)
                    }

                    Text(item.title ?? "Untitled")
                        .font(.caption)
                        .foregroundColor(item.isOverdue ? .primary : .secondary)
                        .lineLimit(1)

                    if item.isOverdue, let due = item.formattedDueDate {
                        Text("— \(due)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }

            if items.count > 3 {
                Text("+\(items.count - 3) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    @ViewBuilder
    private func lastConversationPanel(conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LAST TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.3)
                Spacer()
            }

            HStack(spacing: 6) {
                if let date = conversation.date {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                let durationMin = conversation.duration / 60
                if durationMin > 0 {
                    Text("\(durationMin) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let sentiment = conversation.sentimentLabel, !sentiment.isEmpty {
                    Text(sentiment.capitalized)
                        .font(.caption2)
                        .foregroundColor(sentimentColor(sentiment))
                }
            }

            if let summary = conversation.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let topics = conversation.keyTopics, !topics.isEmpty {
                Text("Topics: \(topics.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Group Content

    @ViewBuilder
    private func groupContent(meeting: UpcomingMeeting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(meeting.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let duration = meeting.duration {
                    let minutes = Int(duration) / 60
                    Text("\(minutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.separatorColor).opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if let attendees = meeting.attendees, !attendees.isEmpty {
                HStack(spacing: 4) {
                    // Avatar stack
                    HStack(spacing: -6) {
                        ForEach(0..<min(attendees.count, 5), id: \.self) { i in
                            Circle()
                                .fill(Color.accentColor.opacity(0.2 + Double(i) * 0.1))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(String(extractName(from: attendees[i]).prefix(1)))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.accentColor)
                                )
                                .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
                        }
                    }

                    let names = attendees.prefix(3).map { extractName(from: $0) }
                    let extra = attendees.count > 3 ? ", +\(attendees.count - 3)" : ""
                    Text("\(attendees.count) attendees: \(names.joined(separator: ", "))\(extra)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyCard: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No upcoming meetings")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        )
    }

    @ViewBuilder
    private func emptyTodayCard(nextDate: Date) -> some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("No meetings today or tomorrow")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Next: \(nextDate, style: .date) at \(nextDate, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func personAvatar(person: Person?, size: CGFloat) -> some View {
        if let person = person, let photoData = person.photo, let nsImage = NSImage(data: photoData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Text(person?.initials ?? "?")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.accentColor)
                )
        }
    }

    @ViewBuilder
    private func healthDots(score: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Double(i) / 5.0 < score ? healthColor(score) : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private func trendArrow(direction: String) -> some View {
        switch direction {
        case "improving":
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text("improving")
                    .font(.system(size: 9))
            }
            .foregroundColor(.green)
        case "declining":
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("declining")
                    .font(.system(size: 9))
            }
            .foregroundColor(.orange)
        default:
            EmptyView()
        }
    }

    private func countdownText(to date: Date) -> some View {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let text: String
        let color: Color

        if minutes < 1 {
            text = "Starting now"
            color = .red
        } else if minutes < 10 {
            text = "In \(minutes) min"
            color = .red
        } else if minutes < 30 {
            text = "In \(minutes) min"
            color = .orange
        } else if minutes < 60 {
            text = "In \(minutes) min"
            color = .green
        } else {
            let hours = minutes / 60
            let remainingMin = minutes % 60
            text = remainingMin > 0 ? "In \(hours)h \(remainingMin)m" : "In \(hours)h"
            color = .green
        }

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
    }

    // MARK: - Inline Brief Section

    @ViewBuilder
    private func inlineBriefSection(meeting: UpcomingMeeting, person: Person) -> some View {
        let hasBrief = briefManager.hasBrief(for: meeting.id)
        let isPending = briefManager.pendingMeetings.contains(meeting.id)
        let conversationCount = person.conversations?.count ?? 0

        if hasBrief, let cached = briefManager.getBrief(for: meeting.id) {
            // Render cached brief inline
            VStack(alignment: .leading, spacing: 8) {
                briefDivider

                let content = cached.briefContent
                if showFullBrief || content.count <= 600 {
                    CompactBriefContentView(content: content)
                } else {
                    CompactBriefContentView(content: String(content.prefix(600)) + "...")
                    Button(action: { withAnimation { showFullBrief = true } }) {
                        Text("Show more")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                briefFooter(meeting: meeting)
            }
        } else if (briefManager.isGenerating && isPending) || isRegenerating {
            // Loading state
            VStack(alignment: .leading, spacing: 8) {
                briefDivider

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing brief...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else if conversationCount == 0 {
            // First meeting — no history
            VStack(alignment: .leading, spacing: 8) {
                briefDivider

                HStack(spacing: 6) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("First meeting — no previous conversation history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else {
            // Auto-trigger generation for today's meetings
            Color.clear
                .frame(height: 0)
                .task(id: meeting.id) {
                    guard isToday(meeting.startDate) else { return }
                    guard !briefManager.hasBrief(for: meeting.id) else { return }
                    await briefManager.generateBriefForMeeting(meeting)
                }
        }
    }

    private var briefDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .frame(maxWidth: 20)
            Text("AI BRIEF")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func briefFooter(meeting: UpcomingMeeting) -> some View {
        HStack {
            Spacer()

            Button(action: {
                isRegenerating = true
                showFullBrief = false
                Task {
                    await briefManager.regenerateBrief(for: meeting)
                    isRegenerating = false
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text("Regenerate")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRegenerating)

            Button(action: {
                if let brief = briefManager.getBrief(for: meeting.id) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(brief.briefContent, forType: .string)
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                    Text("Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Person Matching (from EnhancedMeetingCard pattern)

    private func findMatchedPerson(for meeting: UpcomingMeeting) -> Person? {
        guard let attendees = meeting.attendees, attendees.count == 2 else { return nil }

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
            return nil
        }
    }

    // MARK: - Utility

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

    private func otherAttendeeName(for meeting: UpcomingMeeting) -> String {
        guard let attendees = meeting.attendees, attendees.count == 2 else { return meeting.title }
        let userEmail = UserProfile.shared.email.lowercased()
        let userName = UserProfile.shared.name.lowercased()

        for attendee in attendees {
            let lower = attendee.lowercased()
            if !lower.contains(userEmail) && !lower.contains(userName) {
                return extractName(from: attendee)
            }
        }
        return extractName(from: attendees.first ?? meeting.title)
    }

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
                if urlString.lowercased().hasPrefix("https://") {
                    urlString = urlString.replacingOccurrences(of: "https://", with: "msteams://", options: .caseInsensitive)
                }
                return URL(string: urlString)
            }
        }
        return nil
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func healthColor(_ score: Double) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive": return .green
        case "negative": return .red
        case "neutral": return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Compact Brief Content Renderer

/// Lightweight inline markdown renderer for AI brief content.
/// Adapted from ProfileContentView with smaller fonts for card context.
private struct CompactBriefContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sections: [String] {
        content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @ViewBuilder
    private func sectionView(_ section: String) -> some View {
        let lines = section.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            EmptyView()
        } else if trimmed.hasPrefix("###") {
            Text(formatInline(trimmed.replacingOccurrences(of: "### ", with: "")))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix("##") {
            Text(formatInline(trimmed.replacingOccurrences(of: "## ", with: "")))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
            let bulletText = trimmed
                .replacingOccurrences(of: "^[•\\-\\*]\\s*", with: "", options: .regularExpression)
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(formatInline(bulletText))
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else {
            Text(formatInline(trimmed))
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func formatInline(_ text: String) -> AttributedString {
        // Process **bold** markers
        var result = AttributedString()
        let boldPattern = "\\*\\*([^*]+)\\*\\*"

        guard let regex = try? NSRegularExpression(pattern: boldPattern) else {
            return AttributedString(text)
        }

        let nsText = text as NSString
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            // Text before bold
            if match.range.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                result.append(AttributedString(before))
            }
            // Bold text
            if match.numberOfRanges > 1 {
                let boldContent = nsText.substring(with: match.range(at: 1))
                var boldAttr = AttributedString(boldContent)
                boldAttr.font = .system(size: 12, weight: .semibold)
                result.append(boldAttr)
            }
            lastEnd = match.range.location + match.range.length
        }

        // Remaining text
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            result.append(AttributedString(remaining))
        }

        return result.characters.isEmpty ? AttributedString(text) : result
    }
}

// MARK: - Preview

#Preview {
    NextMeetingBriefCard()
        .frame(width: 700)
        .padding()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
