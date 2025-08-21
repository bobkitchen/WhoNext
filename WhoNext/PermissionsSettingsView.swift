import SwiftUI
import AVFoundation

struct PermissionsSettingsView: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    
    @State private var microphoneStatus: Bool = false
    @State private var screenRecordingStatus: Bool = false
    @State private var isCheckingPermissions: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permissions")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    // Microphone Permission
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(microphoneStatus ? .green : .red)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Microphone Access")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Required for recording meetings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if microphoneStatus {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Grant Access") {
                                openMicrophoneSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    Divider()
                    
                    // Screen Recording Permission
                    HStack {
                        Image(systemName: "rectangle.dashed.badge.record")
                            .foregroundColor(screenRecordingStatus ? .green : .orange)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screen Recording")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Optional: Enables system audio capture from meeting apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if screenRecordingStatus {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Grant Access") {
                                openScreenRecordingSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
            }
            
            // Status explanation
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Permission Status", systemImage: "info.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !microphoneStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Microphone access is required for WhoNext to function. Please grant permission in System Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !screenRecordingStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Screen recording is optional but recommended. Without it, only your microphone audio will be recorded, not the audio from meeting participants.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if microphoneStatus && screenRecordingStatus {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("All permissions granted. WhoNext can capture both your voice and system audio from meeting apps.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
            }
            
            // Reset prompts button
            HStack {
                Button("Reset Permission Prompts") {
                    recordingEngine.resetPermissionPrompts()
                }
                .buttonStyle(.link)
                .font(.caption)
                
                Spacer()
                
                Button("Refresh Status") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingPermissions)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        isCheckingPermissions = true
        
        Task {
            let status = await recordingEngine.checkPermissionStatus()
            await MainActor.run {
                microphoneStatus = status.microphone
                screenRecordingStatus = status.screenRecording
                isCheckingPermissions = false
            }
        }
    }
    
    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsSettingsView()
            .frame(width: 500)
            .padding()
    }
}