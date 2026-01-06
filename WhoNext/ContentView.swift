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
                if appStateManager.selectedTab == .meetings {
                    MeetingsView(
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
                } else if appStateManager.selectedTab == .people {
                    PeopleAndGroupsView(
                        selectedPerson: Binding(
                            get: { appStateManager.selectedPerson },
                            set: { appStateManager.selectedPerson = $0 }
                        )
                    )
                    .environmentObject(appStateManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .loadingOverlay(
                        isLoading: appStateManager.isLoadingPeople,
                        text: "Loading people..."
                    )
                } else if appStateManager.selectedTab == .insights {
                    InsightsView()
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
            
            // Far right: Monitoring window toggle
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    UnifiedRecordingStatusWindowManager.shared.toggle()
                }) {
                    Image(systemName: UnifiedRecordingStatusWindowManager.shared.isVisible ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 18))
                        .foregroundColor(MeetingRecordingEngine.shared.isRecording ? .red : .green)
                        .help(UnifiedRecordingStatusWindowManager.shared.isVisible ? "Hide Recording Monitor" : "Show Recording Monitor")
                }
                .buttonStyle(.borderless)
            }
        }
        .errorAlert(appStateManager.errorManager)
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
