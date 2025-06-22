import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct AddPersonWindow: View {
    @State private var editingName: String = ""
    @State private var editingRole: String = ""
    @State private var editingTimezone: String = ""
    @State private var showingTimezoneDropdown: Bool = false
    @State private var editingNotes: String = ""
    @State private var isDirectReport: Bool = false
    @State private var editingPhotoData: Data? = nil
    @State private var editingPhotoImage: NSImage? = nil
    @State private var showingPhotoPicker = false
    @State private var showingLinkedInWindow = false
    
    let context: NSManagedObjectContext
    let onSave: (Person) -> Void
    let onCancel: () -> Void
    
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
                                Text("Full Name")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("Enter full name", text: $editingName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Role")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("Job title or role", text: $editingRole)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Timezone")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                VStack {
                                    TextField("Search timezones...", text: $editingTimezone)
                                        .textFieldStyle(.roundedBorder)
                                        .onTapGesture {
                                            showingTimezoneDropdown = true
                                        }
                                        .onChange(of: editingTimezone) {
                                            showingTimezoneDropdown = !editingTimezone.isEmpty
                                        }
                                    
                                    if showingTimezoneDropdown && !filteredTimezones.isEmpty {
                                        VStack(spacing: 0) {
                                            ForEach(filteredTimezones.prefix(8), id: \.self) { timezone in
                                                Button(action: {
                                                    editingTimezone = timezone
                                                    showingTimezoneDropdown = false
                                                }) {
                                                    HStack {
                                                        Text(timezone)
                                                            .foregroundColor(.primary)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .onHover { isHovered in
                                                    // Add hover effect if needed
                                                }
                                            }
                                        }
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(6)
                                        .shadow(radius: 4)
                                    }
                                }
                            }
                            
                            Toggle("Direct Report", isOn: $isDirectReport)
                                .toggleStyle(SwitchToggleStyle())
                        }
                    }
                    
                    // Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Profile Notes")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Spacer()
                            
                            Button(action: {
                                showingLinkedInWindow.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 10))
                                    Text("LinkedIn Search")
                                        .font(.system(size: 11))
                                }
                            }
                            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                        }
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.textBackgroundColor))
                                .stroke(Color(.separatorColor), lineWidth: 1)
                            
                            if editingNotes.isEmpty {
                                Text("Add notes about this person...")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            
                            TextEditor(text: $editingNotes)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.clear)
                                .scrollContentBackground(.hidden)
                        }
                        .frame(minHeight: 120)
                        
                        // Quick tip for LinkedIn info
                        Text("💡 Tip: Use 'LinkedIn Search' button above to quickly import profile information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 20)
            }
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()
                
                Button("Add Person") {
                    let newPerson = Person(context: context)
                    newPerson.identifier = UUID()
                    newPerson.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                    newPerson.role = editingRole.trimmingCharacters(in: .whitespacesAndNewlines)
                    newPerson.timezone = editingTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
                    newPerson.isDirectReport = isDirectReport
                    newPerson.notes = editingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    newPerson.createdAt = Date() // Set creation timestamp for sync
                    newPerson.modifiedAt = Date() // Set initial modification timestamp
                    
                    if let photoData = editingPhotoData {
                        newPerson.photo = photoData
                    }
                    
                    onSave(newPerson)
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
            case .failure(let error):
                print("Failed to import photo: \(error)")
            }
        }
        .sheet(isPresented: $showingLinkedInWindow) {
            LinkedInSearchWindow(onDataExtracted: { data in
                populateFormFields(with: data)
            }, onClose: { showingLinkedInWindow = false })
        }
        .onAppear {
            // Set default timezone to user's current timezone
            if editingTimezone.isEmpty {
                editingTimezone = TimeZone.current.identifier
            }
        }
    }
    
    var filteredTimezones: [String] {
        if editingTimezone.isEmpty {
            return TimeZone.knownTimeZoneIdentifiers.sorted()
        } else {
            return TimeZone.knownTimeZoneIdentifiers.filter { timezone in
                timezone.localizedCaseInsensitiveContains(editingTimezone)
            }.sorted()
        }
    }
    
    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined().uppercased()
    }
    
    private func canPasteImage() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue])
    }
    
    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = NSImage(data: imageData) {
            editingPhotoData = imageData
            editingPhotoImage = image
        }
    }
    
    private func populateFormFields(with data: LinkedInProfileData) {
        editingName = data.name
        editingRole = data.headline
        editingTimezone = data.location
        
        var summary = data.about
        
        summary += "\n\nExperience:\n" + data.experience.map { "• \( $0.title ) at \( $0.company ) (\( $0.duration ))" }.joined(separator: "\n")
        
        summary += "\n\nEducation:\n" + data.education.map { "• \( $0.school ) (\( $0.degree ) in \( $0.field ))" }.joined(separator: "\n")
        
        editingNotes = summary
        
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
        } else {
            print("📸 No photo URL provided or invalid URL: '\(data.photo)'")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return AddPersonWindow(context: context, onSave: { _ in }, onCancel: {})
        .environment(\.managedObjectContext, context)
}
