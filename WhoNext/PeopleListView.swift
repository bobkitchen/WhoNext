import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    var body: some View {
        List {
            ForEach(people) { person in
                PersonRowView(
                    person: person,
                    onSelect: { selectedPerson = person },
                    onDelete: { deletePerson(person) }
                )
            }
        }
        .listStyle(.plain)
    }
    
    private func deletePerson(_ person: Person) {
        if selectedPerson == person {
            selectedPerson = nil
        }
        viewContext.delete(person)
        try? viewContext.save()
    }
}

struct PersonRowView: View {
    let person: Person
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(person.initials)
                            .foregroundColor(.white)
                            .font(.caption.weight(.bold))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name ?? "Unnamed")
                        .font(.headline)

                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete \(person.name ?? "person")")
            }
            .padding(.vertical, 4)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}
