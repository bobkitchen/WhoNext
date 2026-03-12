import Foundation

extension Notification.Name {
    static let conversationSaved = Notification.Name("ConversationSaved")
    static let conversationUpdated = Notification.Name("ConversationUpdated")
    static let groupMeetingSaved = Notification.Name("GroupMeetingSaved")
    static let peopleDidImport = Notification.Name("PeopleDidImport")
    static let calendarSelectionChanged = Notification.Name("CalendarSelectionChanged")
    static let triggerAddPerson = Notification.Name("triggerAddPerson")
    static let showRecordingDashboard = Notification.Name("showRecordingDashboard")
    static let triggerCSVImport = Notification.Name("triggerCSVImport")
    static let showParticipantConfirmation = Notification.Name("showParticipantConfirmation")
    static let offlineRediarizationComplete = Notification.Name("offlineRediarizationComplete")
}
