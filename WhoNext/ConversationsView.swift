import SwiftUI
import CoreData

struct ConversationsView: View {
    var conversationManager: ConversationStateManager?
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)],
        animation: .default)
    private var conversations: FetchedResults<Conversation>
    
    @State private var selectedConversation: Conversation?
    @State private var isPresentingDetail = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Conversations")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 10)

            List(conversations) { conversation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversationPreview(conversation.notes))
                        .font(.body)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let date = conversation.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .onTapGesture {
                    selectedConversation = conversation
                    isPresentingDetail = true
                }
            }
            .listStyle(.plain)
        }
        .padding()
        .navigationTitle("Conversations")
        .sheet(isPresented: $isPresentingDetail) {
            if let conversation = selectedConversation {
                ConversationDetailView(conversation: conversation, conversationManager: conversationManager, isInitiallyEditing: false)
            }
        }
    }

    private func conversationPreview(_ text: String?) -> String {
        guard let text = text else { return "No Notes" }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let preview = lines.prefix(2).joined(separator: " ")
        return preview.isEmpty ? "No Notes" : preview
    }
}
