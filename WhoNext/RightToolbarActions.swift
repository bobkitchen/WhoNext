import SwiftUI

struct RightToolbarActions: View {
    @ObservedObject var appState: AppState
    @Binding var searchText: String
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        HStack(spacing: 12) {
            SearchBar(searchText: $searchText) { person in
                appState.selectedTab = .people
                appState.selectedPerson = person
                appState.selectedPersonID = person.identifier
            }
            .frame(width: 200) // Increased width for better usability
            
            Button(action: {
                openWindow(id: "settings")
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Settings")
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    RightToolbarActions(
        appState: AppState(),
        searchText: .constant("")
    )
}