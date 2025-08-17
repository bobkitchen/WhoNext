import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case meetings
    case people
    case analytics

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .meetings:
            return "Meetings"
        case .people:
            return "People"
        case .analytics:
            return "Analytics"
        }
    }
}