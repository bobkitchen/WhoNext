import SwiftUI
import CoreData

struct StatisticsCardsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Navigation callbacks (kept for MeetingsView compatibility)
    var onNavigateToPeople: (() -> Void)?
    var onNavigateToPerson: ((Person) -> Void)?
    var onNavigateToInsights: (() -> Void)?

    var body: some View {
        NextMeetingBriefCard(onPersonTap: onNavigateToPerson)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatisticsCardsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
