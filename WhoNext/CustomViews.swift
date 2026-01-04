import SwiftUI

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == Double(index) ? 1.2 : 0.8)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
                phase = phase < 2 ? phase + 1 : 0
            }
        }
    }
}

struct PersonAvatar: View {
    let initials: String
    let size: CGFloat
    let showOnlineIndicator: Bool
    let photoData: Data?

    init(initials: String, size: CGFloat, showOnlineIndicator: Bool = false, photoData: Data? = nil) {
        self.initials = initials
        self.size = size
        self.showOnlineIndicator = showOnlineIndicator
        self.photoData = photoData
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photoData = photoData, let nsImage = NSImage(data: photoData) {
                // Show photo if available
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                // Fallback to initials
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .foregroundColor(.white)
                            .font(.system(size: size * 0.4, weight: .medium))
                    )
            }

            if showOnlineIndicator {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
    }
} 