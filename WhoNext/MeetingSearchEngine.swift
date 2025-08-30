import Foundation
import CoreData
import SwiftUI
import Combine

/// Full-text search engine for meeting transcripts and summaries
class MeetingSearchEngine: ObservableObject {
    
    // MARK: - Singleton
    static let shared = MeetingSearchEngine()
    
    // MARK: - Published Properties
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var selectedFilters: SearchFilters = SearchFilters()
    @Published var recentSearches: [String] = []
    @Published var savedSearches: [SavedSearch] = []
    @Published var searchSuggestions: [String] = []
    
    // MARK: - Private Properties
    private let context = PersistenceController.shared.container.viewContext
    private var searchCancellable: AnyCancellable?
    private let searchDebounce: TimeInterval = 0.3
    private var searchIndex: SearchIndex?
    
    // MARK: - Initialization
    
    private init() {
        loadRecentSearches()
        loadSavedSearches()
        buildSearchIndex()
        setupSearchDebouncing()
    }
    
    // MARK: - Search Methods
    
    /// Perform a search with the current query and filters
    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Add to recent searches
        addToRecentSearches(searchQuery)
        
        // Generate suggestions
        updateSearchSuggestions()
        
        Task {
            let results = await searchInBackground(
                query: searchQuery,
                filters: selectedFilters
            )
            
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    /// Search in background
    private func searchInBackground(
        query: String,
        filters: SearchFilters
    ) async -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Search in GroupMeetings
        let groupMeetings = await searchGroupMeetings(query: query, filters: filters)
        results.append(contentsOf: groupMeetings)
        
        // Search in Conversations
        let conversations = await searchConversations(query: query, filters: filters)
        results.append(contentsOf: conversations)
        
        // Sort by relevance score
        results.sort { $0.relevanceScore > $1.relevanceScore }
        
        return results
    }
    
    /// Search in GroupMeetings
    private func searchGroupMeetings(
        query: String,
        filters: SearchFilters
    ) async -> [SearchResult] {
        let fetchRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        
        // Build predicate
        var predicates: [NSPredicate] = []
        
        // Text search predicate
        let searchPredicate = NSPredicate(
            format: "transcript CONTAINS[cd] %@ OR summary CONTAINS[cd] %@ OR title CONTAINS[cd] %@ OR notes CONTAINS[cd] %@",
            query, query, query, query
        )
        predicates.append(searchPredicate)
        
        // Date range filter
        if let dateRangeType = filters.dateRange {
            let dateInterval = dateIntervalForRange(dateRangeType)
            predicates.append(NSPredicate(
                format: "date >= %@ AND date <= %@",
                dateInterval.start as NSDate,
                dateInterval.end as NSDate
            ))
        }
        
        // Attendee filter
        if !filters.attendees.isEmpty {
            let attendeePredicate = NSPredicate(
                format: "ANY attendees.name IN %@",
                filters.attendees
            )
            predicates.append(attendeePredicate)
        }
        
        // Duration filter
        if let minDuration = filters.minDuration {
            predicates.append(NSPredicate(
                format: "duration >= %d",
                Int32(minDuration)
            ))
        }
        
        // Sentiment filter
        if let sentimentRange = filters.sentimentRange {
            predicates.append(NSPredicate(
                format: "sentimentScore >= %f AND sentimentScore <= %f",
                sentimentRange.lowerBound,
                sentimentRange.upperBound
            ))
        }
        
        // Combine predicates
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        do {
            let meetings = try context.fetch(fetchRequest)
            
            return meetings.map { meeting in
                let relevance = calculateRelevance(
                    for: query,
                    in: meeting.transcript ?? "",
                    summary: meeting.summary,
                    title: meeting.title
                )
                
                let preview = generatePreview(
                    for: query,
                    in: meeting.transcript ?? "",
                    fallback: meeting.summary ?? ""
                )
                
                return SearchResult(
                    id: meeting.identifier ?? UUID(),
                    type: .groupMeeting,
                    title: meeting.displayTitle,
                    date: meeting.date ?? Date(),
                    preview: preview,
                    relevanceScore: relevance,
                    meeting: meeting,
                    conversation: nil,
                    matchedSegments: findMatchingSegments(query: query, in: meeting)
                )
            }
        } catch {
            print("Failed to search group meetings: \(error)")
            return []
        }
    }
    
    /// Search in Conversations
    private func searchConversations(
        query: String,
        filters: SearchFilters
    ) async -> [SearchResult] {
        let fetchRequest = Conversation.fetchRequest()
        
        // Build predicate
        var predicates: [NSPredicate] = []
        
        // Text search predicate
        let searchPredicate = NSPredicate(
            format: "notes CONTAINS[cd] %@ OR summary CONTAINS[cd] %@",
            query, query
        )
        predicates.append(searchPredicate)
        
        // Date range filter
        if let dateRangeType = filters.dateRange {
            let dateInterval = dateIntervalForRange(dateRangeType)
            predicates.append(NSPredicate(
                format: "date >= %@ AND date <= %@",
                dateInterval.start as NSDate,
                dateInterval.end as NSDate
            ))
        }
        
        // Person filter
        if !filters.attendees.isEmpty {
            let personPredicate = NSPredicate(
                format: "person.name IN %@",
                filters.attendees
            )
            predicates.append(personPredicate)
        }
        
        // Combine predicates
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        do {
            let conversations = try context.fetch(fetchRequest)
            
            return conversations.compactMap { conversationObj -> SearchResult? in
                guard let conversation = conversationObj as? Conversation else { return nil }
                
                let relevance = calculateRelevance(
                    for: query,
                    in: conversation.notes ?? "",
                    summary: conversation.summary,
                    title: nil
                )
                
                let preview = generatePreview(
                    for: query,
                    in: conversation.notes ?? "",
                    fallback: conversation.summary ?? ""
                )
                
                return SearchResult(
                    id: conversation.uuid ?? UUID(),
                    type: .conversation,
                    title: conversation.person?.name ?? "Unknown",
                    date: conversation.date ?? Date(),
                    preview: preview,
                    relevanceScore: relevance,
                    meeting: nil,
                    conversation: conversation,
                    matchedSegments: []
                )
            }
        } catch {
            print("Failed to search conversations: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    /// Convert date range type to DateInterval
    private func dateIntervalForRange(_ range: SearchFilters.DateRange) -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        
        switch range {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return DateInterval(start: startOfDay, end: endOfDay)
            
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek)!
            return DateInterval(start: startOfWeek, end: endOfWeek)
            
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            return DateInterval(start: startOfMonth, end: endOfMonth)
            
        case .lastThreeMonths:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
            return DateInterval(start: threeMonthsAgo, end: now)
            
        case .custom:
            // Default to last 30 days for custom (would need UI to specify)
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
            return DateInterval(start: thirtyDaysAgo, end: now)
        }
    }
    
    /// Calculate relevance score for search result
    private func calculateRelevance(
        for query: String,
        in transcript: String,
        summary: String?,
        title: String?
    ) -> Double {
        let queryLower = query.lowercased()
        let transcriptLower = transcript.lowercased()
        
        var score = 0.0
        
        // Count occurrences in transcript
        let transcriptMatches = transcriptLower.components(separatedBy: queryLower).count - 1
        score += Double(transcriptMatches) * 1.0
        
        // Boost for summary matches
        if let summary = summary?.lowercased() {
            let summaryMatches = summary.components(separatedBy: queryLower).count - 1
            score += Double(summaryMatches) * 3.0 // Summary matches are more relevant
        }
        
        // Boost for title matches
        if let title = title?.lowercased() {
            if title.contains(queryLower) {
                score += 5.0 // Title matches are highly relevant
            }
        }
        
        // Normalize score (0-1 range)
        return min(score / 10.0, 1.0)
    }
    
    /// Generate preview text for search result
    private func generatePreview(
        for query: String,
        in text: String,
        fallback: String
    ) -> String {
        let queryLower = query.lowercased()
        let textLower = text.lowercased()
        
        // Find first occurrence
        if let range = textLower.range(of: queryLower) {
            let startIndex = text.index(text.startIndex, offsetBy: textLower.distance(from: textLower.startIndex, to: range.lowerBound))
            
            // Extract context around match (50 chars before, 100 after)
            let contextStart = text.index(startIndex, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
            let contextEnd = text.index(startIndex, offsetBy: 150, limitedBy: text.endIndex) ?? text.endIndex
            
            let preview = String(text[contextStart..<contextEnd])
            return "..." + preview + "..."
        }
        
        // Fallback to first 150 chars
        let previewLength = min(150, fallback.count)
        return String(fallback.prefix(previewLength)) + (fallback.count > 150 ? "..." : "")
    }
    
    /// Find matching transcript segments
    private func findMatchingSegments(query: String, in meeting: GroupMeeting) -> [TranscriptSegment] {
        guard let segments = meeting.parsedTranscript else { return [] }
        
        let queryLower = query.lowercased()
        
        return segments.filter { segment in
            segment.text.lowercased().contains(queryLower) ||
            (segment.speakerName?.lowercased().contains(queryLower) ?? false)
        }
    }
    
    // MARK: - Search Index
    
    /// Build search index for faster searching
    private func buildSearchIndex() {
        Task {
            searchIndex = await SearchIndex.build(from: context)
            print("✅ Search index built with \(searchIndex?.entryCount ?? 0) entries")
        }
    }
    
    /// Rebuild search index
    func rebuildIndex() {
        buildSearchIndex()
    }
    
    // MARK: - Recent & Saved Searches
    
    private func addToRecentSearches(_ query: String) {
        // Remove if already exists
        recentSearches.removeAll { $0 == query }
        
        // Add to beginning
        recentSearches.insert(query, at: 0)
        
        // Keep only last 10
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(recentSearches, forKey: "RecentMeetingSearches")
    }
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "RecentMeetingSearches") ?? []
    }
    
    func saveSearch(name: String, query: String, filters: SearchFilters) {
        let savedSearch = SavedSearch(
            id: UUID(),
            name: name,
            query: query,
            filters: filters,
            createdAt: Date()
        )
        
        savedSearches.append(savedSearch)
        persistSavedSearches()
    }
    
    private func loadSavedSearches() {
        if let data = UserDefaults.standard.data(forKey: "SavedMeetingSearches"),
           let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            savedSearches = decoded
        }
    }
    
    private func persistSavedSearches() {
        if let encoded = try? JSONEncoder().encode(savedSearches) {
            UserDefaults.standard.set(encoded, forKey: "SavedMeetingSearches")
        }
    }
    
    // MARK: - Search Suggestions
    
    private func updateSearchSuggestions() {
        guard !searchQuery.isEmpty else {
            searchSuggestions = []
            return
        }
        
        // Generate suggestions based on:
        // 1. Recent searches
        // 2. Common keywords from index
        // 3. Speaker names
        
        var suggestions: [String] = []
        
        // From recent searches
        suggestions.append(contentsOf: recentSearches.filter {
            $0.lowercased().contains(searchQuery.lowercased()) && $0 != searchQuery
        })
        
        // From index keywords
        if let index = searchIndex {
            suggestions.append(contentsOf: index.getSuggestions(for: searchQuery))
        }
        
        // Limit to 5 suggestions
        searchSuggestions = Array(suggestions.prefix(5))
    }
    
    // MARK: - Debouncing
    
    private func setupSearchDebouncing() {
        searchCancellable = $searchQuery
            .debounce(for: .seconds(searchDebounce), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.performSearch()
            }
    }
}

// MARK: - Supporting Types

struct SearchResult: Identifiable {
    let id: UUID
    let type: SearchResultType
    let title: String
    let date: Date
    let preview: String
    let relevanceScore: Double
    let meeting: GroupMeeting?
    let conversation: Conversation?
    let matchedSegments: [TranscriptSegment]
    
    // Additional optional properties for enhanced search results
    var snippet: String? {
        // Return preview as snippet for backward compatibility
        return preview.isEmpty ? nil : preview
    }
    
    var participants: [String] {
        // Extract participants from meeting or conversation
        if let meeting = meeting {
            return meeting.attendees?.compactMap { ($0 as? Person)?.name } ?? []
        } else if let conversation = conversation {
            return [conversation.person?.name].compactMap { $0 }
        }
        return []
    }
}

enum SearchResultType {
    case groupMeeting
    case conversation
    case meeting // Add alias for backward compatibility
    
    var isGroupMeeting: Bool {
        self == .groupMeeting || self == .meeting
    }
}

struct SearchFilters: Codable {
    enum DateRange: String, Codable {
        case today
        case thisWeek
        case thisMonth
        case lastThreeMonths
        case custom
    }
    
    enum SearchType: String, Codable {
        case all
        case meetings
        case conversations
    }
    
    var dateRange: DateRange?
    var searchType: SearchType = .all
    var attendees: [String] = []
    var groups: [String] = []
    var minDuration: TimeInterval?
    var maxDuration: TimeInterval?
    var sentimentRange: ClosedRange<Double>?
    var hasAudio: Bool?
    var hasTranscript: Bool?
    var hasSummary: Bool?
    var hasRecording: Bool = false
    
    var hasActiveFilters: Bool {
        dateRange != nil ||
        searchType != .all ||
        !attendees.isEmpty ||
        !groups.isEmpty ||
        minDuration != nil ||
        maxDuration != nil ||
        sentimentRange != nil ||
        hasAudio != nil ||
        hasTranscript != nil ||
        hasSummary != nil ||
        hasRecording
    }
    
    static let empty = SearchFilters()
}

struct SavedSearch: Identifiable, Codable {
    let id: UUID
    let name: String
    let query: String
    let filters: SearchFilters
    let createdAt: Date
}

// MARK: - Search Index

class SearchIndex {
    private var entries: [IndexEntry] = []
    private var keywords: Set<String> = []
    
    var entryCount: Int { entries.count }
    
    struct IndexEntry {
        let id: UUID
        let type: SearchResultType
        let content: String
        let keywords: Set<String>
        let date: Date
    }
    
    static func build(from context: NSManagedObjectContext) async -> SearchIndex {
        let index = SearchIndex()
        
        // Index GroupMeetings
        let meetingRequest: NSFetchRequest<GroupMeeting> = GroupMeeting.fetchRequest()
        if let meetings = try? context.fetch(meetingRequest) {
            for meeting in meetings {
                let content = [
                    meeting.title,
                    meeting.transcript,
                    meeting.summary,
                    meeting.notes
                ].compactMap { $0 }.joined(separator: " ")
                
                let keywords = extractKeywords(from: content)
                
                let entry = IndexEntry(
                    id: meeting.identifier ?? UUID(),
                    type: .groupMeeting,
                    content: content.lowercased(),
                    keywords: keywords,
                    date: meeting.date ?? Date()
                )
                
                index.entries.append(entry)
                index.keywords.formUnion(keywords)
            }
        }
        
        // Index Conversations
        let conversationRequest = Conversation.fetchRequest()
        if let conversations = try? context.fetch(conversationRequest) {
            for conversationObj in conversations {
                guard let conversation = conversationObj as? Conversation else { continue }
                let content = [
                    conversation.notes,
                    conversation.summary
                ].compactMap { $0 }.joined(separator: " ")
                
                let keywords = extractKeywords(from: content)
                
                let entry = IndexEntry(
                    id: conversation.uuid ?? UUID(),
                    type: .conversation,
                    content: content.lowercased(),
                    keywords: keywords,
                    date: conversation.date ?? Date()
                )
                
                index.entries.append(entry)
                index.keywords.formUnion(keywords)
            }
        }
        
        return index
    }
    
    func getSuggestions(for query: String) -> [String] {
        let queryLower = query.lowercased()
        
        return Array(keywords.filter {
            $0.hasPrefix(queryLower) && $0 != queryLower
        }.prefix(5))
    }
    
    private static func extractKeywords(from text: String) -> Set<String> {
        // Simple keyword extraction - can be enhanced with NLP
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: .punctuationCharacters) }
            .filter { $0.count > 3 } // Filter short words
        
        return Set(words)
    }
}

// MARK: - Search View

struct MeetingSearchView: View {
    @StateObject private var searchEngine = MeetingSearchEngine.shared
    @State private var showSavedSearches = false
    @State private var showFilters = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBarView(
                searchText: $searchEngine.searchQuery,
                suggestions: searchEngine.searchSuggestions,
                onSearch: { searchEngine.performSearch() }
            )
            .padding()
            
            // Filters bar
            if showFilters {
                SearchFiltersView(filters: $searchEngine.selectedFilters)
                    .padding(.horizontal)
            }
            
            Divider()
            
            // Results
            if searchEngine.isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchEngine.searchResults.isEmpty && !searchEngine.searchQuery.isEmpty {
                EmptySearchView()
            } else {
                SearchResultsList(results: searchEngine.searchResults)
            }
            
            // Bottom toolbar
            HStack {
                Text("\(searchEngine.searchResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showFilters.toggle() }) {
                    Label("Filters", systemImage: "line.horizontal.3.decrease.circle")
                }
                
                Button(action: { showSavedSearches.toggle() }) {
                    Label("Saved", systemImage: "bookmark")
                }
            }
            .padding()
        }
        .sheet(isPresented: $showSavedSearches) {
            SavedSearchesView(
                savedSearches: searchEngine.savedSearches,
                onSelect: { saved in
                    searchEngine.searchQuery = saved.query
                    searchEngine.selectedFilters = saved.filters
                    searchEngine.performSearch()
                }
            )
        }
    }
}

struct SearchBarView: View {
    @Binding var searchText: String
    let suggestions: [String]
    let onSearch: () -> Void
    @State private var showSuggestions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search meetings and conversations...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit(onSearch)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            if showSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(action: {
                            searchText = suggestion
                            showSuggestions = false
                            onSearch()
                        }) {
                            Text(suggestion)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .offset(y: 4)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextField.textDidChangeNotification)) { _ in
            showSuggestions = !searchText.isEmpty
        }
    }
}

// MARK: - Supporting Views

struct SearchFiltersView: View {
    @Binding var filters: SearchFilters
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Date range filter
                Menu {
                    Button("Any time") { filters.dateRange = nil }
                    Button("Today") { filters.dateRange = .today }
                    Button("This week") { filters.dateRange = .thisWeek }
                    Button("This month") { filters.dateRange = .thisMonth }
                    Button("Last 3 months") { filters.dateRange = .lastThreeMonths }
                } label: {
                    Label(
                        filters.dateRange?.description ?? "Any time",
                        systemImage: "calendar"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Type filter
                Menu {
                    Button("All types") { filters.searchType = .all }
                    Button("Meetings only") { filters.searchType = .meetings }
                    Button("Conversations only") { filters.searchType = .conversations }
                } label: {
                    Label(
                        filters.searchType.description,
                        systemImage: filters.searchType == .meetings ? "video" : "bubble.left.and.bubble.right"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Has recording filter
                Toggle(isOn: $filters.hasRecording) {
                    Label("Has recording", systemImage: "mic.fill")
                }
                .toggleStyle(.button)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Clear filters
                if filters.hasActiveFilters {
                    Button(action: { filters = SearchFilters() }) {
                        Label("Clear filters", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No results found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Try adjusting your search terms or filters")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SearchResultsList: View {
    let results: [SearchResult]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(results) { result in
                    SearchResultRow(result: result)
                }
            }
            .padding()
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.type.isGroupMeeting ? "video.fill" : "bubble.left.and.bubble.right.fill")
                    .foregroundColor(result.type.isGroupMeeting ? .blue : .green)
                
                Text(result.title)
                    .font(.headline)
                
                Spacer()
                
                Text(result.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let snippet = result.snippet {
                Text(snippet)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if !result.participants.isEmpty {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(result.participants.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Show relevance score
            HStack {
                ForEach(0..<5) { index in
                    Image(systemName: index < Int(result.relevanceScore * 5) ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                
                Text("Relevance: \(Int(result.relevanceScore * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            // Handle opening the result
            openSearchResult(result)
        }
    }
    
    private func openSearchResult(_ result: SearchResult) {
        // TODO: Implement navigation to the meeting or conversation
        print("Opening result: \(result.id)")
    }
}

struct SavedSearchesView: View {
    let savedSearches: [SavedSearch]
    let onSelect: (SavedSearch) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Saved Searches")
                .font(.title2)
                .fontWeight(.bold)
            
            if savedSearches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No saved searches")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(savedSearches) { saved in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(saved.name)
                                        .font(.headline)
                                    
                                    Text(saved.query)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Use") {
                                    onSelect(saved)
                                    dismiss()
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

// MARK: - Extensions

extension SearchFilters.DateRange {
    var description: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .thisMonth: return "This month"
        case .lastThreeMonths: return "Last 3 months"
        case .custom: return "Custom range"
        }
    }
}

extension SearchFilters.SearchType {
    var description: String {
        switch self {
        case .all: return "All types"
        case .meetings: return "Meetings"
        case .conversations: return "Conversations"
        }
    }
}