//
//  Persistence.swift
//  WhoNext
//
//  Re-worked 1 May 25 for rock-solid CloudKit sync
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    // MARK: - Preview ---------------------------------------------------------

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        let person          = Person(context: viewContext)
        person.name         = "Preview Person"
        person.role         = "Test Role"
        person.identifier   = UUID()
        person.isDirectReport = false

        try? viewContext.save()
        return controller
    }()

    // MARK: - Core stack ------------------------------------------------------

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {

        let modelName = "WhoNext"
        let cloudID   = "iCloud.com.bobk.whonext"        // ← all-lower-case, exact match

        // Load the compiled model (.momd or .mom)
        guard
            let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd") ??
                           Bundle.main.url(forResource: modelName, withExtension: "mom"),
            let model    = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("❌ Unable to locate Core Data model.")
        }

        // Create a CloudKit-aware container
        container = NSPersistentCloudKitContainer(name: modelName,
                                                  managedObjectModel: model)

        // ---------------------------------------------------------------------
        // TUNE THE PERSISTENT-STORE DESCRIPTION
        // ---------------------------------------------------------------------
        guard let store = container.persistentStoreDescriptions.first else {
            fatalError("❌ Missing persistent-store description.")
        }

        // 1. Tell the store which CloudKit container to use
        store.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: cloudID)

        // 2. Enable history tracking – makes CloudKit export every transaction
        store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)            //  [oai_citation:0‡Stack Overflow](https://stackoverflow.com/questions/71492385/nspersistentcloudkitcontainer-and-persistent-history-tracking?utm_source=chatgpt.com)

        // 3. Post *remote-change* notifications – the other Mac hears the push
        store.setOption(true as NSNumber,
                        forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)     //  [oai_citation:1‡Stack Overflow](https://stackoverflow.com/questions/61790440/coredata-and-cloudkit-sync-works-but-nspersistentstoreremotechange-notification?utm_source=chatgpt.com)

        // 4. Allow lightweight migration
        store.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        store.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        // 5. In-memory override for previews
        if inMemory { store.url = URL(fileURLWithPath: "/dev/null") }

        // ---------------------------------------------------------------------
        // Load stores
        // ---------------------------------------------------------------------
        container.loadPersistentStores { _, error in
            if let error { fatalError("❌ Core Data load error: \(error)") }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
