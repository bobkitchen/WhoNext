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

    // Store the selected people to prevent constant reshuffling
    @State private var selectedPeople: [Person] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeaderView(
                icon: "icon_bell",
                title: "Follow-up Needed",
                count: !selectedPeople.isEmpty ? min(selectedPeople.count, 2) : nil,
                useSystemIcon: false
            )

            if selectedPeople.isEmpty {
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
                    ForEach(selectedPeople.prefix(2)) { person in
                        PersonCard(
                            person: person,
                            isFollowUp: true,
                            onDismiss: {
                                // Only hide the person from suggestions for this session
                                // Do NOT create a conversation or update lastContactDate
                                if let personID = person.identifier {
                                    dismissedPeopleIDs.insert(personID)
                                    // Remove from selected people and refresh with new suggestion
                                    refreshSuggestions()
                                }
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            // Initialize selected people only once when view appears
            if selectedPeople.isEmpty {
                refreshSuggestions()
            }
        }
    }
}

// MARK: - Methods
extension FollowUpNeededView {
    /// Refresh suggestions by selecting new people from the eligible pool
    /// This is only called explicitly when needed, not on every view redraw
    private func refreshSuggestions() {
        let filtered = people.filter { person in
            // Exclude people without names, direct reports, dismissed people, and current user
            guard person.name != nil,
                  !person.isDirectReport,
                  !person.isCurrentUser,
                  let personID = person.identifier,
                  !dismissedPeopleIDs.contains(personID) else {
                return false
            }
            return true
        }

        // Sort by least recently contacted
        let sorted = filtered.sorted {
            ($0.lastContactDate ?? .distantPast) < ($1.lastContactDate ?? .distantPast)
        }

        // Take a larger pool (e.g., top 6 least-recently-contacted), then shuffle ONCE and pick 2
        // This shuffling only happens when this method is called, not on every view redraw
        let pool = Array(sorted.prefix(6)).shuffled()
        selectedPeople = Array(pool.prefix(2))
    }
}

#Preview {
    FollowUpNeededView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}