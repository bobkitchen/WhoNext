import SwiftUI
import AVFoundation
import EventKit
import ScreenCaptureKit

/// Onboarding step for requesting necessary permissions
/// Guides users through granting microphone, calendar, and screen recording access
struct OnboardingPermissionsView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var microphoneStatus: PermissionStatus = .unknown
    @State private var calendarStatus: PermissionStatus = .unknown
    @State private var screenRecordingStatus: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown, granted, denied, notDetermined
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue.gradient)

                Text("App Permissions")
                    .font(.title)
                    .fontWeight(.bold)

                Text("WhoNext needs a few permissions to work properly")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record your voice in meetings",
                    status: microphoneStatus,
                    isRequired: true,
                    onRequest: requestMicrophonePermission
                )

                PermissionCard(
                    icon: "calendar",
                    title: "Calendar",
                    description: "Detect upcoming meetings automatically",
                    status: calendarStatus,
                    isRequired: false,
                    onRequest: requestCalendarPermission
                )

                PermissionCard(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    description: "Capture system audio from meeting apps",
                    status: screenRecordingStatus,
                    isRequired: false,
                    onRequest: requestScreenRecordingPermission
                )
            }
            .padding(.horizontal, 40)

            // Info note
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("You can change these permissions later in System Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(canContinue ? Color.blue : Color.orange)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .onAppear {
            checkAllPermissions()
        }
    }

    private var canContinue: Bool {
        // At minimum, microphone is required
        microphoneStatus == .granted
    }

    // MARK: - Permission Checks

    private func checkAllPermissions() {
        checkMicrophonePermission()
        checkCalendarPermission()
        checkScreenRecordingPermission()
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    private func checkCalendarPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            calendarStatus = .granted
        case .denied, .restricted:
            calendarStatus = .denied
        case .notDetermined, .writeOnly:
            calendarStatus = .notDetermined
        @unknown default:
            calendarStatus = .unknown
        }
    }

    private func checkScreenRecordingPermission() {
        // Check if we have screen recording permission by attempting to get shareable content
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await MainActor.run {
                    screenRecordingStatus = .granted
                }
            } catch {
                await MainActor.run {
                    // If we get an error, permission is likely not granted
                    screenRecordingStatus = .notDetermined
                }
            }
        }
    }

    // MARK: - Permission Requests

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestCalendarPermission() {
        let eventStore = EKEventStore()
        eventStore.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async {
                calendarStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestScreenRecordingPermission() {
        // Open System Preferences to Screen Recording section
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            checkScreenRecordingPermission()
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: OnboardingPermissionsView.PermissionStatus
    let isRequired: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if isRequired {
                        Text("Required")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status / Action
            statusView
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .granted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .denied:
            Button(action: openSystemSettings) {
                Text("Open Settings")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        case .notDetermined, .unknown:
            Button(action: onRequest) {
                Text("Grant Access")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private var iconBackgroundColor: Color {
        switch status {
        case .granted: return Color.green.opacity(0.15)
        case .denied: return Color.red.opacity(0.15)
        default: return Color.blue.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        default: return .blue
        }
    }

    private var borderColor: Color {
        switch status {
        case .granted: return Color.green.opacity(0.3)
        case .denied: return Color.red.opacity(0.3)
        default: return Color.gray.opacity(0.2)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    OnboardingPermissionsView(onContinue: {}, onBack: {})
        .frame(width: 600, height: 600)
}
