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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appStateManager: AppStateManager
    @State private var searchText = ""
    @State private var showingNewConversationSheet = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedItem: NavigationItem = .home
    @State private var people: [Person] = []
    @State private var showingAddPerson = false

    enum NavigationItem: Hashable {
        case home
        case insights
        case people
    }
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _appStateManager = StateObject(wrappedValue: AppStateManager(viewContext: context))
    }

    var body: some View {
        NavigationStack {
            VStack {
                if appStateManager.selectedTab == .people {
                    HStack(spacing: 0) {
                        PeopleListView(
                            selectedPerson: Binding(
                                get: { appStateManager.selectedPerson },
                                set: { appStateManager.selectedPerson = $0 }
                            )
                        )
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                        .loadingOverlay(
                            isLoading: appStateManager.isLoadingPeople,
                            text: "Loading people..."
                        )
                        
                        if let person = appStateManager.selectedPerson {
                            PersonDetailView(person: person)
                                .id(person.identifier) // Force re-init on person change
                                .frame(maxWidth: .infinity)
                                .environmentObject(appStateManager)
                        } else {
                            Text("Select a person")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else if appStateManager.selectedTab == .insights {
                    InsightsView(
                        selectedPersonID: Binding(
                            get: { appStateManager.selectedPersonID },
                            set: { appStateManager.selectedPersonID = $0 }
                        ),
                        selectedPerson: Binding(
                            get: { appStateManager.selectedPerson },
                            set: { appStateManager.selectedPerson = $0 }
                        ),
                        selectedTab: Binding(
                            get: { appStateManager.selectedTab },
                            set: { appStateManager.selectedTab = $0 }
                        )
                    )
                } else if appStateManager.selectedTab == .analytics {
                    AnalyticsView()
                        .environmentObject(appStateManager)
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
            // Use new state manager
            // Far left: New Conversation and New Person (compact)
            ToolbarItem(placement: .navigation) {
                LeftToolbarActions(appState: appStateManager)
            }
            
            // Center: Main navigation (Insights/People/Analytics) with liquid glass styling
            ToolbarItem(placement: .principal) {
                CenterNavigationView(appState: appStateManager)
            }
            
            // Far right: Search bar and settings with better spacing
            ToolbarItem(placement: .automatic) {
                RightToolbarActions(
                    appState: appStateManager,
                    searchText: $searchText
                )
            }
        }
        .errorAlert(appStateManager.errorManager)
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView { name, role, _, isDirectReport, timezone, photo in
                // Create person using legacy approach for now
                let newPerson = Person(context: viewContext)
                newPerson.identifier = UUID()
                newPerson.name = name
                newPerson.role = role
                newPerson.isDirectReport = isDirectReport
                newPerson.timezone = timezone
                newPerson.photo = photo
                
                do {
                    try viewContext.save()
                    
                    // Trigger immediate sync for new person
                    RobustSyncManager.shared.triggerSync()
                    
                    fetchPeople()
                    showingAddPerson = false
                    
                    // Use AppStateManager for selection
                    appStateManager.selectPerson(newPerson)
                } catch {
                    // Use AppStateManager error handling
                    appStateManager.errorManager.handle(error, context: "Failed to create person")
                }
            }
        }
    }
    
    private func fetchPeople() {
        appStateManager.setLoadingPeople(true)
        
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
        
        do {
            people = try viewContext.fetch(request)
        } catch {
            appStateManager.errorManager.handle(error, context: "Failed to fetch people")
        }
        
        appStateManager.setLoadingPeople(false)
    }
}
