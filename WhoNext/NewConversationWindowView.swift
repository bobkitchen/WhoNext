import SwiftUI
import CoreData

struct NewConversationWindowView: View {
    var preselectedPerson: Person? = nil
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var toField: String = ""
    @State private var selectedPerson: Person? = nil
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var duration: Int = 30 // Duration in minutes
    @State private var showSuggestions: Bool = false
    @FocusState private var toFieldFocused: Bool

    var filteredPeople: [Person] {
        let trimmed = toField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return people.filter { $0.name?.localizedCaseInsensitiveContains(trimmed) == true }
    }

    init(preselectedPerson: Person? = nil, onSave: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.preselectedPerson = preselectedPerson
        self.onSave = onSave
        self.onCancel = onCancel
        // SwiftUI @State can't be initialized directly here, so preselection is handled in .onAppear
    }

    @ViewBuilder
    private var toFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                // Text field
                TextField("Search for a person...", text: $toField, onEditingChanged: { editing in
                    if editing {
                        showSuggestions = !filteredPeople.isEmpty
                    } else {
                        // Delay hiding suggestions to allow for selection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showSuggestions = false
                        }
                    }
                })
                .focused($toFieldFocused)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onChange(of: toField) { oldValue, newValue in
                    // Clear selection if text doesn't match any person exactly
                    if let match = people.first(where: { $0.name?.lowercased() == newValue.lowercased() }) {
                        if selectedPerson?.id != match.id {
                            selectedPerson = match
                        }
                    } else {
                        selectedPerson = nil
                    }
                    
                    // Show suggestions if focused and has filtered results
                    showSuggestions = toFieldFocused && !filteredPeople.isEmpty && selectedPerson == nil
                }
                .onSubmit {
                    // Try to find exact match on submit
                    if let match = people.first(where: { $0.name?.lowercased() == toField.lowercased() }) {
                        selectedPerson = match
                        toField = match.name ?? ""
                    }
                    showSuggestions = false
                    toFieldFocused = false
                }
                
                // Suggestions dropdown
                if showSuggestions && !filteredPeople.isEmpty {
                    suggestionsList
                }
            }
            
            // Selected person confirmation
            if let selected = selectedPerson {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name ?? "Unknown")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let role = selected.role, !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Clear selection button
                    Button(action: {
                        selectedPerson = nil
                        toField = ""
                        toFieldFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    @ViewBuilder
    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(filteredPeople.prefix(5), id: \.id) { person in
                Button(action: {
                    selectedPerson = person
                    toField = person.name ?? ""
                    showSuggestions = false
                    toFieldFocused = false
                }) {
                    HStack(spacing: 12) {
                        // Avatar or icon
                        if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(String(person.name?.prefix(1) ?? "?"))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name ?? "Unknown")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                )
                .onHover { hovering in
                    // Hover effect handled by system
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func saveConversation() {
        if let person = selectedPerson {
            let newConversation = Conversation(context: viewContext)
            newConversation.date = date
            newConversation.notes = notes
            newConversation.setValue(Int16(duration), forKey: "duration")
            newConversation.person = person
            do {
                print("[NewConversationWindowView][LOG] Saving context\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
                try viewContext.save()
            } catch {
                print("Failed to save conversation: \(error)")
            }
        }
        onSave?()
        closeWindow()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "plus.bubble.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("New Conversation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Text("Record a conversation with a team member")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Form content
            VStack(alignment: .leading, spacing: 20) {
                // Person selection
                VStack(alignment: .leading, spacing: 8) {
                    Label("Person", systemImage: "person.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    toFieldSection
                }
                
                // Date selection
                VStack(alignment: .leading, spacing: 8) {
                    Label("Date", systemImage: "calendar")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                
                // Duration selection
                VStack(alignment: .leading, spacing: 8) {
                    Label("Duration", systemImage: "clock")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Picker("Duration", selection: $duration) {
                            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        
                        Spacer()
                    }
                }
                
                // Notes section
                VStack(alignment: .leading, spacing: 8) {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $notes)
                        .font(.system(size: 13))
                        .frame(height: 180)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Footer with buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    onCancel?()
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Save Conversation") {
                    saveConversation()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedPerson == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if let preselected = preselectedPerson, selectedPerson == nil {
                selectedPerson = preselected
                toField = preselected.name ?? ""
            }
        }
    }
}

#if canImport(AppKit)
extension View {
    func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
#endif
