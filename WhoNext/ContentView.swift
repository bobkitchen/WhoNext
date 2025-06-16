import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#endif

// Add this at the top or near other Notification.Name extensions
extension Notification.Name {
    static let triggerAddPerson = Notification.Name("triggerAddPerson")
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var showingNewConversationSheet = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedItem: NavigationItem = .home
    @State private var selectedPerson: Person?
    @State private var people: [Person] = []
    @State private var showingAddPerson = false

    enum NavigationItem: Hashable {
        case home
        case insights
        case people
    }

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
                } else if appState.selectedTab == .analytics {
                    AnalyticsView()
                        .environmentObject(appState)
                }
            }
            .navigationTitle("")
        }
#if os(macOS)
        .onAppear {
            // Lock window size to 800x600
            if let window = NSApplication.shared.windows.first {
                let size = NSSize(width: 800, height: 600)
                window.minSize = size
                window.maxSize = size
            }
        }
#endif
        .toolbar {
            // Far left: New Conversation and New Person (compact)
            ToolbarItem(placement: .navigation) {
                LeftToolbarActions(appState: appState)
            }
            
            // Center: Main navigation (Insights/People/Analytics) with liquid glass styling
            ToolbarItem(placement: .principal) {
                CenterNavigationView(appState: appState)
            }
            
            // Far right: Search bar and settings with better spacing
            ToolbarItem(placement: .automatic) {
                RightToolbarActions(
                    appState: appState,
                    searchText: $searchText
                )
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView { name, role, _, isDirectReport, timezone, photo in
                let newPerson = Person(context: viewContext)
                newPerson.identifier = UUID()
                newPerson.name = name
                newPerson.role = role
                newPerson.isDirectReport = isDirectReport
                newPerson.timezone = timezone
                newPerson.photo = photo
                
                try? viewContext.save()
                fetchPeople()
                showingAddPerson = false
            }
        }
    }
    
    private func fetchPeople() {
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
        
        do {
            people = try viewContext.fetch(request)
        } catch {
            print("Error fetching people: \(error)")
        }
    }
}
