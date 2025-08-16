import SwiftUI
import CoreData

extension Notification.Name {
    static let showRecordingDashboard = Notification.Name("showRecordingDashboard")
}

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
        
        Window("Meeting Recording", id: "recording-dashboard") {
            MeetingRecordingView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandMenu("File") {
                Button("Import People from CSV…") {
                    NotificationCenter.default.post(name: .triggerCSVImport, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
            
            CommandMenu("Recording") {
                Button("Start Monitoring") {
                    MeetingRecordingEngine.shared.startMonitoring()
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Button("Stop Monitoring") {
                    MeetingRecordingEngine.shared.stopMonitoring()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Manual Start Recording") {
                    MeetingRecordingEngine.shared.manualStartRecording()
                }
                .disabled(!MeetingRecordingEngine.shared.isMonitoring)
                
                Button("Manual Stop Recording") {
                    MeetingRecordingEngine.shared.manualStopRecording()
                }
                .disabled(!MeetingRecordingEngine.shared.isRecording)
                
                Divider()
                
                Button("Show Recording Dashboard...") {
                    NotificationCenter.default.post(name: .showRecordingDashboard, object: nil)
                }
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
        Task {
            let result = await RobustSyncManager.shared.performSync()
            switch result {
            case .success(let stats):
                print("✅ Launch sync completed: \(stats.totalOperations) operations in \(String(format: "%.1f", stats.duration))s")
            case .failure(let error):
                print("❌ Launch sync failed: \(error.errorDescription ?? "Unknown error")")
            case .partial(let stats, let errors):
                print("⚠️ Launch sync partial: \(stats.totalOperations) operations, \(errors.count) errors")
            }
        }
    }
    
}

extension Notification.Name {
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
}
