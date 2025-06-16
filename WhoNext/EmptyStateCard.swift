import SwiftUI

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let useSystemIcon: Bool
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = .secondary,
        useSystemIcon: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.useSystemIcon = useSystemIcon
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if useSystemIcon {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(iconColor)
            }
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .liquidGlassCard(
            cornerRadius: 16,
            elevation: .low,
            padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
            isInteractive: false
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        EmptyStateCard(
            icon: "calendar.badge.clock",
            title: "No upcoming meetings",
            subtitle: "Your calendar is clear for this week"
        )
        
        EmptyStateCard(
            icon: "checkmark.circle.fill",
            title: "No follow-ups needed",
            subtitle: "All relationships are up to date",
            iconColor: .green
        )
    }
    .padding()
}