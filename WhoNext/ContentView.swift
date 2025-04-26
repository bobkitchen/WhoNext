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
                Button("Open Test Window") {
                    openWindow(id: "testWindow")
                }
                if appState.selectedTab == .people {
                    HStack(spacing: 0) {
                        PeopleListView(
                            selectedPerson: $appState.selectedPerson
                        )
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                        
                        if let person = appState.selectedPerson {
                            PersonDetailView(person: person)
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
                HStack {
                    Button(action: { appState.selectedTab = .insights }) {
                        Label("Insights", systemImage: "lightbulb")
                            .foregroundColor(appState.selectedTab == .insights ? .accentColor : .primary)
                    }
                    Button(action: { appState.selectedTab = .people }) {
                        Label("People", systemImage: "person.3")
                            .foregroundColor(appState.selectedTab == .people ? .accentColor : .primary)
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    NewConversationWindowManager.shared.presentWindow()
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .imageScale(.large)
                        .help("New Conversation")
                }
                Button(action: {
                    openWindow(id: "testWindow")
                }) {
                    Text("Test Window")
                }
            }
            ToolbarItem(placement: .principal) {
                Text("WhoNext")
                    .font(.headline)
                    .foregroundColor(.secondary)
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
