import SwiftUI
import CoreData

struct GlobalNewConversationSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var selectedPerson: Person?
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var toField: String = ""
    @State private var showSuggestions: Bool = false
    @Binding var isPresented: Bool

    var filteredPeople: [Person] {
        let trimmed = toField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return people.filter { $0.name?.localizedCaseInsensitiveContains(trimmed) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle()
                .fill(Color.red)
                .frame(height: 8)
            Text("DEBUG AUTOCOMPLETE")
                .foregroundColor(.red)
                .bold()
            Text("New Conversation")
                .font(.title2)
                .bold()

            // Autocomplete To: field
            VStack(alignment: .leading, spacing: 2) {
                Text("To:")
                ZStack(alignment: .topLeading) {
                    TextField("Type a name...", text: $toField, onEditingChanged: { editing in
                        showSuggestions = editing && !filteredPeople.isEmpty
                    })
                    .frame(width: 220)
                    .onChange(of: toField) { newValue in
                        showSuggestions = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filteredPeople.isEmpty
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
                    .overlay(alignment: .topLeading) {
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
                            }
                            .background(Color.white)
                            .border(Color.gray)
                            .zIndex(1)
                            .frame(width: 220)
                            .offset(y: 28)
                        }
                    }
                }
            }

            DatePicker("Date", selection: $date, displayedComponents: .date)

            Text("Notes:")
                .font(.headline)
            TextEditor(text: $notes)
                .frame(minHeight: 150)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveConversation()
                }
                .disabled(selectedPerson == nil)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 320)
    }

    private func saveConversation() {
        guard let person = selectedPerson else { return }
        let newConversation = Conversation(context: viewContext)
        newConversation.date = date
        newConversation.notes = notes
        newConversation.person = person
        do {
            print("[GlobalNewConversationSheet][LOG] Saving context\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
            try viewContext.save()
            isPresented = false
            notes = ""
            date = Date()
            selectedPerson = nil
            toField = ""
        } catch {
            print("Error saving conversation: \(error.localizedDescription)")
        }
    }
}
