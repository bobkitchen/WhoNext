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
                HStack(spacing: 8) {
                    Button(action: {
                        NewConversationWindowManager.shared.presentWindow(for: nil)
                    }) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
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
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("New Person")
                    
                    Button(action: {
                        TranscriptImportWindowManager.shared.presentWindow()
                    }) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Import Transcript")
                }
            }
            
            // Center: Main navigation (Insights/People/Analytics)
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    Button(action: { appState.selectedTab = .insights }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 14, weight: .medium))
                            Text("Insights")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(appState.selectedTab == .insights ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appState.selectedTab == .insights ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { appState.selectedTab = .people }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2")
                                .font(.system(size: 14, weight: .medium))
                            Text("People")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(appState.selectedTab == .people ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appState.selectedTab == .people ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { appState.selectedTab = .analytics }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Analytics")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(appState.selectedTab == .analytics ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appState.selectedTab == .analytics ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
                .animation(nil, value: appState.selectedTab) // Disable initial appearance animation
                .onAppear {
                    // Disable any implicit animations on initial load
                    withAnimation(.none) {}
                }
            }
            
            // Far right: Search bar (compact for now, will improve in responsive phase)
            ToolbarItem(placement: .automatic) {
                SearchBar(searchText: $searchText) { person in
                    appState.selectedTab = .people
                    appState.selectedPerson = person
                    appState.selectedPersonID = person.identifier
                }
                .frame(width: 180) // Reduced width to fit
            }
            
            // Settings button
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    openWindow(id: "settings")
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
