import AppKit

class NewConversationWindowManager {
    static let shared = NewConversationWindowManager()
    private var windowController: NewConversationWindowController?

    // Present window, optionally pre-selecting a person
    func presentWindow(for person: Person? = nil) {
        if windowController == nil {
            windowController = NewConversationWindowController(person: person, onSave: {
                // Handle save logic here
                self.windowController = nil
            }, onCancel: {
                // Handle cancel logic here
                self.windowController = nil
            })
        }
        windowController?.showWindow()
    }
}
