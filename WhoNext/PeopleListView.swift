import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: nil
    ) private var people: FetchedResults<Person>

    @State private var showingAddPersonSheet = false

    var body: some View {
        List {
            ForEach(people) { person in
                HStack(spacing: 16) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .systemGray).opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Text(person.initials)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    // Name and Role
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name ?? "Unnamed")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(.primary)

                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Delete Button
                    Button(action: { deletePerson(person) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                    }
                    .buttonStyle(.plain)
                    .help("Delete \(person.name ?? "person")")
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Defer selection to prevent jumping
                    DispatchQueue.main.async {
                        selectedPerson = person
                    }
                }
                .background(person.id == selectedPerson?.id ? Color.accentColor.opacity(0.1) : Color.clear)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showingAddPersonSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Add new person")
            }
        }
        .sheet(isPresented: $showingAddPersonSheet) {
            AddPersonView { name, role, timezone, isDirectReport, notes, photoData in
                let newPerson = Person(context: viewContext)
                let newId = UUID()
                newPerson.identifier = newId
                newPerson.name = name
                newPerson.role = role
                newPerson.timezone = timezone
                newPerson.isDirectReport = isDirectReport
                newPerson.notes = notes
                if let photoData = photoData {
                    newPerson.photo = photoData
                }
                do {
                    try viewContext.save()
                    // Set the selection to the new person by identifier
                    DispatchQueue.main.async {
                        // Find the new person in the context after save
                        let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
                        fetchRequest.predicate = NSPredicate(format: "identifier == %@", newId as CVarArg)
                        if let results = try? viewContext.fetch(fetchRequest), let savedPerson = results.first {
                            selectedPerson = savedPerson
                        } else {
                            selectedPerson = newPerson // fallback
                        }
                    }
                } catch {
                    // Handle error
                }
                showingAddPersonSheet = false
            }
        }
        .onChange(of: people.map { $0.identifier }) { _ in
            // Defensive: re-sync selectedPerson by identifier if needed
            if let id = selectedPerson?.identifier {
                if let match = people.first(where: { $0.identifier == id }) {
                    selectedPerson = match
                } else {
                    selectedPerson = nil
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.windowBackgroundColor))
    }
    
    private func deletePerson(_ person: Person) {
        if selectedPerson == person {
            selectedPerson = nil
        }
        viewContext.delete(person)
        print("[PeopleListView][LOG] Deleting person and saving context\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        try? viewContext.save()
    }
}
