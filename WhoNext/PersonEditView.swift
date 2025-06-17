import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct PersonEditView: View {
    @ObservedObject var person: Person
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
    @State private var showingLinkedInDropZone = false
    
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
                                                    .onHover { isHovered in
                                                        // Add hover effect if needed
                                                    }
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
                                showingLinkedInDropZone.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("LinkedIn PDF")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // LinkedIn PDF Drop Zone (conditionally shown)
                        if showingLinkedInDropZone {
                            LinkedInPDFDropZone { generatedSummary in
                                // Append the generated summary to existing notes
                                if !editingNotes.isEmpty {
                                    editingNotes += "\n\n" + generatedSummary
                                } else {
                                    editingNotes = generatedSummary
                                }
                                showingLinkedInDropZone = false
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        // Markdown Preview (if notes contain markdown formatting)
                        if !editingNotes.isEmpty && editingNotes.contains("**") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preview:")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                ScrollView {
                                    Text(AttributedString(MarkdownHelper.attributedString(from: editingNotes)))
                                        .font(.system(size: 14))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                }
                                .frame(minHeight: 200)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                        } else {
                            // Show TextEditor only when no markdown formatting is detected
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
                        }
                        
                        // Helper text
                        if !showingLinkedInDropZone {
                            Text("💡 Tip: Use the LinkedIn PDF button above to automatically generate a professional summary from LinkedIn profile pages.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    onCancel?()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                    onSave?()
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
    
    private func saveChanges() {
        person.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        person.role = editingRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingRole.trimmingCharacters(in: .whitespacesAndNewlines)
        person.timezone = editingTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
        person.notes = editingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        person.isDirectReport = isDirectReport
        person.photo = editingPhotoData
        person.modifiedAt = Date() // Mark as modified for sync
        
        do {
            try viewContext.save()
            
            // Trigger immediate sync for updates
            RobustSyncManager.shared.triggerSync()
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

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let person = Person(context: context)
    person.name = "John Doe"
    person.role = "Software Engineer"
    
    return PersonEditView(person: person)
        .environment(\.managedObjectContext, context)
}
