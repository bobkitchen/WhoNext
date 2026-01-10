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
    @ObservedObject private var userProfile = UserProfile.shared
    @State private var searchText = ""
    @State private var showingNewConversationSheet = false
    @State private var showingOnboarding = false
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

            // Far right: Record Meeting button
            ToolbarItem(placement: .automatic) {
                RecordMeetingToolbarButton()
            }

            // Far right: Monitoring status indicator (replaces floating window toggle)
            ToolbarItem(placement: .automatic) {
                MonitoringIndicator()
            }
        }
        .errorAlert(appStateManager.errorManager)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .onAppear {
            // Show onboarding if user hasn't completed it yet
            if !userProfile.hasCompletedOnboarding {
                showingOnboarding = true
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

// MARK: - Record Meeting Toolbar Button

/// Toolbar button for starting/stopping meeting recording
/// Visible across all tabs for quick access - larger, more prominent design
struct RecordMeetingToolbarButton: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared

    var body: some View {
        Button(action: {
            // Ensure we're on the main thread for UI updates
            Task { @MainActor in
                if recordingEngine.isRecording {
                    recordingEngine.manualStopRecording()
                } else {
                    recordingEngine.manualStartRecording()
                    // Open the recording window when starting
                    RecordingWindowManager.shared.show()
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: recordingEngine.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text(recordingEngine.isRecording ? "STOP" : "RECORD")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(recordingEngine.isRecording ? .white : .red)
            .background(recordingEngine.isRecording ? Color.red : Color.red.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(recordingEngine.isRecording ? "Stop Recording" : "Start Recording")
    }
}
