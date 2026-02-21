import Foundation

/// In-memory handoff for meeting data between SimpleRecordingEngine and the review UI.
/// Replaces the previous UserDefaults-based IPC which was an anti-pattern for same-process communication.
@MainActor
class MeetingHandoff: ObservableObject {
    static let shared = MeetingHandoff()
    private init() {}

    struct PendingMeeting {
        let transcript: String
        let title: String
        let date: Date
        let duration: TimeInterval
        let participants: [SerializableParticipant]
        let userNotes: String?
    }

    @Published private(set) var pending: PendingMeeting?

    func store(_ meeting: PendingMeeting) {
        pending = meeting
    }

    func consume() -> PendingMeeting? {
        defer { pending = nil }
        return pending
    }
}
