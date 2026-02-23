import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let orphanedMeeting = UTType(exportedAs: "com.whonext.orphanedMeeting", conformingTo: .data)
}

enum MeetingKind: String, Codable {
    case conversation
    case groupMeeting
}

struct DraggableMeetingItem: Codable, Transferable {
    let id: UUID
    let kind: MeetingKind

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .orphanedMeeting)
    }
}
