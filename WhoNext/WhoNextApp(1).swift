import SwiftUI
import CoreData

// Notification.Name extensions consolidated in Utilities/NotificationNames.swift

@main
struct WhoNextApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .fallbackNotifications()
                .onAppear {
                    // Serialize launch operations to avoid Core Data context
                    // contention with CloudKit sync. Previously, all operations
                    // fired simultaneously and caused "entangle context after
                    // pre-commit" crashes when CloudKit imported remote changes
                    // while multiple subsystems were fetching/saving on viewContext.
                    Task { @MainActor in
                        // Phase 1: Quick cleanup (viewContext, but before CloudKit storms)
                        cleanupUserPersonRecords()

                        // Phase 2: Wait for CloudKit initial sync to settle
                        triggerLaunchSync()
                        // Give CloudKit a moment to process the initial burst of
                        // remote change notifications before other subsystems
                        // start hammering viewContext
                        try? await Task.sleep(for: .milliseconds(500))

                        // Phase 3: Sentiment analysis (viewContext reads)
                        initializeSentimentAnalysis()

                        // Phase 4: Pre-warm recording engine (uses background context)
                        startAutoRecordingMonitoring()

                        // Phase 5: Reminders sync (viewContext fetch + save)
                        startRemindersSync()

                        // Phase 6: Obsidian sync (already has its own 3s delay)
                        triggerObsidianSync()
                    }
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
            
            CommandMenu("Developer") {
                Button("Export Diarization Diagnostics") {
                    Task { @MainActor in
                        do {
                            let url = try DiarizationDiagnostics.shared.exportToJSON()
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        } catch {
                            print("[Developer] Diagnostic export failed: \(error)")
                        }
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
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
            debugLog("✅ Sentiment Analysis: Ready")
        } else {
            debugLog("⚠️ Sentiment Analysis: Not available on this device")
        }
        
        // Log migration status
        let status = SentimentAnalysisMigration.getMigrationStatus(context: context)
        debugLog("📊 Sentiment Analysis Status: \(status.message)")
    }
    
    /// Trigger sync on app launch to ensure fresh data
    private func triggerLaunchSync() {
        // Wait for CloudKit to sync user profile data before proceeding
        // This ensures the user profile is populated from iCloud on fresh installs
        Task {
            debugLog("☁️ CloudKit: Waiting for initial user profile sync...")
            await UserProfile.shared.waitForInitialSync()
            debugLog("☁️ CloudKit: User profile sync complete - \(UserProfile.shared.name.isEmpty ? "empty profile" : "loaded: \(UserProfile.shared.name)")")
        }
    }
    
    /// Auto-start meeting monitoring for seamless recording
    private func startAutoRecordingMonitoring() {
        // DISABLED: Do NOT auto-start monitoring to avoid interfering with AirPods/audio
        // Users can manually start monitoring via the toolbar button or menu command
        debugLog("🎯 Auto-Recording: Auto-start disabled - user can manually start monitoring")
        debugLog("🎯 Use the toolbar button or Recording > Start Monitoring menu to begin")

        // Don't start monitoring automatically
        // MeetingRecordingEngine.shared.startMonitoring()

        // BUT DO pre-warm the recording engine so first recording starts fast
        prewarmRecordingEngine()
    }

    /// Pre-warm heavy components so first recording starts quickly
    private func prewarmRecordingEngine() {
        Task.detached(priority: .background) {
            debugLog("🔥 Pre-warming recording engine components...")

            await MeetingRecordingEngine.shared.preWarm()

            debugLog("🔥 Recording engine pre-warm complete")
        }
    }

    /// Start observing Apple Reminders changes and perform initial sync
    private func startRemindersSync() {
        Task {
            // Start observing changes from Apple Reminders
            await RemindersIntegration.shared.startObservingChanges()

            // Perform initial sync on a background context to avoid
            // contention with CloudKit sync on viewContext
            let bgContext = persistenceController.container.newBackgroundContext()
            bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            await RemindersIntegration.shared.syncAllReminders(in: bgContext)

            debugLog("📋 Reminders: Started observer and completed initial sync")
        }
    }

    /// Sync meeting notes to the user's Obsidian vault on launch
    private func triggerObsidianSync() {
        guard ObsidianSyncService.shared.isEnabled else { return }
        Task {
            // Let CloudKit sync settle first
            try? await Task.sleep(for: .seconds(3))
            await ObsidianSyncService.shared.fullSync()
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
                    debugLog("🗑️ Removing user Person record: \(person.name ?? "Unknown")")
                    context.delete(person)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                try context.save()
                debugLog("✅ Cleaned up \(deletedCount) user Person record(s)")
            } else {
                debugLog("✅ No user Person records to clean up")
            }
        } catch {
            debugLog("❌ Failed to cleanup user Person records: \(error)")
        }
    }

    // MARK: - URL Scheme Handling (Widget Integration)

    /// Handle deep links from the widget and other sources
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "whonext" else {
            debugLog("🔗 Deep Link: Unknown scheme - \(url)")
            return
        }

        debugLog("🔗 Deep Link: Received \(url)")

        switch url.host {
        case "join":
            // Join meeting action from widget
            // Teams app should already be opening, start recording after delay
            handleJoinMeeting(url)

        case "open":
            // Simple open app action
            debugLog("🔗 Deep Link: App opened via widget")
            // App is already open, nothing else needed

        default:
            debugLog("🔗 Deep Link: Unknown action - \(url.host ?? "nil")")
        }
    }

    /// Handle join meeting deep link
    private func handleJoinMeeting(_ url: URL) {
        // Extract meeting ID from URL parameters if needed
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let meetingId = components?.queryItems?.first(where: { $0.name == "meetingId" })?.value

        debugLog("🔗 Deep Link: Join meeting request - ID: \(meetingId ?? "none")")

        // Start recording with 2-second delay
        // This gives Teams time to open and establish audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            debugLog("🎙️ Starting recording from widget join action...")
            MeetingRecordingEngine.shared.manualStartRecording()
        }
    }

}

// triggerCSVImport and showParticipantConfirmation consolidated in Utilities/NotificationNames.swift
