import Cocoa
import SwiftUI

class NewConversationWindowController: NSWindowController {
    private var onSave: (() -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(person: Person? = nil, onSave: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        let context = PersistenceController.shared.container.viewContext
        let conversationManager = ConversationStateManager(viewContext: context)
        let contentView = NSHostingView(rootView:
            NewConversationWindowView(
                preselectedPerson: person, 
                conversationManager: conversationManager,
                onSave: {
                    onSave?()
                }, 
                onCancel: {
                    onCancel?()
                }
            )
            .environment(\.managedObjectContext, context)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "New Conversation"
        window.contentView = contentView
        window.center()
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("NewConversationWindow")
        self.init(window: window)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    func showWindow() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
