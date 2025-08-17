import SwiftUI

struct SectionHeaderView: View {
    let icon: String
    let title: String
    let count: Int?
    let iconColor: Color
    let useSystemIcon: Bool
    
    init(
        icon: String,
        title: String,
        count: Int? = nil,
        iconColor: Color = .accentColor,
        useSystemIcon: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.iconColor = iconColor
        self.useSystemIcon = useSystemIcon
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if useSystemIcon {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(iconColor)
            }
            
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            if let count = count {
                Text("(\(count))")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(.secondary.opacity(0.1))
                    }
            }
            
            Spacer()
        }
        .liquidGlassSectionHeader()
    }
}

#Preview {
    VStack(spacing: 20) {
        SectionHeaderView(
            icon: "calendar.badge.clock",
            title: "Upcoming Meetings",
            count: 3
        )
        
        SectionHeaderView(
            icon: "icon_bell",
            title: "Follow-up Needed",
            count: 2,
            useSystemIcon: false
        )
        
        SectionHeaderView(
            icon: "chart.line.uptrend.xyaxis",
            title: "Analytics"
        )
    }
    .padding()
}