//
//  Conversation+CoreDataProperties.swift
//  WhoNext
//
//  Created by Bob Kitchen on 4/5/25.
//

import Foundation
import CoreData

extension WhoNext.Conversation {  // Explicitly use the full module path for Conversation

    @nonobjc public class func fetchConversationRequest() -> NSFetchRequest<WhoNext.Conversation> {  // Use the full module path here too
        return NSFetchRequest<WhoNext.Conversation>(entityName: "Conversation")
    }

    @NSManaged public var date: Date?
    @NSManaged public var id: Date?
    @NSManaged public var notes: String?
    @NSManaged public var uuid: UUID?
    @NSManaged public var lastAnalyzed: Date?
    @NSManaged public var summary: String?
    @NSManaged public var person: Person?

}

extension WhoNext.Conversation : Identifiable {  // Same here for Identifiable conformance
    // Add Identifiable-related methods, if any
}
