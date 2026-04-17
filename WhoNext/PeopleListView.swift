import SwiftUI
import CoreData
import AppKit

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == false"),
        animation: nil
    ) private var allPeople: FetchedResults<Person>

    // Multi-select state. Users tap the "Select" button in the header to
    // enter selection mode; while active, a row click toggles that row's
    // membership in `multiSelectedIDs` instead of changing the detail pane.
    @State private var multiSelectedIDs: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var showDeleteConfirmation = false

    // Filter out current user from People directory
    private var people: [Person] {
        allPeople.filter { !$0.isCurrentUser }
    }

    private func openAddPersonWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Person"
        let contentView = NSHostingView(rootView: AddPersonWindow(
            context: viewContext,
            onSave: { person in
                viewContext.insert(person)
                try? viewContext.save()
                selectedPerson = person
                // CloudKit sync happens automatically
                window.close()
            },
            onCancel: {
                window.close()
            }
        ))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            peopleHeader
            
            // People List or Empty State
            if people.isEmpty {
                // Enhanced Empty State
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .symbolEffect(.breathe.wholeSymbol)
                    
                    VStack(spacing: 8) {
                        Text("No People Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text("Add people to start tracking conversations and generating insights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button(action: openAddPersonWindow) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Add Your First Person")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassBackground(cornerRadius: 0, elevation: .low)
            } else {
                // People List
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(people, id: \.identifier) { person in
                            let isMulti = person.identifier.map { multiSelectedIDs.contains($0) } ?? false
                            LiquidGlassListRow(
                                isSelected: selectedPerson == person || isMulti,
                                action: { handleRowClick(on: person) }
                            ) {
                                PersonRowView(
                                    person: person,
                                    isSelected: selectedPerson == person,
                                    isMultiSelected: isMulti,
                                    isSelectionMode: isSelectionMode,
                                    onDelete: { deletePerson(person) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .background(.background.opacity(0.1))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isSelectionMode {
                        multiSelectActionBar
                            .padding(12)
                    }
                }
            }
        }
        .onAppear {
            NotificationCenter.default.addObserver(forName: .triggerAddPerson, object: nil, queue: .main) { _ in
                openAddPersonWindow()
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .triggerAddPerson, object: nil)
        }
        .onChange(of: people.map { $0.identifier }) { oldValue, newValue in
            // Defensive: re-sync selectedPerson by identifier if needed
            if let id = selectedPerson?.identifier {
                if let match = people.first(where: { $0.identifier == id }) {
                    selectedPerson = match
                } else {
                    selectedPerson = nil
                }
            }
        }
    }
    
    private func deletePerson(_ person: Person) {
        if selectedPerson == person {
            selectedPerson = nil
        }

        // Delete person - CloudKit sync handles propagation automatically
        viewContext.delete(person)
        try? viewContext.save()
    }

    // MARK: - Header

    private var peopleHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("People")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("\(people.count) contacts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelectionMode {
                Button(action: exitSelectionMode) {
                    Text("Done").font(.caption).fontWeight(.medium)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .small))
            } else {
                if !people.isEmpty {
                    Button(action: enterSelectionMode) {
                        Text("Select").font(.caption).fontWeight(.medium)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                }
                Button(action: openAddPersonWindow) {
                    Text("Add").font(.caption).fontWeight(.medium)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Selection handling

    /// In selection mode, a click toggles that row's membership in the
    /// multi-select set. Otherwise it selects the row as the detail view
    /// subject (original behavior).
    private func handleRowClick(on person: Person) {
        if isSelectionMode {
            guard let id = person.identifier else { return }
            if multiSelectedIDs.contains(id) {
                multiSelectedIDs.remove(id)
            } else {
                multiSelectedIDs.insert(id)
            }
        } else {
            selectedPerson = person
        }
    }

    private func enterSelectionMode() {
        isSelectionMode = true
        multiSelectedIDs.removeAll()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        multiSelectedIDs.removeAll()
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: multiSelectedIDs.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(multiSelectedIDs.isEmpty ? .secondary : Color.accentColor)
            Text(multiSelectedIDs.isEmpty ? "Tap rows to select" : "\(multiSelectedIDs.count) selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(multiSelectedIDs.isEmpty ? .secondary : .primary)

            Spacer()

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(multiSelectedIDs.isEmpty ? Color.red.opacity(0.3) : Color.red.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(multiSelectedIDs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .confirmationDialog(
            "Delete \(multiSelectedIDs.count) \(multiSelectedIDs.count == 1 ? "person" : "people")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedPeople()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their conversations and meetings will remain but become unassigned. This cannot be undone.")
        }
    }

    private func deleteSelectedPeople() {
        let toDelete = people.filter { p in
            guard let id = p.identifier else { return false }
            return multiSelectedIDs.contains(id)
        }
        guard !toDelete.isEmpty else { return }

        if let current = selectedPerson, toDelete.contains(current) {
            selectedPerson = nil
        }

        for person in toDelete {
            viewContext.delete(person)
        }
        try? viewContext.save()
        exitSelectionMode()
    }
}

struct PersonRowView: View {
    let person: Person
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var isSelectionMode: Bool = false
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced Avatar
            if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                        }
                    
                    Text(person.initials)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            // Name and Role
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name ?? "Unnamed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    CategoryBadge(category: person.category)
                }
                
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status indicators
            HStack(spacing: 8) {
                if isSelectionMode {
                    // In selection mode the trailing slot is a pure toggle —
                    // empty circle = not selected, filled = selected. The
                    // conversation count and trash affordance are hidden so
                    // clicks anywhere on the row act as toggle.
                    Image(systemName: isMultiSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isMultiSelected ? Color.accentColor : .secondary.opacity(0.6))
                } else {
                    // Conversation count indicator
                    if let conversationCount = person.conversations?.count, conversationCount > 0 {
                        Text("\(conversationCount)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.secondary.opacity(0.1))
                            }
                    }

                    // Delete button (appears on hover or selection)
                    if isSelected || isHovered {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .animation(.liquidGlassFast, value: isSelected || isHovered)
                        .accessibilityLabel("Delete \(person.name ?? "person")")
                        .onHover { hovering in
                            // Subtle hover effect on the delete button itself
                        }
                    }
                }
            }
            .opacity(isSelectionMode || isSelected || isHovered ? 1.0 : 0.7)
            .animation(.liquidGlassFast, value: isSelected || isHovered || isMultiSelected || isSelectionMode)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details")
    }
    
    private var accessibilityLabel: String {
        var label = person.name ?? "Unnamed person"
        if let role = person.role, !role.isEmpty {
            label += ", \(role)"
        }
        label += ", \(person.category.displayName)"
        return label
    }
}
