import SwiftUI
import CoreData

struct TimelineView: View {
    let people: [Person]
    let onPersonSelected: ((Person) -> Void)?
    @State private var selectedTimeframe: TimeFrame = .month
    @State private var animateTimeline = false
    
    init(people: [Person], onPersonSelected: ((Person) -> Void)? = nil) {
        self.people = people
        self.onPersonSelected = onPersonSelected
    }
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case quarter = "Quarter"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Timeframe picker
            HStack {
                Spacer()
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(TimeFrame.allCases, id: \.self) { timeframe in
                        Text(timeframe.rawValue).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            
            // Timeline content
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(timelineData, id: \.date) { item in
                        TimelineItemView(item: item, onPersonSelected: onPersonSelected)
                            .scaleEffect(animateTimeline ? 1.0 : 0.8)
                            .opacity(animateTimeline ? 1.0 : 0.0)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.8)
                                .delay(Double(timelineData.firstIndex(where: { $0.date == item.date }) ?? 0) * 0.1),
                                value: animateTimeline
                            )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .frame(height: 120)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            withAnimation {
                animateTimeline = true
            }
        }
        .onChange(of: selectedTimeframe) { _, _ in
            animateTimeline = false
            withAnimation {
                animateTimeline = true
            }
        }
    }
    
    private var timelineData: [TimelineItem] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -selectedTimeframe.days, to: now) ?? now
        
        var items: [TimelineItem] = []
        var conversations: [(Person, Date)] = []
        
        // Collect all conversations within timeframe
        for person in people {
            if let conversationsSet = person.conversations as? Set<Conversation> {
                for conversation in conversationsSet {
                    if let date = conversation.date, date >= startDate {
                        conversations.append((person, date))
                    }
                }
            }
        }
        
        // Group by date and create timeline items
        let groupedByDate = Dictionary(grouping: conversations) { conversation in
            calendar.startOfDay(for: conversation.1)
        }
        
        for (date, dayConversations) in groupedByDate.sorted(by: { $0.key < $1.key }) {
            let item = TimelineItem(
                date: date,
                conversations: dayConversations.map { $0.0 },
                type: dayConversations.count > 2 ? .busy : .normal
            )
            items.append(item)
        }
        
        return items
    }
}

struct TimelineItem {
    let date: Date
    let conversations: [Person]
    let type: TimelineItemType
    
    enum TimelineItemType {
        case normal
        case busy
        
        var color: Color {
            switch self {
            case .normal: return .blue
            case .busy: return .orange
            }
        }
    }
}

struct TimelineItemView: View {
    let item: TimelineItem
    let onPersonSelected: ((Person) -> Void)?
    @State private var isHovered = false
    
    init(item: TimelineItem, onPersonSelected: ((Person) -> Void)? = nil) {
        self.item = item
        self.onPersonSelected = onPersonSelected
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Date
            Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Activity indicator
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Circle()
                    .fill(item.type.color)
                    .frame(width: isHovered ? 24 : 16, height: isHovered ? 24 : 16)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                if item.conversations.count > 1 {
                    Text("\(item.conversations.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            
            // People avatars (max 3)
            HStack(spacing: -8) {
                ForEach(Array(item.conversations.prefix(3).enumerated()), id: \.offset) { index, person in
                    Button(action: {
                        onPersonSelected?(person)
                    }) {
                        PersonAvatarView(person: person, size: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color(NSColor.controlBackgroundColor), lineWidth: 2)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .zIndex(Double(3 - index))
                }
                
                if item.conversations.count > 3 {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("+\(item.conversations.count - 3)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(NSColor.controlBackgroundColor), lineWidth: 2)
                        )
                }
            }
        }
        .frame(width: 60)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltipText)
    }
    
    private var tooltipText: String {
        let names = item.conversations.prefix(3).compactMap { $0.name }.joined(separator: ", ")
        let extra = item.conversations.count > 3 ? " and \(item.conversations.count - 3) more" : ""
        return "Conversations with \(names)\(extra)"
    }
}

struct PersonAvatarView: View {
    let person: Person
    let size: CGFloat
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [avatarColor, avatarColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(.white)
            )
    }
    
    private var initials: String {
        guard let name = person.name else { return "?" }
        let components = name.components(separatedBy: " ")
        let first = components.first?.prefix(1) ?? "?"
        let last = components.count > 1 ? components.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)"
    }
    
    private var avatarColor: Color {
        guard let name = person.name else { return .gray }
        let hash = name.hashValue
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        return colors[abs(hash) % colors.count]
    }
}

#Preview {
    TimelineView(people: [])
        .frame(width: 600, height: 200)
        .padding()
}
