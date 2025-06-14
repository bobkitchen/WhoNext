import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Welcome Section
            VStack(spacing: 16) {
                // App Icon with Animation
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                
                VStack(spacing: 8) {
                    Text("Welcome to WhoNext")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Manage your professional relationships and conversations")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            Spacer()
            
            // Quick Start Hint
            VStack(spacing: 12) {
                Text("Get Started")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                VStack(spacing: 8) {
                    Text("• Use the toolbar buttons to add people and conversations")
                    Text("• Switch between People, Insights, and Analytics tabs")
                    Text("• Search for contacts using the search bar")
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassBackground(cornerRadius: 0, elevation: .low)
    }
}

#Preview {
    HomeView()
}
