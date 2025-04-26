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
                .font(.title2)
                .bold()
            HStack {
                Text("To:")
                TextField("Type a name...", text: $toField, onEditingChanged: { editing in
                    showSuggestions = editing && !filteredPeople.isEmpty
                })
                .focused($toFieldFocused)
                .frame(width: 220)
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
                .sheet(isPresented: $showSuggestions) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Suggestions")
                            .font(.headline)
                            .padding(.top)
                        ForEach(filteredPeople.prefix(5), id: \.id) { person in
                            Button(action: {
                                toField = person.name ?? ""
                                selectedPerson = person
                                showSuggestions = false
                            }) {
                                HStack {
                                    Text(person.name ?? "")
                                        .foregroundColor(.primary)
                                    if let role = person.role, !role.isEmpty {
                                        Text("(") + Text(role) + Text(")")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(width: 300, height: 200)
                    .padding()
                }
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Text("Notes:")
            TextEditor(text: $notes)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel?()
                    closeWindow()
                }
                Button("Save") {
                    onSave?()
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPerson == nil)
            }
        }
        .padding()
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }
}

#if canImport(AppKit)
extension View {
    func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
#endif
