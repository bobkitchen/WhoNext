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

                    // Start observing Apple Reminders changes and sync
                    startRemindersSync()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
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

                Button("Start Recording") {
                    MeetingRecordingEngine.shared.manualStartRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Stop Recording") {
                    MeetingRecordingEngine.shared.manualStopRecording()
                }
                .keyboardShortcut(".", modifiers: [.command])

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
        // Wait for CloudKit to sync user profile data before proceeding
        // This ensures the user profile is populated from iCloud on fresh installs
        Task {
            print("☁️ CloudKit: Waiting for initial user profile sync...")
            await UserProfile.shared.waitForInitialSync()
            print("☁️ CloudKit: User profile sync complete - \(UserProfile.shared.name.isEmpty ? "empty profile" : "loaded: \(UserProfile.shared.name)")")
        }
    }
    
    /// Auto-start meeting monitoring for seamless recording
    private func startAutoRecordingMonitoring() {
        // DISABLED: Do NOT auto-start monitoring to avoid interfering with AirPods/audio
        // Users can manually start monitoring via the toolbar button or menu command
        print("🎯 Auto-Recording: Auto-start disabled - user can manually start monitoring")
        print("🎯 Use the toolbar button or Recording > Start Monitoring menu to begin")

        // Don't start monitoring automatically
        // MeetingRecordingEngine.shared.startMonitoring()

        // BUT DO pre-warm the recording engine so first recording starts fast
        prewarmRecordingEngine()
    }

    /// Pre-warm heavy components so first recording starts quickly
    private func prewarmRecordingEngine() {
        Task.detached(priority: .background) {
            print("🔥 Pre-warming recording engine components...")

            // Access the shared engine to trigger its lazy initialization
            // This starts pre-warming of ModernSpeechFramework in the background
            _ = MeetingRecordingEngine.shared

            print("🔥 Recording engine pre-warm triggered")
        }
    }

    /// Start observing Apple Reminders changes and perform initial sync
    private func startRemindersSync() {
        Task {
            // Start observing changes from Apple Reminders
            await RemindersIntegration.shared.startObservingChanges()

            // Perform initial sync to catch any changes made while app was closed
            let context = persistenceController.container.viewContext
            await RemindersIntegration.shared.syncAllReminders(in: context)

            print("📋 Reminders: Started observer and completed initial sync")
        }
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

    // MARK: - URL Scheme Handling (Widget Integration)

    /// Handle deep links from the widget and other sources
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "whonext" else {
            print("🔗 Deep Link: Unknown scheme - \(url)")
            return
        }

        print("🔗 Deep Link: Received \(url)")

        switch url.host {
        case "join":
            // Join meeting action from widget
            // Teams app should already be opening, start recording after delay
            handleJoinMeeting(url)

        case "open":
            // Simple open app action
            print("🔗 Deep Link: App opened via widget")
            // App is already open, nothing else needed

        default:
            print("🔗 Deep Link: Unknown action - \(url.host ?? "nil")")
        }
    }

    /// Handle join meeting deep link
    private func handleJoinMeeting(_ url: URL) {
        // Extract meeting ID from URL parameters if needed
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let meetingId = components?.queryItems?.first(where: { $0.name == "meetingId" })?.value

        print("🔗 Deep Link: Join meeting request - ID: \(meetingId ?? "none")")

        // Start recording with 2-second delay
        // This gives Teams time to open and establish audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("🎙️ Starting recording from widget join action...")
            MeetingRecordingEngine.shared.manualStartRecording()
        }
    }

}

extension Notification.Name {
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
    static let showParticipantConfirmation = Notification.Name("showParticipantConfirmation")
}
