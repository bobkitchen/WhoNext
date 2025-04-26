import SwiftUI
import CoreData

@main
struct WhoNextApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
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
        }
    }
}

extension Notification.Name {
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
}
