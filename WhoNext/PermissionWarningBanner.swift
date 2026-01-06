//
//  PermissionWarningBanner.swift
//  WhoNext
//
//  Created on 1/1/26.
//

import SwiftUI
import AppKit

/// Warning banner shown when system audio permission is not granted
struct PermissionWarningBanner: View {
    @ObservedObject var audioCapture: SystemAudioCapture
    @State private var isDismissed = false

    var body: some View {
        if shouldShow {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording Microphone Only")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Grant screen recording permission to capture meeting audio from Zoom, Teams, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: openSystemPreferences) {
                    Text("Open Settings")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { isDismissed = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var shouldShow: Bool {
        !isDismissed && audioCapture.captureMode == .microphoneOnly
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Simpler inline warning for compact views
struct CompactPermissionWarning: View {
    @ObservedObject var audioCapture: SystemAudioCapture

    var body: some View {
        if audioCapture.captureMode == .microphoneOnly {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("Microphone only")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Fix") {
                    openSystemPreferences()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
