import SwiftUI
import CoreData

@main
struct WhoNextApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Initialize sentiment analysis on app startup
                    initializeSentimentAnalysis()
                    
                    // Trigger initial sync on app launch
                    triggerLaunchSync()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 800)
        .windowResizability(.automatic)
        .windowToolbarStyle(.unified)
        // Removed direct Window for NewConversationWindow. Now handled in ContentView via .sheet presentation.
        Window("Test Window", id: "testWindow") {
            TestWindow()
        }
        .commands {
            CommandMenu("File") {
                Button("Import People from CSV…") {
                    NotificationCenter.default.post(name: .triggerCSVImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
    
    /// Initialize sentiment analysis features on app startup
    private func initializeSentimentAnalysis() {
        let context = persistenceController.container.viewContext
        
        // Perform initial setup for existing conversations
        SentimentAnalysisMigration.performInitialSetup(context: context)
        
        // Log sentiment analysis availability
        if SentimentAnalysisMigration.isAnalysisReady() {
            print("✅ Sentiment Analysis: Ready")
        } else {
            print("⚠️ Sentiment Analysis: Not available on this device")
        }
        
        // Log migration status
        let status = SentimentAnalysisMigration.getMigrationStatus(context: context)
        print("📊 Sentiment Analysis Status: \(status.message)")
    }
    
    /// Trigger sync on app launch to ensure fresh data
    private func triggerLaunchSync() {
        print("🚀 App Launch: Triggering sync to ensure fresh data...")
        ProperSyncManager.shared.triggerSync()
    }
    
}

extension Notification.Name {
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
}
