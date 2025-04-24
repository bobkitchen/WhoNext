import SwiftUI
import UniformTypeIdentifiers

struct AddPersonView: View {
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var timezone: String = ""
    @State private var isDirectReport: Bool = false
    @State private var notes: String = ""
    @State private var photoData: Data? = nil
    @State private var photoImage: NSImage? = nil
    @State private var showingPhotoPicker = false
    var onSave: (String, String, String, Bool, String, Data?) -> Void
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header - mirror edit view
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .systemGray).opacity(0.15))
                            .frame(width: 64, height: 64)
                        if let photoImage = photoImage {
                            Image(nsImage: photoImage)
                                .resizable()
                                .scaledToFill()
                                .clipShape(Circle())
                                .frame(width: 64, height: 64)
                        } else {
                            Text(initials(from: name))
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Choose Photo") { showingPhotoPicker = true }
                        .font(.system(size: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Full Name", text: $name)
                        .font(.system(size: 20, weight: .semibold))
                        .textFieldStyle(.plain)
                        .frame(width: 260)
                    TextField("Role", text: $role)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .textFieldStyle(.plain)
                        .frame(width: 260)
                    TextField("Timezone", text: $timezone)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .textFieldStyle(.plain)
                        .frame(width: 260)
                        .padding(.top, 2)
                    Toggle("Direct Report", isOn: $isDirectReport)
                        .font(.system(size: 13))
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.system(size: 15, weight: .semibold))
                TextEditor(text: $notes)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Add") {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSave(name.trimmingCharacters(in: .whitespaces),
                               role.trimmingCharacters(in: .whitespaces),
                               timezone.trimmingCharacters(in: .whitespaces),
                               isDirectReport,
                               notes.trimmingCharacters(in: .whitespacesAndNewlines),
                               photoData)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .fileImporter(isPresented: $showingPhotoPicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    photoData = data
                    photoImage = image
                }
            default:
                break
            }
        }
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).map { String($0.prefix(1)) }
        return initials.joined()
    }
}
