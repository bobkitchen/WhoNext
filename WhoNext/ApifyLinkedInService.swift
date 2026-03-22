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

    // MARK: - Search via DuckDuckGo

    nonisolated func searchLinkedInProfiles(name: String, company: String?) async throws -> [LinkedInCandidate] {
        var query = "site:linkedin.com/in/ \"\(name)\""
        if let company = company, !company.isEmpty {
            query += " \"\(company)\""
        }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw LinkedInEnrichmentError.searchFailed("Could not construct search URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw LinkedInEnrichmentError.searchFailed("Could not decode search response")
        }

        return parseSearchResults(html: html)
    }

    nonisolated private func parseSearchResults(html: String) -> [LinkedInCandidate] {
        var candidates: [LinkedInCandidate] = []

        // DuckDuckGo HTML results have <a class="result__a" href="...">Title</a>
        // and <a class="result__snippet">Description</a>
        let resultPattern = #"<a[^>]+class="result__a"[^>]+href="([^"]*linkedin\.com/in/[^"]*)"[^>]*>([^<]*)</a>"#
        let snippetPattern = #"<a[^>]+class="result__snippet"[^>]*>([^<]*(?:<[^>]*>[^<]*)*)</a>"#

        guard let resultRegex = try? NSRegularExpression(pattern: resultPattern, options: []),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: []) else {
            return candidates
        }

        let range = NSRange(html.startIndex..., in: html)
        let resultMatches = resultRegex.matches(in: html, options: [], range: range)
        let snippetMatches = snippetRegex.matches(in: html, options: [], range: range)

        for (i, match) in resultMatches.enumerated() {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }

            var urlString = String(html[urlRange])
            // DuckDuckGo wraps URLs in redirects — extract the actual URL
            if let linkedinRange = urlString.range(of: "linkedin.com/in/") {
                let prefix = urlString[..<linkedinRange.lowerBound]
                if prefix.contains("uddg=") || prefix.contains("//duckduckgo.com") {
                    // Extract the linkedin URL from the redirect
                    if let decoded = urlString.removingPercentEncoding,
                       let start = decoded.range(of: "https://www.linkedin.com/in/") ?? decoded.range(of: "https://linkedin.com/in/") {
                        urlString = String(decoded[start.lowerBound...])
                        // Trim any trailing query params from DDG
                        if let ampersand = urlString.firstIndex(of: "&") {
                            urlString = String(urlString[..<ampersand])
                        }
                    }
                }
            }

            // Ensure URL starts with https://
            if !urlString.hasPrefix("http") {
                urlString = "https://\(urlString)"
            }

            let title = String(html[titleRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var headline = ""
            if i < snippetMatches.count {
                if let snippetRange = Range(snippetMatches[i].range(at: 1), in: html) {
                    headline = String(html[snippetRange])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Only include actual LinkedIn profile URLs
            guard urlString.contains("linkedin.com/in/") else { continue }

            candidates.append(LinkedInCandidate(
                url: urlString,
                name: title,
                headline: headline
            ))
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
