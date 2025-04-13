import Foundation
import SwiftUI

class AppState: ObservableObject {
    @Published var selectedTab: SidebarItem = .insights
    @Published var selectedPersonID: UUID?
    @Published var selectedPerson: Person?
}
