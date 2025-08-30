import SwiftUI
import Charts

/// Displays detailed analytics and visualizations for meeting speakers
struct SpeakerAnalyticsView: View {
    let participants: [IdentifiedParticipant]
    
    @State private var selectedTimeRange: TimeRange = .all
    @State private var showDetails: Bool = false
    
    enum TimeRange: String, CaseIterable {
        case all = "All"
        case last5 = "Last 5 min"
        case last10 = "Last 10 min"
        
        var seconds: TimeInterval? {
            switch self {
            case .all: return nil
            case .last5: return 300
            case .last10: return 600
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var totalSpeakingTime: TimeInterval {
        participants.reduce(0) { $0 + $1.totalSpeakingTime }
    }
    
    var activeSpeaker: IdentifiedParticipant? {
        participants.first { $0.isCurrentlySpeaking }
    }
    
    var speakingTimeData: [(String, Double)] {
        participants.map { participant in
            let percentage = totalSpeakingTime > 0 ? participant.totalSpeakingTime / totalSpeakingTime : 0
            return (participant.displayName, percentage)
        }.sorted { $0.1 > $1.1 }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with time range selector
            HStack {
                Text("Speaker Analytics")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            
            // Active Speaker Indicator
            if let active = activeSpeaker {
                ActiveSpeakerCard(participant: active)
            }
            
            // Speaking Time Distribution
            speakingTimeChart
            
            // Detailed Statistics
            if showDetails {
                detailedStats
            }
            
            // Show/Hide Details Button
            Button(action: { showDetails.toggle() }) {
                HStack {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                    Text(showDetails ? "Hide Details" : "Show Details")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Subviews
    
    private var speakingTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speaking Time Distribution")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Horizontal bar chart
            VStack(spacing: 8) {
                ForEach(speakingTimeData, id: \.0) { name, percentage in
                    HStack(spacing: 8) {
                        // Speaker name
                        Text(name)
                            .font(.system(size: 11))
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)
                        
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorForSpeaker(name))
                                    .frame(width: geometry.size.width * CGFloat(percentage))
                                    .animation(.easeInOut(duration: 0.3), value: percentage)
                            }
                        }
                        .frame(height: 16)
                        
                        // Percentage
                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(8)
        }
    }
    
    private var detailedStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Statistics")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(participants) { participant in
                    ParticipantStatCard(participant: participant)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func colorForSpeaker(_ name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Supporting Views

struct ActiveSpeakerCard: View {
    let participant: IdentifiedParticipant
    @State private var animateSpeaking = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar with animation
            ZStack {
                Circle()
                    .fill(participant.confidenceLevel.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Text(participant.displayName.prefix(2).uppercased())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(participant.confidenceLevel.color)
                
                // Speaking animation
                Circle()
                    .stroke(participant.confidenceLevel.color, lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(animateSpeaking ? 1.2 : 1.0)
                    .opacity(animateSpeaking ? 0 : 1)
                    .animation(
                        Animation.easeOut(duration: 1.0)
                            .repeatForever(autoreverses: false),
                        value: animateSpeaking
                    )
            }
            .onAppear { animateSpeaking = true }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    
                    Text("\(participant.displayName) is speaking")
                        .font(.system(size: 12, weight: .medium))
                }
                
                Text("Speaking for \(formatDuration(participant.totalSpeakingTime))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Confidence indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", participant.confidence * 100))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(participant.confidenceLevel.color)
                
                Text("confidence")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct ParticipantStatCard: View {
    let participant: IdentifiedParticipant
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(participant.confidenceLevel.color.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(participant.displayName.prefix(1).uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(participant.confidenceLevel.color)
                    )
                
                Text(participant.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                Spacer()
            }
            
            Divider()
            
            // Stats
            VStack(alignment: .leading, spacing: 4) {
                StatRow(label: "Total Time:", value: formatDuration(participant.totalSpeakingTime))
                StatRow(label: "Last Spoke:", value: formatLastSpoke(participant.lastSpokeAt))
                StatRow(label: "Confidence:", value: String(format: "%.0f%%", participant.confidence * 100))
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return minutes > 0 ? String(format: "%dm %ds", minutes, secs) : String(format: "%ds", secs)
    }
    
    private func formatLastSpoke(_ date: Date?) -> String {
        guard let date = date else { return "Never" }
        
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 9, weight: .medium))
        }
    }
}

// MARK: - Preview

struct SpeakerAnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        SpeakerAnalyticsView(participants: [])
            .frame(width: 400, height: 300)
    }
}