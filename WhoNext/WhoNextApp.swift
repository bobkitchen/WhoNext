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
                .fallbackNotifications()
                .onAppear {
                    // Clean up any Person records for the current user
                    cleanupUserPersonRecords()

                    // Initialize sentiment analysis on app startup
                    initializeSentimentAnalysis()

                    // Trigger initial sync on app launch
                    triggerLaunchSync()

                    // Auto-start meeting monitoring for seamless recording
                    startAutoRecordingMonitoring()
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
        // DISABLED: Now using CloudKit for automatic sync instead of Supabase
        // CloudKit sync happens automatically via NSPersistentCloudKitContainer
        print("☁️ CloudKit: Automatic sync enabled - no manual sync needed")
    }
    
    /// Auto-start meeting monitoring for seamless recording
    private func startAutoRecordingMonitoring() {
        // DISABLED: Do NOT auto-start monitoring to avoid interfering with AirPods/audio
        // Users can manually start monitoring via the toolbar button or menu command
        print("🎯 Auto-Recording: Auto-start disabled - user can manually start monitoring")
        print("🎯 Use the toolbar button or Recording > Start Monitoring menu to begin")

        // Don't start monitoring automatically
        // MeetingRecordingEngine.shared.startMonitoring()
    }

    /// Remove any Person records that belong to the current user
    private func cleanupUserPersonRecords() {
        let context = persistenceController.container.viewContext
        let request = NSFetchRequest<Person>(entityName: "Person")

        do {
            let allPeople = try context.fetch(request)
            var deletedCount = 0

            for person in allPeople {
                if person.isCurrentUser {
                    print("🗑️ Removing user Person record: \(person.name ?? "Unknown")")
                    context.delete(person)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                try context.save()
                print("✅ Cleaned up \(deletedCount) user Person record(s)")
            } else {
                print("✅ No user Person records to clean up")
            }
        } catch {
            print("❌ Failed to cleanup user Person records: \(error)")
        }
    }

}

extension Notification.Name {
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
    static let showParticipantConfirmation = Notification.Name("showParticipantConfirmation")
}
