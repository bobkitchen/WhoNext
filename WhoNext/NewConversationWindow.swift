import SwiftUI
import CoreData

struct NewConversationWindow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    @Binding var isPresented: Bool
    @State private var selectedPerson: Person? = nil
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isEditorFocused: Bool = false
    @State private var searchText: String = ""
    @State private var richNotes: NSAttributedString = NSAttributedString(string: "")
    @State private var showDropdown: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    private func resetFields() {
        selectedPerson = nil
        date = Date()
        notes = ""
        richNotes = NSAttributedString(string: "")
        searchText = ""
    }

    var filteredPeople: [Person] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(people)
        }
        return people.filter { person in
            (person.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Conversation")
                .font(.title2)
                .fontWeight(.bold)
            // Custom autocomplete staff picker
            VStack(alignment: .leading, spacing: 4) {
                TextField("Search staff...", text: $searchText, onEditingChanged: { editing in
                    showDropdown = editing
                })
                .focused($isSearchFieldFocused)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: searchText) { oldValue, newValue in showDropdown = true }
                .onTapGesture { showDropdown = true }
                .onSubmit {
                    if let first = filteredPeople.first {
                        selectedPerson = first
                        searchText = first.name ?? ""
                        showDropdown = false
                    }
                }
                if showDropdown && !filteredPeople.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredPeople, id: \.self) { person in
                                Button(action: {
                                    selectedPerson = person
                                    searchText = person.name ?? ""
                                    showDropdown = false
                                    isSearchFieldFocused = false
                                }) {
                                    HStack {
                                        Text(person.name ?? "<unknown>")
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedPerson == person {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15)))
                }
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Text("Notes:")
            RichTextEditor(text: $richNotes, isEditable: true, onAction: nil, isFocused: $isEditorFocused)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
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
        .frame(minWidth: 400, minHeight: 420)
        .onAppear {
            resetFields()
        }
    }

    private func saveConversation() {
        guard let person = selectedPerson else { print("No person selected"); return }
        let newConversation = Conversation(context: viewContext)
        newConversation.date = date
        newConversation.notes = richNotes.string // Save plain text for previews/legacy
        newConversation.notesRTF = try? richNotes.data(from: NSRange(location: 0, length: richNotes.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        newConversation.person = person
        newConversation.uuid = UUID()
        do {
            try viewContext.save()
            isPresented = false
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
}
