//
//  Persistence.swift
//  WhoNext
//
//  Created by Bob Kitchen on 3/29/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<1 {
            let newPerson = Person(context: viewContext)
            newPerson.name = "Preview Person"
            newPerson.role = "Test Role"
            newPerson.identifier = UUID()
            newPerson.isDirectReport = false
        }
        do {
            print("[PersistenceController][LOG] Preview context save called\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        print("[PersistenceController][LOG] init called with inMemory=\(inMemory)\n\tCallStack: \(Thread.callStackSymbols.joined(separator: "\n\t"))")
        // Try loading the Core Data model with both possible extensions
        let modelName = "WhoNext"
        var model: NSManagedObjectModel?
        
        // First try .momd (compiled model directory)
        if let momdURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
           let momdModel = NSManagedObjectModel(contentsOf: momdURL) {
            model = momdModel
        }
        
        // If that fails, try .mom (single model file)
        if model == nil,
           let momURL = Bundle.main.url(forResource: modelName, withExtension: "mom"),
           let momModel = NSManagedObjectModel(contentsOf: momURL) {
            model = momModel
        }
        
        guard let loadedModel = model else {
            fatalError("Failed to load Core Data model. Tried both .momd and .mom extensions.")
        }
        
        container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: loadedModel)
        
        // Configure the persistent store
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Enable automatic lightweight migration
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        // Enable CloudKit syncing with the correct container identifier
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bobk.whonext")
        
        // Load the persistent stores synchronously to ensure everything is ready
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        // Configure the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
