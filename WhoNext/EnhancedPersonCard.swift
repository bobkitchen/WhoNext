import SwiftUI
import CoreData

// MARK: - Enhanced Person Card
struct EnhancedPersonCard: View {
    let person: Person
    @Binding var selectedPerson: Person?
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var isHovered = false
    @State private var showingActions = false
    
    private var isSelected: Bool {
        selectedPerson?.identifier == person.identifier
    }
    
    // Calculate relationship health based on meeting frequency
    private var relationshipHealth: RelationshipHealth {
        guard let conversations = person.conversations as? Set<Conversation> else {
            return .unknown
        }
        
        let recentCount = conversations.filter { conversation in
            guard let date = conversation.date else { return false }
            return date > Date().addingTimeInterval(-30 * 24 * 60 * 60) // Last 30 days
        }.count
        
        if recentCount >= 4 { return .healthy }
        else if recentCount >= 2 { return .moderate }
        else if recentCount >= 1 { return .needsAttention }
        else { return .inactive }
    }
    
    private var lastInteraction: String {
        guard let conversations = person.conversations as? Set<Conversation>,
              let lastConversation = conversations.max(by: { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }),
              let date = lastConversation.date else {
            return "No meetings yet"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var meetingCount: Int {
        (person.conversations as? Set<Conversation>)?.count ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Avatar
                avatarView
                
                // Person Info
                VStack(alignment: .leading, spacing: 4) {
                    // Name and badges
                    HStack(spacing: 6) {
                        Text(person.name ?? "Unnamed")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if person.isDirectReport {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                        
                        // Online status indicator
                        Circle()
                            .fill(onlineStatusColor)
                            .frame(width: 6, height: 6)
                    }
                    
                    // Role and department
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Stats row
                    HStack(spacing: 12) {
                        // Meeting count
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text("\(meetingCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        
                        // Last interaction
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(lastInteraction)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Health indicator
                        healthIndicator
                    }
                }
                
                Spacer()
                
                // Action buttons (visible on hover)
                if isHovered || isSelected {
                    actionButtons
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .hoverEffect(scale: 1.01)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedPerson = person
            }
        }
        .contextMenu {
            contextMenuItems
        }
    }
    
    // MARK: - Subviews
    
    private var avatarView: some View {
        Group {
            if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(avatarBackgroundColor)
                        .frame(width: 40, height: 40)
                    
                    Text(person.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .overlay(
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
    
    private var healthIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(relationshipHealth.color)
                .frame(width: 8, height: 8)
            Text(relationshipHealth.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(relationshipHealth.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(relationshipHealth.color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Schedule meeting
            Button(action: scheduleMeeting) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Schedule meeting")
            
            // View details
            Button(action: viewDetails) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("View details")
        }
    }
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: scheduleMeeting) {
            Label("Schedule Meeting", systemImage: "calendar.badge.plus")
        }
        
        Button(action: viewDetails) {
            Label("View Details", systemImage: "person.crop.circle")
        }
        
        Divider()
        
        if person.isDirectReport {
            Button(action: removeFromDirectReports) {
                Label("Remove from Direct Reports", systemImage: "star.slash")
            }
        } else {
            Button(action: addToDirectReports) {
                Label("Add to Direct Reports", systemImage: "star")
            }
        }
        
        Divider()
        
        Button(role: .destructive, action: deletePerson) {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Computed Properties
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.3) : 
                (isHovered ? Color.borderSubtle : Color.clear),
                lineWidth: 1
            )
    }
    
    private var onlineStatusColor: Color {
        // Simulate online status - in real app, this would check actual status
        Bool.random() ? .green : .gray
    }
    
    private var avatarBackgroundColor: Color {
        let colors: [Color] = [.primaryBlue, .primaryGreen, .primaryPurple, .orange, .pink]
        let index = abs((person.name ?? "").hashValue) % colors.count
        return colors[index]
    }
    
    // MARK: - Actions
    
    private func scheduleMeeting() {
        // TODO: Implement meeting scheduling
        print("Schedule meeting with \(person.name ?? "person")")
    }
    
    private func viewDetails() {
        selectedPerson = person
    }
    
    private func addToDirectReports() {
        person.isDirectReport = true
        try? viewContext.save()
    }
    
    private func removeFromDirectReports() {
        person.isDirectReport = false
        try? viewContext.save()
    }
    
    private func deletePerson() {
        if selectedPerson == person {
            selectedPerson = nil
        }
        viewContext.delete(person)
        try? viewContext.save()
        
        Task {
            await RobustSyncManager.shared.performSync()
        }
    }
}

// MARK: - Relationship Health Enum
enum RelationshipHealth {
    case healthy
    case moderate
    case needsAttention
    case inactive
    case unknown
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .moderate: return .orange
        case .needsAttention: return .yellow
        case .inactive: return .red
        case .unknown: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .moderate: return "Moderate"
        case .needsAttention: return "Check-in"
        case .inactive: return "Inactive"
        case .unknown: return "New"
        }
    }
}

// MARK: - Person Section Header
struct PersonSectionHeader: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("(\(count))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}