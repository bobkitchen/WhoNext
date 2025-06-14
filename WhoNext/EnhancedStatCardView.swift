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
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating, value: animateValue)
                
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
                    .animation(.liquidGlassSpring, value: animateValue)
                    .contentTransition(.numericText())
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .liquidGlassCard(
            cornerRadius: 16,
            elevation: isHovered ? .high : .medium,
            padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
            isInteractive: true
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.liquidGlass, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            // Animate value on appear
            withAnimation(.liquidGlass.delay(0.1)) {
                animateValue = true
            }
            
            // Reset animation after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.liquidGlass) {
                    animateValue = false
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint(subtitle)
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    @State private var animatedProgress: Double = 0
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.5), color]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.liquidGlassSpring.delay(0.2), value: animatedProgress)
            
            // Center text
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.liquidGlassSpring, value: isAnimating)
        }
        .onAppear {
            withAnimation(.liquidGlassSpring.delay(0.3)) {
                animatedProgress = progress
                isAnimating = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.liquidGlass) {
                    isAnimating = false
                }
            }
        }
        .onChange(of: progress) { newProgress in
            withAnimation(.liquidGlass) {
                animatedProgress = newProgress
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
