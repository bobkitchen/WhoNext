import SwiftUI
import AppKit

class TranscriptImportWindowManager: ObservableObject {
    static let shared = TranscriptImportWindowManager()
    
    private var windowController: NSWindowController?
    
    private init() {}
    
    func presentWindow() {
        // If window already exists, bring it to front
        if let existingController = windowController,
           let window = existingController.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let contentView = TranscriptImportWindowView()
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Import Transcript"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("TranscriptImportWindow")
        
        // Set minimum size
        window.minSize = NSSize(width: 600, height: 400)
        
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        
        // Bring to front
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        // Handle window closing
        window.delegate = WindowDelegate { [weak self] in
            self?.windowController = nil
        }
    }
}

// Helper class to handle window delegate
private class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
