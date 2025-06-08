import SwiftUI
import CoreData

struct ConversationDetailView: View {
    var conversation: Conversation
    var isInitiallyEditing: Bool = false

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var updatedNotes: String = ""
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Conversation on \(formattedDate(conversation.date))")
                    .font(.title2.bold())
                Spacer()
                
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete this conversation")
                
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
                    .onChange(of: updatedNotes) { _, newValue in
                        conversation.notes = newValue
                        do {
                            try viewContext.save()
                        } catch {
                            print("Failed to save conversation notes: \(error)")
                        }
                    }
            } else {
                ScrollView {
                    if let notes = conversation.notes {
                        MarkdownView(markdown: notes)
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
            isEditing = isInitiallyEditing
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteConversation()
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func deleteConversation() {
        viewContext.delete(conversation)
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
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
