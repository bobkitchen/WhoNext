import Foundation
import SwiftUI
import CoreData
import Combine

// MARK: - App State Manager
@MainActor
class AppStateManager: ObservableObject {
    // MARK: - Navigation State
    @Published var selectedTab: SidebarItem = .meetings
    @Published var selectedPersonID: UUID?
    @Published var selectedPerson: Person? {
        didSet {
            selectedPersonID = selectedPerson?.identifier
        }
    }
    
    // MARK: - Global Loading States
    @Published var isInitializing = true
    @Published var hasDataLoaded = false
    @Published var isLoadingPeople = false
    @Published var isGeneratingContent = false
    @Published var isSyncing = false
    
    // MARK: - Dependencies
    let navigationManager: NavigationStateManager
    let conversationManager: ConversationStateManager
    let errorManager: ErrorManager
    
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    
    // MARK: - Caching Layer
    private var cachedPeople: [Person] = []
    private var cachedConversations: [Conversation] = []
    private var peopleLastFetched: Date?
    private var conversationsLastFetched: Date?
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes
    private let shortCacheInterval: TimeInterval = 120 // 2 minutes for frequently updated data
    
    // MARK: - Memory Management
    private var lastMemoryCleanup = Date()
    private let memoryCleanupInterval: TimeInterval = 900 // 15 minutes
    private let maxCachedPeople = 1000
    private let maxCachedConversations = 2000
    
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.errorManager = ErrorManager.shared
        self.navigationManager = NavigationStateManager()
        self.conversationManager = ConversationStateManager(viewContext: viewContext, errorManager: errorManager)
        
        setupBindings()
        isInitialized = true
        initializeApp()
    }
    
    private func setupBindings() {
        // Temporarily simplified - direct AppStateManager usage only
        print("🚀 AppStateManager initialized with selectedTab: \(selectedTab)")
    }
    
    private func initializeApp() {
        Task {
            // Initialize app state
            await MainActor.run {
                self.hasDataLoaded = true
                self.isInitializing = false
            }
        }
    }
    
    // MARK: - Public Methods
    
    func selectTab(_ tab: SidebarItem) {
        navigationManager.navigate(to: tab)
    }
    
    func selectPerson(_ person: Person?) {
        selectedPerson = person
        
        if let person = person {
            navigationManager.selectPerson(person)
            conversationManager.loadConversations(for: person)
        }
    }
    
    func createPerson(name: String, role: String?, isDirectReport: Bool, timezone: String?, photo: Data?) -> Person? {
        let person = Person(context: viewContext)
        person.identifier = UUID()
        person.name = name
        person.role = role
        person.isDirectReport = isDirectReport
        person.timezone = timezone
        person.photo = photo
        
        do {
            try viewContext.save()
            
            // Trigger immediate sync for new person
            RobustSyncManager.shared.triggerSync()
            
            invalidatePeopleCache() // Invalidate cache when new person is added
            return person
        } catch {
            errorManager.handle(error, context: "Failed to create person")
            return nil
        }
    }
    
    // MARK: - Caching Methods
    
    func getCachedPeople() -> [Person] {
        if shouldRefreshPeopleCache() {
            refreshPeopleCache()
        }
        return cachedPeople
    }
    
    func getCachedConversations() -> [Conversation] {
        if shouldRefreshConversationsCache() {
            refreshConversationsCache()
        }
        return cachedConversations
    }
    
    private func shouldRefreshPeopleCache() -> Bool {
        guard let lastFetched = peopleLastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) > cacheExpirationInterval
    }
    
    private func shouldRefreshConversationsCache() -> Bool {
        guard let lastFetched = conversationsLastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) > shortCacheInterval
    }
    
    private func refreshPeopleCache() {
        Task { @MainActor in
            setLoadingPeople(true)
            defer { setLoadingPeople(false) }
            
            let request = NSFetchRequest<Person>(entityName: "Person")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
            request.relationshipKeyPathsForPrefetching = ["conversations"]
            request.fetchBatchSize = 50
            
            do {
                cachedPeople = try viewContext.fetch(request)
                peopleLastFetched = Date()
            } catch {
                errorManager.handle(error, context: "Failed to refresh people cache")
            }
        }
    }
    
    private func refreshConversationsCache() {
        Task { @MainActor in
            let request = NSFetchRequest<Conversation>(entityName: "Conversation")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)]
            request.relationshipKeyPathsForPrefetching = ["person"]
            request.fetchBatchSize = 100
            
            do {
                cachedConversations = try viewContext.fetch(request)
                conversationsLastFetched = Date()
            } catch {
                errorManager.handle(error, context: "Failed to refresh conversations cache")
            }
        }
    }
    
    func invalidatePeopleCache() {
        peopleLastFetched = nil
        cachedPeople = []
    }
    
    func invalidateConversationsCache() {
        conversationsLastFetched = nil
        cachedConversations = []
    }
    
    func invalidateAllCaches() {
        invalidatePeopleCache()
        invalidateConversationsCache()
    }
    
    // MARK: - Loading State Management
    
    func setLoadingPeople(_ loading: Bool) {
        isLoadingPeople = loading
    }
    
    func setGeneratingContent(_ loading: Bool) {
        isGeneratingContent = loading
    }
    
    func setSyncing(_ loading: Bool) {
        isSyncing = loading
    }
    
    func performWithLoading<T>(_ loadingType: LoadingType, operation: () async throws -> T) async rethrows -> T {
        setLoading(loadingType, true)
        defer { setLoading(loadingType, false) }
        return try await operation()
    }
    
    private func setLoading(_ type: LoadingType, _ loading: Bool) {
        switch type {
        case .people:
            isLoadingPeople = loading
        case .content:
            isGeneratingContent = loading
        case .sync:
            isSyncing = loading
        }
    }
    
    // MARK: - Memory Management
    
    private func performMemoryCleanup() {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryCleanup) >= memoryCleanupInterval else { return }
        
        lastMemoryCleanup = now
        
        // Limit cached data to prevent memory bloat
        if cachedPeople.count > maxCachedPeople {
            cachedPeople = Array(cachedPeople.prefix(maxCachedPeople))
        }
        
        if cachedConversations.count > maxCachedConversations {
            cachedConversations = Array(cachedConversations.prefix(maxCachedConversations))
        }
        
        // Trigger cleanup in child managers
        conversationManager.clearCache()
        navigationManager.clearHistory()
        
        // Force cache refresh if data is stale
        if shouldRefreshPeopleCache() {
            peopleLastFetched = nil
        }
        if shouldRefreshConversationsCache() {
            conversationsLastFetched = nil
        }
    }
    
    func forceMemoryCleanup() {
        performMemoryCleanup()
    }
    
    func getMemoryFootprint() -> AppMemoryFootprint {
        let conversationFootprint = conversationManager.getMemoryFootprint()
        let navigationFootprint = navigationManager.getMemoryFootprint()
        
        let totalPeople = cachedPeople.count
        let totalConversations = cachedConversations.count
        let estimatedAppBytes = (totalPeople * 2048) + (totalConversations * 1024) // Rough estimates
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let totalMemoryString = formatter.string(fromByteCount: Int64(estimatedAppBytes))
        
        return AppMemoryFootprint(
            cachedPeople: totalPeople,
            cachedConversations: totalConversations,
            conversationManagerFootprint: conversationFootprint,
            navigationManagerFootprint: navigationFootprint,
            totalMemoryEstimate: totalMemoryString
        )
    }
    
    deinit {
        // Synchronous cleanup for deinit
        cancellables.removeAll()
        cachedPeople.removeAll()
        cachedConversations.removeAll()
    }
    
}

// MARK: - Memory Footprint Types
struct AppMemoryFootprint {
    let cachedPeople: Int
    let cachedConversations: Int
    let conversationManagerFootprint: (conversationCount: Int, memoryEstimate: String)
    let navigationManagerFootprint: (historyCount: Int, windowCount: Int, memoryEstimate: String)
    let totalMemoryEstimate: String
}

// MARK: - Loading Types
enum LoadingType {
    case people
    case content
    case sync
}