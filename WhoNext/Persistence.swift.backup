//
//  Persistence.swift
//  WhoNext
//
//  Updated for Supabase integration - CloudKit removed
//

import CoreData

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

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {

        let modelName = "WhoNext"

        // Load the compiled model (.momd or .mom)
        guard
            let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd") ??
                           Bundle.main.url(forResource: modelName, withExtension: "mom"),
            let model    = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("❌ Unable to locate Core Data model.")
        }

        // Create a regular Core Data container (no CloudKit)
        container = NSPersistentContainer(name: modelName,
                                         managedObjectModel: model)

        // ---------------------------------------------------------------------
        // TUNE THE PERSISTENT-STORE DESCRIPTION
        // ---------------------------------------------------------------------
        guard let store = container.persistentStoreDescriptions.first else {
            fatalError("❌ Missing persistent-store description.")
        }

        // 1. Allow lightweight migration
        store.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        store.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        // 2. Enable persistent history tracking to avoid read-only mode
        store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        store.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // 3. In-memory override for previews
        if inMemory { store.url = URL(fileURLWithPath: "/dev/null") }

        // ---------------------------------------------------------------------
        // Load stores
        // ---------------------------------------------------------------------
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("❌ Core Data load error: \(error)")
                print("❌ Store description: \(storeDescription)")
                fatalError("❌ Core Data load error: \(error)")
            } else {
                print("✅ Core Data store loaded successfully")
                print("✅ Store URL: \(storeDescription.url?.absoluteString ?? "unknown")")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
