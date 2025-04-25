import SwiftUI
import AppKit
import CoreData

struct TokenField: NSViewRepresentable {
    @Binding var selectedPerson: Person?
    let people: [Person]
    let onSelect: (Person) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTokenField {
        let tokenField = NSTokenField()
        tokenField.delegate = context.coordinator
        tokenField.placeholderString = "Type a name..."
        tokenField.completionDelay = 0.1
        tokenField.target = context.coordinator
        tokenField.action = #selector(Coordinator.tokenFieldDidChange(_:))
        tokenField.tokenStyle = .rounded
        // REMOVED: tokenField.sendsTextChangedEvents = true (not available on NSTokenField)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.textDidChange(_:)), name: NSText.didChangeNotification, object: tokenField)
        return tokenField
    }
    
    func updateNSView(_ nsView: NSTokenField, context: Context) {
        if let selected = selectedPerson {
            nsView.objectValue = [selected.name ?? ""]
        } else {
            nsView.objectValue = []
        }
    }
    
    class Coordinator: NSObject, NSTokenFieldDelegate {
        let parent: TokenField
        init(_ parent: TokenField) {
            self.parent = parent
        }
        
        func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
            let filtered = parent.people.compactMap { person in
                let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (!name.isEmpty && name.localizedCaseInsensitiveContains(substring)) ? name : nil
            }
            // Remove duplicates and sort
            let uniqueSorted = Array(Set(filtered)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return uniqueSorted
        }
        
        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing string: String) -> Any? {
            parent.people.first { $0.name == string }
        }
        
        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            if let person = representedObject as? Person {
                return person.name
            }
            return representedObject as? String
        }
        
        @objc func tokenFieldDidChange(_ sender: NSTokenField) {
            guard let tokens = sender.objectValue as? [String], let token = tokens.first else {
                parent.selectedPerson = nil
                return
            }
            if let person = parent.people.first(where: { $0.name == token }) {
                parent.selectedPerson = person
                parent.onSelect(person)
            }
        }
        // Show completions as you type
        @objc func textDidChange(_ notification: Notification) {
            guard let tokenField = notification.object as? NSTokenField else { return }
            tokenField.complete(nil)
        }
    }
}
