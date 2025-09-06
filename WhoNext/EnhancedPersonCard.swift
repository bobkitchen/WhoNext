import SwiftUI
import CoreData
import AppKit

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
        else { return .unknown }  // Changed from .inactive to .unknown
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
        HStack(spacing: 14) {
            // Avatar
            avatarView
                .frame(width: 44, height: 44)
            
            // Person Info
            VStack(alignment: .leading, spacing: 6) {
                // Name and badges row
                HStack(spacing: 8) {
                    Text(person.name ?? "Unnamed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if person.isDirectReport {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .symbolRenderingMode(.multicolor)
                    }
                    
                    Spacer()
                }
                
                // Role
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Stats row
                HStack(spacing: 16) {
                    // Meeting count
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text("\(meetingCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    
                    // Last interaction
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(lastInteraction)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right side items
            HStack(spacing: 12) {
                // Health indicator
                healthIndicator
                
                // Action buttons (visible on hover)
                if isHovered || isSelected {
                    actionButtons
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    
    @ViewBuilder
    private var avatarView: some View {
        if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        } else {
            ZStack {
                Circle()
                    .fill(avatarBackgroundColor)
                    .frame(width: 40, height: 40)
                
                Text(person.initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
    }
    
    private var healthIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(relationshipHealth.color)
                .frame(width: 7, height: 7)
            Text(relationshipHealth.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(relationshipHealth.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(relationshipHealth.color.opacity(0.15))
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: 6) {
            // Schedule meeting
            Button(action: scheduleMeeting) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            .help("Schedule meeting")
            
            // View details
            Button(action: viewDetails) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
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
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isSelected ? 
                Color.accentColor.opacity(0.08) : 
                (isHovered ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.4) : 
                (isHovered ? Color(NSColor.separatorColor).opacity(0.3) : Color.clear),
                lineWidth: isSelected ? 1.5 : 1
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
        let person = self.person
        
        // Get templates from UserDefaults (AppStorage)
        let subjectTemplate = UserDefaults.standard.string(forKey: "emailSubjectTemplate") ?? "1:1 - {name} + BK"
        let bodyTemplate = UserDefaults.standard.string(forKey: "emailBodyTemplate") ?? """
        Hi {firstName},
        
        I wanted to follow up on our conversation and see how things are going.
        
        Would you have time for a quick chat this week?
        
        Best regards
        """
        
        // Replace placeholders
        let firstName = person.name?.components(separatedBy: " ").first ?? "there"
        let fullName = person.name ?? "Meeting"
        
        let subject = subjectTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        let body = bodyTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)
        
        // Get email address
        let email = inferEmailFromName(person)
        
        // Create email using mailto (only reliable method for new Outlook)
        openEmailInOutlook(to: email, subject: subject, body: body)
    }
    
    private func openEmailInOutlook(to: String, subject: String, body: String) {
        // URL encode the components
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTo = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email parameters")
            return
        }
        
        let mailtoString = "mailto:\(encodedTo)?subject=\(encodedSubject)&body=\(encodedBody)"
        
        if let url = URL(string: mailtoString) {
            NSWorkspace.shared.open(url)
            print("✅ Email opened in default mail client for scheduling with \(person.name ?? "person")")
        }
    }
    
    private func inferEmailFromName(_ person: Person) -> String {
        // Simple email inference if not stored
        let nameParts = person.name?.components(separatedBy: " ") ?? []
        let firstName = nameParts.first?.lowercased() ?? "unknown"
        let lastName = nameParts.count > 1 ? nameParts[1].lowercased() : ""
        // Note: User should update this domain to match their organization
        return "\(firstName).\(lastName)@example.com"
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
    case unknown
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .moderate: return .orange
        case .needsAttention: return .yellow
        case .unknown: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .moderate: return "Moderate"
        case .needsAttention: return "Check-in"
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor.opacity(0.8))
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("(\(count))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}