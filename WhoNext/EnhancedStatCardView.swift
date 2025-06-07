import SwiftUI

struct EnhancedStatCardView: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let progress: Double? // Optional progress value (0.0 to 1.0)
    
    @State private var isHovered = false
    @State private var animateValue = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
                    .symbolRenderingMode(.hierarchical)
                
                Spacer()
                
                if let progress = progress {
                    CircularProgressView(progress: progress, color: color)
                        .frame(width: 32, height: 32)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .scaleEffect(animateValue ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: animateValue)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        color.opacity(isHovered ? 0.12 : 0.08),
                        color.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .cornerRadius(16)
                
                // Border
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                color.opacity(0.3),
                                color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(
            color: color.opacity(isHovered ? 0.15 : 0.05),
            radius: isHovered ? 12 : 8,
            x: 0,
            y: isHovered ? 6 : 4
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                animateValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animateValue = false
                }
            }
        }
    }
}

// Enhanced Circular Progress Indicator
struct CircularProgressView: View {
    let progress: Double
    let color: Color
    @State private var animatedProgress: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 4)
            
            // Progress circle with gradient and glow
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            color,
                            color.opacity(0.8),
                            color,
                            color.opacity(0.6)
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 0)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1).repeatCount(1), value: isAnimating)
            
            // Percentage text
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.1).repeatCount(1), value: isAnimating)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                animatedProgress = progress
            }
            
            // Pulse animation on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isAnimating = false
                }
            }
        }
        .onChange(of: progress) { newProgress in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = newProgress
            }
            
            // Pulse on change
            isAnimating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAnimating = false
            }
        }
    }
}

// Preview
struct EnhancedStatCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            EnhancedStatCardView(
                icon: "flag.fill",
                title: "Cycle Progress",
                value: "4 / 83",
                subtitle: "Team members contacted",
                color: .blue,
                progress: 4.0 / 83.0
            )
            
            EnhancedStatCardView(
                icon: "clock.fill",
                title: "Weeks Remaining",
                value: "40 weeks",
                subtitle: "At 2 per week",
                color: .orange,
                progress: nil
            )
            
            EnhancedStatCardView(
                icon: "flame.fill",
                title: "Streak",
                value: "1 week",
                subtitle: "Weeks in a row",
                color: .red,
                progress: nil
            )
        }
        .padding()
        .frame(width: 300)
    }
}
