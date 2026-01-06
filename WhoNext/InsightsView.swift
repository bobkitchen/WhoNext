import SwiftUI
import CoreData

struct InsightsView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var chatInput: String = ""
    @FocusState private var isChatFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // AI Insights Panel - Fixed at top with padding around it
            AIInsightsPanelView(
                chatInput: $chatInput,
                isFocused: $isChatFocused
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor))

            // Analytics Dashboard - Scrollable below
            ScrollView(.vertical, showsIndicators: false) {
                AnalyticsDashboardView(chatInput: $chatInput, isChatFocused: $isChatFocused)
                    .padding(.top, 12)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    let context = PersistenceController.shared.container.viewContext
    InsightsView()
        .environment(\.managedObjectContext, context)
        .environmentObject(AppStateManager(viewContext: context))
}
