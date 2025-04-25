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
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Conversation")
                .font(.title2)
                .bold()

            Picker("Person", selection: $selectedPerson) {
                Text("Select a person").tag(Person?.none)
                ForEach(people, id: \ .self) { person in
                    Text(person.name ?? "Unknown").tag(Person?.some(person))
                }
            }
            .pickerStyle(.menu)

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
            try viewContext.save()
            isPresented = false
            notes = ""
            date = Date()
            selectedPerson = nil
        } catch {
            print("Error saving conversation: \(error.localizedDescription)")
        }
    }
}
