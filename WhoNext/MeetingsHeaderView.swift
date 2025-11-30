import SwiftUI

struct MeetingsHeaderView: View {
    @Binding var selectedFilter: MeetingsView.MeetingFilter
    let todaysCount: Int
    let thisWeeksCount: Int
    let onJoinMeeting: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Top row with title and stats
            HStack(alignment: .center, spacing: 16) {
                // Title
                Text("Meetings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Stats badge
                HStack(spacing: 8) {
                    Text("\(todaysCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("today")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 12)
                    
                    Text("\(thisWeeksCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("this week")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.separatorColor).opacity(0.1))
                .cornerRadius(6)
                
                Spacer()
                
                // Record Button (Quick Action)
                Button(action: onJoinMeeting) {
                    Label("Record Meeting", systemImage: "record.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // Bottom row with filters
            HStack(spacing: 16) {
                // Filter Chips
                HStack(spacing: 8) {
                    ForEach(MeetingsView.MeetingFilter.allCases, id: \.self) { filter in
                        MeetingFilterChip(
                            title: filter.rawValue,
                            icon: filter.icon,
                            isSelected: selectedFilter == filter,
                            action: { selectedFilter = filter }
                        )
                    }
                }
                
                Spacer()
                
                // Additional controls could go here (e.g. Calendar settings)
                Button(action: { 
                    // Open settings
                    NotificationCenter.default.post(name: Notification.Name("showRecordingDashboard"), object: nil)
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Recording Settings")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MeetingFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(Color(NSColor.separatorColor).opacity(0.2), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
