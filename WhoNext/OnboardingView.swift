import SwiftUI

/// Main onboarding container that guides new users through setup
/// Steps: Welcome → Profile → Permissions → Voice Training → Complete
struct OnboardingView: View {
    @ObservedObject private var userProfile = UserProfile.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .welcome
    @State private var animateTransition = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case profile = 1
        case permissions = 2
        case voiceTraining = 3
        case complete = 4

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .profile: return "Profile"
            case .permissions: return "Permissions"
            case .voiceTraining: return "Voice Training"
            case .complete: return "Complete"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator (except welcome and complete)
            if currentStep != .welcome && currentStep != .complete {
                OnboardingProgressView(currentStep: currentStep)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
            }

            // Step content
            SwiftUI.Group {
                switch currentStep {
                case .welcome:
                    OnboardingWelcomeView(onContinue: { goToNextStep() })
                case .profile:
                    OnboardingProfileView(onContinue: { goToNextStep() }, onBack: { goToPreviousStep() })
                case .permissions:
                    OnboardingPermissionsView(onContinue: { goToNextStep() }, onBack: { goToPreviousStep() })
                case .voiceTraining:
                    OnboardingVoiceView(onContinue: { goToNextStep() }, onSkip: { goToNextStep() }, onBack: { goToPreviousStep() })
                case .complete:
                    OnboardingCompleteView(onFinish: { completeOnboarding() })
                }
            }
            .transition(AnyTransition.asymmetric(
                insertion: AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity),
                removal: AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity)
            ))
            .animation(Animation.easeInOut(duration: 0.3), value: currentStep)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func goToNextStep() {
        withAnimation {
            if let nextIndex = OnboardingStep.allCases.firstIndex(where: { $0.rawValue == currentStep.rawValue + 1 }) {
                currentStep = OnboardingStep.allCases[nextIndex]
            }
        }
    }

    private func goToPreviousStep() {
        withAnimation {
            if let prevIndex = OnboardingStep.allCases.firstIndex(where: { $0.rawValue == currentStep.rawValue - 1 }) {
                currentStep = OnboardingStep.allCases[prevIndex]
            }
        }
    }

    private func completeOnboarding() {
        userProfile.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressView: View {
    let currentStep: OnboardingView.OnboardingStep

    private let steps: [OnboardingView.OnboardingStep] = [.profile, .permissions, .voiceTraining]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(steps, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 10, height: 10)

                    Text(step.title)
                        .font(.caption)
                        .foregroundColor(step == currentStep ? .primary : .secondary)
                }

                if step != steps.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private func stepColor(for step: OnboardingView.OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Welcome Step

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                Text("Welcome to WhoNext")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your personal relationship intelligence platform")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Feature highlights
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "waveform", title: "Automatic Meeting Recording", description: "Capture conversations with smart detection")
                FeatureRow(icon: "text.quote", title: "Real-time Transcription", description: "Get accurate transcripts as you speak")
                FeatureRow(icon: "person.crop.circle.badge.checkmark", title: "Speaker Identification", description: "Know who said what in every meeting")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Relationship Insights", description: "Track health and engagement over time")
            }
            .padding(.horizontal, 60)

            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
