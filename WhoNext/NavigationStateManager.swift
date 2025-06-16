import Foundation
import SwiftUI
import Combine

@MainActor
class NavigationStateManager: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedTab: SidebarItem = .insights
    @Published var selectedPerson: Person? {
        didSet {
            // Keep selectedPersonID in sync automatically
            selectedPersonID = selectedPerson?.identifier
        }
    }
    @Published var selectedPersonID: UUID? {
        didSet {
            // If someone sets the ID directly, we need to resolve the person
            if let id = selectedPersonID, selectedPerson?.identifier != id {
                // This will be resolved by the PersonRepository when implemented
                // For now, we maintain both for backward compatibility
            }
        }
    }
    
    // MARK: - Navigation Stack
    @Published var navigationHistory: [NavigationItem] = []
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    
    // MARK: - Window Management
    @Published var activeWindows: Set<WindowType> = []
    
    // MARK: - Memory Management
    private var cancellables = Set<AnyCancellable>()
    private let maxNavigationHistory = 50
    private var lastCleanupTime = Date()
    private let cleanupInterval: TimeInterval = 600 // 10 minutes
    
    init() {
        setupCleanupTimer()
    }
    
    deinit {
        // Synchronous cleanup for deinit - only non-Published properties
        cancellables.removeAll()
    }
    
    // MARK: - Navigation Methods
    func navigate(to tab: SidebarItem) {
        selectedTab = tab
        recordNavigation(.tab(tab))
    }
    
    func selectPerson(_ person: Person, switchToTab: Bool = true) {
        selectedPerson = person
        selectedPersonID = person.identifier
        
        if switchToTab && selectedTab != .people {
            selectedTab = .people
        }
        
        recordNavigation(.person(person.identifier ?? UUID()))
    }
    
    func selectPersonById(_ id: UUID, switchToTab: Bool = true) {
        selectedPersonID = id
        
        if switchToTab && selectedTab != .people {
            selectedTab = .people
        }
        
        recordNavigation(.person(id))
    }
    
    func clearSelection() {
        selectedPerson = nil
        selectedPersonID = nil
        recordNavigation(.tab(selectedTab))
    }
    
    // MARK: - Window Management
    func openWindow(_ type: WindowType) {
        activeWindows.insert(type)
    }
    
    func closeWindow(_ type: WindowType) {
        activeWindows.remove(type)
    }
    
    func isWindowOpen(_ type: WindowType) -> Bool {
        activeWindows.contains(type)
    }
    
    // MARK: - Navigation History
    private func recordNavigation(_ item: NavigationItem) {
        navigationHistory.append(item)
        
        // Prevent unlimited history growth
        if navigationHistory.count > maxNavigationHistory {
            navigationHistory.removeFirst()
        }
        
        updateNavigationButtons()
    }
    
    private func updateNavigationButtons() {
        canGoBack = navigationHistory.count > 1
        canGoForward = false // For future implementation
    }
    
    func goBack() {
        guard canGoBack, navigationHistory.count > 1 else { return }
        
        navigationHistory.removeLast()
        let previousItem = navigationHistory.last!
        
        switch previousItem {
        case .tab(let tab):
            selectedTab = tab
            clearSelection()
        case .person(let personId):
            selectedPersonID = personId
            selectedTab = .people
        }
        
        updateNavigationButtons()
    }
}

// MARK: - Supporting Types
enum NavigationItem: Hashable {
    case tab(SidebarItem)
    case person(UUID)
}

enum WindowType: String, CaseIterable {
    case settings
    case newConversation
    case addPerson
    case transcriptImport
    case preMeetingBrief
    case linkedInSearch
    case linkedInCapture
    
    var id: String { rawValue }
}

// MARK: - Convenience Extensions
extension NavigationStateManager {
    /// Convenience method for search results
    func handleSearchResult(_ person: Person) {
        selectPerson(person, switchToTab: true)
    }
    
    /// Convenience method for meeting card taps
    func handleMeetingCardTap(for person: Person) {
        selectPerson(person, switchToTab: true)
    }
    
    /// Reset navigation state (useful for testing or logout)
    func reset() {
        selectedTab = .insights
        selectedPerson = nil
        selectedPersonID = nil
        navigationHistory = []
        activeWindows = []
        updateNavigationButtons()
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
        
        // Limit navigation history to prevent memory bloat
        if navigationHistory.count > maxNavigationHistory {
            navigationHistory = Array(navigationHistory.suffix(maxNavigationHistory))
            updateNavigationButtons()
        }
        
        // Clear any stale window references
        cleanupStaleWindows()
    }
    
    private func cleanupStaleWindows() {
        // Remove window references that may no longer be valid
        // This could be expanded to check actual window state if needed
        // For now, we'll trust the window management to be accurate
        // In the future, we could add window state validation here
    }
    
    
    func clearHistory() {
        navigationHistory.removeAll()
        updateNavigationButtons()
    }
    
    func getMemoryFootprint() -> (historyCount: Int, windowCount: Int, memoryEstimate: String) {
        let historyCount = navigationHistory.count
        let windowCount = activeWindows.count
        let estimatedBytes = (historyCount * 64) + (windowCount * 32) // Rough estimates
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let memoryString = formatter.string(fromByteCount: Int64(estimatedBytes))
        return (historyCount, windowCount, memoryString)
    }
}