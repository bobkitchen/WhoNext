import SwiftUI

struct PersonCard: View {
    let person: Person
    let isFollowUp: Bool  // Determines if this is a follow-up card or upcoming meeting card
    @State private var isHovered = false
    var onDismiss: (() -> Void)?  // Optional dismiss action for follow-up cards
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile section
            HStack(spacing: 12) {
                PersonAvatar(
                    initials: person.initials,
                    size: 48,
                    showOnlineIndicator: false
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name ?? "Unknown")
                        .font(.system(size: 16, weight: .semibold))
                    if let role = person.role {
                        Text(role)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if isFollowUp {
                    Spacer()
                    Button(action: {
                        onDismiss?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Last contact or scheduled meeting info
            if isFollowUp, let lastContact = person.lastContactDate {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Last contact: \(lastContact.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else if let scheduled = person.scheduledConversationDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(scheduled.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13))
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 4 : 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// Preview provider for development
struct PersonCard_Previews: PreviewProvider {
    static var previews: some View {
        PersonCard(person: Person(), isFollowUp: true)
            .frame(width: 300)
            .padding()
    }
} 
