import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct PersonEditView: View {
    @ObservedObject var person: Person
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var editingName: String = ""
    @State private var editingRole: String = ""
    @State private var editingTimezone: String = ""
    @State private var editingNotes: String = ""
    @State private var isDirectReport: Bool = false
    @State private var editingPhotoData: Data? = nil
    @State private var editingPhotoImage: NSImage? = nil
    @State private var showingPhotoPicker = false
    @State private var showingLinkedInDropZone = false
    
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Text("Edit Person")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding(.bottom, 8)
            
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
                                .buttonStyle(.bordered)
                                
                                Button("Paste from Clipboard") {
                                    pasteImageFromClipboard()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canPasteImage())
                                
                                if editingPhotoImage != nil {
                                    Button("Remove Photo") {
                                        editingPhotoData = nil
                                        editingPhotoImage = nil
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
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
                                TextField("Enter timezone", text: $editingTimezone)
                                    .textFieldStyle(.roundedBorder)
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
                        
                        TextEditor(text: $editingNotes)
                            .font(.system(size: 14))
                            .frame(minHeight: showingLinkedInDropZone ? 100 : 120)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
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
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveChanges()
                    onSave?()
                }
                .buttonStyle(.borderedProminent)
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
        
        do {
            try viewContext.save()
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
