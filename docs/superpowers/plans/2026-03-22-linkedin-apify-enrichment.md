# LinkedIn Apify Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual LinkedIn paste import with one-click enrichment: auto-search LinkedIn → pick candidate → Apify scrapes structured data → maps to Person fields.

**Architecture:** New `ApifyLinkedInService` handles DuckDuckGo search and Apify API calls. New `LinkedInProfile` Codable structs decode the response. PersonDetailView gets a simplified "Enrich from LinkedIn" button replacing the paste/PDF UI. Apify token stored in Keychain via existing SecureStorage pattern.

**Tech Stack:** Swift, SwiftUI, Core Data (CloudKit-synced), URLSession, Keychain (SecureStorage)

**Spec:** `docs/superpowers/specs/2026-03-22-linkedin-apify-enrichment-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `WhoNext.xcdatamodeld/.../contents` | Modify | Add `company`, `linkedinUrl` attributes to Person entity |
| `Person.swift` | Modify | Add `@NSManaged` properties + convenience accessors |
| `SecureStorage.swift` | Modify | Add `.apify` case to support Apify token storage |
| `LinkedInProfile.swift` | Create | Codable structs for Apify response + LinkedInCandidate |
| `ApifyLinkedInService.swift` | Create | Search (DuckDuckGo) + Enrich (Apify) + Photo download |
| `PersonDetailView(1).swift` | Modify | Replace LinkedIn import section with Enrich button + state machine |
| `AddPersonWindow.swift` | Modify | Add Company field to person creation form |
| `SettingsView(1).swift` | Modify | Add Apify token field in settings |
| `LinkedInPDFProcessor.swift` | Delete | No longer needed |
| `CompactLinkedInDropZone(1).swift` | Delete | No longer needed |
| `LinkedInPDFDropZone.swift` | Delete | No longer needed |

---

### Task 1: Core Data Model — Add `company` and `linkedinUrl` to Person

**Files:**
- Modify: `WhoNext/WhoNext.xcdatamodeld/WhoNext.xcdatamodel/contents` (before first `<relationship>` in Person entity, ~line 67)
- Modify: `WhoNext/Person.swift` (~line 95, after `voiceSampleCount`)

- [ ] **Step 1: Add attributes to xcdatamodel XML**

In the Person entity, add before the first `<relationship>` tag:
```xml
<attribute name="company" optional="YES" attributeType="String"/>
<attribute name="linkedinUrl" optional="YES" attributeType="String"/>
```

- [ ] **Step 2: Add @NSManaged properties to Person.swift**

After the `voiceSampleCount` declaration (~line 95):
```swift
@NSManaged public var company: String?
@NSManaged public var linkedinUrl: String?
```

- [ ] **Step 3: Build to verify model compiles**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add WhoNext/WhoNext.xcdatamodeld WhoNext/Person.swift
git commit -m "feat: add company and linkedinUrl fields to Person model"
```

---

### Task 2: SecureStorage — Add Apify token support

**Files:**
- Modify: `WhoNext/SecureStorage.swift` (AIProvider enum or add parallel key)
- Modify: `WhoNext/AIService(1).swift` (AIProvider enum, ~line 4)

- [ ] **Step 1: Add `.apify` case to AIProvider enum**

In `AIService(1).swift` (~line 4), add to the enum:
```swift
case apify = "apify"
```

Update `displayName` computed property:
```swift
case .apify: return "Apify"
```

Update `requiresAPIKey`:
```swift
case .openai, .claude, .openrouter, .apify: return true
```

Add a computed property to distinguish AI providers from utility providers (so `.apify` won't appear in AI provider pickers):
```swift
var isAIProvider: Bool {
    switch self {
    case .openai, .claude, .openrouter: return true
    case .apify: return false
    }
}
```

Update any UI that iterates `AIProvider.allCases` for AI model selection to filter with `.filter(\.isAIProvider)`.

- [ ] **Step 2: Add apifyApiKey property to AIService**

After the `openrouterApiKey` property (~line 91):
```swift
var apifyApiKey: String {
    get { SecureStorage.getAPIKey(for: .apify) }
    set { SecureStorage.setAPIKey(newValue, for: .apify) }
}
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add WhoNext/AIService\(1\).swift
git commit -m "feat: add Apify token support to SecureStorage via AIProvider"
```

---

### Task 3: Create LinkedInProfile.swift — Codable structs

**Files:**
- Create: `WhoNext/LinkedInProfile.swift`

- [ ] **Step 1: Create the file with all Codable structs**

```swift
import Foundation

// MARK: - Search Result

struct LinkedInCandidate: Identifiable, Sendable {
    let id = UUID()
    let url: String
    let name: String
    let headline: String
}

// MARK: - Apify Response

struct LinkedInProfile: Codable, Sendable {
    let firstName: String?
    let lastName: String?
    let headline: String?
    let locationName: String?
    let publicIdentifier: String?
    let positions: [LinkedInPosition]?
    let educations: [LinkedInEducation]?
    let skills: [String]?
    let about: String?
    let followerCount: Int?
    let connectionCount: Int?
    let profilePicture: String?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }

    var currentPosition: LinkedInPosition? {
        positions?.first(where: { $0.current == true }) ?? positions?.first
    }

    func formattedMarkdown() -> String {
        var lines: [String] = []

        // Header
        let name = fullName.isEmpty ? "Unknown" : fullName
        lines.append("**\(name)**")
        if let headline = headline {
            lines.append(headline)
        }
        if let location = locationName {
            lines.append("📍 \(location)")
        }

        // About
        if let about = about, !about.isEmpty {
            lines.append("")
            lines.append("## About")
            lines.append(about)
        }

        // Experience
        if let positions = positions, !positions.isEmpty {
            lines.append("")
            lines.append("## Experience")
            for pos in positions {
                let title = pos.title ?? "Unknown Role"
                let company = pos.companyName ?? "Unknown Company"
                lines.append("**\(title)** — \(company)")

                var dateRange = pos.formattedDateRange()
                if let duration = pos.formattedDuration() {
                    dateRange += " (\(duration))"
                }
                if !dateRange.isEmpty {
                    lines.append(dateRange)
                }

                if let desc = pos.description, !desc.isEmpty {
                    lines.append(desc)
                }
                lines.append("")
            }
        }

        // Education
        if let educations = educations, !educations.isEmpty {
            lines.append("## Education")
            for edu in educations {
                let school = edu.schoolName ?? "Unknown School"
                var detail = "**\(school)**"
                let qualParts = [edu.degree, edu.fieldOfStudy].compactMap { $0 }
                if !qualParts.isEmpty {
                    detail += " — \(qualParts.joined(separator: ", "))"
                }
                lines.append(detail)

                if let start = edu.startYear {
                    let end = edu.endYear.map { String($0) } ?? "Present"
                    lines.append("\(start) – \(end)")
                }
                lines.append("")
            }
        }

        // Skills
        if let skills = skills, !skills.isEmpty {
            lines.append("## Skills")
            lines.append(skills.joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }
}

struct LinkedInPosition: Codable, Sendable {
    let title: String?
    let companyName: String?
    let companyUrl: String?
    let startYear: Int?
    let startMonth: Int?
    let endYear: Int?
    let endMonth: Int?
    let durationYear: Int?
    let durationMonth: Int?
    let current: Bool?
    let description: String?

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    func formattedDateRange() -> String {
        guard let startYear = startYear else { return "" }
        let startMonthStr = startMonth.flatMap { m in
            (1...12).contains(m) ? Self.monthNames[m - 1] : nil
        }
        let start = [startMonthStr, String(startYear)].compactMap { $0 }.joined(separator: " ")

        let end: String
        if current == true || endYear == nil {
            end = "Present"
        } else {
            let endMonthStr = endMonth.flatMap { m in
                (1...12).contains(m) ? Self.monthNames[m - 1] : nil
            }
            end = [endMonthStr, endYear.map { String($0) }].compactMap { $0 }.joined(separator: " ")
        }

        return "\(start) – \(end)"
    }

    func formattedDuration() -> String? {
        guard let years = durationYear, let months = durationMonth else { return nil }
        var parts: [String] = []
        if years > 0 { parts.append("\(years) yr\(years == 1 ? "" : "s")") }
        if months > 0 { parts.append("\(months) mo\(months == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct LinkedInEducation: Codable, Sendable {
    let schoolName: String?
    let degree: String?
    let fieldOfStudy: String?
    let startYear: Int?
    let endYear: Int?
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add WhoNext/LinkedInProfile.swift
git commit -m "feat: add LinkedInProfile Codable structs for Apify response"
```

---

### Task 4: Create ApifyLinkedInService.swift — Search + Enrich + Photo

**Files:**
- Create: `WhoNext/ApifyLinkedInService.swift`

- [ ] **Step 1: Create the service file**

```swift
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
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add WhoNext/ApifyLinkedInService.swift
git commit -m "feat: add ApifyLinkedInService with search, enrich, and photo download"
```

---

### Task 5: Settings UI — Add Apify token field

**Files:**
- Modify: `WhoNext/SettingsView(1).swift` (~lines 11-18 for state, ~213-246 for loading/saving, UI section after OpenRouter config)

- [ ] **Step 1: Add state variable**

After `openrouterApiKey` state declaration (~line 13):
```swift
@State private var apifyApiKey: String = ""
```

- [ ] **Step 2: Add onAppear loading**

In the `.onAppear` block (~line 217), add:
```swift
apifyApiKey = SecureStorage.getAPIKey(for: .apify)
```

- [ ] **Step 3: Add onChange saving**

After the last `.onChange(of: openrouterApiKey)` block (~line 246), add:
```swift
.onChange(of: apifyApiKey) { _, newValue in
    if hasLoadedKeys {
        if newValue.isEmpty {
            SecureStorage.clearAPIKey(for: .apify)
        } else {
            SecureStorage.setAPIKey(newValue, for: .apify)
        }
    }
}
```

- [ ] **Step 4: Add UI section**

After the existing AI provider settings section, add a new section:
```swift
// LinkedIn Enrichment
VStack(alignment: .leading, spacing: 12) {
    Text("LinkedIn Enrichment")
        .font(.system(size: 16, weight: .semibold))

    Text("Enrich contacts with LinkedIn profile data via Apify. Get a token at apify.com — $5 free credit (~2,500 profiles).")
        .font(.system(size: 12))
        .foregroundColor(.secondary)

    VStack(alignment: .leading, spacing: 4) {
        Text("Apify API Token")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
        SecureField("apify_api_...", text: $apifyApiKey)
            .textFieldStyle(.roundedBorder)
    }
}
.padding()
.background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
```

- [ ] **Step 5: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add WhoNext/SettingsView\(1\).swift
git commit -m "feat: add Apify token configuration to Settings"
```

---

### Task 6: AddPersonWindow — Add Company field

**Files:**
- Modify: `WhoNext/AddPersonWindow.swift` (~lines 6-14 for state, ~line 103 for form, ~line 206 for save action)

- [ ] **Step 1: Add state variable**

After `editingRole` (~line 7):
```swift
@State private var editingCompany: String = ""
```

- [ ] **Step 2: Add Company field to form**

After the Role `VStack` block (~line 103, after the Role TextField), add:
```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Company / Organization")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
    TextField("Company or organization name", text: $editingCompany)
        .textFieldStyle(.roundedBorder)
}
```

- [ ] **Step 3: Set company on save**

In the "Add Person" button action (~line 206), after `newPerson.role = ...`:
```swift
newPerson.company = editingCompany.trimmingCharacters(in: .whitespacesAndNewlines)
```

- [ ] **Step 4: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add WhoNext/AddPersonWindow.swift
git commit -m "feat: add Company field to Add Person form"
```

---

### Task 8: PersonDetailView — Replace LinkedIn import with Enrich button

> **Dependency:** Task 7 (LinkedInCandidatePickerView) must be completed before this task, since this view references it.

**Files:**
- Modify: `WhoNext/PersonDetailView(1).swift` (replace entire `linkedInImportView` computed property ~lines 229-392, remove paste/process functions ~lines 873-1052)

This is the largest task. It replaces the entire paste-based LinkedIn import UI with the new Enrich flow.

- [ ] **Step 1: Add enrichment state enum and properties**

Near the top of PersonDetailView, add state properties for the enrichment flow:
```swift
// LinkedIn Enrichment
enum LinkedInEnrichState {
    case idle
    case searching
    case selecting([LinkedInCandidate])
    case enriching(String) // URL being enriched
    case success
    case error(String)
}
@State private var enrichState: LinkedInEnrichState = .idle
@State private var showCandidatePicker = false
```

- [ ] **Step 2: Replace linkedInImportView**

Replace the entire `linkedInImportView` computed property (~lines 229-350) with:
```swift
@ViewBuilder
private var linkedInImportView: some View {
    VStack(alignment: .leading, spacing: 12) {
        // Enrich button
        switch enrichState {
        case .idle:
            if person.linkedinUrl != nil {
                Button(action: { reEnrich() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Re-enrich from LinkedIn")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            } else {
                Button(action: { startEnrichment() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14))
                        Text("Enrich from LinkedIn")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching for \(person.name ?? "person") on LinkedIn...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .selecting:
            // Handled by sheet
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Select a profile...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .enriching:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Enriching profile...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("Profile enriched successfully")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                Button("Try Again") { enrichState = .idle }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
        }
    }
    .sheet(isPresented: $showCandidatePicker) {
        if case .selecting(let candidates) = enrichState {
            LinkedInCandidatePickerView(
                candidates: candidates,
                personName: person.name ?? "Unknown",
                onSelect: { candidate in
                    showCandidatePicker = false
                    enrichFromCandidate(candidate)
                },
                onCancel: {
                    showCandidatePicker = false
                    enrichState = .idle
                }
            )
        }
    }
}
```

- [ ] **Step 3: Add enrichment action functions**

Replace the old paste/process functions (~lines 873-1052) with:
```swift
// MARK: - LinkedIn Enrichment

private func startEnrichment() {
    guard ApifyLinkedInService.shared.hasToken else {
        enrichState = .error("Apify API token not configured. Set it in Settings → LinkedIn Enrichment.")
        return
    }

    enrichState = .searching
    let name = person.name ?? ""
    let company = person.company

    Task {
        do {
            let candidates = try await ApifyLinkedInService.shared.searchLinkedInProfiles(name: name, company: company)
            await MainActor.run {
                if candidates.isEmpty {
                    enrichState = .error("No LinkedIn profiles found for \"\(name)\". Check the name and company.")
                } else if candidates.count == 1 {
                    enrichFromCandidate(candidates[0])
                } else {
                    enrichState = .selecting(candidates)
                    showCandidatePicker = true
                }
            }
        } catch {
            await MainActor.run {
                enrichState = .error(error.localizedDescription)
            }
        }
    }
}

private func reEnrich() {
    guard let url = person.linkedinUrl else { return }
    guard ApifyLinkedInService.shared.hasToken else {
        enrichState = .error("Apify API token not configured. Set it in Settings → LinkedIn Enrichment.")
        return
    }

    enrichState = .enriching(url)
    let token = SecureStorage.getAPIKey(for: .apify)

    Task {
        do {
            let profile = try await ApifyLinkedInService.shared.enrichProfile(url: url, token: token)
            let photoData: Data?
            if let photoUrl = profile.profilePicture {
                photoData = try? await ApifyLinkedInService.shared.downloadPhoto(from: photoUrl)
            } else {
                photoData = nil
            }

            await MainActor.run {
                ApifyLinkedInService.shared.applyProfile(profile, to: person, linkedinUrl: url, photoData: photoData)
                try? viewContext.save()
                enrichState = .success
                Task { try? await Task.sleep(for: .seconds(3)); enrichState = .idle }
            }
        } catch {
            await MainActor.run {
                enrichState = .error(error.localizedDescription)
            }
        }
    }
}

private func enrichFromCandidate(_ candidate: LinkedInCandidate) {
    enrichState = .enriching(candidate.url)
    let token = SecureStorage.getAPIKey(for: .apify)

    Task {
        do {
            let profile = try await ApifyLinkedInService.shared.enrichProfile(url: candidate.url, token: token)
            let photoData: Data?
            if let photoUrl = profile.profilePicture {
                photoData = try? await ApifyLinkedInService.shared.downloadPhoto(from: photoUrl)
            } else {
                photoData = nil
            }

            await MainActor.run {
                ApifyLinkedInService.shared.applyProfile(profile, to: person, linkedinUrl: candidate.url, photoData: photoData)
                try? viewContext.save()
                enrichState = .success
                Task { try? await Task.sleep(for: .seconds(3)); enrichState = .idle }
            }
        } catch {
            await MainActor.run {
                enrichState = .error(error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 4: Remove old state variables and functions**

Remove these @State properties (no longer needed):
- `experienceText`
- `educationText`
- `isProcessingProfile`
- `clipboardError`
- `showLinkedInImport`
- `photoSaved`

Remove these functions:
- `pasteExperience()`
- `pasteEducation()`
- `pastePhoto()`
- `processProfile()`
- `structureLinkedInClipboard(experience:education:)`
- `saveLinkedInMarkdown(_:)`
- `extractLocationFromMarkdown(_:)`

- [ ] **Step 5: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED (may need to fix references to removed properties/functions)

- [ ] **Step 6: Commit**

```bash
git add WhoNext/PersonDetailView\(1\).swift
git commit -m "feat: replace LinkedIn paste import with Enrich from LinkedIn button"
```

---

### Task 7: Create LinkedInCandidatePickerView.swift

**Files:**
- Create: `WhoNext/LinkedInCandidatePickerView.swift`

- [ ] **Step 1: Create the picker view**

```swift
import SwiftUI

struct LinkedInCandidatePickerView: View {
    let candidates: [LinkedInCandidate]
    let personName: String
    let onSelect: (LinkedInCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Select LinkedIn Profile")
                    .font(.system(size: 16, weight: .semibold))
                Text("Multiple profiles found for \"\(personName)\". Select the correct one.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Candidate list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(candidates) { candidate in
                        Button(action: { onSelect(candidate) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)

                                if !candidate.headline.isEmpty {
                                    Text(candidate.headline)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Text(candidate.url)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.blue.opacity(0.7))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)

            Divider()

            // Footer
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 420)
    }
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add WhoNext/LinkedInCandidatePickerView.swift
git commit -m "feat: add LinkedIn candidate picker view for search results"
```

---

### Task 9: Delete legacy LinkedIn import files

**Files:**
- Delete: `WhoNext/LinkedInPDFProcessor.swift`
- Delete: `WhoNext/CompactLinkedInDropZone(1).swift`
- Delete: `WhoNext/LinkedInPDFDropZone.swift`

- [ ] **Step 1: Remove files**

```bash
git rm WhoNext/LinkedInPDFProcessor.swift
git rm "WhoNext/CompactLinkedInDropZone(1).swift"
git rm WhoNext/LinkedInPDFDropZone.swift
```

- [ ] **Step 2: Remove Xcode project references**

Open the Xcode project and verify deleted files are not still referenced. If build breaks due to missing file references, remove them from the `.pbxproj` file.

- [ ] **Step 3: Check for remaining references to deleted types**

Search for `LinkedInPDFProcessor`, `CompactLinkedInDropZone`, `LinkedInPDFDropZone` across the codebase. Remove any remaining `import` or usage references.

- [ ] **Step 4: Build to verify**

Run:
```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: remove legacy LinkedIn PDF import files"
```

---

### Task 10: Final integration build + push

- [ ] **Step 1: Clean build**

```bash
xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -configuration Debug clean build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Quick smoke check**

Launch the app and verify:
1. Person detail view shows "Enrich from LinkedIn" button (not the old paste UI)
2. Settings has the Apify token field
3. Add Person form shows Company field
4. Entering a token and clicking Enrich triggers the search flow

- [ ] **Step 3: Push**

```bash
git push
```
