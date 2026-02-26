import SwiftUI
import CoreData

struct EnhancedPeopleView: View {
    @Binding var selectedPerson: Person?
    @Binding var selectedGroup: Group?
    @Binding var selectedInboxConversation: Conversation?
    @Binding var selectedInboxGroupMeeting: GroupMeeting?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow

    // View state
    @State private var viewMode: ViewMode = .individuals
    @State private var searchText = ""
    @State private var selectedFilters: Set<PersonFilter> = []
    @State private var sortOption: PersonSortOption = .name
    @State private var showingImport = false
    @State private var isInboxExpanded = true
    @State private var selectedInboxItem: InboxEntry?

    // Fetch request for people
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == false"),
        animation: .default
    ) private var allPeople: FetchedResults<Person>

    // Computed properties for grouped people
    private var filteredPeople: [Person] {
        var result = Array(allPeople)

        // Exclude current user and speaker placeholders from People directory
        result = result.filter { !$0.isCurrentUser && !InboxEntry.isSpeakerPlaceholder($0.name ?? "") }

        // Apply search
        if !searchText.isEmpty {
            result = result.filter { person in
                let name = person.name?.lowercased() ?? ""
                let role = person.role?.lowercased() ?? ""
                let search = searchText.lowercased()
                return name.contains(search) || role.contains(search)
            }
        }

        // Apply filters
        for filter in selectedFilters {
            result = applyFilter(filter, to: result)
        }

        // Apply sorting
        result = sortPeople(result, by: sortOption)

        return result
    }
    
    private var directReports: [Person] {
        filteredPeople.filter { $0.category == .directReport }
    }
    
    private var recentlyContacted: [Person] {
        filteredPeople.filter { person in
            guard let conversations = person.conversations as? Set<Conversation>,
                  let lastConversation = conversations.max(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }),
                  let date = lastConversation.date else {
                return false
            }
            return date > Date().addingTimeInterval(-7 * 24 * 60 * 60) // Last 7 days
        }
    }

    private var inboxItems: [InboxEntry] {
        // Gather conversations from "Speaker X" placeholder persons
        var entries: [InboxEntry] = []
        for person in allPeople {
            guard let name = person.name, InboxEntry.isSpeakerPlaceholder(name) else { continue }
            if let conversations = person.conversations as? Set<Conversation> {
                for conversation in conversations where !conversation.isSoftDeleted {
                    entries.append(.conversation(conversation))
                }
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    enum ViewMode: String, CaseIterable {
        case individuals = "Individuals"
        case groups = "Groups"
        
        var icon: String {
            switch self {
            case .individuals: return "person.fill"
            case .groups: return "person.3.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern header with integrated controls
            headerView
            
            // Main content area
            VStack(spacing: 0) {
                // Search and filters
                VStack(spacing: 12) {
                    EnhancedPeopleSearchBar(searchText: $searchText)
                        .padding(.horizontal, 20)
                    
                    PeopleFilterChips(selectedFilters: $selectedFilters)
                }
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
                
                // Content based on view mode
                if viewMode == .individuals {
                    peopleListContent
                } else {
                    GroupsListView(selectedGroup: $selectedGroup, onGroupSelected: { group in
                        // Clear person selection when a group is selected
                        selectedPerson = nil
                        selectedGroup = group
                    })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedPerson) { _, newValue in
            if newValue != nil {
                selectedInboxItem = nil
                selectedInboxConversation = nil
                selectedInboxGroupMeeting = nil
            }
        }
        .onChange(of: selectedGroup) { _, newValue in
            if newValue != nil {
                selectedInboxItem = nil
                selectedInboxConversation = nil
                selectedInboxGroupMeeting = nil
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row with title and actions
            HStack(alignment: .center, spacing: 16) {
                // Title
                Text("People & Groups")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Stats badge
                HStack(spacing: 8) {
                    Text("\(allPeople.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("contacts")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 12)
                    
                    Text("\(directReports.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("direct reports")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.separatorColor).opacity(0.1))
                .cornerRadius(6)
                
                Spacer()
                
                // Add button
                Button(action: {
                    let windowController = AddPersonWindowController(
                        onSave: {
                            // Person will be saved automatically
                        },
                        onCancel: {
                            // Nothing to do on cancel
                        }
                    )
                    windowController.showWindow()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // Bottom row with view toggle and sort
            HStack(spacing: 16) {
                // View mode toggle
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                
                Text("Groups")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(viewMode == .groups ? 1 : 0)
                
                Spacer()
                
                // Sort options
                PeopleSortOptions(sortOption: $sortOption)
                
                // Import button
                Button(action: { showingImport = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Import from CSV")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
    }
    
    // MARK: - People List Content
    private var peopleListContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if filteredPeople.isEmpty && inboxItems.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    // Inbox section — always at the top when there are items
                    if !inboxItems.isEmpty {
                        inboxSection
                    }

                    // Favorites section
                    if !directReports.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PersonSectionHeader(
                                title: "Direct Reports",
                                count: directReports.count,
                                icon: "arrow.down.right.circle.fill"
                            )
                            
                            LazyVStack(spacing: 6) {
                                ForEach(directReports, id: \.identifier) { person in
                                    EnhancedPersonCard(
                                        person: person,
                                        selectedPerson: $selectedPerson
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    
                    // Recently contacted section
                    if !recentlyContacted.isEmpty && recentlyContacted != directReports {
                        VStack(alignment: .leading, spacing: 8) {
                            PersonSectionHeader(
                                title: "Recently Contacted",
                                count: recentlyContacted.count,
                                icon: "clock.fill"
                            )
                            
                            LazyVStack(spacing: 8) {
                                ForEach(recentlyContacted.filter { !directReports.contains($0) }, id: \.identifier) { person in
                                    EnhancedPersonCard(
                                        person: person,
                                        selectedPerson: $selectedPerson
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    
                    // All people section
                    let remainingPeople = filteredPeople.filter { 
                        !directReports.contains($0) && !recentlyContacted.contains($0)
                    }
                    
                    if !remainingPeople.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PersonSectionHeader(
                                title: "All People",
                                count: remainingPeople.count,
                                icon: "person.2.fill"
                            )
                            
                            LazyVStack(spacing: 8) {
                                ForEach(remainingPeople, id: \.identifier) { person in
                                    EnhancedPersonCard(
                                        person: person,
                                        selectedPerson: $selectedPerson
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    
                    // Bottom padding
                    Spacer(minLength: 20)
                }
                .padding(.top, 12)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Inbox Section
    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isInboxExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)

                    Text("Inbox")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(inboxItems.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isInboxExpanded ? 90 : 0))

                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isInboxExpanded {
                LazyVStack(spacing: 6) {
                    ForEach(inboxItems) { entry in
                        InboxMeetingCard(
                            entry: entry,
                            isSelected: selectedInboxItem?.id == entry.id,
                            onSelect: {
                                selectInboxItem(entry)
                            }
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func selectInboxItem(_ entry: InboxEntry) {
        selectedInboxItem = entry
        selectedPerson = nil
        selectedGroup = nil
        switch entry {
        case .conversation(let c):
            selectedInboxConversation = c
            selectedInboxGroupMeeting = nil
        case .groupMeeting(let g):
            selectedInboxGroupMeeting = g
            selectedInboxConversation = nil
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
                .symbolEffect(.breathe)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No People Yet" : "No Results Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(searchText.isEmpty ? 
                     "Add people to start tracking conversations and building relationships." :
                     "Try adjusting your search or filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            if searchText.isEmpty {
                HStack(spacing: 12) {
                    Button(action: { showingImport = true }) {
                        Label("Import CSV", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: {
                        let windowController = AddPersonWindowController(
                            onSave: {
                                // Person will be saved automatically
                            },
                            onCancel: {
                                // Nothing to do on cancel
                            }
                        )
                        windowController.showWindow()
                    }) {
                        Label("Add Person", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                Button(action: { 
                    searchText = ""
                    selectedFilters.removeAll()
                }) {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Functions
    
    private func applyFilter(_ filter: PersonFilter, to people: [Person]) -> [Person] {
        switch filter {
        case .category(let cat):
            return people.filter { $0.category == cat }
        case .recentlyContacted:
            return people.filter { person in
                guard let conversations = person.conversations as? Set<Conversation>,
                      let lastConversation = conversations.max(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }),
                      let date = lastConversation.date else {
                    return false
                }
                return date > Date().addingTimeInterval(-7 * 24 * 60 * 60)
            }
        case .needsCheckIn:
            return people.filter { person in
                guard let conversations = person.conversations as? Set<Conversation>,
                      let lastConversation = conversations.max(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }),
                      let date = lastConversation.date else {
                    return true
                }
                return date < Date().addingTimeInterval(-14 * 24 * 60 * 60)
            }
        case .noMeetings:
            return people.filter { person in
                (person.conversations as? Set<Conversation>)?.isEmpty ?? true
            }
        case .healthy:
            return people.filter { person in
                guard let conversations = person.conversations as? Set<Conversation> else {
                    return false
                }
                let recentCount = conversations.filter { conversation in
                    guard let date = conversation.date else { return false }
                    return date > Date().addingTimeInterval(-30 * 24 * 60 * 60)
                }.count
                return recentCount >= 4
            }
        case .hasNotes:
            return people.filter { person in
                !(person.notes?.isEmpty ?? true)
            }
        case .frequentMeetings:
            return people.filter { person in
                guard let conversations = person.conversations as? Set<Conversation> else {
                    return false
                }
                return conversations.count >= 10
            }
        }
    }
    
    private func sortPeople(_ people: [Person], by option: PersonSortOption) -> [Person] {
        switch option {
        case .name:
            return people.sorted { ($0.name ?? "") < ($1.name ?? "") }
        case .lastMeeting:
            return people.sorted { person1, person2 in
                let date1 = (person1.conversations as? Set<Conversation>)?
                    .compactMap { $0.date }
                    .max() ?? Date.distantPast
                let date2 = (person2.conversations as? Set<Conversation>)?
                    .compactMap { $0.date }
                    .max() ?? Date.distantPast
                return date1 > date2
            }
        case .meetingCount:
            return people.sorted { person1, person2 in
                let count1 = (person1.conversations as? Set<Conversation>)?.count ?? 0
                let count2 = (person2.conversations as? Set<Conversation>)?.count ?? 0
                return count1 > count2
            }
        case .relationship:
            // Sort by relationship health
            return people
        }
    }
}