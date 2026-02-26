import Foundation
import CoreData

/// Pure formatting struct that generates Obsidian-compatible markdown with YAML frontmatter.
/// No side effects, no file I/O — just string generation.
struct ObsidianNoteFormatter {

    // MARK: - Date Formatters

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    // MARK: - Meeting Notes

    /// Generate a full Obsidian note for a 1:1 conversation.
    func meetingNote(from conversation: Conversation) -> String {
        let personName = conversation.person?.wrappedName ?? "Unknown"
        let date = conversation.date ?? Date()
        let uid = conversation.uuid?.uuidString ?? UUID().uuidString

        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("type: meeting")
        lines.append("meeting_type: 1on1")
        lines.append("uid: \"\(uid)\"")
        lines.append("date: \(Self.isoFormatter.string(from: date))")
        lines.append("duration_minutes: \(conversation.duration / 60)")
        lines.append("person: \"[[People/\(personName)|\(personName)]]\"")

        if let sentiment = conversation.sentimentLabel, !sentiment.isEmpty {
            lines.append("sentiment: \(sentiment.lowercased())")
        }
        if conversation.sentimentScore > 0 {
            lines.append("sentiment_score: \(String(format: "%.2f", conversation.sentimentScore))")
        }
        if let engagement = conversation.engagementLevel, !engagement.isEmpty {
            lines.append("engagement: \(engagement.lowercased())")
        }
        if let topics = conversation.keyTopics, !topics.isEmpty {
            lines.append("key_topics:")
            for topic in topics {
                lines.append("  - \"\(topic)\"")
            }
        }
        lines.append("synced_from: WhoNext")
        lines.append("---")
        lines.append("")

        // Title
        lines.append("# 1:1 with \(personName) - \(Self.displayDateFormatter.string(from: date))")
        lines.append("")
        lines.append("> Meeting with [[People/\(personName)|\(personName)]]")
        lines.append("")

        // Summary
        if let summary = conversation.summary, !summary.isEmpty {
            lines.append("## Summary")
            lines.append(stripSentimentData(from: summary))
            lines.append("")
        }

        // Key Topics
        if let topics = conversation.keyTopics, !topics.isEmpty {
            lines.append("## Key Topics")
            for topic in topics {
                lines.append("- \(topic)")
            }
            lines.append("")
        }

        // Action Items
        let actionItems = fetchActionItems(for: conversation)
        if !actionItems.isEmpty {
            lines.append("## Action Items")
            for item in actionItems {
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                var line = "- \(checkbox) \(item.title ?? "Untitled")"
                if let assignee = item.assignee, !assignee.isEmpty {
                    line += " (**\(assignee)**)"
                }
                if let dueDate = item.dueDate {
                    line += " -- due \(Self.displayDateFormatter.string(from: dueDate))"
                }
                if let priority = item.priority, !priority.isEmpty {
                    line += " `\(priority)`"
                }
                lines.append(line)
            }
            lines.append("")
        }

        // Notes
        if let notes = conversation.notes, !notes.isEmpty {
            let cleanNotes = stripSentimentData(from: notes)
            if !cleanNotes.isEmpty {
                lines.append("## Notes")
                lines.append(cleanNotes)
                lines.append("")
            }
        }

        // Footer
        lines.append("---")
        lines.append("*Synced from WhoNext*")

        return lines.joined(separator: "\n")
    }

    /// Generate a full Obsidian note for a group meeting.
    func meetingNote(from meeting: GroupMeeting) -> String {
        let date = meeting.date ?? Date()
        let uid = meeting.identifier?.uuidString ?? UUID().uuidString
        let title = meeting.displayTitle
        let attendees = meeting.sortedAttendees

        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("type: meeting")
        lines.append("meeting_type: group")
        lines.append("uid: \"\(uid)\"")
        lines.append("date: \(Self.isoFormatter.string(from: date))")
        lines.append("duration_minutes: \(meeting.duration / 60)")
        lines.append("title: \"\(title)\"")

        if let groupName = meeting.group?.name {
            lines.append("group: \"\(groupName)\"")
        }

        if !attendees.isEmpty {
            lines.append("attendees:")
            for person in attendees {
                lines.append("  - \"[[People/\(person.wrappedName)|\(person.wrappedName)]]\"")
            }
        }
        lines.append("attendee_count: \(meeting.attendeeCount)")

        lines.append("sentiment: \(meeting.sentimentLabel.lowercased())")
        if meeting.sentimentScore > 0 {
            lines.append("sentiment_score: \(String(format: "%.2f", meeting.sentimentScore))")
        }
        if meeting.qualityScore > 0 {
            lines.append("quality_score: \(String(format: "%.2f", meeting.qualityScore))")
        }

        if let topics = meeting.keyTopics as? [String], !topics.isEmpty {
            lines.append("key_topics:")
            for topic in topics {
                lines.append("  - \"\(topic)\"")
            }
        }

        lines.append("synced_from: WhoNext")
        lines.append("---")
        lines.append("")

        // Title
        lines.append("# \(title) - \(Self.displayDateFormatter.string(from: date))")
        lines.append("")

        // Attendees
        if !attendees.isEmpty {
            let attendeeLinks = attendees.map { "[[People/\($0.wrappedName)|\($0.wrappedName)]]" }
            lines.append("**Attendees:** \(attendeeLinks.joined(separator: ", "))")
            lines.append("")
        }

        if let groupName = meeting.group?.name {
            lines.append("> Group: \(groupName)")
            lines.append("")
        }

        // Summary
        if let summary = meeting.summary, !summary.isEmpty {
            lines.append("## Summary")
            lines.append(stripSentimentData(from: summary))
            lines.append("")
        }

        // Key Topics
        if let topics = meeting.keyTopics as? [String], !topics.isEmpty {
            lines.append("## Key Topics")
            for topic in topics {
                lines.append("- \(topic)")
            }
            lines.append("")
        }

        // Notes
        if let notes = meeting.notes, !notes.isEmpty {
            let cleanNotes = stripSentimentData(from: notes)
            if !cleanNotes.isEmpty {
                lines.append("## Notes")
                lines.append(cleanNotes)
                lines.append("")
            }
        }

        // Transcript
        if let segments = meeting.parsedTranscript, !segments.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            for segment in segments {
                let timestamp = formatTimestamp(segment.timestamp)
                let speaker = segment.speakerName ?? segment.speakerID ?? "Unknown"
                lines.append("**[\(timestamp)] \(speaker):** \(segment.text)")
                lines.append("")
            }
        } else if let transcript = meeting.transcript, !transcript.isEmpty {
            lines.append("## Transcript")
            lines.append(transcript)
            lines.append("")
        }

        // Footer
        lines.append("---")
        lines.append("*Synced from WhoNext*")

        return lines.joined(separator: "\n")
    }

    // MARK: - Person Profile Notes

    /// Generate an Obsidian person profile note with backlinks to their meetings.
    func personNote(from person: Person, conversations: [Conversation], groupMeetings: [GroupMeeting]) -> String {
        let name = person.wrappedName
        let uid = person.identifier?.uuidString ?? UUID().uuidString

        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("type: person")
        lines.append("uid: \"\(uid)\"")
        lines.append("name: \"\(name)\"")
        if let role = person.role, !role.isEmpty {
            lines.append("role: \"\(role)\"")
        }
        lines.append("category: \"\(person.category.rawValue)\"")
        if let tz = person.timezone, !tz.isEmpty, tz != "Unknown" {
            lines.append("timezone: \"\(tz)\"")
        }
        if let lastContact = person.mostRecentContactDate {
            lines.append("last_contact: \(Self.isoFormatter.string(from: lastContact))")
        }
        lines.append("synced_from: WhoNext")
        lines.append("---")
        lines.append("")

        // Title
        lines.append("# \(name)")
        lines.append("")

        // Metadata
        if let role = person.role, !role.isEmpty {
            lines.append("**Role:** \(role)")
        }
        lines.append("**Category:** \(person.category.displayName)")
        if let tz = person.timezone, !tz.isEmpty, tz != "Unknown" {
            lines.append("**Timezone:** \(tz)")
        }
        if let lastContact = person.mostRecentContactDate {
            lines.append("**Last Contact:** \(Self.displayDateFormatter.string(from: lastContact))")
        }
        lines.append("")

        // Person notes
        if let notes = person.notes, !notes.isEmpty {
            lines.append("## Notes")
            lines.append(notes)
            lines.append("")
        }

        // 1:1 Meetings
        let oneOnOnes = conversations.filter { !$0.isSoftDeleted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if !oneOnOnes.isEmpty {
            lines.append("## 1:1 Meetings")
            for conv in oneOnOnes {
                let filename = filenameForConversation(conv).replacingOccurrences(of: ".md", with: "")
                let dateStr = conv.date.map { Self.displayDateFormatter.string(from: $0) } ?? "Unknown date"
                var line = "- [[Meetings/\(filename)|\(dateStr)]]"
                if let summary = conv.summary, !summary.isEmpty {
                    let preview = stripSentimentData(from: summary)
                    let truncated = String(preview.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !truncated.isEmpty {
                        line += " -- \(truncated)"
                        if preview.count > 80 { line += "..." }
                    }
                }
                lines.append(line)
            }
            lines.append("")
        }

        // Group Meetings
        let groups = groupMeetings.filter { !$0.isSoftDeleted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        if !groups.isEmpty {
            lines.append("## Group Meetings")
            for meeting in groups {
                let filename = filenameForGroupMeeting(meeting).replacingOccurrences(of: ".md", with: "")
                let dateStr = meeting.date.map { Self.displayDateFormatter.string(from: $0) } ?? "Unknown date"
                lines.append("- [[Meetings/\(filename)|\(dateStr) - \(meeting.displayTitle)]]")
            }
            lines.append("")
        }

        // Footer stats
        let totalMeetings = oneOnOnes.count + groups.count
        lines.append("---")
        lines.append("*Total meetings: \(totalMeetings) (\(oneOnOnes.count) 1:1s, \(groups.count) group)*")

        return lines.joined(separator: "\n")
    }

    // MARK: - Filenames

    func filenameForConversation(_ conversation: Conversation) -> String {
        let date = conversation.date ?? Date()
        let personName = conversation.person?.wrappedName ?? "Unknown"
        let dateStr = Self.filenameDateFormatter.string(from: date)
        return sanitizeFilename("\(dateStr) - 1on1 with \(personName).md")
    }

    func filenameForGroupMeeting(_ meeting: GroupMeeting) -> String {
        let date = meeting.date ?? Date()
        let dateStr = Self.filenameDateFormatter.string(from: date)
        let title = meeting.displayTitle
        return sanitizeFilename("\(dateStr) - \(title).md")
    }

    func filenameForPerson(_ person: Person) -> String {
        return sanitizeFilename("\(person.wrappedName).md")
    }

    // MARK: - Helpers

    /// Remove characters that are invalid in filenames.
    func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?*\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "-")
    }

    /// Strip the `[SENTIMENT_DATA]` JSON block appended to notes/summaries.
    func stripSentimentData(from text: String) -> String {
        if let range = text.range(of: "\n\n[SENTIMENT_DATA]\n") {
            return String(text[..<range.lowerBound])
        }
        return text
    }

    /// Format seconds as MM:SS for transcript timestamps.
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Fetch action items for a conversation using its Core Data context.
    private func fetchActionItems(for conversation: Conversation) -> [ActionItem] {
        guard let context = conversation.managedObjectContext else { return [] }
        return ActionItem.fetchForConversation(conversation, in: context)
    }
}
