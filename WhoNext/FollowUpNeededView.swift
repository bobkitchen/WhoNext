import SwiftUI
import CoreData

struct FollowUpNeededView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>
    
    // Track dismissed people for current session only
    @State private var dismissedPeopleIDs: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeaderView(
                icon: "icon_bell",
                title: "Follow-up Needed",
                count: !suggestedPeople.isEmpty ? min(suggestedPeople.count, 2) : nil,
                useSystemIcon: false
            )
            
            if suggestedPeople.isEmpty {
                EmptyStateCard(
                    icon: "checkmark.circle.fill",
                    title: "No follow-ups needed",
                    subtitle: "All relationships are up to date",
                    iconColor: .green.opacity(0.5)
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(suggestedPeople.prefix(2))) { person in
                        PersonCardView(
                            person: person,
                            isFollowUp: true,
                            onDismiss: {
                                // Only hide the person from suggestions for this session
                                // Do NOT create a conversation or update lastContactDate
                                if let personID = person.identifier {
                                    dismissedPeopleIDs.insert(personID)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Computed Properties
extension FollowUpNeededView {
    private var suggestedPeople: [Person] {
        let filtered = people.filter { person in
            // Exclude people without names, direct reports, and dismissed people
            guard let name = person.name,
                  !person.isDirectReport,
                  let personID = person.identifier,
                  !dismissedPeopleIDs.contains(personID) else {
                return false
            }
            return true
        }
        // Sort by least recently contacted, then shuffle for randomness among those with the same lastContactDate
        let sorted = filtered.sorted {
            ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast)
        }
        // Take a larger pool (e.g., top 6 least-recently-contacted), then shuffle and pick 2
        let pool = Array(sorted.prefix(6)).shuffled()
        let result = Array(pool.prefix(2))
        return result
    }
}

#Preview {
    FollowUpNeededView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}