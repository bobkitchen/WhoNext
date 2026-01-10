import SwiftUI
import CoreData

struct InsightsView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var chatInput: String = ""
    @FocusState private var isChatFocused: Bool
    @State private var showAIChat: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Analytics Dashboard - Now the main content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    AnalyticsDashboardView(chatInput: $chatInput, isChatFocused: $isChatFocused)
                        .padding(.top, 20)

                    // AI Chat Section - Now at bottom as supplementary
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("Ask AI")
                                .font(.title2)
                                .fontWeight(.bold)

                            Spacer()

                            Button(action: { showAIChat.toggle() }) {
                                Image(systemName: showAIChat ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if showAIChat {
                            AIInsightsPanelView(
                                chatInput: $chatInput,
                                isFocused: $isChatFocused
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            // Collapsed state with quick prompts
                            HStack(spacing: 12) {
                                quickPromptButton("Who needs attention?") {
                                    chatInput = "Who needs attention right now?"
                                    showAIChat = true
                                    isChatFocused = true
                                }

                                quickPromptButton("Summarize my week") {
                                    chatInput = "Summarize my relationship activities this week"
                                    showAIChat = true
                                    isChatFocused = true
                                }

                                quickPromptButton("Coaching tips") {
                                    chatInput = "Give me coaching tips for my relationships"
                                    showAIChat = true
                                    isChatFocused = true
                                }

                                Spacer()
                            }
                        }
                    }
                    .padding(24)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAIChat)
    }

    private func quickPromptButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .foregroundColor(.purple)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let context = PersistenceController.shared.container.viewContext
    InsightsView()
        .environment(\.managedObjectContext, context)
        .environmentObject(AppStateManager(viewContext: context))
}
