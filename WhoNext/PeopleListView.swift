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

    // Multi-select state. `multiSelectedIDs` is the set of Person.identifier
    // values currently marked for bulk action (via ⌘-click or ⇧-click).
    // `shiftAnchorID` is the last plain/⌘-click target, used as the origin for
    // a subsequent ⇧-click range select (Finder-style).
    @State private var multiSelectedIDs: Set<UUID> = []
    @State private var shiftAnchorID: UUID?
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
            // Header with Add button
            LiquidGlassSectionHeader(
                "People",
                subtitle: "\(people.count) contacts",
                actionTitle: "Add",
                action: openAddPersonWindow
            )
            
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
                            // Inline row wrapper (no SwiftUI Button) so the
                            // modifier-gated TapGestures below actually get
                            // the tap. A Button swallows clicks at the AppKit
                            // layer before ancestor gestures see them — that's
                            // why ⌘-click was not multi-selecting.
                            PersonRowContainer(
                                isSelected: selectedPerson == person,
                                isMultiSelected: isMulti,
                                onPlainClick: { handlePlainClick(on: person) },
                                onCmdClick: { handleCmdClick(on: person) },
                                onShiftClick: { handleShiftClick(on: person) }
                            ) {
                                PersonRowView(
                                    person: person,
                                    isSelected: selectedPerson == person,
                                    isMultiSelected: isMulti,
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
                    if !multiSelectedIDs.isEmpty {
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

    // MARK: - Multi-select handling

    /// Plain click: single-select (existing behavior) and clear the
    /// multi-select set.
    private func handlePlainClick(on person: Person) {
        selectedPerson = person
        multiSelectedIDs.removeAll()
        shiftAnchorID = person.identifier
    }

    /// ⌘-click: toggle this person in the multi-select set. The detail view
    /// selection stays untouched so the user can compare what they're about
    /// to delete against the visible detail pane.
    private func handleCmdClick(on person: Person) {
        guard let id = person.identifier else {
            // No identifier — can't participate in multi-select; fall back.
            handlePlainClick(on: person)
            return
        }
        if multiSelectedIDs.contains(id) {
            multiSelectedIDs.remove(id)
        } else {
            multiSelectedIDs.insert(id)
        }
        shiftAnchorID = id
    }

    /// ⇧-click: select the contiguous range between the last anchor and this
    /// row, Finder-style. Without an anchor, falls back to toggling this row.
    private func handleShiftClick(on person: Person) {
        guard let id = person.identifier else {
            handlePlainClick(on: person)
            return
        }
        guard let anchor = shiftAnchorID,
              let anchorIdx = people.firstIndex(where: { $0.identifier == anchor }),
              let curIdx = people.firstIndex(where: { $0.identifier == id })
        else {
            multiSelectedIDs.insert(id)
            shiftAnchorID = id
            return
        }
        let range = min(anchorIdx, curIdx)...max(anchorIdx, curIdx)
        for p in people[range] {
            if let pid = p.identifier { multiSelectedIDs.insert(pid) }
        }
    }

    private var multiSelectActionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("\(multiSelectedIDs.count) selected")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Button("Cancel") {
                multiSelectedIDs.removeAll()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
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
        multiSelectedIDs.removeAll()
        shiftAnchorID = nil
        try? viewContext.save()
    }
}

/// Styled row container that replicates LiquidGlassListRow's hover/selection
/// look without a SwiftUI `Button`. Modifier-aware clicks are handled via an
/// NSView overlay that reads `event.modifierFlags` directly off the mouseDown
/// event — SwiftUI's `TapGesture().modifiers(...)` is unreliable inside
/// LazyVStacks, and `NSEvent.modifierFlags` (the class property) can be stale
/// by the time a SwiftUI gesture callback fires. The overlay's hitTest yields
/// the trailing edge back to SwiftUI so the inline delete button still works
/// — but only while the button is actually visible (on hover or selection).
private struct PersonRowContainer<Content: View>: View {
    let isSelected: Bool
    let isMultiSelected: Bool
    let onPlainClick: () -> Void
    let onCmdClick: () -> Void
    let onShiftClick: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundMaterial)
                    .animation(.liquidGlassFast, value: isSelected || isHovered || isMultiSelected)
            }
            .contentShape(Rectangle())
            .onHover { hovering in isHovered = hovering }
            .overlay {
                ModifierClickCatcher(
                    // Let clicks on the trailing edge fall through to the
                    // inline delete button, but only while it's visible.
                    excludeTrailingWidth: (isHovered || isSelected) ? 44 : 0
                ) { flags in
                    if flags.contains(.command) {
                        onCmdClick()
                    } else if flags.contains(.shift) {
                        onShiftClick()
                    } else {
                        onPlainClick()
                    }
                }
            }
    }

    private var backgroundMaterial: AnyShapeStyle {
        if isSelected || isMultiSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else if isHovered {
            return AnyShapeStyle(.primary.opacity(0.05))
        } else {
            return AnyShapeStyle(.clear)
        }
    }
}

/// NSView overlay that catches `mouseDown` and reports the event's modifier
/// flags. Reading `event.modifierFlags` off the event parameter is reliable;
/// `NSEvent.modifierFlags` (the class property) is a live hardware query that
/// can read stale by the time a SwiftUI gesture callback runs. SwiftUI's own
/// `TapGesture().modifiers(.command)` is unreliable inside `LazyVStack` /
/// `ScrollView` — this is the canonical macOS workaround.
///
/// `excludeTrailingWidth` > 0 makes the rightmost slice return `nil` from
/// `hitTest` so AppKit falls through to whatever's behind (the SwiftUI delete
/// button, in our case). Setting it to 0 reclaims the full width.
private struct ModifierClickCatcher: NSViewRepresentable {
    var excludeTrailingWidth: CGFloat = 0
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.onClick = onClick
        v.excludeTrailingWidth = excludeTrailingWidth
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CatcherView else { return }
        v.onClick = onClick
        v.excludeTrailingWidth = excludeTrailingWidth
    }

    final class CatcherView: NSView {
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var excludeTrailingWidth: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            if excludeTrailingWidth > 0, point.x > bounds.maxX - excludeTrailingWidth {
                return nil
            }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(event.modifierFlags)
        }

        // Register clicks even when our window isn't key yet — avoids a
        // "click to focus, click to act" double-tap on the People list when
        // returning from another app.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

struct PersonRowView: View {
    let person: Person
    let isSelected: Bool
    var isMultiSelected: Bool = false
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
                if isMultiSelected {
                    // When this row is part of a multi-select batch, replace
                    // the conversation count + trash affordance with a single
                    // filled checkmark so the selected state is unambiguous.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
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
            .opacity(isMultiSelected || isSelected || isHovered ? 1.0 : 0.7)
            .animation(.liquidGlassFast, value: isSelected || isHovered || isMultiSelected)
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
