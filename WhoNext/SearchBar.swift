import SwiftUI
import CoreData
import AppKit

struct SearchBar: NSViewRepresentable {
    @Binding var searchText: String
    let onPersonSelected: (Person) -> Void
    @Environment(\.managedObjectContext) private var viewContext
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = context.coordinator
        searchField.placeholderString = "Search people..."
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldDidChange(_:))
        
        // Set fixed width
        searchField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        
        return searchField
    }
    
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != searchText {
            nsView.stringValue = searchText
        }
    }
    
    class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: SearchBar
        var searchPopover: NSPopover?
        
        init(_ parent: SearchBar) {
            self.parent = parent
            super.init()
        }
        
        @objc func searchFieldDidChange(_ sender: NSSearchField) {
            parent.searchText = sender.stringValue
            
            if sender.stringValue.isEmpty {
                searchPopover?.close()
                return
            }
            
            let fetch = NSFetchRequest<Person>(entityName: "Person")
            fetch.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
            
            // Create predicate for search
            let searchString = sender.stringValue.lowercased()
            fetch.predicate = NSPredicate(
                format: "name CONTAINS[cd] %@ OR role CONTAINS[cd] %@ OR notes CONTAINS[cd] %@",
                searchString, searchString, searchString
            )
            
            do {
                let results = try parent.viewContext.fetch(fetch)
                showSuggestions(results, relativeTo: sender)
            } catch {
                print("Failed to fetch suggestions: \(error)")
            }
        }
        
        func showSuggestions(_ people: [Person], relativeTo searchField: NSSearchField) {
            if searchPopover == nil {
                searchPopover = NSPopover()
                searchPopover?.behavior = .transient
            }
            
            let suggestionsView = SuggestionsView(
                people: people,
                onSelect: { [weak self] person in
                    self?.searchPopover?.close()
                    searchField.stringValue = ""
                    self?.parent.searchText = ""
                    self?.parent.onPersonSelected(person)
                }
            )
            
            searchPopover?.contentViewController = NSHostingController(rootView: suggestionsView)
            
            if !searchPopover!.isShown {
                searchPopover?.show(relativeTo: searchField.bounds, of: searchField, preferredEdge: .maxY)
            }
        }
    }
}

struct SuggestionsView: View {
    let people: [Person]
    let onSelect: (Person) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(people.prefix(5)) { person in
                Button(action: { onSelect(person) }) {
                    HStack(spacing: 8) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: .systemGray).opacity(0.15))
                                .frame(width: 24, height: 24)
                            
                            Text(person.initials)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name ?? "")
                                .font(.system(size: 12, weight: .medium))
                            
                            if let role = person.role {
                                Text(role)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                
                if person.id != people.last?.id {
                    Divider()
                }
            }
        }
        .frame(width: 300)
        .padding(.vertical, 4)
    }
} 