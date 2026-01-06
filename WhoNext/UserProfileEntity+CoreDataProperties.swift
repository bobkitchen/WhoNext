import Foundation
import CoreData

extension UserProfileEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfileEntity> {
        return NSFetchRequest<UserProfileEntity>(entityName: "UserProfileEntity")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var email: String?
    @NSManaged public var identifier: UUID?
    @NSManaged public var jobTitle: String?
    @NSManaged public var lastVoiceUpdate: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var name: String?
    @NSManaged public var organization: String?
    @NSManaged public var photo: Data?
    @NSManaged public var voiceConfidence: Float
    @NSManaged public var voiceEmbedding: Data?
    @NSManaged public var voiceSampleCount: Int32
}

extension UserProfileEntity: Identifiable {
    public var id: UUID {
        identifier ?? UUID()
    }
}
