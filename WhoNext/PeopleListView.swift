import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: nil
    ) private var people: FetchedResults<Person>

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
        .listStyle(.plain)
        .background(Color(.windowBackgroundColor))
    }
    
    private func deletePerson(_ person: Person) {
        if selectedPerson == person {
            selectedPerson = nil
        }
        viewContext.delete(person)
        try? viewContext.save()
    }
}
