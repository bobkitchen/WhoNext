import AppKit

class NewConversationWindowManager {
    static let shared = NewConversationWindowManager()
    private var windowController: NewConversationWindowController?

    func presentWindow() {
        if windowController == nil {
            windowController = NewConversationWindowController(onSave: {
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
