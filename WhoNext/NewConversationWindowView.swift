import SwiftUI
import CoreData

struct NewConversationWindowView: View {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var toField: String = ""
    @State private var selectedPerson: Person? = nil
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var showSuggestions: Bool = false
    @FocusState private var toFieldFocused: Bool

    var filteredPeople: [Person] {
        let trimmed = toField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return people.filter { $0.name?.localizedCaseInsensitiveContains(trimmed) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Conversation")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("To:")
                ZStack(alignment: .topLeading) {
                    TextField("Type a name...", text: $toField, onEditingChanged: { editing in
                        showSuggestions = editing && !filteredPeople.isEmpty
                    })
                    .focused($toFieldFocused)
                    .frame(width: 280)
                    .onChange(of: toField) { newValue in
                        showSuggestions = toFieldFocused && !filteredPeople.isEmpty
                        if let match = people.first(where: { $0.name == newValue }) {
                            selectedPerson = match
                        } else {
                            selectedPerson = nil
                        }
                    }
                    .onSubmit {
                        if let match = people.first(where: { $0.name == toField }) {
                            selectedPerson = match
                            showSuggestions = false
                        }
                    }
                    if showSuggestions && !filteredPeople.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredPeople.prefix(5), id: \.id) { person in
                                Button(action: {
                                    toField = person.name ?? ""
                                    selectedPerson = person
                                    showSuggestions = false
                                }) {
                                    HStack {
                                        Text(person.name ?? "")
                                            .fontWeight(selectedPerson?.id == person.id ? .medium : .regular)
                                        if let role = person.role, !role.isEmpty {
                                            Text("· " + role)
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(selectedPerson?.id == person.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                        .shadow(radius: 6)
                        .frame(width: 300)
                        .offset(y: 34)
                    }
                }
                if let selected = selectedPerson {
                    Text(selected.role ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .padding(.vertical, 4)
            Text("Notes:")
            TextEditor(text: $notes)
                .frame(height: 120)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
                .background(Color(.textBackgroundColor))
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel?()
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let person = selectedPerson {
                        let newConversation = Conversation(context: viewContext)
                        newConversation.date = date
                        newConversation.notes = notes
                        newConversation.person = person
                        do {
                            try viewContext.save()
                        } catch {
                            print("Failed to save conversation: \(error)")
                        }
                    }
                    onSave?()
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedPerson == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 540, minHeight: 320, maxHeight: .infinity)
    }
}

#if canImport(AppKit)
extension View {
    func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
#endif
