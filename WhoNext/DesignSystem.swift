import SwiftUI
import CoreData

// MARK: - Color Palette
extension Color {
    static let primaryGreen = Color(red: 16/255, green: 185/255, blue: 129/255)  // Emerald for active
    static let primaryBlue = Color(red: 59/255, green: 130/255, blue: 246/255)   // Blue for 1:1s
    static let primaryPurple = Color(red: 139/255, green: 92/255, blue: 246/255) // Purple for groups
    static let surfaceElevated = Color(NSColor.controlBackgroundColor)
    static let borderSubtle = Color(NSColor.separatorColor).opacity(0.5)
}

// MARK: - Hover Effect Modifier
struct HoverEffect: ViewModifier {
    @State private var isHovered = false
    let scaleAmount: CGFloat
    
    init(scale: CGFloat = 1.02) {
        self.scaleAmount = scale
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scaleAmount : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.05),
                radius: isHovered ? 8 : 4,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.02) -> some View {
        modifier(HoverEffect(scale: scale))
    }
}

// MARK: - Glowing Pulse Animation
struct GlowingPulse: ViewModifier {
    @State private var isAnimating = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color.opacity(0.3))
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .opacity(isAnimating ? 0 : 0.5)
                    .animation(
                        .easeInOut(duration: 2)
                        .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Stat Pill Component
struct StatPill: View {
    let icon: String
    let value: String
    let color: Color
    
    init(icon: String, value: String, color: Color = .secondary) {
        self.icon = icon
        self.value = value
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Participant Avatar Stack
struct ParticipantAvatarStack: View {
    let participants: [String]
    let maxVisible = 3
    
    var body: some View {
        HStack(spacing: -8) {
            ForEach(participants.prefix(maxVisible), id: \.self) { participant in
                EnhancedPersonAvatar(name: participant)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
            
            if participants.count > maxVisible {
                MoreAvatar(count: participants.count - maxVisible)
            }
        }
    }
}

// MARK: - Enhanced Person Avatar
struct EnhancedPersonAvatar: View {
    let name: String
    @Environment(\.managedObjectContext) private var viewContext
    @State private var photoData: Data?

    private var initials: String {
        let names = name.split(separator: " ")
        if names.count >= 2 {
            return String(names[0].prefix(1)) + String(names[1].prefix(1))
        } else if !names.isEmpty {
            return String(names[0].prefix(2))
        }
        return "?"
    }

    private var backgroundColor: Color {
        let colors: [Color] = [.primaryBlue, .primaryGreen, .primaryPurple, .orange, .pink]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
        ZStack {
            if let photoData = photoData, let nsImage = NSImage(data: photoData) {
                // Show photo if available
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                // Fallback to colored circle with initials
                Circle()
                    .fill(backgroundColor)
                Text(initials.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            lookupPerson()
        }
    }

    private func lookupPerson() {
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        request.fetchLimit = 1

        if let person = try? viewContext.fetch(request).first {
            photoData = person.photo
        }
    }
}

// MARK: - More Avatar
struct MoreAvatar: View {
    let count: Int
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
            Text("+\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Duration Chip
struct DurationChip: View {
    let duration: TimeInterval
    
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }
    }
    
    var body: some View {
        Text(formattedDuration)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
    }
}

// MARK: - Meeting Type Badge
struct MeetingTypeBadge: View {
    enum MeetingType {
        case oneOnOne
        case group
        case unknown
        
        var icon: String {
            switch self {
            case .oneOnOne: return "person.2"
            case .group: return "person.3"
            case .unknown: return "questionmark.circle"
            }
        }
        
        var displayName: String {
            switch self {
            case .oneOnOne: return "1:1"
            case .group: return "Group"
            case .unknown: return "Unknown"
            }
        }
        
        var color: Color {
            switch self {
            case .oneOnOne: return .primaryBlue
            case .group: return .primaryPurple
            case .unknown: return .gray
            }
        }
    }
    
    let type: MeetingType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 10))
            Text(type.displayName)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(type.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(type.color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Loading Skeleton
struct SkeletonLoader: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray.opacity(0.1),
                Color.gray.opacity(0.2),
                Color.gray.opacity(0.1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: isAnimating ? 300 : -300)
        .animation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
    }
}

// MARK: - Smooth Transition
struct SmoothTransition: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
    }
}

extension View {
    func smoothTransition(isVisible: Bool = true) -> some View {
        modifier(SmoothTransition(isVisible: isVisible))
    }
}

// MARK: - Enhanced Waveform Visualization
struct EnhancedWaveformView: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.2, count: 20)
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primaryGreen)
                    .frame(width: 3, height: amplitudes[index] * 20)
                    .animation(.easeInOut(duration: 0.1), value: amplitudes[index])
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                for i in 0..<amplitudes.count {
                    amplitudes[i] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}