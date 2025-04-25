import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct PersonDetailView: View {
    let person: Person
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isEditing = false
    
    // State for edit mode
    @State private var editingName = ""
    @State private var editingRole = ""
    @State private var editingTimezone = ""
    @State private var editingNotes = ""
    @State private var isDirectReport = false
    @State private var editingPhotoData: Data? = nil
    @State private var editingPhotoImage: NSImage? = nil
    @State private var showingPhotoPicker = false

    var sortedConversations: [Conversation] {
        let set = person.conversations as? Set<Conversation> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                // Avatar and photo button vertically stacked
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .systemGray).opacity(0.15))
                            .frame(width: 64, height: 64)
                        if isEditing {
                            if let image = editingPhotoImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(Circle())
                                    .frame(width: 64, height: 64)
                            } else {
                                Text(initials(from: editingName))
                                    .font(.system(size: 24, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        } else if let data = person.photo, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .clipShape(Circle())
                                .frame(width: 64, height: 64)
                        } else {
                            Text(person.initials)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    if isEditing {
                        Button("Choose Photo") { showingPhotoPicker = true }
                            .font(.system(size: 12))
                    }
                }
                // Name, role, etc. remain to the right, with more space
                VStack(alignment: .leading, spacing: 6) {
                    if isEditing {
                        TextField("Name", text: $editingName)
                            .font(.system(size: 20, weight: .semibold))
                            .textFieldStyle(.plain)
                        TextField("Role", text: $editingRole)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .textFieldStyle(.plain)
                        TextField("Timezone", text: $editingTimezone)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .textFieldStyle(.plain)
                            .padding(.top, 2)
                        Toggle("Direct Report", isOn: $isDirectReport)
                            .font(.system(size: 13))
                            .toggleStyle(.checkbox)
                            .padding(.top, 4)
                    } else {
                        Text(person.name ?? "")
                            .font(.system(size: 20, weight: .semibold))
                        if let role = person.role {
                            Text(role)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        if let timezone = person.timezone {
                            Text(timezone)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        if person.isDirectReport {
                            Text("Direct Report")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { 
                    if isEditing {
                        saveChanges()
                    }
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "Save" : "Edit")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            
            // Notes Section (when editing)
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: 15, weight: .semibold))
                    
                    TextEditor(text: $editingNotes)
                        .font(.system(size: 13))
                        .frame(height: 100)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
            } else if let notes = person.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            // Conversations Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Conversations")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Spacer()
                    
                    Button(action: createNewConversation) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
                
                if sortedConversations.isEmpty {
                    Text("No conversations yet.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showingPhotoPicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    editingPhotoData = data
                    editingPhotoImage = image
                }
            default:
                break
            }
        }
        .onAppear {
            editingName = person.name ?? ""
            editingRole = person.role ?? ""
            editingTimezone = person.timezone ?? ""
            editingNotes = person.notes ?? ""
            isDirectReport = person.isDirectReport
            if let data = person.photo, let image = NSImage(data: data) {
                editingPhotoData = data
                editingPhotoImage = image
            } else {
                editingPhotoData = nil
                editingPhotoImage = nil
            }
        }
    }
    
    private func saveChanges() {
        person.name = editingName
        person.role = editingRole
        person.timezone = editingTimezone
        person.notes = editingNotes
        person.isDirectReport = isDirectReport
        if let editingPhotoData = editingPhotoData {
            person.photo = editingPhotoData
        }
        try? viewContext.save()
    }
    
    private func createNewConversation() {
        let conversation = Conversation(context: viewContext)
        conversation.date = Date()
        conversation.person = person
        conversation.uuid = UUID()
        conversation.notes = ""
        
        try? viewContext.save()
        openConversationWindow(for: conversation)
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

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
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
        window.title = "Conversation with \(person.name ?? "Unknown")"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ConversationDetailView(conversation: conversation)
                .environment(\.managedObjectContext, viewContext)
        )
        window.makeKeyAndOrderFront(nil)
    }
}
