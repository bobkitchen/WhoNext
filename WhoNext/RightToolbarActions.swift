import SwiftUI

struct RightToolbarActions<T: StateManagement>: View {
    @ObservedObject var appState: T
    @Binding var searchText: String
    
    var body: some View {
        HStack(spacing: 12) {
            SearchBar(searchText: $searchText) { person in
                appState.selectedTab = .people
                appState.selectedPerson = person
                appState.selectedPersonID = person.identifier
            }
            .frame(width: 200) // Increased width for better usability
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    let context = PersistenceController.shared.container.viewContext
    RightToolbarActions(
        appState: AppStateManager(viewContext: context),
        searchText: .constant("")
    )
}