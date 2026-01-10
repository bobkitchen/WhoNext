import SwiftUI
import AppKit

/// Onboarding step for user profile setup
/// Captures name, email, job title, organization, and optional photo
struct OnboardingProfileView: View {
    @ObservedObject private var userProfile = UserProfile.shared

    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var jobTitle: String = ""
    @State private var organization: String = ""
    @State private var selectedImage: NSImage? = nil
    @State private var showingImagePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue.gradient)

                        Text("Set Up Your Profile")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("This helps identify you in meeting transcripts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Profile form
                    VStack(spacing: 20) {
                        // Photo picker
                        HStack {
                            Button(action: { showingImagePicker = true }) {
                                if let image = selectedImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                } else if let photoData = userProfile.photo, let nsImage = NSImage(data: photoData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 80, height: 80)
                                        VStack(spacing: 4) {
                                            Image(systemName: "camera.fill")
                                                .font(.title2)
                                            Text("Add Photo")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Profile Photo")
                                    .font(.headline)
                                Text("Optional - helps identify you visually")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 40)

                        // Form fields
                        VStack(spacing: 16) {
                            ProfileTextField(
                                label: "Name",
                                placeholder: "Your full name",
                                text: $name,
                                icon: "person.fill",
                                isRequired: true
                            )

                            ProfileTextField(
                                label: "Email",
                                placeholder: "your@email.com",
                                text: $email,
                                icon: "envelope.fill",
                                isRequired: false
                            )

                            ProfileTextField(
                                label: "Job Title",
                                placeholder: "e.g., Product Manager",
                                text: $jobTitle,
                                icon: "briefcase.fill",
                                isRequired: false
                            )

                            ProfileTextField(
                                label: "Organization",
                                placeholder: "e.g., Acme Corp",
                                text: $organization,
                                icon: "building.2.fill",
                                isRequired: false
                            )
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 20)
            }

            // Navigation buttons - pinned at bottom
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

                Button(action: saveAndContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(canContinue ? Color.blue : Color.gray)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            // Pre-populate from existing profile or system
            if name.isEmpty {
                name = userProfile.name.isEmpty ? NSFullUserName() : userProfile.name
            }
            if email.isEmpty {
                email = userProfile.email
            }
            if jobTitle.isEmpty {
                jobTitle = userProfile.jobTitle
            }
            if organization.isEmpty {
                organization = userProfile.organization
            }
        }
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let image = NSImage(contentsOf: url) {
                        selectedImage = image
                    }
                }
            }
        }
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveAndContinue() {
        // Save to UserProfile
        userProfile.name = name.trimmingCharacters(in: .whitespaces)
        userProfile.email = email.trimmingCharacters(in: .whitespaces)
        userProfile.jobTitle = jobTitle.trimmingCharacters(in: .whitespaces)
        userProfile.organization = organization.trimmingCharacters(in: .whitespaces)

        if let image = selectedImage {
            userProfile.photo = image.tiffRepresentation
        }

        onContinue()
    }
}

// MARK: - Profile Text Field

struct ProfileTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    let isRequired: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

#Preview {
    OnboardingProfileView(onContinue: {}, onBack: {})
        .frame(width: 600, height: 600)
}
