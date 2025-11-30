import SwiftUI

// MARK: - Enhanced Search Bar
struct EnhancedPeopleSearchBar: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Search icon with animation
            Image(systemName: isFocused ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(isFocused ? .accentColor : .secondary)
                .animation(.spring(response: 0.3), value: isFocused)
            
            // Search field
            TextField("Search people by name, role, or department...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
            
            // Clear button
            if !searchText.isEmpty {
                Button(action: { 
                    withAnimation(.spring(response: 0.3)) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isFocused ? Color.accentColor.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.2), 
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: isFocused ? Color.accentColor.opacity(0.1) : .clear, radius: 5, y: 2)
    }
}

// MARK: - Filter Chips
struct PeopleFilterChips: View {
    @Binding var selectedFilters: Set<PersonFilter>
    @State private var showAllFilters = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Quick filters
                ForEach(PersonFilter.quickFilters, id: \.self) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: selectedFilters.contains(filter),
                        action: { toggleFilter(filter) }
                    )
                }
                
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)
                
                // More filters button
                Button(action: { showAllFilters.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11))
                        Text("More")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor).opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                // Clear all filters
                if !selectedFilters.isEmpty {
                    Button(action: clearAllFilters) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                            Text("Clear all")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAllFilters) {
            AllFiltersView(selectedFilters: $selectedFilters)
        }
    }
    
    private func toggleFilter(_ filter: PersonFilter) {
        withAnimation(.spring(response: 0.3)) {
            if selectedFilters.contains(filter) {
                selectedFilters.remove(filter)
            } else {
                selectedFilters.insert(filter)
            }
        }
    }
    
    private func clearAllFilters() {
        withAnimation(.spring(response: 0.3)) {
            selectedFilters.removeAll()
        }
    }
}

// MARK: - Filter Chip Component
struct FilterChip: View {
    let filter: PersonFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11))
                Text(filter.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor).opacity(0.2), lineWidth: isSelected ? 0 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.05)
    }
}

// MARK: - All Filters View
struct AllFiltersView: View {
    @Binding var selectedFilters: Set<PersonFilter>
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Filters")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Filter sections
                    ForEach(PersonFilter.Category.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 150), spacing: 12)
                            ], spacing: 12) {
                                ForEach(PersonFilter.filters(for: category), id: \.self) { filter in
                                    FilterChip(
                                        filter: filter,
                                        isSelected: selectedFilters.contains(filter),
                                        action: { toggleFilter(filter) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func toggleFilter(_ filter: PersonFilter) {
        withAnimation(.spring(response: 0.3)) {
            if selectedFilters.contains(filter) {
                selectedFilters.remove(filter)
            } else {
                selectedFilters.insert(filter)
            }
        }
    }
}

// MARK: - Person Filter Enum
enum PersonFilter: Hashable {
    case directReport
    case recentlyContacted
    case needsCheckIn
    case healthy
    case hasNotes
    case noMeetings
    case frequentMeetings
    case role(String)
    case department(String)
    
    var label: String {
        switch self {
        case .directReport: return "Direct Reports"
        case .recentlyContacted: return "Recently Met"
        case .needsCheckIn: return "Needs Check-in"
        case .healthy: return "Healthy"
        case .hasNotes: return "Has Notes"
        case .noMeetings: return "No Meetings"
        case .frequentMeetings: return "Frequent"
        case .role(let role): return role
        case .department(let dept): return dept
        }
    }
    
    var icon: String {
        switch self {
        case .directReport: return "star.fill"
        case .recentlyContacted: return "clock.fill"
        case .needsCheckIn: return "exclamationmark.circle.fill"
        case .healthy: return "checkmark.circle.fill"
        case .hasNotes: return "note.text"
        case .noMeetings: return "calendar.badge.minus"
        case .frequentMeetings: return "calendar.badge.plus"
        case .role: return "briefcase.fill"
        case .department: return "building.2.fill"
        }
    }
    
    static var quickFilters: [PersonFilter] {
        [.directReport, .recentlyContacted, .needsCheckIn, .healthy]
    }
    
    enum Category: CaseIterable {
        case relationship
        case activity
        case metadata
        
        var title: String {
            switch self {
            case .relationship: return "Relationship"
            case .activity: return "Activity"
            case .metadata: return "Metadata"
            }
        }
    }
    
    static func filters(for category: Category) -> [PersonFilter] {
        switch category {
        case .relationship:
            return [.directReport, .healthy, .needsCheckIn]
        case .activity:
            return [.recentlyContacted, .frequentMeetings, .noMeetings]
        case .metadata:
            return [.hasNotes]
        }
    }
}

// MARK: - Sort Options
struct PeopleSortOptions: View {
    @Binding var sortOption: PersonSortOption
    
    var body: some View {
        Menu {
            ForEach(PersonSortOption.allCases, id: \.self) { option in
                Button(action: { sortOption = option }) {
                    HStack {
                        Text(option.label)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(sortOption.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
    }
}

enum PersonSortOption: CaseIterable {
    case name
    case lastMeeting
    case meetingCount
    case relationship
    
    var label: String {
        switch self {
        case .name: return "Name"
        case .lastMeeting: return "Last Meeting"
        case .meetingCount: return "Most Meetings"
        case .relationship: return "Relationship"
        }
    }
}