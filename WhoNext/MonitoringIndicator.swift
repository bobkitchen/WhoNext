import SwiftUI

/// Compact toolbar indicator for monitoring/recording status
/// Replaces the floating window for monitoring, shows inline in main toolbar
struct MonitoringIndicator: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            // Status dot with pulse animation
            statusDot

            // Status text
            if recordingEngine.isRecording {
                // Show duration when recording
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            } else if recordingEngine.isMonitoring {
                Text("Monitoring")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundStyle)
        .clipShape(Capsule())
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: recordingEngine.isMonitoring) { _, _ in
            startPulseAnimation()
        }
        .onChange(of: recordingEngine.isRecording) { _, _ in
            startPulseAnimation()
        }
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        ZStack {
            // Pulse ring (only when active)
            if isActive {
                Circle()
                    .stroke(statusColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            }

            // Main dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? statusColor.opacity(0.5) : .clear, radius: 3)
        }
        .frame(width: 16, height: 16)
    }

    // MARK: - Background Style

    @ViewBuilder
    private var backgroundStyle: some View {
        if recordingEngine.isRecording {
            Color.red.opacity(0.1)
        } else if recordingEngine.isMonitoring {
            Color.green.opacity(0.1)
        } else {
            Color.clear
        }
    }

    // MARK: - Computed Properties

    private var isActive: Bool {
        recordingEngine.isMonitoring || recordingEngine.isRecording
    }

    private var statusColor: Color {
        if recordingEngine.isRecording {
            return .red
        } else if recordingEngine.isMonitoring {
            return .green
        } else {
            return .gray
        }
    }

    private var formattedDuration: String {
        let duration = recordingEngine.recordingDuration
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Animation

    private func startPulseAnimation() {
        guard isActive else {
            isPulsing = false
            return
        }

        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }
}

// MARK: - Preview

#Preview {
    HStack {
        MonitoringIndicator()
    }
    .padding()
}
