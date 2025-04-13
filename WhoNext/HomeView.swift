import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to WhoNext")
                .font(.largeTitle)
                .bold()
            Text("This will become your smart suggestion dashboard.")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}
