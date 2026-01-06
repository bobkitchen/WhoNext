import SwiftUI

/// Notification data for AI provider fallback
struct FallbackNotification: Identifiable, Equatable {
    let id = UUID()
    let reason: FallbackReason
    let fromProvider: String
    let toProvider: String
    let timestamp: Date = Date()

    enum FallbackReason: Equatable {
        case contentPolicy(content: String)
        case serviceUnavailable
        case apiError(message: String)
        case timeout

        var displayText: String {
            switch self {
            case .contentPolicy(let content):
                return "Apple Intelligence refused sensitive content: \(content)"
            case .serviceUnavailable:
                return "Primary AI service unavailable"
            case .apiError(let message):
                return "API Error: \(message)"
            case .timeout:
                return "Request timeout"
            }
        }

        var icon: String {
            switch self {
            case .contentPolicy: return "exclamationmark.shield"
            case .serviceUnavailable: return "exclamationmark.triangle"
            case .apiError: return "exclamationmark.circle"
            case .timeout: return "clock.badge.exclamationmark"
            }
        }
    }

    var title: String {
        "AI Provider Fallback"
    }

    var message: String {
        "\(reason.displayText)\n\nAutomatically switched from \(fromProvider) to \(toProvider)"
    }
}

/// Banner view for displaying fallback notifications
struct FallbackNotificationBanner: View {
    let notification: FallbackNotification
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.reason.icon)
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(notification.reason.displayText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text("Switched to \(notification.toProvider)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }

            // Auto-dismiss after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}

/// Manager for fallback notifications
class FallbackNotificationManager: ObservableObject {
    static let shared = FallbackNotificationManager()

    @Published var currentNotification: FallbackNotification?

    private init() {}

    func showFallback(
        reason: FallbackNotification.FallbackReason,
        from fromProvider: String,
        to toProvider: String
    ) {
        DispatchQueue.main.async {
            self.currentNotification = FallbackNotification(
                reason: reason,
                fromProvider: fromProvider,
                toProvider: toProvider
            )

            print("🔔 [Fallback] \(reason.displayText)")
            print("🔔 [Fallback] Switched from \(fromProvider) to \(toProvider)")
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.currentNotification = nil
        }
    }
}

/// View modifier to show fallback notifications
struct FallbackNotificationModifier: ViewModifier {
    @ObservedObject private var manager = FallbackNotificationManager.shared

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let notification = manager.currentNotification {
                FallbackNotificationBanner(
                    notification: notification,
                    onDismiss: { manager.dismiss() }
                )
                .padding(.top, 8)
                .zIndex(999)
            }
        }
    }
}

extension View {
    func fallbackNotifications() -> some View {
        modifier(FallbackNotificationModifier())
    }
}
