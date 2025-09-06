import SwiftUI
import CoreData

struct PeopleAndGroupsView: View {
    @Binding var selectedPerson: Person?
    
    var body: some View {
        // Use the enhanced people view with all the modern UI improvements
        EnhancedPeopleView(selectedPerson: $selectedPerson)
    }
}