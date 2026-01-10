import SwiftUI

/// Onboarding step for voice training
/// Guides users through recording voice samples for speaker identification
struct OnboardingVoiceView: View {
    @ObservedObject private var userProfile = UserProfile.shared
    @StateObject private var recorder = VoiceTrainingRecorder()

    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var currentPromptIndex = 0
    @State private var completedPrompts: Set<Int> = []

    // Shorter prompts for onboarding (full training available later)
    private let trainingPrompts = [
        "Hey, this is my voice. I'm training the app to recognize me.",
        "I often attend meetings with colleagues to discuss projects.",
        "Can you hear me clearly? I'm speaking at my normal pace."
    ]

    private let minimumSamplesRequired = 2

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue.gradient)

                Text("Train Your Voice")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Help WhoNext identify you as a speaker in meetings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Progress dots
            HStack(spacing: 10) {
                ForEach(0..<trainingPrompts.count, id: \.self) { index in
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 12, height: 12)
                        .overlay(
                            completedPrompts.contains(index) ?
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                            : nil
                        )
                }
            }

            // Training area
            VStack(spacing: 20) {
                // Current prompt
                VStack(spacing: 12) {
                    Text("Read this aloud:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(trainingPrompts[currentPromptIndex])
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .frame(maxWidth: 450)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                        )
                }

                // Recording button
                VStack(spacing: 12) {
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(recorder.isRecording ? Color.red : Color.blue)
                                .frame(width: 72, height: 72)
                                .shadow(color: recorder.isRecording ? .red.opacity(0.4) : .blue.opacity(0.4), radius: 10)

                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)

                    Text(recorder.isRecording ? "Recording... Tap to stop" : "Tap to record")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Recording indicator
                    if recorder.isRecording {
                        HStack(spacing: 4) {
                            ForEach(0..<5) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.red)
                                    .frame(width: 4, height: CGFloat.random(in: 10...30))
                                    .animation(.easeInOut(duration: 0.2).repeatForever(), value: recorder.isRecording)
                            }
                        }
                        .frame(height: 30)
                    }
                }
            }
            .padding(.horizontal, 40)

            // Status
            if completedPrompts.count > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(completedPrompts.count) of \(trainingPrompts.count) samples recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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

                // Skip button (only if not enough samples)
                if completedPrompts.count < minimumSamplesRequired {
                    Button(action: onSkip) {
                        Text("Skip for Now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onContinue) {
                    Text(completedPrompts.count >= minimumSamplesRequired ? "Continue" : "Need \(minimumSamplesRequired) samples")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(completedPrompts.count >= minimumSamplesRequired ? Color.blue : Color.gray)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(completedPrompts.count < minimumSamplesRequired)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .onAppear {
            // Load existing progress
            if userProfile.voiceSampleCount > 0 {
                // User already has voice samples - mark some as complete
                let existingSamples = min(userProfile.voiceSampleCount, trainingPrompts.count)
                for i in 0..<existingSamples {
                    completedPrompts.insert(i)
                }
                // Move to next incomplete prompt
                currentPromptIndex = min(existingSamples, trainingPrompts.count - 1)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if completedPrompts.contains(index) {
            return .green
        } else if index == currentPromptIndex {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }

    private func toggleRecording() {
        Task {
            if recorder.isRecording {
                // Stop recording and save
                do {
                    try await recorder.stopRecording()
                    // VoiceTrainingRecorder saves to UserProfile automatically
                    completedPrompts.insert(currentPromptIndex)

                    // Move to next prompt
                    if currentPromptIndex < trainingPrompts.count - 1 {
                        currentPromptIndex += 1
                    }
                } catch {
                    print("Failed to stop recording: \(error)")
                }
            } else {
                // Start recording
                do {
                    try await recorder.startRecording()
                } catch {
                    print("Failed to start recording: \(error)")
                }
            }
        }
    }
}

// MARK: - Completion View

struct OnboardingCompleteView: View {
    let onFinish: () -> Void

    @ObservedObject private var userProfile = UserProfile.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success animation
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                }

                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("WhoNext is ready to help you manage your relationships")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Summary of what was set up
            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(icon: "person.fill", text: "Profile: \(userProfile.name)", isComplete: true)
                SummaryRow(icon: "mic.fill", text: "Microphone access granted", isComplete: true)
                SummaryRow(
                    icon: "waveform",
                    text: userProfile.voiceSampleCount > 0 ? "Voice trained (\(userProfile.voiceSampleCount) samples)" : "Voice training skipped",
                    isComplete: userProfile.voiceSampleCount > 0
                )
            }
            .padding(.horizontal, 60)

            Spacer()

            // Get started button
            Button(action: onFinish) {
                HStack {
                    Text("Start Using WhoNext")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
}

struct SummaryRow: View {
    let icon: String
    let text: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isComplete ? .green : .gray)

            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    OnboardingVoiceView(onContinue: {}, onSkip: {}, onBack: {})
        .frame(width: 600, height: 600)
}
