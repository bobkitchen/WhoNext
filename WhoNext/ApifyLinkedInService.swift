import Foundation
import AppKit

enum LinkedInEnrichmentError: LocalizedError {
    case noApifyToken
    case searchFailed(String)
    case runFailed(String)
    case timeout
    case noResults
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noApifyToken: return "Apify API token not configured. Set it in Settings."
        case .searchFailed(let msg): return "LinkedIn search failed: \(msg)"
        case .runFailed(let status): return "Apify run failed with status: \(status)"
        case .timeout: return "Apify enrichment timed out. Try again."
        case .noResults: return "No profile data returned from Apify."
        case .decodingError(let msg): return "Failed to parse profile data: \(msg)"
        }
    }
}

@MainActor
class ApifyLinkedInService: ObservableObject {
    static let shared = ApifyLinkedInService()

    private static let apifyBase = "https://api.apify.com/v2"
    private static let actor = "dataweave~linkedin-profile-scraper"
    private static let pollInterval: TimeInterval = 3
    private static let maxPollDuration: TimeInterval = 60

    private var apifyToken: String {
        SecureStorage.getAPIKey(for: .apify)
    }

    var hasToken: Bool {
        !apifyToken.isEmpty
    }

    // MARK: - Search via Apify Google Search

    private static let searchActor = "apify~google-search-scraper"

    nonisolated func searchLinkedInProfiles(name: String, company: String?, token: String) async throws -> [LinkedInCandidate] {
        guard !token.isEmpty else {
            throw LinkedInEnrichmentError.noApifyToken
        }

        var query = "site:linkedin.com/in/ \"\(name)\""
        if let company = company, !company.isEmpty {
            query += " \"\(company)\""
        }

        print("🔍 [LinkedIn] Searching via Apify Google: \(query)")

        // Step 1: Start Google Search run
        let startURL = URL(string: "\(Self.apifyBase)/acts/\(Self.searchActor)/runs?token=\(token)")!
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let searchInput: [String: Any] = [
            "queries": query,
            "maxPagesPerQuery": 1,
            "resultsPerPage": 5
        ]
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: searchInput)

        let (startData, _) = try await URLSession.shared.data(for: startRequest)

        struct ApifyRunResponse: Codable {
            struct RunData: Codable {
                let id: String
                let defaultDatasetId: String
            }
            let data: RunData
        }

        let runResponse = try JSONDecoder().decode(ApifyRunResponse.self, from: startData)
        let runId = runResponse.data.id
        let datasetId = runResponse.data.defaultDatasetId

        print("🔍 [LinkedIn] Search run started: \(runId)")

        // Step 2: Poll for completion
        let startTime = Date()
        while true {
            try await Task.sleep(for: .seconds(Self.pollInterval))

            if Date().timeIntervalSince(startTime) > Self.maxPollDuration {
                throw LinkedInEnrichmentError.timeout
            }

            let pollURL = URL(string: "\(Self.apifyBase)/acts/\(Self.searchActor)/runs/\(runId)?token=\(token)")!
            let (pollData, _) = try await URLSession.shared.data(from: pollURL)

            struct PollResponse: Codable {
                struct PollData: Codable {
                    let status: String
                }
                let data: PollData
            }

            let pollResponse = try JSONDecoder().decode(PollResponse.self, from: pollData)
            let status = pollResponse.data.status

            print("🔍 [LinkedIn] Search poll: \(status)")

            if status == "SUCCEEDED" { break }
            if status != "RUNNING" && status != "READY" {
                throw LinkedInEnrichmentError.searchFailed("Google search run failed: \(status)")
            }
        }

        // Step 3: Fetch results
        let resultsURL = URL(string: "\(Self.apifyBase)/datasets/\(datasetId)/items?token=\(token)")!
        let (resultsData, _) = try await URLSession.shared.data(from: resultsURL)

        // Parse Apify Google Search response
        let searchResults = try JSONDecoder().decode([GoogleSearchPage].self, from: resultsData)
        var candidates: [LinkedInCandidate] = []

        for page in searchResults {
            for result in (page.organicResults ?? []) {
                guard let url = result.url, url.contains("linkedin.com/in/") else { continue }
                candidates.append(LinkedInCandidate(
                    url: url,
                    name: result.title ?? "Unknown",
                    headline: result.description ?? ""
                ))
            }
        }

        print("🔍 [LinkedIn] Found \(candidates.count) candidates")
        for (i, c) in candidates.enumerated() {
            print("🔍 [LinkedIn]   [\(i)] \(c.name) — \(c.url)")
        }

        return candidates
    }

    // MARK: - Enrich via Apify

    nonisolated func enrichProfile(url: String, token: String) async throws -> LinkedInProfile {
        guard !token.isEmpty else {
            throw LinkedInEnrichmentError.noApifyToken
        }

        // Step 1: Start run
        let startURL = URL(string: "\(Self.apifyBase)/acts/\(Self.actor)/runs?token=\(token)")!
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONEncoder().encode(["urls": [url]])

        let (startData, _) = try await URLSession.shared.data(for: startRequest)

        struct ApifyRunResponse: Codable {
            struct RunData: Codable {
                let id: String
                let defaultDatasetId: String
            }
            let data: RunData
        }

        let runResponse = try JSONDecoder().decode(ApifyRunResponse.self, from: startData)
        let runId = runResponse.data.id
        let datasetId = runResponse.data.defaultDatasetId

        // Step 2: Poll for completion
        let startTime = Date()
        while true {
            try await Task.sleep(for: .seconds(Self.pollInterval))

            if Date().timeIntervalSince(startTime) > Self.maxPollDuration {
                throw LinkedInEnrichmentError.timeout
            }

            let pollURL = URL(string: "\(Self.apifyBase)/acts/\(Self.actor)/runs/\(runId)?token=\(token)")!
            let (pollData, _) = try await URLSession.shared.data(from: pollURL)

            struct PollResponse: Codable {
                struct PollData: Codable {
                    let status: String
                }
                let data: PollData
            }

            let pollResponse = try JSONDecoder().decode(PollResponse.self, from: pollData)
            let status = pollResponse.data.status

            if status == "SUCCEEDED" { break }
            if status != "RUNNING" && status != "READY" {
                throw LinkedInEnrichmentError.runFailed(status)
            }
        }

        // Step 3: Fetch results
        let resultsURL = URL(string: "\(Self.apifyBase)/datasets/\(datasetId)/items?token=\(token)")!
        let (resultsData, _) = try await URLSession.shared.data(from: resultsURL)

        let profiles = try JSONDecoder().decode([LinkedInProfile].self, from: resultsData)
        guard let profile = profiles.first else {
            throw LinkedInEnrichmentError.noResults
        }

        return profile
    }

    // MARK: - Photo Download

    nonisolated func downloadPhoto(from urlString: String) async throws -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data) else { return nil }

        // Resize to max 400px
        let maxDim: CGFloat = 400
        let size = image.size
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }

        return jpeg
    }

    // MARK: - Map to Person

    func applyProfile(_ profile: LinkedInProfile, to person: Person, linkedinUrl: String, photoData: Data?) {
        // Current position
        if let current = profile.currentPosition {
            if let title = current.title {
                person.role = title
            }
            if let company = current.companyName {
                person.company = company
            }
        }

        // LinkedIn URL
        person.linkedinUrl = linkedinUrl

        // Photo
        if let photoData = photoData {
            person.photo = photoData
        }

        // Timezone from location (skip if mapper returns UTC and person already has one)
        if let location = profile.locationName {
            let mapped = TimezoneMapper.mapLocationToTimezone(location)
            if mapped != "UTC" || (person.timezone?.isEmpty ?? true) || person.timezone == "UTC" {
                person.timezone = mapped
            }
        }

        // Notes — append if existing notes, replace if empty
        let markdown = profile.formattedMarkdown()
        if let existingNotes = person.notes, !existingNotes.isEmpty {
            person.notes = existingNotes + "\n\n---\n\n## LinkedIn Profile\n\n" + markdown
        } else {
            person.notes = markdown
        }

        person.modifiedAt = Date()
    }
}

// MARK: - Apify Google Search Response

struct GoogleSearchPage: Codable {
    let organicResults: [GoogleSearchResult]?
}

struct GoogleSearchResult: Codable {
    let title: String?
    let url: String?
    let description: String?
}
