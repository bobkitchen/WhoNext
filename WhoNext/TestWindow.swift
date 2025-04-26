import SwiftUI

struct TestWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        VStack(spacing: 20) {
            Text("Test Window")
                .font(.title)
            Button("Close Window") {
                print("Close Window pressed")
                dismissWindow()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 300, height: 150)
        .padding()
    }
}
