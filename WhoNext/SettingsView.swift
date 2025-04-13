import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var pastedPeopleText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .bold()

            Text("This is where you’ll configure app preferences like reminders or weekly goals.")

            // People Data Import
            Text("Paste people data below, one person per line, format: Name, Role")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $pastedPeopleText)
                .frame(height: 150)
                .border(Color.gray.opacity(0.3))

            Button("Import Pasted People") {
                importPeople(from: pastedPeopleText)
            }
            .buttonStyle(.borderedProminent)

            Divider()

            Spacer()
        }
        .padding()
    }

    // Function to handle importing people from pasted text
    private func importPeople(from text: String) {
        let lines = text.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            let newPerson = Person(context: viewContext)
            newPerson.id = UUID()
            newPerson.name = parts[0]
            newPerson.role = parts[1]
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to import people: \(error)")
        }
    }
}
