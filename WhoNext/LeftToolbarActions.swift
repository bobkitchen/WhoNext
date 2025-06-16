import SwiftUI

struct LeftToolbarActions: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                NewConversationWindowManager.shared.presentWindow(for: nil)
            }) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("New Conversation")
            .padding(.horizontal, 4)
            
            Button(action: {
                // If not on People tab, switch to People, then trigger add person after a short delay
                if appState.selectedTab != .people {
                    appState.selectedTab = .people
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: .triggerAddPerson, object: nil)
                    }
                } else {
                    NotificationCenter.default.post(name: .triggerAddPerson, object: nil)
                }
            }) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("New Person")
            .padding(.horizontal, 4)
            
            Button(action: {
                TranscriptImportWindowManager.shared.presentWindow()
            }) {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Import Transcript")
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    LeftToolbarActions(appState: AppState())
}