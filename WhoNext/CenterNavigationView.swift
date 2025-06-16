import SwiftUI

struct CenterNavigationView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            NavigationTabButton(
                icon: "chart.line.uptrend.xyaxis",
                title: "Insights",
                isSelected: appState.selectedTab == .insights,
                action: { appState.selectedTab = .insights }
            )
            
            NavigationTabButton(
                icon: "person.2",
                title: "People", 
                isSelected: appState.selectedTab == .people,
                action: { appState.selectedTab = .people }
            )
            
            NavigationTabButton(
                icon: "chart.bar.fill",
                title: "Analytics",
                isSelected: appState.selectedTab == .analytics,
                action: { appState.selectedTab = .analytics }
            )
        }
        .padding(2)
        .liquidGlassBackground(cornerRadius: 10, elevation: .medium)
        .animation(.liquidGlassFast, value: appState.selectedTab)
    }
}

struct NavigationTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help(title)
    }
}

#Preview {
    CenterNavigationView(appState: AppState())
}