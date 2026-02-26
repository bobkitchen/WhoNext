import SwiftUI

/// Settings view for Obsidian vault sync, embedded in DataSyncSettingsView.
struct ObsidianSyncSettingsView: View {
    @ObservedObject private var syncService = ObsidianSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Status Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Obsidian Vault Sync")
                    .font(.headline)

                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(syncService.isEnabled ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(syncService.isEnabled ? "Connected" : "Not Configured")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let path = syncService.vaultPath {
                                Text(path.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Select your Obsidian vault to start syncing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(syncService.isEnabled ? "Change Vault" : "Select Vault") {
                        syncService.selectVaultFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Sync Controls (only when enabled)
            if syncService.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync Status")
                        .font(.headline)

                    if let lastSync = syncService.lastSyncDate {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = syncService.lastError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if syncService.syncInProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("Syncing...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Sync Now") {
                            Task {
                                await syncService.fullSync()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(syncService.syncInProgress)

                        Button("Disable Sync") {
                            syncService.disable()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Label("Meeting notes sync automatically when saved", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("Full sync runs on app launch", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("Files are written to WhoNext/Meetings/ and WhoNext/People/", systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
}
