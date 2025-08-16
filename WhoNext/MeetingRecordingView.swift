import SwiftUI
import AVFoundation

struct MeetingRecordingView: View {
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    @ObservedObject private var config = MeetingRecordingConfiguration.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerView
            
            // Status Card
            statusCard
            
            // Current Meeting Card (if recording)
            if let meeting = recordingEngine.currentMeeting {
                currentMeetingCard(meeting)
            }
            
            // Controls
            controlsSection
            
            // Quick Access to Settings
            quickSettingsLink
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting Recording")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Automatically detect and record meetings with transcription")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(recordingEngine.isMonitoring ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                
                Text(recordingEngine.isMonitoring ? "Monitoring" : "Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(20)
        }
    }
    
    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Recording Status", systemImage: "mic.circle.fill")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(recordingStateText)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(recordingStateColor.opacity(0.2))
                        .foregroundColor(recordingStateColor)
                        .cornerRadius(8)
                }
                
                Divider()
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Auto-Record")
                        Text(config.autoRecordingEnabled ? "Enabled" : "Disabled")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(config.autoRecordingEnabled ? .green : .gray)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(alignment: .leading) {
                        Text("Confidence Threshold")
                        Text("\(Int(config.confidenceThreshold * 100))%")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(alignment: .leading) {
                        Text("Detection Status")
                        if recordingEngine.isMonitoring {
                            Text("Active")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        } else {
                            Text("Inactive")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func currentMeetingCard(_ meeting: LiveMeeting) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Live Recording", systemImage: "record.circle")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Text(meeting.formattedDuration)
                        .font(.system(.body, design: .monospaced))
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(meeting.displayTitle)
                            .font(.body)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("Participants")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(meeting.participantCount)")
                            .font(.body)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("Transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(meeting.transcript.count) segments")
                            .font(.body)
                    }
                }
                
                if !meeting.transcript.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(meeting.transcript.last?.text ?? "")
                            .font(.caption)
                            .lineLimit(2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                }
                
                HStack {
                    Button(action: { recordingEngine.manualStopRecording() }) {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    
                    Spacer()
                    
                    Button(action: showLiveMeetingWindow) {
                        Label("Show Live Window", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }
    
    private var controlsSection: some View {
        GroupBox {
            VStack(spacing: 16) {
                HStack {
                    Label("Manual Controls", systemImage: "hand.raised.fill")
                        .font(.headline)
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    if !recordingEngine.isMonitoring {
                        Button(action: {
                            recordingEngine.startMonitoring()
                        }) {
                            Label("Start Monitoring", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    } else {
                        Button(action: {
                            recordingEngine.stopMonitoring()
                        }) {
                            Label("Stop Monitoring", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.orange)
                    }
                    
                    if !recordingEngine.isRecording {
                        Button(action: {
                            recordingEngine.manualStartRecording()
                        }) {
                            Label("Start Recording", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!recordingEngine.isMonitoring)
                    } else {
                        Button(action: {
                            recordingEngine.manualStopRecording()
                        }) {
                            Label("Stop Recording", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
            }
            .padding()
        }
    }
    
    private var quickSettingsLink: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Label("Quick Settings", systemImage: "gearshape.fill")
                        .font(.headline)
                    
                    Spacer()
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Auto-Recording:")
                            Text(config.autoRecordingEnabled ? "Enabled" : "Disabled")
                                .foregroundColor(config.autoRecordingEnabled ? .green : .gray)
                                .fontWeight(.medium)
                        }
                        
                        HStack {
                            Text("Confidence:")
                            Text("\(Int(config.confidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Storage:")
                            Text("\(config.storageRetentionDays) days retention")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: openSettings) {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
    
    private var recordingStateText: String {
        switch recordingEngine.recordingState {
        case .idle:
            return "Idle"
        case .monitoring:
            return "Monitoring"
        case .conversationDetected:
            return "Conversation Detected"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private var recordingStateColor: Color {
        switch recordingEngine.recordingState {
        case .idle:
            return .gray
        case .monitoring:
            return .blue
        case .conversationDetected:
            return .orange
        case .recording:
            return .red
        case .processing:
            return .purple
        case .error:
            return .red
        }
    }
    
    private func showLiveMeetingWindow() {
        if let meeting = recordingEngine.currentMeeting {
            LiveMeetingWindowManager.shared.showWindow(for: meeting)
        }
    }
    
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}


#Preview {
    MeetingRecordingView()
        .frame(width: 800, height: 600)
}