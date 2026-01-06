import SwiftUI
import CoreData
import AppKit

struct GroupDetailView: View {
    @ObservedObject var group: Group
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var appStateManager: AppStateManager

    @State private var preMeetingBrief: String?
    @State private var isGeneratingBrief = false
    @StateObject private var hybridAI = HybridAIService()
    @State private var preMeetingBriefWindowController: GroupPreMeetingBriefWindowController?
    @State private var showingEditGroup = false
    @State private var showingAddMember = false
    @State private var showingAddMeeting = false
    @State private var selectedMeeting: GroupMeeting?

    private var meetings: [GroupMeeting] {
        group.sortedMeetings.filter { !$0.isSoftDeleted }
    }

    private var members: [Person] {
        group.sortedMembers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                descriptionView
                membersView
                analyticsView
                preMeetingBriefView
                meetingsView
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .errorAlert(ErrorManager.shared)
        .sheet(isPresented: $showingEditGroup) {
            GroupEditView(group: group)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberToGroupView(group: group)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingAddMeeting) {
            CreateGroupMeetingView(group: group)
                .environment(\.managedObjectContext, viewContext)
        }
        .onDisappear {
            closePreMeetingBriefWindow()
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack(alignment: .top, spacing: 24) {
            // Group Icon
            ZStack {
                Circle()
                    .fill(groupColor.opacity(0.15))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle()
                            .stroke(groupColor.opacity(0.3), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: groupIcon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(groupColor)
                    }
                    .shadow(color: groupColor.opacity(0.2), radius: 4, x: 0, y: 2)
            }

            // Group Info
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name ?? "Unnamed Group")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    // Member count badge
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(members.count) members")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(.secondary.opacity(0.1))
                    }

                    // Meeting count badge
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(meetings.count) meetings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(.secondary.opacity(0.1))
                    }

                    // Group type badge
                    if let type = group.type, !type.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(groupColor)
                            Text(type)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(groupColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(groupColor.opacity(0.1))
                                .overlay {
                                    Capsule()
                                        .stroke(groupColor.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                    }
                }

                // Last meeting info
                if let lastMeeting = group.mostRecentMeeting, let date = lastMeeting.date {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Last meeting: \(relativeDate(date))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: { showingAddMember = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("Add Member")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))

                Button(action: { showingEditGroup = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                        Text("Edit")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
            }
        }
        .liquidGlassCard(
            cornerRadius: 16,
            elevation: .medium,
            padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
            isInteractive: false
        )
    }

    // MARK: - Description View
    @ViewBuilder
    private var descriptionView: some View {
        if let description = group.groupDescription, !description.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("About")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .cornerRadius(12)
        }
    }

    // MARK: - Members View
    private var membersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Members")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()

                Button(action: { showingAddMember = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if members.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No members yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("Add members to track who participates in this group's meetings")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Member avatars grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(members, id: \.identifier) { person in
                        MemberCard(person: person, group: group)
                            .environment(\.managedObjectContext, viewContext)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Analytics View
    @ViewBuilder
    private var analyticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                Text("Group Analytics")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("(\(meetings.count) meetings)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if meetings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No meeting data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Record meetings to see analytics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                // Analytics Cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    // Average Sentiment Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "face.smiling.fill")
                                .font(.system(size: 12))
                                .foregroundColor(averageSentimentColor)
                            Text("Avg Sentiment")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text(averageSentimentLabel)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(averageSentimentColor)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Total Duration Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            Text("Total Time")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text(formattedTotalDuration)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Meeting Frequency Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("Frequency")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text(meetingFrequency)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Pre-Meeting Brief View
    @ViewBuilder
    private var preMeetingBriefView: some View {
        if !meetings.isEmpty || !members.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Pre-Meeting Brief")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if let brief = preMeetingBrief, !brief.isEmpty {
                        HStack(spacing: 8) {
                            // Pop Out button
                            Button(action: {
                                openPreMeetingBriefWindow(brief)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                    Text("Pop Out")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Copy button
                            Button(action: {
                                copyToClipboard(brief)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 10))
                                    Text("Copy")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Button(action: isGeneratingBrief ? {} : generatePreMeetingBrief) {
                            HStack(spacing: 4) {
                                if isGeneratingBrief {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                }
                                Text(isGeneratingBrief ? "Generating..." : "Generate")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isGeneratingBrief)
                    }
                }

                if let brief = preMeetingBrief, !brief.isEmpty {
                    ScrollView {
                        Text(brief)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .cornerRadius(12)
        }
    }

    // MARK: - Meetings View
    private var meetingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Meetings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                Button(action: { showingAddMeeting = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("New Meeting")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if meetings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))

                    VStack(spacing: 8) {
                        Text("No meetings yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Record or add meetings to start tracking this group's discussions")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: { showingAddMeeting = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                            Text("Add First Meeting")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(meetings) { meeting in
                        GroupMeetingRowView(meeting: meeting)
                            .environment(\.managedObjectContext, viewContext)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var groupColor: Color {
        switch group.type?.lowercased() {
        case "team":
            return .blue
        case "project":
            return .purple
        case "department":
            return .green
        case "external":
            return .orange
        default:
            return .accentColor
        }
    }

    private var groupIcon: String {
        switch group.type?.lowercased() {
        case "team":
            return "person.3.fill"
        case "project":
            return "folder.fill"
        case "department":
            return "building.2.fill"
        case "external":
            return "globe"
        default:
            return "person.3.fill"
        }
    }

    private var averageSentiment: Double {
        let sentiments = meetings.map { $0.sentimentScore }
        guard !sentiments.isEmpty else { return 0.5 }
        return sentiments.reduce(0, +) / Double(sentiments.count)
    }

    private var averageSentimentLabel: String {
        if averageSentiment >= 0.7 { return "Positive" }
        else if averageSentiment >= 0.4 { return "Neutral" }
        else { return "Negative" }
    }

    private var averageSentimentColor: Color {
        if averageSentiment >= 0.7 { return .green }
        else if averageSentiment >= 0.4 { return .blue }
        else { return .red }
    }

    private var totalDuration: Int {
        meetings.reduce(0) { $0 + Int($1.duration) }
    }

    private var formattedTotalDuration: String {
        let hours = totalDuration / 3600
        let minutes = (totalDuration % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var meetingFrequency: String {
        guard meetings.count >= 2 else { return "N/A" }

        let sortedDates = meetings.compactMap { $0.date }.sorted()
        guard let firstDate = sortedDates.first, let lastDate = sortedDates.last else {
            return "N/A"
        }

        let daysBetween = Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0
        guard daysBetween > 0 else { return "Daily" }

        let avgDays = Double(daysBetween) / Double(meetings.count - 1)

        if avgDays <= 1 { return "Daily" }
        else if avgDays <= 7 { return "Weekly" }
        else if avgDays <= 14 { return "Bi-weekly" }
        else if avgDays <= 30 { return "Monthly" }
        else { return "Occasional" }
    }

    // MARK: - Helper Methods

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func generatePreMeetingBrief() {
        isGeneratingBrief = true
        preMeetingBrief = nil

        Task {
            do {
                let context = generateGroupContext()
                let brief = try await hybridAI.generatePreMeetingBrief(personData: members, context: context)

                await MainActor.run {
                    self.preMeetingBrief = brief
                    self.isGeneratingBrief = false
                }
            } catch {
                await MainActor.run {
                    ErrorManager.shared.handle(error, context: "Failed to generate group pre-meeting brief")
                    self.isGeneratingBrief = false
                }
            }
        }
    }

    private func generateGroupContext() -> String {
        var context = """
        GROUP: \(group.name ?? "Unnamed Group")
        TYPE: \(group.type ?? "General")
        MEMBERS: \(members.map { $0.name ?? "Unknown" }.joined(separator: ", "))
        TOTAL MEETINGS: \(meetings.count)

        """

        if let description = group.groupDescription, !description.isEmpty {
            context += "DESCRIPTION: \(description)\n\n"
        }

        // Add recent meeting summaries
        let recentMeetings = meetings.prefix(3)
        if !recentMeetings.isEmpty {
            context += "RECENT MEETINGS:\n"
            for meeting in recentMeetings {
                if let date = meeting.date {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    context += "\n--- \(dateFormatter.string(from: date)) ---\n"
                }
                if let summary = meeting.summary, !summary.isEmpty {
                    context += summary + "\n"
                } else if let transcript = meeting.transcript, !transcript.isEmpty {
                    // Use first 500 chars of transcript if no summary
                    context += String(transcript.prefix(500)) + "...\n"
                }
            }
        }

        return context
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openPreMeetingBriefWindow(_ briefContent: String) {
        closePreMeetingBriefWindow()

        let windowController = GroupPreMeetingBriefWindowController(
            groupName: group.name ?? "Unknown Group",
            briefContent: briefContent
        ) { [self] in
            preMeetingBriefWindowController = nil
        }

        preMeetingBriefWindowController = windowController
        windowController.showWindow(nil)
    }

    private func closePreMeetingBriefWindow() {
        preMeetingBriefWindowController?.close()
        preMeetingBriefWindowController = nil
    }
}

// MARK: - Member Card
struct MemberCard: View {
    let person: Person
    let group: Group
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                if let data = person.photo, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(person.initials)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .overlay {
                Circle()
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            }

            // Name
            Text(person.name ?? "Unknown")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Role
            if let role = person.role, !role.isEmpty {
                Text(role)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: {
                removeMember()
            }) {
                Label("Remove from Group", systemImage: "person.badge.minus")
            }
        }
    }

    private func removeMember() {
        group.removeMember(person)
        try? viewContext.save()
    }
}

// MARK: - Group Meeting Row View
struct GroupMeetingRowView: View {
    let meeting: GroupMeeting
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dateIndicator
            meetingContent
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            openMeetingWindow()
        }
        .contextMenu {
            Button(action: openMeetingWindow) {
                Label("Open in Window", systemImage: "macwindow")
            }

            Divider()

            Button(action: deleteMeeting) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var dateIndicator: some View {
        VStack(spacing: 4) {
            if let date = meeting.date {
                Text(dayFormatter.string(from: date))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(monthFormatter.string(from: date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 50)
        .padding(.vertical, 4)
    }

    private var meetingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()

                // Sentiment indicator
                Circle()
                    .fill(sentimentColor)
                    .frame(width: 8, height: 8)

                if let date = meeting.date {
                    Text(timeFormatter.string(from: date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Duration and attendees
            HStack(spacing: 12) {
                if meeting.duration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(meeting.formattedDuration)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                if meeting.attendeeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(meeting.attendeeCount) attendees")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Summary preview
            if let summary = meeting.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentimentColor: Color {
        if meeting.sentimentScore >= 0.7 { return .green }
        else if meeting.sentimentScore >= 0.4 { return .orange }
        else { return .red }
    }

    private func openMeetingWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = meeting.displayTitle
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: GroupMeetingDetailView(meeting: meeting)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }

    private func deleteMeeting() {
        meeting.softDelete()
        try? viewContext.save()
    }

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Group Pre-Meeting Brief Window Controller
class GroupPreMeetingBriefWindowController: NSWindowController {
    private let onClose: () -> Void

    init(groupName: String, briefContent: String, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "Pre-Meeting Brief - \(groupName)"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        window.contentView = NSHostingView(
            rootView: GroupPreMeetingBriefWindow(
                groupName: groupName,
                briefContent: briefContent,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        super.close()
        onClose()
    }
}

extension GroupPreMeetingBriefWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - Group Pre-Meeting Brief Window View
struct GroupPreMeetingBriefWindow: View {
    let groupName: String
    let briefContent: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                Text("\(groupName) - Pre-Meeting Brief")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Text(briefContent)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            HStack {
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(briefContent, forType: .string)
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Group Meeting Detail View
struct GroupMeetingDetailView: View {
    let meeting: GroupMeeting
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(meeting.displayTitle)
                        .font(.system(size: 24, weight: .bold))

                    HStack(spacing: 16) {
                        if let date = meeting.date {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                Text(dateFormatter.string(from: date))
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.secondary)
                        }

                        if meeting.duration > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                Text(meeting.formattedDuration)
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.secondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "person.2")
                                .font(.system(size: 12))
                            Text("\(meeting.attendeeCount) attendees")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Attendees
                if meeting.attendeeCount > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attendees")
                            .font(.system(size: 16, weight: .semibold))

                        FlowLayout(spacing: 8) {
                            ForEach(meeting.sortedAttendees, id: \.identifier) { person in
                                HStack(spacing: 6) {
                                    if let data = person.photo, let image = NSImage(data: data) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 24, height: 24)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.2))
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Text(person.initials)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.accentColor)
                                            }
                                    }
                                    Text(person.name ?? "Unknown")
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(16)
                            }
                        }
                    }
                }

                // Summary
                if let summary = meeting.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.system(size: 16, weight: .semibold))

                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }

                // Transcript
                if let transcript = meeting.transcript, !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcript")
                            .font(.system(size: 16, weight: .semibold))

                        Text(transcript)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(16)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                    }
                }

                // Notes
                if let notes = meeting.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.system(size: 16, weight: .semibold))

                        Text(notes)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Flow Layout for Tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing

                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}
