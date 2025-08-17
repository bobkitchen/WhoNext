import SwiftUI
import CoreData

struct PeopleAndGroupsView: View {
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var viewMode: ViewMode = .individuals
    @State private var searchText = ""
    
    enum ViewMode: String, CaseIterable {
        case individuals = "Individuals"
        case groups = "Groups"
        
        var icon: String {
            switch self {
            case .individuals:
                return "person.fill"
            case .groups:
                return "person.3.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Toggle
            headerView
            
            // Search Bar
            searchBar
            
            // Content based on selection
            if viewMode == .individuals {
                PeopleListView(selectedPerson: $selectedPerson)
            } else {
                GroupsListView()
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            // Title
            Text("People & Groups")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            // View Mode Toggle
            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search \(viewMode.rawValue.lowercased())...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}