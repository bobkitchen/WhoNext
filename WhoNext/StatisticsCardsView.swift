import SwiftUI
import CoreData

struct StatisticsCardsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Navigation callbacks
    var onNavigateToPeople: (() -> Void)?
    var onNavigateToPerson: ((Person) -> Void)?
    var onNavigateToInsights: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            // Card 1: Relationship Pulse - Portfolio health overview
            RelationshipPulseCard(onTap: onNavigateToPeople)

            // Card 2: Needs Attention - Specific people needing attention
            NeedsAttentionCard(
                onTap: onNavigateToPeople,
                onPersonTap: onNavigateToPerson
            )

            // Card 3: Recent Highlights - Weekly accomplishments
            RecentHighlightsCard(onTap: onNavigateToInsights)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatisticsCardsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}