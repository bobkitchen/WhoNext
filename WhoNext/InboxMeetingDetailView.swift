import SwiftUI
import CoreData

struct InboxMeetingDetailView: View {
    let meeting: GroupMeeting

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    Text("Meeting Details")
                        .font(.headline)

                    Spacer()

                    // Type badge
                    Text("Group Meeting")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }

                // Details card
                detailsCard

                // Summary
                if let summary = meeting.summary, !summary.isEmpty {
                    sectionView(title: "Summary", content: summary)
                }

                // Transcript
                if let transcript = meeting.transcript, !transcript.isEmpty {
                    sectionView(title: "Transcript", content: transcript)
                }

                // Notes
                if let notes = meeting.notes, !notes.isEmpty {
                    sectionView(title: "Notes", content: notes)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(meeting.title?.isEmpty == false ? meeting.title! : "Untitled Meeting")
                    .font(.title3)
                    .fontWeight(.medium)
            }

            HStack(spacing: 24) {
                // Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text((meeting.date ?? Date()).formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                }

                // Duration
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(meeting.duration) minutes")
                        .font(.body)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section View

    private func sectionView(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
