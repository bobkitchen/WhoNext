import SwiftUI

/// Dedicated voice training view with guided prompts
/// Shows a series of phrases for the user to read while recording
struct VoiceTrainingView: View {
    @ObservedObject private var userProfile = UserProfile.shared
    @StateObject private var recorder = VoiceTrainingRecorder()
    @Environment(\.dismiss) private var dismiss

    @State private var currentPromptIndex = 0
    @State private var completedPrompts: Set<Int> = []
    @State private var showingCompletion = false

    // Training prompts - designed to cover various phonemes and speech patterns
    private let trainingPrompts = [
        "Hey, this is my voice. I'm training the app to recognize me in meetings.",
        "The quick brown fox jumps over the lazy dog while speaking naturally.",
        "I often attend meetings with colleagues to discuss important projects and decisions.",
        "My name is on the calendar for this meeting, and I'd like to be identified automatically.",
        "Can you hear me clearly? I'm speaking at my normal conversation volume and pace."
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Voice Training")
                        .font(.headline)

                    Spacer()

                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 28, height: 28)
                }
                .padding(.horizontal)
                .padding(.top)

                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<trainingPrompts.count, id: \.self) { index in
                        Circle()
                            .fill(completedPrompts.contains(index) ? Color.green :
                                  index == currentPromptIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if !showingCompletion {
                // Training content
                VStack(spacing: 32) {
                    Spacer()

                    // Instruction
                    VStack(spacing: 12) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(recorder.isRecording ? .red : .blue)
                            .symbolEffect(.pulse, isActive: recorder.isRecording)

                        Text("Read this phrase aloud:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    // Current prompt to read
                    Text(trainingPrompts[currentPromptIndex])
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                        )

                    // Recording status
                    if recorder.isRecording {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .foregroundColor(.red)
                                    .symbolEffect(.variableColor.iterative.reversing)

                                Text("Recording: \(String(format: "%.1f", recorder.recordingDuration))s")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }

                            if recorder.recordingDuration < 5.0 {
                                Text("Keep reading - minimum 5 seconds")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("You can stop now or keep reading")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    } else if recorder.recordingState == .processing {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Processing voice sample...")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    } else if case .completed = recorder.recordingState {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Sample saved successfully!")
                                .font(.callout)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    } else if case .error(let message) = recorder.recordingState {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.callout)
                            }

                            if let error = recorder.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 16) {
                        if recorder.isRecording {
                            Button {
                                Task {
                                    try? await recorder.stopRecording()
                                    completedPrompts.insert(currentPromptIndex)

                                    // Move to next prompt or show completion
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if currentPromptIndex < trainingPrompts.count - 1 {
                                            currentPromptIndex += 1
                                            recorder.recordingState = .idle
                                        } else {
                                            showingCompletion = true
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "stop.circle.fill")
                                    Text("Stop Recording")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)

                            Button {
                                Task {
                                    await recorder.cancelRecording()
                                }
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else {
                            Button {
                                Task {
                                    try? await recorder.startRecording()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "mic.circle.fill")
                                    Text("Start Recording")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(recorder.recordingState == .processing)

                            if currentPromptIndex > 0 {
                                Button {
                                    currentPromptIndex -= 1
                                    recorder.recordingState = .idle
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.left")
                                        Text("Previous")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }

                            if completedPrompts.contains(currentPromptIndex) && currentPromptIndex < trainingPrompts.count - 1 {
                                Button {
                                    currentPromptIndex += 1
                                    recorder.recordingState = .idle
                                } label: {
                                    HStack {
                                        Text("Next")
                                        Image(systemName: "arrow.right")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                }
            } else {
                // Completion screen
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)

                    Text("Training Complete!")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Your voice profile has been created with \(userProfile.voiceSampleCount) samples")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Voice Recognition: \(userProfile.voiceProfileStatus)")
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(.blue)
                            Text("You'll now be identified automatically in meetings")
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.up")
                                .foregroundColor(.cyan)
                            Text("Syncing voice profile to iCloud...")
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                            Text("Your profile improves with each meeting")
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .onAppear {
                        // Force sync voice profile to CloudKit after training completion
                        userProfile.forceSyncToCloud()
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(width: 600, height: 500)
    }
}

#Preview {
    VoiceTrainingView()
}
