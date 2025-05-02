import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var appState = AppState()
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var showingNewConversationSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                if appState.selectedTab == .people {
                    HStack(spacing: 0) {
                        PeopleListView(
                            selectedPerson: $appState.selectedPerson
                        )
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                        
                        if let person = appState.selectedPerson {
                            PersonDetailView(person: person)
                                .id(person.identifier) // Force re-init on person change
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Select a person")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else if appState.selectedTab == .insights {
                    InsightsView(
                        selectedPersonID: $appState.selectedPersonID,
                        selectedPerson: $appState.selectedPerson,
                        selectedTab: $appState.selectedTab
                    )
                }
            }
            .navigationTitle("")
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 20) {
                    Button(action: { appState.selectedTab = .insights }) {
                        Image(systemName: "lightbulb")
                            .foregroundColor(appState.selectedTab == .insights ? .accentColor : .primary)
                    }
                    Button(action: { appState.selectedTab = .people }) {
                        Image(systemName: "person.3")
                            .foregroundColor(appState.selectedTab == .people ? .accentColor : .primary)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Text("WhoNext")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    NewConversationWindowManager.shared.presentWindow(for: nil)
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .imageScale(.large)
                        .help("New Conversation")
                }
            }
            ToolbarItem(placement: .automatic) {
                SearchBar(searchText: $searchText) { person in
                    appState.selectedTab = .people
                    appState.selectedPerson = person
                    appState.selectedPersonID = person.identifier
                }
            }
        }
    }
}
