import SwiftUI

struct AddPersonView: View {
    @State private var name: String = ""
    @State private var role: String = ""
    var onSave: (String, String) -> Void
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add New Person")
                .font(.headline)

            TextField("Full Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 280)

            TextField("Role (optional)", text: $role)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 280)

            HStack {
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Add") {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSave(name.trimmingCharacters(in: .whitespaces), role.trimmingCharacters(in: .whitespaces))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }
}
