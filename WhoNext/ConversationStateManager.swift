import Foundation
import SwiftUI
import CoreData
import Combine

// MARK: - Conversation State Manager
@MainActor
class ConversationStateManager: ObservableObject {
    @Published var selectedConversation: Conversation?
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    
    private let viewContext: NSManagedObjectContext
    private let errorManager: ErrorManager
    private var cancellables = Set<AnyCancellable>()
    private var loadingTasks = Set<Task<Void, Never>>()
    
    // Memory management
    private let maxCachedConversations = 500
    private var lastCleanupTime = Date()
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    
    init(viewContext: NSManagedObjectContext, errorManager: ErrorManager? = nil) {
        self.viewContext = viewContext
        self.errorManager = errorManager ?? ErrorManager()
        setupCleanupTimer()
    }
    
    deinit {
        // Synchronous cleanup for deinit - only non-Published properties
        loadingTasks.forEach { $0.cancel() }
        loadingTasks.removeAll()
        cancellables.removeAll()
    }
    
    // MARK: - Conversation Management
    
    func loadConversations(for person: Person? = nil) {
        isLoading = true
        
        let task = Task {
            do {
                let request = NSFetchRequest<Conversation>(entityName: "Conversation")
                if let person = person {
                    request.predicate = NSPredicate(format: "person == %@", person)
                }
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)]
                // Optimize with prefetching and batch size
                request.relationshipKeyPathsForPrefetching = ["person"]
                request.fetchBatchSize = 50
                
                let results = try viewContext.fetch(request)
                
                // Check if task was cancelled before updating UI
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.conversations = results
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorManager.handle(error, context: "Failed to load conversations")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
        
        loadingTasks.insert(task)
    }
    
    func createConversation(for person: Person, notes: String = "", duration: Int32 = 0, date: Date = Date()) {
        let conversation = Conversation(context: viewContext)
        conversation.uuid = UUID()
        conversation.person = person
        conversation.notes = notes
        conversation.date = date
        conversation.duration = duration
        
        do {
            try viewContext.save()
            // CloudKit sync happens automatically via NSPersistentCloudKitContainer
            loadConversations(for: person)
        } catch {
            errorManager.handle(error, context: "Failed to create conversation")
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        // Delete locally - CloudKit sync handles propagation automatically
        viewContext.delete(conversation)
        do {
            try viewContext.save()
            conversations.removeAll { $0.uuid == conversation.uuid }
        } catch {
            errorManager.handle(error, context: "Failed to delete conversation")
        }
    }
    
    func selectConversation(_ conversation: Conversation?) {
        selectedConversation = conversation
    }
    
    // MARK: - Computed Properties
    
    func getConversations(for person: Person) -> [Conversation] {
        return conversations.filter { $0.person == person }
    }
    
    func getConversationCount(for person: Person) -> Int {
        return getConversations(for: person).count
    }
    
    // MARK: - Memory Management
    
    private func setupCleanupTimer() {
        Timer.publish(every: cleanupInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performPeriodicCleanup()
            }
            .store(in: &cancellables)
    }
    
    private func performPeriodicCleanup() {
        let now = Date()
        guard now.timeIntervalSince(lastCleanupTime) >= cleanupInterval else { return }
        
        lastCleanupTime = now
        
        // Limit cached conversations to prevent memory bloat
        if conversations.count > maxCachedConversations {
            // Keep only the most recent conversations
            conversations = Array(conversations.prefix(maxCachedConversations))
        }
        
        // Cancel any stale loading tasks
        cleanupStaleTasks()
    }
    
    private func cleanupStaleTasks() {
        loadingTasks = loadingTasks.filter { !$0.isCancelled }
    }
    
    
    func clearCache() {
        conversations.removeAll()
        selectedConversation = nil
    }
    
    func getMemoryFootprint() -> (conversationCount: Int, memoryEstimate: String) {
        let count = conversations.count
        let estimatedBytes = count * 1024 // Rough estimate: 1KB per conversation
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let memoryString = formatter.string(fromByteCount: Int64(estimatedBytes))
        return (count, memoryString)
    }
}