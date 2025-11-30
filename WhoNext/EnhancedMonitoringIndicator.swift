import SwiftUI
import Combine

struct EnhancedMonitoringIndicator: View {
    @ObservedObject var recordingEngine = MeetingRecordingEngine.shared
    @State private var isExpanded = false
    @State private var pulseAnimation = false
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.2, count: 12)
    @State private var timer: Timer?
    
    private var statusColor: Color {
        if recordingEngine.isRecording {
            return .red
        } else if recordingEngine.isMonitoring {
            return .primaryGreen
        } else {
            return .gray
        }
    }
    
    private var statusText: String {
        if recordingEngine.isRecording {
            if let meeting = recordingEngine.currentMeeting {
                return "Recording: \(meeting.calendarTitle ?? "Meeting")"
            }
            return "Recording..."
        } else if recordingEngine.isMonitoring {
            // Check if conversation is being detected
            // Simplified - just show monitoring status
            return "Auto-Monitoring Active"
        } else {
            return "Monitoring Inactive"
        }
    }
    
    private var timeInfo: String? {
        if recordingEngine.isRecording, let meeting = recordingEngine.currentMeeting {
            let duration = meeting.duration
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator with Glow
            ZStack {
                // Glow effect
                if recordingEngine.isMonitoring || recordingEngine.isRecording {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: pulseAnimation ? 25 : 15)
                        .blur(radius: 3)
                        .animation(
                            .easeInOut(duration: 2)
                            .repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                }
                
                // Main indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
            }
            .frame(width: 30, height: 30)
            
            // Status Text and Info
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let time = timeInfo {
                    Text(time)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            // Audio Waveform when detecting
            if recordingEngine.isRecording {
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(statusColor.opacity(0.8))
                            .frame(width: 2, height: audioLevels[index] * 16)
                            .animation(.easeInOut(duration: 0.1), value: audioLevels[index])
                    }
                }
                .frame(width: 40, height: 20)
                .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
            
            // Expand/Collapse Button
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(statusColor.opacity(0.2), lineWidth: 1)
                )
        )
        .hoverEffect(scale: 1.01)
        .onAppear {
            pulseAnimation = true
            startWaveformAnimation()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .overlay(alignment: .top) {
            if isExpanded {
                expandedDetails
                    .offset(y: 50)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Meeting Info
            if let meeting = recordingEngine.currentMeeting {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Current Meeting", systemImage: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text(meeting.calendarTitle ?? "Untitled Meeting")
                        .font(.system(size: 12))
                    
                    // Speaker Detection
                    if meeting.detectedSpeakerCount > 0 {
                        HStack(spacing: 8) {
                            StatPill(
                                icon: "person.wave.2",
                                value: "\(meeting.detectedSpeakerCount) speakers",
                                color: .primaryBlue
                            )
                            
                            // Show meeting type badge based on speaker count
                            if meeting.detectedSpeakerCount == 2 {
                                MeetingTypeBadge(type: .oneOnOne)
                            } else if meeting.detectedSpeakerCount > 2 {
                                MeetingTypeBadge(type: .group)
                            }
                        }
                    }
                }
                
                Divider()
            }
            
            // Audio Detection Status
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(recordingEngine.isMonitoring ? .green : .gray)
                    Text("Microphone")
                        .font(.system(size: 11))
                    Spacer()
                    Text(recordingEngine.isMonitoring ? "Monitoring" : "Inactive")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(recordingEngine.isRecording ? .green : .gray)
                    Text("System Audio")
                        .font(.system(size: 11))
                    Spacer()
                    Text(recordingEngine.isRecording ? "Capturing" : "Ready")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Two-way conversation detection removed - status property doesn't exist
            }
            
            // Quick Actions
            if !recordingEngine.isRecording {
                Divider()
                
                HStack(spacing: 8) {
                    Button(action: { recordingEngine.manualStartRecording() }) {
                        Label("Start Recording", systemImage: "record.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: { recordingEngine.stopMonitoring() }) {
                        Label("Stop Monitoring", systemImage: "stop.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Divider()
                
                Button(action: { recordingEngine.manualStopRecording() }) {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .frame(width: 280)
    }
    
    private func startWaveformAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if recordingEngine.isRecording {
                // Simulate audio levels
                for i in 0..<audioLevels.count {
                    audioLevels[i] = CGFloat.random(in: 0.3...1.0)
                }
            } else {
                // Flat line when no audio
                for i in 0..<audioLevels.count {
                    audioLevels[i] = 0.2
                }
            }
        }
    }
}

// MARK: - Preview
struct EnhancedMonitoringIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            EnhancedMonitoringIndicator()
                .frame(width: 400)
            
            EnhancedMonitoringIndicator()
                .frame(width: 400)
        }
        .padding()
    }
}