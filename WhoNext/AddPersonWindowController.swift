import Cocoa
import SwiftUI

class AddPersonWindowController: NSWindowController {
    private var onSave: (() -> Void)?
    private var onCancel: (() -> Void)?

    convenience init(onSave: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        let context = PersistenceController.shared.container.viewContext

        // Create a temporary person for the form
        let tempPerson = Person(context: context)
        tempPerson.identifier = UUID()
        tempPerson.name = ""
        tempPerson.role = ""

        let contentView = NSHostingView(rootView:
            AddPersonWindowView(
                person: tempPerson,
                isNewPerson: true,
                onSave: {
                    onSave?()
                },
                onCancel: {
                    // Delete the temp person if cancelled
                    context.delete(tempPerson)
                    try? context.save()
                    onCancel?()
                }
            )
            .environment(\.managedObjectContext, context)
        )

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "New Person"
        window.contentView = contentView
        window.center()
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("AddPersonWindow")

        self.init(window: window)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    func showWindow() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
