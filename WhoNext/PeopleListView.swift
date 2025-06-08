import SwiftUI
import CoreData

struct PeopleListView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: nil
    ) private var people: FetchedResults<Person>

    @State private var showingAddPersonSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with Add button
            HStack {
                Text("People")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingAddPersonSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                        Text("Add")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // People List or Empty State
            if people.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    VStack(spacing: 6) {
                        Text("No People Yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Add people to start tracking conversations and generating insights.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    Button(action: { showingAddPersonSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Add Your First Person")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                // People List
                List {
                    ForEach(people) { person in
                        PersonRowView(
                            person: person,
                            isSelected: person.id == selectedPerson?.id,
                            onSelect: { selectedPerson = person },
                            onDelete: { deletePerson(person) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear {
            NotificationCenter.default.addObserver(forName: .triggerAddPerson, object: nil, queue: .main) { _ in
                showingAddPersonSheet = true
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .triggerAddPerson, object: nil)
        }
        .sheet(isPresented: $showingAddPersonSheet) {
            AddPersonView { name, role, timezone, isDirectReport, notes, photoData in
                let newPerson = Person(context: viewContext)
                let newId = UUID()
                newPerson.identifier = newId
                newPerson.name = name
                newPerson.role = role
                newPerson.timezone = timezone
                newPerson.isDirectReport = isDirectReport
                newPerson.notes = notes
                if let photoData = photoData {
                    newPerson.photo = photoData
                }
                do {
                    try viewContext.save()
                    // Set the selection to the new person by identifier
                    DispatchQueue.main.async {
                        // Find the new person in the context after save
                        let fetchRequest = NSFetchRequest<Person>(entityName: "Person")
                        fetchRequest.predicate = NSPredicate(format: "identifier == %@", newId as CVarArg)
                        if let results = try? viewContext.fetch(fetchRequest), let savedPerson = results.first {
                            selectedPerson = savedPerson
                        } else {
                            selectedPerson = newPerson // fallback
                        }
                    }
                } catch {
                    // Handle error
                }
                showingAddPersonSheet = false
            }
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
        viewContext.delete(person)
        try? viewContext.save()
    }
}

struct PersonRowView: View {
    let person: Person
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            Group {
                if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 28, height: 28)
                        
                        Text(person.initials)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Name and Role
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(person.name ?? "Unnamed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if person.isDirectReport {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor)
                    }
                }
                
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Delete Button (only show on hover or selection)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .opacity(0.7)
                    .padding(3)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete \(person.name ?? "person")")
            .opacity(isSelected ? 1.0 : 0.0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Defer selection to prevent jumping
            DispatchQueue.main.async {
                onSelect()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
