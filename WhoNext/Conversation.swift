import Foundation
import CoreData

@objc(Conversation)
public class Conversation: NSManagedObject {
    @NSManaged public var date: Date?
    @NSManaged public var legacyId: Date?
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var notes: String?
    @NSManaged public var summary: String?
    @NSManaged public var uuid: UUID?
    @NSManaged public var person: Person?
    @NSManaged public var notesRTF: Data?

    public var notesAttributedString: NSAttributedString? {
        get {
            guard let data = notesRTF else { return nil }
            return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        }
        set {
            notesRTF = newValue.flatMap { try? $0.data(from: NSRange(location: 0, length: $0.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) }
        }
    }
}

extension Conversation: Identifiable {
    public var id: UUID {
        get {
            return uuid ?? UUID()
        }
        set {
            uuid = newValue
        }
    }
}