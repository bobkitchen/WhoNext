import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: nil
    ) private var allPeople: FetchedResults<Person>

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
                            LiquidGlassListRow(
                                isSelected: selectedPerson == person,
                                action: { selectedPerson = person }
                            ) {
                                PersonRowView(
                                    person: person,
                                    isSelected: selectedPerson == person,
                                    onDelete: { deletePerson(person) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .background(.background.opacity(0.1))
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
}

struct PersonRowView: View {
    let person: Person
    let isSelected: Bool
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
                    
                    if person.isDirectReport {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .symbolRenderingMode(.hierarchical)
                    }
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
            .opacity(isSelected || isHovered ? 1.0 : 0.7)
            .animation(.liquidGlassFast, value: isSelected || isHovered)
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
        if person.isDirectReport {
            label += ", Direct report"
        }
        return label
    }
}
