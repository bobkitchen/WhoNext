import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct AddPersonWindowView: View {
    @ObservedObject var person: Person
    var isNewPerson: Bool = true
    @Environment(\.managedObjectContext) private var viewContext

    @State private var editingName: String = ""
    @State private var editingRole: String = ""
    @State private var editingTimezone: String = ""
    @State private var showingTimezoneDropdown: Bool = false
    @State private var editingNotes: String = ""
    @State private var isDirectReport: Bool = false
    @State private var editingPhotoData: Data? = nil
    @State private var editingPhotoImage: NSImage? = nil
    @State private var showingPhotoPicker = false
    @State private var showingLinkedInSearch = false

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Photo Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Photo")
                            .font(.system(size: 16, weight: .semibold))

                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(nsColor: .systemGray).opacity(0.15))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                            .opacity(canPasteImage() ? 1 : 0)
                                    )

                                if let image = editingPhotoImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .clipShape(Circle())
                                        .frame(width: 80, height: 80)
                                } else {
                                    Text(initials(from: editingName))
                                        .font(.system(size: 32, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onTapGesture {
                                pasteImageFromClipboard()
                            }
                            .help(canPasteImage() ? "Click to paste image from clipboard" : "Copy an image to clipboard first")

                            VStack(alignment: .leading, spacing: 8) {
                                Button("Choose Photo") {
                                    showingPhotoPicker = true
                                }
                                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))

                                Button("Paste from Clipboard") {
                                    pasteImageFromClipboard()
                                }
                                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                                .disabled(!canPasteImage())

                                if editingPhotoImage != nil {
                                    Button("Remove Photo") {
                                        editingPhotoData = nil
                                        editingPhotoImage = nil
                                    }
                                    .buttonStyle(LiquidGlassButtonStyle(variant: .destructive, size: .small))
                                }
                            }
                        }
                    }

                    // Basic Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Basic Information")
                            .font(.system(size: 16, weight: .semibold))

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("Enter name", text: $editingName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Role")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("Enter role", text: $editingRole)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Timezone")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 0) {
                                    TextField("Type to search timezone", text: $editingTimezone)
                                        .textFieldStyle(.roundedBorder)
                                        .onChange(of: editingTimezone) { _, _ in
                                            showingTimezoneDropdown = !editingTimezone.isEmpty && !filteredTimezones.isEmpty
                                        }

                                    if showingTimezoneDropdown && !filteredTimezones.isEmpty {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 2) {
                                                ForEach(filteredTimezones.prefix(8), id: \.self) { timezone in
                                                    Button(action: {
                                                        editingTimezone = timezone
                                                        showingTimezoneDropdown = false
                                                    }) {
                                                        Text(timezone)
                                                            .font(.system(size: 13))
                                                            .foregroundColor(.primary)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                    .background(Color.clear)
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 120)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                        .padding(.top, 2)
                                    }
                                }
                            }

                            Toggle("Direct Report", isOn: $isDirectReport)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }

                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Profile Notes")
                                .font(.system(size: 16, weight: .semibold))

                            Spacer()

                            Button(action: {
                                showingLinkedInSearch = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                    Text("Search LinkedIn")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Always show editable TextEditor
                        TextEditor(text: $editingNotes)
                            .font(.system(size: 14))
                            .frame(minHeight: 200)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )

                        // Helper text
                        Text("💡 Tip: Use markdown formatting like **bold** and ## Headings. Click 'Search LinkedIn' to import profile data.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }

            // Action Buttons
            HStack {
                Button("Cancel") {
                    onCancel?()
                    closeWindow()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))

                Spacer()

                Button("Save") {
                    saveChanges()
                    onSave?()
                    closeWindow()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showingPhotoPicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    editingPhotoData = data
                    editingPhotoImage = image
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showingLinkedInSearch) {
            LinkedInSearchWindow(
                personName: editingName,
                personRole: editingRole,
                onDataExtracted: { profileData in
                    populateFromLinkedInData(profileData)
                    showingLinkedInSearch = false
                },
                onClose: {
                    showingLinkedInSearch = false
                }
            )
            .frame(minWidth: 900, minHeight: 700)
        }
        .onAppear {
            loadPersonData()
        }
    }

    var filteredTimezones: [String] {
        if editingTimezone.isEmpty {
            return TimeZone.knownTimeZoneIdentifiers.sorted()
        } else {
            return TimeZone.knownTimeZoneIdentifiers.sorted().filter { $0.lowercased().contains(editingTimezone.lowercased()) }
        }
    }

    private func loadPersonData() {
        editingName = person.name ?? ""
        editingRole = person.role ?? ""
        editingTimezone = person.timezone ?? ""
        editingNotes = person.notes ?? ""
        isDirectReport = person.isDirectReport

        if let data = person.photo, let image = NSImage(data: data) {
            editingPhotoData = data
            editingPhotoImage = image
        } else {
            editingPhotoData = nil
            editingPhotoImage = nil
        }
    }

    private func cleanMarkdown(_ text: String) -> String {
        // Remove existing markdown formatting (asterisks, etc.)
        return text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func populateFromLinkedInData(_ data: LinkedInProfileData) {
        print("✅ [AddPersonWindowView] LinkedIn data extracted!")
        print("   LinkedIn headline: '\(data.headline)'")

        // Format LinkedIn data into notes (similar to PersonDetailView)
        var formatted = ""

        // Header
        if !data.name.isEmpty {
            formatted += "**\(cleanMarkdown(data.name))**\n"
        }
        if !data.headline.isEmpty {
            formatted += "\(cleanMarkdown(data.headline))\n"
        }
        if !data.location.isEmpty {
            formatted += "📍 \(cleanMarkdown(data.location))\n"
        }
        formatted += "\n"

        // About section
        if !data.about.isEmpty {
            formatted += "## About\n"
            formatted += "\(cleanMarkdown(data.about))\n\n"
        }

        // Experience section
        if !data.experience.isEmpty {
            formatted += "## Experience\n"
            for exp in data.experience {
                formatted += "• **\(cleanMarkdown(exp.title))**"
                if !exp.company.isEmpty {
                    formatted += " at \(cleanMarkdown(exp.company))"
                }
                if !exp.duration.isEmpty {
                    formatted += " — \(cleanMarkdown(exp.duration))"
                }
                formatted += "\n"
            }
            formatted += "\n"
        }

        // Education section
        if !data.education.isEmpty {
            formatted += "## Education\n"
            for edu in data.education {
                formatted += "• \(cleanMarkdown(edu.school))"
                if !edu.degree.isEmpty {
                    formatted += " — \(cleanMarkdown(edu.degree))"
                }
                if !edu.field.isEmpty {
                    formatted += " in \(cleanMarkdown(edu.field))"
                }
                formatted += "\n"
            }
            formatted += "\n"
        }

        // Skills section
        if !data.skills.isEmpty {
            formatted += "## Skills\n"
            formatted += data.skills.prefix(15).map { "• \(cleanMarkdown($0))" }.joined(separator: "\n")
            formatted += "\n"
        }

        // Update editing fields
        editingNotes = formatted.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only populate empty fields - never overwrite existing data
        if !data.name.isEmpty && editingName.isEmpty {
            editingName = data.name
            print("📝 Updated name: \(data.name)")
        }

        if !data.location.isEmpty && editingTimezone.isEmpty {
            editingTimezone = data.location
            print("📝 Updated location: \(data.location)")
        }

        // Role is NOT auto-populated - LinkedIn headline is in notes
        print("ℹ️  LinkedIn headline '\(data.headline)' saved to notes only (not applied to role field)")

        // Download and set photo if available
        if !data.photo.isEmpty, let photoURL = URL(string: data.photo) {
            print("📸 Downloading photo from: \(data.photo)")

            Task {
                do {
                    let (imageData, _) = try await URLSession.shared.data(from: photoURL)

                    await MainActor.run {
                        self.editingPhotoData = imageData
                        self.editingPhotoImage = NSImage(data: imageData)
                        print("✅ Photo downloaded and set successfully")
                    }
                } catch {
                    print("❌ Failed to download photo: \(error)")
                }
            }
        }
    }

    private func saveChanges() {
        person.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        person.role = editingRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingRole.trimmingCharacters(in: .whitespacesAndNewlines)
        person.timezone = editingTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
        person.notes = editingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        person.isDirectReport = isDirectReport
        person.photo = editingPhotoData
        person.modifiedAt = Date()

        do {
            try viewContext.save()
            // CloudKit sync happens automatically via NSPersistentCloudKitContainer
        } catch {
            print("Failed to save person: \(error)")
        }
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined().uppercased()
    }

    private func canPasteImage() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.types?.contains(.png) == true ||
               pasteboard.types?.contains(.tiff) == true ||
               pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue])
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general

        // Try to get image data from various formats
        if let imageData = pasteboard.data(forType: .png) ??
                          pasteboard.data(forType: .tiff),
           let image = NSImage(data: imageData) {
            editingPhotoData = imageData
            editingPhotoImage = image
        } else if let image = NSImage(pasteboard: pasteboard) {
            // Fallback: try to get NSImage directly and convert to PNG
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                editingPhotoData = pngData
                editingPhotoImage = image
            }
        }
    }
}
