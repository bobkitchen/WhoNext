import Foundation
import AppKit

enum LinkedInEnrichmentError: LocalizedError {
    case noApifyToken
    case httpError(Int, String)
    case searchFailed(String)
    case runFailed(String)
    case timeout
    case noResults
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noApifyToken: return "Apify API token not configured. Set it in Settings."
        case .httpError(let code, let body):
            let preview = body.isEmpty ? "<empty body>" : String(body.prefix(300))
            return "Apify HTTP \(code): \(preview)"
        case .searchFailed(let msg): return "LinkedIn search failed: \(msg)"
        case .runFailed(let status): return "Apify run failed with status: \(status)"
        case .timeout: return "Apify enrichment timed out. Try again."
        case .noResults: return "Apify returned no profile data. LinkedIn likely blocked the scraper — retry in a few minutes, or check the actor's run log on apify.com."
        case .decodingError(let msg): return "Failed to parse profile data: \(msg)"
        }
    }
}

@MainActor
class ApifyLinkedInService: ObservableObject {
    static let shared = ApifyLinkedInService()

    private static let apifyBase = "https://api.apify.com/v2"
    // The prior `dataweave~linkedin-profile-scraper` actor started returning
    // `{"error": "API returned status 401: ..."}` for every profile in late
    // April 2026, likely because its upstream credentials lapsed. harvestapi's
    // scraper is actively maintained and uses its own LinkedIn session pool.
    private static let actor = "harvestapi~linkedin-profile-scraper"
    private static let pollInterval: TimeInterval = 3
    private static let maxPollDuration: TimeInterval = 60

    private var apifyToken: String {
        SecureStorage.getAPIKey(for: .apify)
    }

    var hasToken: Bool {
        !apifyToken.isEmpty
    }

    // MARK: - Diagnostic helpers

    /// Throws `.httpError` if the response isn't 2xx, logging the full body so a user
    /// pasting a log can tell 401 (token invalid) apart from 402 (credits), 404
    /// (actor gone), or a schema change.
    nonisolated private static func verifyOK(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            debugLog("❌ [LinkedIn] \(context) HTTP \(http.statusCode): \(body.prefix(500))")
            SessionLog.shared.flush()
            throw LinkedInEnrichmentError.httpError(http.statusCode, body)
        }
        debugLog("🔍 [LinkedIn] \(context) HTTP \(http.statusCode), \(data.count) bytes")
        // Flush so diagnostic output hits disk mid-flow — the 200-entry buffer
        // threshold is useless when the user opens the log file while we're
        // still stuck in the poll loop.
        SessionLog.shared.flush()
    }

    /// Decode, or log the body preview alongside the decoder error so a silent
    /// schema drift at Apify is visible in the log immediately.
    nonisolated private static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? "<non-utf8 body>"
            debugLog("❌ [LinkedIn] \(context) decode failed: \(error). Body: \(preview)")
            SessionLog.shared.flush()
            throw LinkedInEnrichmentError.decodingError("\(context): \(error.localizedDescription). Response: \(preview)")
        }
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

        debugLog("🔍 [LinkedIn] Searching via Apify Google: \(query)")

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

        let (startData, startResp) = try await URLSession.shared.data(for: startRequest)
        try Self.verifyOK(startResp, data: startData, context: "search/start")

        struct ApifyRunResponse: Codable {
            struct RunData: Codable {
                let id: String
                let defaultDatasetId: String
            }
            let data: RunData
        }

        let runResponse = try Self.decodeJSON(ApifyRunResponse.self, from: startData, context: "search/start")
        let runId = runResponse.data.id
        let datasetId = runResponse.data.defaultDatasetId

        debugLog("🔍 [LinkedIn] Search run started: \(runId)")

        // Step 2: Poll for completion
        let startTime = Date()
        while true {
            try await Task.sleep(for: .seconds(Self.pollInterval))

            if Date().timeIntervalSince(startTime) > Self.maxPollDuration {
                throw LinkedInEnrichmentError.timeout
            }

            let pollURL = URL(string: "\(Self.apifyBase)/acts/\(Self.searchActor)/runs/\(runId)?token=\(token)")!
            let (pollData, pollResp) = try await URLSession.shared.data(from: pollURL)
            try Self.verifyOK(pollResp, data: pollData, context: "search/poll")

            struct PollResponse: Codable {
                struct PollData: Codable {
                    let status: String
                }
                let data: PollData
            }

            let pollResponse = try Self.decodeJSON(PollResponse.self, from: pollData, context: "search/poll")
            let status = pollResponse.data.status

            debugLog("🔍 [LinkedIn] Search poll: \(status)")

            if status == "SUCCEEDED" { break }
            if status != "RUNNING" && status != "READY" {
                throw LinkedInEnrichmentError.searchFailed("Google search run failed: \(status)")
            }
        }

        // Step 3: Fetch results
        let resultsURL = URL(string: "\(Self.apifyBase)/datasets/\(datasetId)/items?token=\(token)")!
        let (resultsData, resultsResp) = try await URLSession.shared.data(from: resultsURL)
        try Self.verifyOK(resultsResp, data: resultsData, context: "search/results")

        // Parse Apify Google Search response
        let searchResults = try Self.decodeJSON([GoogleSearchPage].self, from: resultsData, context: "search/results")
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

        debugLog("🔍 [LinkedIn] Found \(candidates.count) candidates")
        if candidates.isEmpty {
            // Empty candidates with a successful run usually means the scraper's
            // response shape shifted. Log enough of the body to diff against code.
            let preview = String(data: resultsData, encoding: .utf8).map { String($0.prefix(800)) } ?? "<non-utf8>"
            debugLog("🔍 [LinkedIn] Zero candidates. Raw results preview: \(preview)")
        }
        for (i, c) in candidates.enumerated() {
            debugLog("🔍 [LinkedIn]   [\(i)] \(c.name) — \(c.url)")
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
        // harvestapi's input shape: `queries` takes either a search term or a
        // full linkedin.com/in/ URL; `profileScraperMode` selects the billing
        // tier. The "no email" tier is cheapest and returns all the fields we
        // map into Person.
        let enrichInput: [String: Any] = [
            "profileScraperMode": "Profile details no email ($4 per 1k)",
            "queries": [url]
        ]
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: enrichInput)

        let (startData, startResp) = try await URLSession.shared.data(for: startRequest)
        try Self.verifyOK(startResp, data: startData, context: "enrich/start")

        struct ApifyRunResponse: Codable {
            struct RunData: Codable {
                let id: String
                let defaultDatasetId: String
            }
            let data: RunData
        }

        let runResponse = try Self.decodeJSON(ApifyRunResponse.self, from: startData, context: "enrich/start")
        let runId = runResponse.data.id
        let datasetId = runResponse.data.defaultDatasetId

        debugLog("🔍 [LinkedIn] Enrich run started: \(runId)")

        // Step 2: Poll for completion
        let startTime = Date()
        while true {
            try await Task.sleep(for: .seconds(Self.pollInterval))

            if Date().timeIntervalSince(startTime) > Self.maxPollDuration {
                throw LinkedInEnrichmentError.timeout
            }

            let pollURL = URL(string: "\(Self.apifyBase)/acts/\(Self.actor)/runs/\(runId)?token=\(token)")!
            let (pollData, pollResp) = try await URLSession.shared.data(from: pollURL)
            try Self.verifyOK(pollResp, data: pollData, context: "enrich/poll")

            struct PollResponse: Codable {
                struct PollData: Codable {
                    let status: String
                }
                let data: PollData
            }

            let pollResponse = try Self.decodeJSON(PollResponse.self, from: pollData, context: "enrich/poll")
            let status = pollResponse.data.status

            debugLog("🔍 [LinkedIn] Enrich poll: \(status)")

            if status == "SUCCEEDED" { break }
            if status != "RUNNING" && status != "READY" {
                throw LinkedInEnrichmentError.runFailed(status)
            }
        }

        // Step 3: Fetch results
        let resultsURL = URL(string: "\(Self.apifyBase)/datasets/\(datasetId)/items?token=\(token)")!
        let (resultsData, resultsResp) = try await URLSession.shared.data(from: resultsURL)
        try Self.verifyOK(resultsResp, data: resultsData, context: "enrich/results")

        // Always log a body preview — enrich results are small (a few KB) and seeing
        // the raw payload is the only way to diagnose a scraper that returns a
        // "successful" run containing just an error stub.
        let bodyPreview = String(data: resultsData, encoding: .utf8).map { String($0.prefix(800)) } ?? "<non-utf8>"
        debugLog("🔍 [LinkedIn] enrich/results body: \(bodyPreview)")

        let profiles = try Self.decodeJSON([LinkedInProfile].self, from: resultsData, context: "enrich/results")
        guard let profile = profiles.first else {
            debugLog("🔍 [LinkedIn] Enrich returned empty array.")
            throw LinkedInEnrichmentError.noResults
        }

        // Every LinkedInProfile field is optional, so a response of [{}] or an
        // error stub like [{"error": "ACCESS_DENIED", "url": "..."}] decodes
        // successfully with every field nil. Treat that as a failure instead of
        // silently "succeeding" with empty data that overwrites nothing.
        let hasData = profile.firstName != nil
            || profile.lastName != nil
            || profile.headline != nil
            || (profile.experience?.isEmpty == false)
        guard hasData else {
            debugLog("❌ [LinkedIn] Enrich decoded but profile has no usable fields — likely anti-bot block.")
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

    func applyProfile(_ profile: LinkedInProfile, to person: Person, linkedinUrl: String, photoData: Data?, isReEnrich: Bool = false) {
        // Current position — only set if empty (don't clobber manual edits)
        if let current = profile.currentPosition {
            if let title = current.position, person.role?.isEmpty ?? true {
                person.role = title
            }
            if let company = current.companyName, person.company?.isEmpty ?? true {
                person.company = company
            }
        }

        // LinkedIn URL
        person.linkedinUrl = linkedinUrl

        // Photo — always update (re-enrich gets fresh photo)
        if let photoData = photoData {
            person.photo = photoData
        }

        // Timezone from location (skip if mapper returns UTC and person already has one)
        if let location = profile.locationText {
            let mapped = TimezoneMapper.mapLocationToTimezone(location)
            if mapped != "UTC" || (person.timezone?.isEmpty ?? true) || person.timezone == "UTC" {
                person.timezone = mapped
            }
        }

        // Notes — replace entirely on re-enrich, set if empty on first enrich
        let markdown = profile.formattedMarkdown()
        if isReEnrich {
            person.notes = markdown
        } else if person.notes?.isEmpty ?? true {
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
