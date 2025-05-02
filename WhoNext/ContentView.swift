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
            // Far left: New Conversation and New Person (always visible)
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    Button(action: {
                        NewConversationWindowManager.shared.presentWindow(for: nil)
                    }) {
                        Label("New Conversation", systemImage: "plus.bubble")
                    }
                    .help("New Conversation")
                    Button(action: {
                        // If not on People tab, switch to People, then trigger add person after a short delay
                        if appState.selectedTab != .people {
                            appState.selectedTab = .people
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NotificationCenter.default.post(name: .triggerAddPerson, object: nil)
                            }
                        } else {
                            NotificationCenter.default.post(name: .triggerAddPerson, object: nil)
                        }
                    }) {
                        Label("New Person", systemImage: "person.crop.circle.badge.plus")
                    }
                    .help("Add new person")
                }
            }
            // Center: Segmented control for Insights/People (always visible)
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $appState.selectedTab) {
                    Text("Insights").tag(SidebarItem.insights)
                    Text("People").tag(SidebarItem.people)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            // Far right: Search bar (always visible)
            ToolbarItem(placement: .automatic) {
                HStack {
                    SearchBar(searchText: $searchText) { person in
                        appState.selectedTab = .people
                        appState.selectedPerson = person
                        appState.selectedPersonID = person.identifier
                    }
                    .frame(width: 220)
                }
            }
        }
    }
}
