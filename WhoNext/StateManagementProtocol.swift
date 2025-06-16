import Foundation
import SwiftUI

// MARK: - State Management Protocol
@MainActor
protocol StateManagement: ObservableObject {
    var selectedTab: SidebarItem { get set }
    var selectedPerson: Person? { get set }
    var selectedPersonID: UUID? { get set }
}

// MARK: - AppStateManager Conformance
extension AppStateManager: StateManagement {
    // Already has the required properties
}