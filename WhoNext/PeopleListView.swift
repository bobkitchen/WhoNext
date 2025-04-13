import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @State private var hoveredPersonID: NSManagedObjectID?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(people) { person in
                    let isHovered = hoveredPersonID == person.objectID

                    Button(action: {
                        selectedPerson = person
                    }) {
                        HStack(alignment: .center, spacing: 12) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(initials(for: person))
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
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(isHovered ? 0.2 : 0), radius: isHovered ? 6 : 0, x: 0, y: 3)
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        hoveredPersonID = hovering ? person.objectID : nil
                    }
                    .accessibilityIdentifier("personButton_\\(person.objectID.uriRepresentation().absoluteString)")
                }
            }
            .padding()
        }
    }
    
    private func initials(for person: Person) -> String {
        let components = (person.name ?? "")
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)) }

        return components.joined().uppercased()
    }
}
