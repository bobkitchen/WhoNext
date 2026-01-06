import SwiftUI

struct LeftToolbarActions<T: StateManagement>: View {
    @ObservedObject var appState: T
    
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
                // Open the Add Person window
                let windowController = AddPersonWindowController(
                    onSave: {
                        // Switch to People tab to show the new person
                        appState.selectedTab = .people
                    },
                    onCancel: {
                        // Nothing to do on cancel
                    }
                )
                windowController.showWindow()
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
    let context = PersistenceController.shared.container.viewContext
    LeftToolbarActions(appState: AppStateManager(viewContext: context))
}