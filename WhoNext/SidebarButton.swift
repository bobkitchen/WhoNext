import SwiftUI

struct SidebarButton: View {
    let icon: String
    let label: String
    let item: String
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(label)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(selection == item ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .foregroundStyle(selection == item ? Color.accentColor : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item
        }
    }
}
