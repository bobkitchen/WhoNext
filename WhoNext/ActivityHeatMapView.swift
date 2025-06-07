import SwiftUI
import CoreData

struct ActivityHeatMapView: View {
    let people: [Person]
    @State private var animateHeatMap = false
    
    private let daysOfWeek = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let weeksToShow = 12
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40 // Account for week labels and padding
            let cellSize = min((availableWidth - 24) / 7, 20) // Max 20px, responsive to width
            
            VStack(alignment: .leading, spacing: 16) {
                // Heat map grid
                VStack(spacing: 4) {
                    // Days of week header
                    HStack(spacing: 4) {
                        Spacer().frame(width: 30) // Space for week labels
                        ForEach(daysOfWeek, id: \.self) { day in
                            Text(day)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .frame(width: cellSize, height: 16)
                        }
                        Spacer()
                    }
                    
                    // Heat map cells
                    VStack(spacing: 2) {
                        ForEach(0..<weeksToShow, id: \.self) { weekIndex in
                            HStack(spacing: 2) {
                                // Week label
                                Text(weekLabel(for: weekIndex))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                
                                // Daily activity cells
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    let date = dateForWeek(weekIndex, day: dayIndex)
                                    let activity = activityLevel(for: date)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(colorForActivity(activity))
                                        .frame(width: cellSize, height: cellSize)
                                        .scaleEffect(animateHeatMap ? 1.0 : 0.0)
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.8)
                                            .delay(Double(weekIndex * 7 + dayIndex) * 0.01),
                                            value: animateHeatMap
                                        )
                                        .help(tooltipForDate(date, activity: activity))
                                }
                                Spacer()
                            }
                        }
                    }
                }
                
                // Legend
                HStack {
                    Text("Less")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForActivity(level))
                                .frame(width: 12, height: 12)
                        }
                    }
                    
                    Text("More")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Activity summary
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalConversations) conversations")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("in last 12 weeks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 200) // Fixed height for the heat map
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            withAnimation {
                animateHeatMap = true
            }
        }
    }
    
    private func dateForWeek(_ weekIndex: Int, day dayIndex: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weeksAgo = calendar.date(byAdding: .weekOfYear, value: -(weeksToShow - 1 - weekIndex), to: startOfWeek) ?? now
        return calendar.date(byAdding: .day, value: dayIndex, to: weeksAgo) ?? weeksAgo
    }
    
    private func weekLabel(for weekIndex: Int) -> String {
        let date = dateForWeek(weekIndex, day: 0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func activityLevel(for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        var conversationCount = 0
        
        for person in people {
            if let conversations = person.conversations as? Set<Conversation> {
                for conversation in conversations {
                    if let conversationDate = conversation.date,
                       conversationDate >= dayStart && conversationDate < dayEnd {
                        conversationCount += 1
                    }
                }
            }
        }
        
        // Map conversation count to activity level (0-4)
        switch conversationCount {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3...4: return 3
        default: return 4
        }
    }
    
    private func colorForActivity(_ level: Int) -> Color {
        switch level {
        case 0: return Color.gray.opacity(0.1)
        case 1: return Color.blue.opacity(0.3)
        case 2: return Color.blue.opacity(0.5)
        case 3: return Color.blue.opacity(0.7)
        case 4: return Color.blue.opacity(0.9)
        default: return Color.gray.opacity(0.1)
        }
    }
    
    private func tooltipForDate(_ date: Date, activity: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateString = formatter.string(from: date)
        
        switch activity {
        case 0: return "\(dateString): No conversations"
        case 1: return "\(dateString): 1 conversation"
        default: return "\(dateString): \(activity == 4 ? "5+" : "\(activity)") conversations"
        }
    }
    
    private var totalConversations: Int {
        let calendar = Calendar.current
        let twelveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -12, to: Date()) ?? Date()
        
        var total = 0
        for person in people {
            if let conversations = person.conversations as? Set<Conversation> {
                total += conversations.filter { conversation in
                    guard let date = conversation.date else { return false }
                    return date >= twelveWeeksAgo
                }.count
            }
        }
        return total
    }
}

#Preview {
    ActivityHeatMapView(people: [])
        .frame(width: 400, height: 300)
        .padding()
}
