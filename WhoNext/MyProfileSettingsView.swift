import SwiftUI
import UniformTypeIdentifiers

/// Settings view for the user's profile including photo, name, and voice training
struct MyProfileSettingsView: View {
    @ObservedObject private var userProfile = UserProfile.shared
    @State private var showingVoiceTraining = false
    @State private var showingPhotoPicker = false
    @State private var isHoveringPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Profile Header with Photo
            profileHeaderSection

            Divider()

            // Profile Details
            profileDetailsSection

            Divider()

            // Voice Recognition
            voiceRecognitionSection
        }
        .sheet(isPresented: $showingVoiceTraining) {
            VoiceTrainingView()
        }
    }

    // MARK: - Profile Header Section

    private var profileHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Profile")
                .font(.headline)

            HStack(spacing: 20) {
                // Avatar/Photo
                avatarView

                // Quick info
                VStack(alignment: .leading, spacing: 4) {
                    if !userProfile.name.isEmpty {
                        Text(userProfile.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                    } else {
                        Text("Set your name")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    if !userProfile.jobTitle.isEmpty || !userProfile.organization.isEmpty {
                        Text([userProfile.jobTitle, userProfile.organization]
                            .filter { !$0.isEmpty }
                            .joined(separator: " at "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Voice status badge
                    HStack(spacing: 6) {
                        if userProfile.hasVoiceProfile {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundColor(.green)
                            Text("Voice trained")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "waveform.circle")
                                .foregroundColor(.orange)
                            Text("Voice not trained")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Avatar View

    private var avatarView: some View {
        ZStack {
            // Photo or initials
            if let photoData = userProfile.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text(userProfile.initials)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            // Hover overlay for changing photo
            if isHoveringPhoto {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 80, height: 80)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20))
                            Text("Change")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                    )
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringPhoto = hovering
            }
        }
        .onTapGesture {
            selectPhoto()
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handlePhotoDrop(providers: providers)
            return true
        }
        .contextMenu {
            if userProfile.photo != nil {
                Button(role: .destructive) {
                    userProfile.photo = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }

            Button {
                selectPhoto()
            } label: {
                Label("Choose Photo...", systemImage: "photo")
            }
        }
        .help("Click to change photo, or drag and drop an image")
    }

    // MARK: - Profile Details Section

    private var profileDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Information")
                .font(.headline)

            Text("This information helps identify you in meetings and personalizes your experience.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Name:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Your Name", text: .init(
                        get: { userProfile.name },
                        set: { userProfile.name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                }

                HStack {
                    Text("Email:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("your.email@example.com", text: .init(
                        get: { userProfile.email },
                        set: { userProfile.email = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                }

                HStack {
                    Text("Job Title:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Your Job Title", text: .init(
                        get: { userProfile.jobTitle },
                        set: { userProfile.jobTitle = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                }

                HStack {
                    Text("Organization:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Your Organization", text: .init(
                        get: { userProfile.organization },
                        set: { userProfile.organization = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Voice Recognition Section

    private var voiceRecognitionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Recognition")
                .font(.headline)

            Text("Train the app to recognize your voice for automatic speaker identification in meetings.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                // Voice Profile Status
                HStack {
                    Text("Status:")
                        .frame(width: 120, alignment: .trailing)

                    if userProfile.hasVoiceProfile {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(userProfile.voiceProfileStatus)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("Not trained")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Training Instructions
                if !userProfile.hasVoiceProfile || userProfile.voiceConfidence < 0.9 {
                    HStack(alignment: .top) {
                        Spacer()
                            .frame(width: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How to train your voice:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Record 3-5 voice samples (at least 5 seconds each)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Speak naturally as you would in a meeting")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Use different sentences for better accuracy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: 350, alignment: .leading)
                    }
                }

                // Sample Count and Progress
                HStack(alignment: .top) {
                    Text("Samples:")
                        .frame(width: 120, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        if userProfile.voiceSampleCount > 0 {
                            Text("\(userProfile.voiceSampleCount) sample\(userProfile.voiceSampleCount == 1 ? "" : "s") collected")
                                .font(.caption)

                            if let lastUpdate = userProfile.lastVoiceUpdate {
                                Text("Last updated: \(lastUpdate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No samples yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Progress bar
                        if userProfile.voiceSampleCount < 5 {
                            ProgressView(value: Double(userProfile.voiceSampleCount), total: 5.0)
                                .frame(width: 200)
                            Text("\(max(0, 5 - userProfile.voiceSampleCount)) more sample\(max(0, 5 - userProfile.voiceSampleCount) == 1 ? "" : "s") recommended")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Action Buttons
                HStack {
                    Spacer()
                        .frame(width: 120)

                    HStack(spacing: 12) {
                        Button {
                            showingVoiceTraining = true
                        } label: {
                            Label(userProfile.hasVoiceProfile ? "Retrain Voice" : "Train Voice",
                                  systemImage: "waveform.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        if userProfile.hasVoiceProfile {
                            Button(role: .destructive) {
                                userProfile.clearVoiceProfile()
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Photo Handling

    private func selectPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a profile photo"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            loadPhoto(from: url)
        }
    }

    private func loadPhoto(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }

        // Resize to reasonable size for storage
        let resized = resizeImage(image, maxSize: 400)

        // Convert to JPEG data
        if let tiffData = resized.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            userProfile.photo = jpegData
        }
    }

    private func handlePhotoDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let nsImage = image as? NSImage else { return }

                DispatchQueue.main.async {
                    let resized = resizeImage(nsImage, maxSize: 400)

                    if let tiffData = resized.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        userProfile.photo = jpegData
                    }
                }
            }
        }
    }

    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let originalSize = image.size

        guard originalSize.width > maxSize || originalSize.height > maxSize else {
            return image
        }

        let ratio = min(maxSize / originalSize.width, maxSize / originalSize.height)
        let newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }
}

// MARK: - UserProfile Extension for Initials

extension UserProfile {
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "ME"
    }
}

#Preview {
    MyProfileSettingsView()
        .frame(width: 600, height: 700)
        .padding()
}
