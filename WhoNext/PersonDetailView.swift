import SwiftUI
import CoreData
import MarkdownUI
import UniformTypeIdentifiers

struct PersonDetailView: View {
    @ObservedObject var person: Person
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedConversation: Conversation?
    @State private var isPresentingDetail = false
    @State private var isEditing = false
    @State private var updatedName: String = ""
    @State private var updatedRole: String = ""
    @State private var updatedTimezone: String = ""
    @State private var updatedNotes: String = ""

    var sortedConversations: [Conversation] {
        let set = person.conversations as? Set<Conversation> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: - Header Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 8) {
                            if let imageData = person.photo, let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            } else {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 60, height: 60)
                                    .overlay(Text(initials(from: person.name)).foregroundColor(.white))
                            }

                            if isEditing {
                                Button("Change Photo") {
                                    selectNewPhoto()
                                }
                                .font(.caption)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if isEditing {
                                TextField("Name", text: $updatedName)
                                    .font(.title2.bold())
                                TextField("Role", text: $updatedRole)
                                    .font(.body)
                                Picker("Time Zone", selection: $updatedTimezone) {
                                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { id in
                                        Text(id).tag(id)
                                    }
                                }
                                .font(.subheadline)
                                .pickerStyle(.menu)
                                Toggle("Direct Report", isOn: .init(
                                    get: { person.isDirectReport },
                                    set: { person.isDirectReport = $0 }
                                ))
                                .font(.subheadline)
                            } else {
                                Text(person.name ?? "No Name")
                                    .font(.title2.bold())
                                Text("Role: \(person.role ?? "No Role")")
                                    .font(.body)
                                Text("Time Zone: \(person.timezone ?? "No Time Zone")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if person.isDirectReport {
                                    Text("Direct Report")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        Button(action: {
                            if isEditing {
                                person.name = updatedName
                                person.role = updatedRole
                                person.timezone = updatedTimezone
                                person.notes = updatedNotes
                                do {
                                    try viewContext.save()
                                } catch {
                                    print("Failed to save person details: \(error)")
                                }
                            }
                            isEditing.toggle()
                        }) {
                            Text(isEditing ? "Save" : "Edit")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                )
                .padding(.horizontal, 4)

                // MARK: - Notes Section
                if isEditing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextEditor(text: $updatedNotes)
                            .frame(height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal)
                } else if let notes = person.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Markdown(notes)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                // MARK: - Conversations Header
                HStack {
                    Text("Conversations")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: {
                        let newConversation = Conversation(context: viewContext)
                        newConversation.date = Date()
                        newConversation.notes = "New conversation started."
                        newConversation.uuid = UUID() // Ensure this line is present before saving
                        newConversation.person = person

                        do {
                            try viewContext.save()
                            openConversationWindow(for: newConversation)
                        } catch {
                            print("Failed to create new conversation: \(error)")
                        }
                    }) {
                        Text("New")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)

                // MARK: - Conversations List
                if sortedConversations.isEmpty {
                    Text("No conversations yet.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(sortedConversations, id: \.uuid) { conversation in
                            Button(action: {
                                openConversationWindow(for: conversation)
                            }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(formattedDate(conversation.date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let preview = conversation.notes, !preview.isEmpty {
                                        Text(previewText(from: preview))
                                            .font(.caption)
                                            .lineSpacing(2)
                                            .lineLimit(3)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("No notes yet")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .frame(width: 160, height: 160, alignment: .topLeading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .frame(minHeight: 200)
                }

                Spacer()
            }
            .padding(.top)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            updatedName = person.name ?? ""
            updatedRole = person.role ?? ""
            updatedTimezone = person.timezone ?? ""
            updatedNotes = person.notes ?? ""
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func previewText(from notes: String) -> String {
        let lines = notes.split(separator: "\n")
        return lines.prefix(2).joined(separator: " ")
    }

    private func deleteConversation(at offsets: IndexSet) {
        for index in offsets {
            let conversation = sortedConversations[index]
            viewContext.delete(conversation)
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    private func initials(from name: String?) -> String {
        let components = name?.split(separator: " ") ?? []
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined()
    }

    private func selectNewPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.begin { response in
            if response == .OK, let url = panel.url, let imageData = try? Data(contentsOf: url) {
                person.photo = imageData
                do {
                    try viewContext.save()
                } catch {
                    print("Failed to save new photo: \(error)")
                }
            }
        }
    }

    private func openConversationWindow(for conversation: Conversation) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ConversationDetailView.formattedWindowTitle(for: conversation, person: person)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: conversation)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
}
