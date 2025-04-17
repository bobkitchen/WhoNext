import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var appState = AppState()

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
                        selectedPerson: $appState.selectedPerson
                    )
                }
            }
            .navigationTitle("") 
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {
                        appState.selectedTab = .insights
                    }) {
                        Label("Insights", systemImage: "lightbulb")
                            .foregroundColor(appState.selectedTab == .insights ? .accentColor : .primary)
                    }

                    Button(action: {
                        appState.selectedTab = .people
                    }) {
                        Label("People", systemImage: "person.3")
                            .foregroundColor(appState.selectedTab == .people ? .accentColor : .primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("WhoNext")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
