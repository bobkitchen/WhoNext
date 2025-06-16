import SwiftUI

struct ChatSectionView: View {
    var body: some View {
        ChatView()
            .frame(minWidth: 400, maxHeight: 480)
            .liquidGlassCard(
                cornerRadius: 20,
                elevation: .medium,
                padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                isInteractive: true
            )
            .alignmentGuide(.top) { d in d[.top] } // Align top with cards
    }
}

#Preview {
    ChatSectionView()
}