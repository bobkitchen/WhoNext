import SwiftUI
import CoreData
import MarkdownUI

struct ConversationDetailView: View {
    var conversation: Conversation
    var isInitiallyEditing: Bool = false

    @Environment(\.managedObjectContext) private var viewContext
    @State private var isEditing = false
    @State private var updatedNotes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Conversation on \(formattedDate(conversation.date))")
                    .font(.title2.bold())
                Spacer()
                Picker("", selection: $isEditing) {
                    Text("Preview").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 160)
            }

            if isEditing {
                TextEditor(text: $updatedNotes)
                    .font(.body)
                    .padding(10)
                    .frame(minHeight: 300)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: updatedNotes) { newValue in
                        conversation.notes = newValue
                        try? viewContext.save()
                    }
            } else {
                ScrollView {
                    if let notes = conversation.notes {
                        Markdown(notes)
                            .padding()
                    } else {
                        Text("No notes available.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            updatedNotes = conversation.notes ?? ""
            if isInitiallyEditing {
                isEditing = true
            }
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    static func formattedWindowTitle(for conversation: Conversation, person: Person) -> String {
        let dateString: String = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: conversation.date ?? Date())
        }()

        let personName = person.name ?? "Unknown"
        let preview = (conversation.notes ?? "")
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "(No notes yet)"

        return "\(personName) – \(dateString): \(preview)"
    }
}
