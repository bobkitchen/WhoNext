import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case people
    case insights

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .people:
            return "People"
        case .insights:
            return "Insights"
        }
    }
}
