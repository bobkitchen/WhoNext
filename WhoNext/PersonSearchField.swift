import SwiftUI
import CoreData

struct PersonSearchField: View {
    @Binding var text: String
    @Binding var selectedPerson: Person?
    @Binding var namingMode: NamingMode
    
    @State private var searchResults: [Person] = []
    @State private var showingSuggestions = false
    @State private var isSearching = false
    
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isFocused: Bool
    
    let placeholder: String
    let onCommit: () -> Void
    
    init(text: Binding<String>, 
         selectedPerson: Binding<Person?> = .constant(nil),
         namingMode: Binding<NamingMode> = .constant(.unnamed),
         placeholder: String = "Speaker Name",
         onCommit: @escaping () -> Void = {}) {
        self._text = text
        self._selectedPerson = selectedPerson
        self._namingMode = namingMode
        self.placeholder = placeholder
        self.onCommit = onCommit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            HStack {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        searchPeople(query: newValue)
                    }
                    .onSubmit {
                        handleSubmit()
                    }
                
                // Status indicator
                namingModeIndicator
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            // Suggestions dropdown
            if showingSuggestions && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5)) { person in
                        suggestionRow(for: person)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .shadow(radius: 4)
            }
            
            // Naming mode options
            if !text.isEmpty && isFocused {
                namingModeOptions
            }
        }
    }
    
    @ViewBuilder
    private var namingModeIndicator: some View {
        switch namingMode {
        case .linkedToPerson:
            Image(systemName: "link.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
                .help("Linked to person record - voice recognized")
        case .suggestedByVoice:
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
                .help("Voice match suggested - tap to confirm")
        case .namedByUser:
            Image(systemName: "person.crop.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14))
                .help("Named by user")
        case .transcriptOnly:
            Image(systemName: "doc.text.fill")
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .help("Transcript only - not saved to contacts")
        case .unnamed:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.yellow)
                .font(.system(size: 14))
                .help("Unnamed speaker")
        }
    }
    
    private func suggestionRow(for person: Person) -> some View {
        Button(action: {
            selectPerson(person)
        }) {
            HStack {
                // Person icon
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.wrappedName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Voice confidence indicator if available
                if person.voiceConfidence > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text("\(Int(person.voiceConfidence * 100))%")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color(NSColor.controlBackgroundColor))
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private var namingModeOptions: some View {
        HStack(spacing: 8) {
            // Show different options based on search results
            if !searchResults.isEmpty {
                // Option to link to existing person
                if let firstMatch = searchResults.first {
                    Button(action: {
                        selectPerson(firstMatch)
                    }) {
                        Label("Link to \(firstMatch.wrappedName)", systemImage: "link")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Option for transcript only
            Button(action: {
                namingMode = .transcriptOnly
                showingSuggestions = false
                onCommit()
            }) {
                Label("This transcript only", systemImage: "doc.text")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // Option to create new person
            if !text.isEmpty && searchResults.isEmpty {
                Button(action: {
                    createNewPerson()
                }) {
                    Label("Create new person", systemImage: "person.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }
    
    private func searchPeople(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            showingSuggestions = false
            return
        }
        
        // Add safety check for Core Data context
        guard viewContext.persistentStoreCoordinator != nil else {
            print("⚠️ Core Data context not ready for search")
            searchResults = []
            showingSuggestions = false
            return
        }
        
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [
            NSSortDescriptor(key: "voiceConfidence", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        request.fetchLimit = 10
        
        do {
            searchResults = try viewContext.fetch(request)
            showingSuggestions = !searchResults.isEmpty
        } catch {
            print("Error searching people: \(error)")
            searchResults = []
            showingSuggestions = false
        }
    }
    
    private func selectPerson(_ person: Person) {
        text = person.wrappedName
        selectedPerson = person
        namingMode = .linkedToPerson
        showingSuggestions = false
        onCommit()
    }
    
    private func createNewPerson() {
        // Add safety check for Core Data context
        guard viewContext.persistentStoreCoordinator != nil else {
            print("⚠️ Core Data context not ready for creating person")
            return
        }
        
        let person = Person(context: viewContext)
        person.name = text
        person.identifier = UUID()
        person.createdAt = Date()
        person.modifiedAt = Date()
        
        do {
            try viewContext.save()
            selectedPerson = person
            namingMode = .linkedToPerson
            showingSuggestions = false
            onCommit()
        } catch {
            print("Error creating new person: \(error)")
            // Roll back changes if save fails
            viewContext.rollback()
        }
    }
    
    private func handleSubmit() {
        if selectedPerson == nil && !searchResults.isEmpty {
            // Auto-select first match if there's a clear match
            if let firstMatch = searchResults.first {
                selectPerson(firstMatch)
            }
        } else {
            onCommit()
        }
    }
}

