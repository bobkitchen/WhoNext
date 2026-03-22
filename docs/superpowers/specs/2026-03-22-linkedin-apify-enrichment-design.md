# LinkedIn Apify Enrichment — Design Spec

**Date:** 2026-03-22
**Status:** Approved

## Problem

WhoNext's LinkedIn import requires users to manually copy-paste experience/education text from their browser into the app, then wait for an AI call to structure it. Six previous attempts at automated scraping all failed. The result is a clunky multi-step flow that dumps everything into `person.notes` as a markdown blob with no structured field population.

## Solution

Replace the manual paste flow with a one-click **"Enrich from LinkedIn"** button that:

1. Searches Google for the person's LinkedIn profile using their name + company
2. Presents candidate profiles for the user to select (auto-selects if only one match)
3. Calls the Apify `dataweave~linkedin-profile-scraper` to fetch structured profile data
4. Maps structured fields to the Person Core Data record
5. Downloads and stores the profile photo

No AI calls needed — Apify returns structured JSON.

## Core Data Model Changes

Add two fields to the `Person` entity (lightweight migration):

| Field | Type | Purpose |
|-------|------|---------|
| `company` | `String?` | Current organization name |
| `linkedinUrl` | `String?` | Confirmed LinkedIn profile URL |

`company` is user-editable (shown in AddPerson and PersonDetail edit forms). `linkedinUrl` is set automatically by the enrichment flow.

**CloudKit note:** The WhoNext model uses CloudKit syncing. Adding optional attributes to an existing entity is supported by CloudKit automatic schema migration — no manual dashboard changes needed in development mode.

## New Service: ApifyLinkedInService

Single service class with three responsibilities:

### Search

```
searchLinkedInProfiles(name: String, company: String?) async throws -> [LinkedInCandidate]
```

- Uses **DuckDuckGo HTML search** (`https://html.duckduckgo.com/html/?q=...`) — no API key required, no CAPTCHAs, stable HTML format
- Constructs query: `site:linkedin.com/in/ "Name" "Company"`
- Parses the simple HTML response for `linkedin.com/in/` URLs with surrounding snippet text (result titles and descriptions)
- Returns array of `LinkedInCandidate { url, name, headline }`
- Falls back to manual URL entry if search returns no results or fails

### Enrichment

```
enrichProfile(url: String) async throws -> LinkedInProfile
```

- POST to `https://api.apify.com/v2/acts/dataweave~linkedin-profile-scraper/runs?token=TOKEN` with `{ "urls": [url] }`
- Poll `GET .../runs/RUN_ID?token=TOKEN` every 3s until `SUCCEEDED` (60s timeout)
- Fetch results from `GET .../datasets/DATASET_ID/items?token=TOKEN`
- Decode into `LinkedInProfile` struct

### Photo Download

```
downloadPhoto(url: String) async throws -> Data?
```

Downloads profile photo URL, resizes to max 400px, compresses to JPEG at 0.8 quality (matching existing `pastePhoto()` pattern).

### Token Storage

Reads/writes `apifyToken` via the existing `SecureStorage` Keychain mechanism (not UserDefaults — AI service keys were migrated to Keychain via `SecureStorage.swift`). Add a storage key for Apify alongside the existing AI provider keys.

## Data Structs

### LinkedInCandidate

```swift
struct LinkedInCandidate: Identifiable {
    let id = UUID()
    let url: String
    let name: String
    let headline: String
}
```

### LinkedInProfile (Codable)

Maps to Apify response schema:

```swift
struct LinkedInProfile: Codable {
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
}

struct LinkedInPosition: Codable {
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
}

struct LinkedInEducation: Codable {
    let schoolName: String?
    let degree: String?
    let fieldOfStudy: String?
    let startYear: Int?
    let endYear: Int?
}
```

## Field Mapping: Apify → Person

| Apify Field | Person Field | Logic |
|-------------|-------------|-------|
| `positions` where `current == true` → `title` | `person.role` | Current job title |
| `positions` where `current == true` → `companyName` | `person.company` | New field |
| `locationName` | `person.timezone` | Via existing `TimezoneMapper`; skip if mapper returns UTC and person already has a timezone |
| `profilePicture` URL | `person.photo` | Download, compress to JPEG |
| Selected candidate URL | `person.linkedinUrl` | Store confirmed URL |
| All fields | `person.notes` | Formatted markdown (no AI needed). If `person.notes` already has content, prepend a `## LinkedIn Profile` header and append below existing notes with a separator. |

### Notes Markdown Format

```markdown
**Bob Kitchen**
Senior VP, International Programs
📍 New York, New York, United States

## Experience
**Senior VP, International Programs** — International Rescue Committee
Apr 2015 – Present (11 years)

**Director of Operations** — UNICEF
Jan 2010 – Mar 2015 (5 years)

## Education
**University of Cambridge** — International Relations
1998 – 1999

## Skills
Strategic Planning, Humanitarian, Program Management
```

## UI Flow

### Entry Point

On `PersonDetailView`, replace the entire existing LinkedIn import section (paste experience/education, PDF drop zone) with a single **"Enrich from LinkedIn"** button.

### State Machine

```
Idle
  → User taps "Enrich from LinkedIn"
  → If no Apify token: show "Set up LinkedIn enrichment" → navigate to Settings

Searching
  → Spinner: "Searching for {name} on LinkedIn..."
  → Call searchLinkedInProfiles(name, company)
  → If 0 results: "No profiles found" message
  → If 1 result: auto-select, skip to Enriching
  → If 2+ results: show candidate picker

Selecting (sheet/popover)
  → List of candidates: name, headline, URL
  → User taps one to select

Enriching
  → Spinner: "Enriching profile..."
  → Call enrichProfile(url)
  → Download photo

Done
  → Map all data to Person fields
  → Save Core Data context
  → Inline success confirmation
  → PersonDetailView refreshes
```

### Re-enrichment

If `person.linkedinUrl` is already set, the button shows **"Re-enrich from LinkedIn"** and skips search — goes directly to Apify enrichment using the stored URL.

## Settings

Add an **"LinkedIn Enrichment"** section to the existing Settings/Preferences view:

- Apify API Token (secure text field)
- Helper text: "Get a token at apify.com — $5 free credit (~2,500 profiles)"

## Files Changed

| File | Action |
|------|--------|
| `WhoNext.xcdatamodeld` | Add `company`, `linkedinUrl` to Person entity |
| `Person.swift` | Add accessors for new fields |
| `ApifyLinkedInService.swift` | **New** — search + enrich + photo download |
| `LinkedInProfile.swift` | **New** — Codable structs for Apify response |
| `LinkedInCandidatePickerView.swift` | **New** — selection UI for search results |
| `PersonDetailView(1).swift` | Replace LinkedIn import section with Enrich button + states |
| `AddPersonWindow.swift` / `AddPersonView.swift` | Add Company field |
| Settings view | Add Apify token field |
| `LinkedInPDFProcessor.swift` | **Delete** |
| `CompactLinkedInDropZone(1).swift` | **Delete** |
| `LinkedInPDFDropZone.swift` | **Delete** |

## Error Handling

- **No token:** Button prompts to configure in Settings
- **Google search fails:** Show error, offer manual URL entry as escape hatch
- **Apify run fails/times out:** Show error with retry option
- **Profile not found by Apify:** Show "Profile could not be enriched"
- **Photo download fails:** Silently skip — all other fields still populate
- **Sparse data:** Handle all Apify fields as optional; write what's available

## Out of Scope

- Batch enrichment (enrich multiple people at once)
- Automatic periodic re-enrichment
- LinkedIn URL field in the Person edit form (set only by enrichment flow)
- Preserving the paste/PDF import paths (removed per user decision)
