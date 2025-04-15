import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @State private var hoveredPersonID: NSManagedObjectID?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    var body: some View {
        List(people) { person in
            PersonRowView(
                person: person,
                isSelected: selectedPerson?.id == person.id,
                isHovered: hoveredPersonID == person.objectID,
                onSelect: { selectedPerson = person },
                onDelete: { deletePerson(person) }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    hoveredPersonID = hovering ? person.objectID : nil
                }
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
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
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
                        .foregroundColor(.primary)

                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(isHovered ? .red : .secondary)
                        .opacity(isHovered ? 1.0 : 0.5)
                }
                .buttonStyle(.plain)
                .help("Delete \(person.name ?? "person")")
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ? Color.accentColor.opacity(0.1) :
                    isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear
                )
        )
    }
}
