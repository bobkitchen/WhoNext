import SwiftUI
import CoreData

struct PeopleAndGroupsView: View {
    @Binding var selectedPerson: Person?
    @EnvironmentObject var appStateManager: AppStateManager
    
    var body: some View {
        HStack(spacing: 0) {
            // Enhanced people list on the left
            EnhancedPeopleView(selectedPerson: $selectedPerson)
                .frame(minWidth: 400, maxWidth: 500)
            
            Divider()
            
            // Person detail on the right
            if let person = selectedPerson {
                PersonDetailView(person: person)
                    .id(person.identifier)
                    .frame(maxWidth: .infinity)
                    .environmentObject(appStateManager)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.3))
                    
                    Text("Select a person to view details")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}