# LinkedIn Data Acquisition — Development Log

## Goal
Given a person's name and job title, find their LinkedIn profile and extract:
- Work history
- Education history
- Profile photo
- Skills
- Summary/bio

Write a structured summary into `person.notes` and download their photo into `person.photo`.

---

## What We've Tried (History)

### Attempt 1: Voyager API Interception (LinkedInSearchWindow.swift)
- **Approach:** Open LinkedIn in WKWebView, inject JavaScript to monkey-patch `window.fetch` and `XMLHttpRequest` to intercept LinkedIn's internal Voyager API responses. Parse JSON looking for `$type` fields like `com.linkedin.voyager.dash.identity.profile.Profile`.
- **Result:** NEVER WORKED. LinkedIn obfuscates API responses, changes `$type` identifiers, and the intercepted data was mostly messenger noise and SDUI fragments. The `parseVoyagerJSON` function almost never found a clean profile match. Debug UI (orange overlay, red "FORCE SCAN DOM" button) was left in the production code.
- **Lesson:** LinkedIn actively prevents this. Even if it worked briefly, it's a maintenance treadmill — LinkedIn changes their internal API format regularly. DO NOT revisit this approach.

### Attempt 2: DOM CSS Selector Scraping (LinkedInCaptureWindow.swift)
- **Approach:** User navigates to a LinkedIn profile in WKWebView, clicks "Capture". JavaScript uses CSS selectors (`.pv-text-details__left-panel h1`, `.pv-entity__summary-info`, `.pv-education-entity`) to extract structured data from the page.
- **Result:** DEAD CODE. These CSS selectors target LinkedIn's pre-2022 frontend. LinkedIn has completely rewritten their frontend in React with different class names. The selectors return nothing. No entry point in the app even opens this window anymore.
- **Lesson:** CSS selector-based scraping breaks every time LinkedIn ships a frontend update (which is frequently). DO NOT use CSS selectors for LinkedIn data extraction.

### Attempt 3: PDF Drop Zone + OCR (CompactLinkedInDropZone + LinkedInPDFProcessor)
- **Approach:** User saves LinkedIn profile as PDF from their browser, drops it into WhoNext. Apple Vision OCR extracts text, AI structures it into markdown.
- **Result:** THIS WORKS. The OCR path is reliable. AI does a good job structuring the text. Timezone auto-detected from location.
- **Limitations:** Manual (user must save PDF first). No photo extraction. Everything goes into `person.notes` as text — no structured fields.
- **Status:** Keep as fallback. Lives in `CompactLinkedInDropZone(1).swift` and `LinkedInPDFProcessor.swift`.

### Attempt 4: People Data Labs API (Researched, NOT implemented)
- **Approach:** Use PDL's person enrichment API (name + title → structured profile data).
- **Result:** REJECTED after research. PDL only has work history for 37.5% of records, education for 30.1%, skills for 6%, NO profile photos ever. Data is months stale. Match accuracy for name+title is poor (confidence 2-5/10). Not worth the API cost or complexity. LinkedIn's own data is dramatically better.
- **Lesson:** Third-party data aggregators don't have the depth needed for pre-meeting briefings. LinkedIn remains the only source with reliably complete, current professional profiles.

---

## Current Approach: Attempt 5 — innerText + AI (February 2026)

### Strategy
Replace the broken LinkedInSearchWindow with a simple, robust flow:

1. **User clicks "Find on LinkedIn"** on a person's detail view
2. **WKWebView opens** with Google search: `site:linkedin.com/in "Name" "Title"`
3. **User clicks through** to the correct LinkedIn profile (solves common-name matching)
4. **User clicks "Capture Profile"**
5. **JavaScript grabs `document.body.innerText`** — the full visible page text. No CSS selectors, no API interception, nothing that breaks when LinkedIn changes their frontend.
6. **JavaScript also extracts the profile photo URL** — find `<img>` tags by size/position heuristics (profile photos are large images near the top of the page)
7. **Send page text to AI** (via existing AIService) to structure into: name, headline, work history, education, skills, summary
8. **Download photo**, populate `person.photo`
9. **Write structured markdown** into `person.notes`, update `person.role`

### Why This Should Be More Robust
- `document.body.innerText` returns whatever text the user can see on screen — it works regardless of LinkedIn's internal HTML structure, React component names, or CSS classes
- AI handles the messy text extraction — it doesn't matter if LinkedIn changes their layout or wording
- The only fragile part is photo URL extraction, and that has a clear fallback (no photo)
- User selects the correct profile manually, eliminating wrong-person matches

### Key Design Decisions
- Rewrite `LinkedInSearchWindow.swift` — remove all Voyager interception code, JS monkey-patching, debug overlays
- Keep `CompactLinkedInDropZone` as a manual PDF fallback
- Mark `LinkedInCaptureWindow.swift` and `LinkedInPDFDropZone.swift` as dead code (consider deleting)

### Files Involved
- `LinkedInSearchWindow.swift` — **REWRITE**: Simple WKWebView + innerText capture + AI structuring
- `PersonDetailView(1).swift` — Entry point for "Find on LinkedIn" button
- `PersonEditView.swift` — Also hosts LinkedIn search sheet
- `AddPersonWindow.swift` / `AddPersonWindowView.swift` — Also host LinkedIn search sheet
- `AIService(1).swift` — Used for structuring the captured text
- `LinkedInPDFProcessor.swift` — Keep as-is (PDF OCR fallback)
- `CompactLinkedInDropZone(1).swift` — Keep as-is (PDF drop fallback)

### What Success Looks Like
- User taps one button, browses to correct profile, taps capture
- Within 5-10 seconds: person.notes has structured work history + education + skills, person.photo has their headshot, person.role is updated
- Works for any LinkedIn profile regardless of LinkedIn's frontend changes
- No debug UI visible to users

### Implementation Status (February 24, 2026)

**BUILT AND COMPILED.** `LinkedInSearchWindow.swift` fully rewritten:
- Removed ALL Voyager interception code (~600 lines of JS monkey-patching, VoyagerRoot/VoyagerItem/VoyagerDate structs, noise filters, debug UI)
- Replaced with clean innerText + AI flow (~380 lines total)
- Google search starts at `site:linkedin.com/in "Name" "Title"` (not LinkedIn search directly)
- "Capture Profile" button runs `document.body.innerText` via `evaluateJavaScript`
- Photo extraction: scans `<img>` tags for `media.licdn.com` URLs with width >= 100px
- AI prompt asks for JSON with name, headline, location, about, experience[], education[], skills[]
- `cleanJSONResponse()` strips markdown fences and extracts JSON object
- `LinkedInProfileData` struct unchanged — callers (`AddPersonWindow`, `AddPersonWindowView`, `PersonEditView`) need no changes
- No debug UI (no orange overlay, no "FORCE SCAN DOM" button, no debug log panel)

**Bug Fix (February 24, 2026) — Google search broken in WKWebView:**
- **Problem:** Google search returned no results in the embedded WKWebView. Google detected the WebView as a non-standard browser and showed a consent/localization wall (Swahili UI in Nairobi) with no actual search results.
- **Root cause:** WKWebView sends a default user agent that Google recognizes as an embedded browser. Google degrades or blocks search results for embedded browsers as a security measure (same policy that blocks OAuth in WebViews since 2021).
- **Fix applied:**
  1. **Switched from Google to LinkedIn's own people search** (`linkedin.com/search/results/people/?keywords=...`) — avoids Google blocking entirely. User needs to be logged into LinkedIn anyway to see full profiles.
  2. **Set Safari user agent** on WKWebView (`customUserAgent`) so LinkedIn and any other site treat it as a real browser.
  3. **Added URL bar** so user can navigate manually if the initial search doesn't find the right person (can paste a LinkedIn URL directly, or try Google in the URL bar).
  4. **Added URL tracking** — the URL bar updates as the user navigates, showing current page.
- **Lesson:** Google actively blocks embedded WKWebView browsers. Never use Google search as the starting point in a WKWebView. Go directly to the target site (LinkedIn) or use DuckDuckGo/Bing as alternatives.

**Bug Fix #2 (February 24, 2026) — JSON decoding crash on missing `photo` key:**
- **Problem:** The AI successfully returned structured JSON (name, headline, experience, education) but didn't include `photo`, `pageUrl`, or `pageTitle` keys. `JSONDecoder` threw `keyNotFound` because `LinkedInProfileData` required all fields.
- **Symptom:** "AI is structuring the profile..." spinner, then silently returns to browsing state. No data placed into person record.
- **Fix:** Added custom `init(from decoder:)` to `LinkedInProfileData` that uses `decodeIfPresent` with defaults for ALL fields. Now any missing key gets a sensible default (empty string/array) instead of crashing.
- **Secondary observation:** Only 895 characters of text were captured from the LinkedIn page. This suggests either: (a) the user was on a minimal profile view that hadn't fully expanded, or (b) LinkedIn's SPA rendering means `innerText` doesn't capture content that hasn't been scrolled into view. Future improvement: add a scroll-to-bottom before capture, or instruct user to expand all sections first.
- **Lesson:** When decoding AI-generated JSON, NEVER use required fields. Always use `decodeIfPresent` with defaults — AI will inevitably omit fields it considers empty or irrelevant.

**Bug Fix #3 (February 24, 2026) — Only 1 of 2 jobs captured (lazy loading):**
- **Problem:** LinkedIn's SPA lazy-loads content as you scroll. `document.body.innerText` only captures what's currently rendered. On a profile with 2 jobs, only 895 chars were captured (should be thousands).
- **Fix:** Before capturing, JavaScript now auto-scrolls the page from top to bottom in steps (300ms per viewport), clicks "show more"/"see more" expand buttons, waits 500ms for rendering, then scrolls back to top before extracting `innerText`. This forces LinkedIn to render all lazy-loaded sections.
- **Lesson:** Always scroll a SPA to the bottom before scraping `innerText`. Lazy loading means what you see is NOT what `innerText` returns.

**Bug Fix #4 (February 24, 2026) — Wrong photo captured (logged-in user's avatar):**
- **Problem:** The photo heuristic grabbed the first large `media.licdn.com` image, which was the logged-in user's avatar in the navbar, not the profile being viewed.
- **Fix:** Photo extraction now walks up the DOM tree to skip images inside `<nav>`, `<header>`, or elements with class names containing `global-nav`, `search-global`, or `feed-identity`. Then picks the largest remaining `media.licdn.com` image (profile photos are typically 200x200+).
- **Lesson:** LinkedIn's nav bar contains the logged-in user's photo. Always filter out nav/header images when looking for the profile subject's photo.

**Bug Fix #5 (February 24, 2026) — Only first job captured, missing full experience/education:**
- **Problem:** LinkedIn profile pages show only the most recent 1-2 experience entries. The rest are behind a "Show all X experiences" link that navigates to a separate page (`/in/username/details/experience/`). Scrolling and clicking "show more" buttons on the main profile page doesn't expand these — they're separate pages.
- **Fix:** Multi-page capture strategy:
  1. Capture main profile page (name, headline, location, about, photo)
  2. Navigate to `/in/username/details/experience/`, scroll to bottom, capture all experience text
  3. Navigate to `/in/username/details/education/`, scroll to bottom, capture all education text
  4. Combine all three page texts and send to AI for structuring
- **Lesson:** LinkedIn profiles are actually multi-page. The main profile is a summary. Full experience and education live on separate `/details/` sub-pages. Any scraping approach must visit these sub-pages to get complete data.

**Bug Fix #6 (February 24, 2026) — Details pages captured 0 chars (navigation timing):**
- **Problem:** Bug fix #5's multi-page strategy navigated to `/details/experience/` correctly but captured **0 chars**. Logs confirmed: `experience details page captured 0 chars`, `education details page captured 0 chars`. The fixed 3-second `DispatchQueue.main.asyncAfter` delay fired before the LinkedIn SPA finished loading and rendering the page content.
- **Root cause:** `webView.load()` is asynchronous. The 3-second timer started immediately when `load()` was called, not when the page finished loading. LinkedIn's SPA pages need time to: (1) complete HTTP navigation, (2) execute JavaScript, (3) render content. On slower connections, 3 seconds wasn't enough for step 1, let alone steps 2-3.
- **Fix:** Replaced fixed delay with `WKNavigationDelegate.didFinish` callback:
  1. Added `onNavigationFinished` callback property to `WebViewModel`
  2. Updated `Coordinator.webView(_:didFinish:)` to fire and clear the callback
  3. `loadDetailsPage` sets the callback BEFORE calling `webView.load()`
  4. When `didFinish` fires (page HTML loaded), wait 2 more seconds for JS rendering, then scroll and capture
  5. Added 12-second timeout fallback in case `didFinish` never fires
  6. Used `CaptureGuard` (reference type) to prevent duplicate captures from both callback and timeout
- **Lesson:** Never use fixed delays for WKWebView page loads — always use the navigation delegate's `didFinish` callback, then add a short delay for SPA JavaScript rendering. LinkedIn pages especially need this since they're heavy SPAs.

**FINAL CONCLUSION (February 24, 2026):**

After 8 bug fixes across the innerText/WKWebView approach, fundamental issues remain:
- LinkedIn's React SPA hides sections from `innerText` in embedded WKWebView browsers
- Details pages (`/details/experience/`, `/details/education/`) frequently return 0 chars
- Navigation timing is unreliable — `didFinish` fires before SPA content renders
- Multi-page capture strategy (main + experience + education pages) adds fragility at each step
- Each bug fix revealed another layer of LinkedIn's anti-scraping behavior

**Verdict:** WKWebView-based extraction is fundamentally broken for LinkedIn's modern SPA. The approach requires too many workarounds and is brittle against LinkedIn's frequent frontend changes. **Abandoned in favor of Attempt 6.**

---

### Attempt 6: Clipboard Paste + AI (February 24, 2026)

**Approach:** User copies text from a LinkedIn profile in their **real browser** (Safari/Chrome), pastes into WhoNext, AI structures it into markdown. Separate "Paste Photo" button for profile images.

**Why this works:**
- The user's real browser has full access to LinkedIn's rendered content (logged in, cookies, JavaScript execution)
- `Cmd+A, Cmd+C` captures ALL visible text including lazy-loaded sections
- No WKWebView, no JavaScript injection, no navigation timing issues
- AI structures the raw text into clean markdown (reuses the proven prompt from PDF OCR)

**Implementation:**
- "Paste Profile Text" button on `PersonDetailView` reads `NSPasteboard.general.string(forType: .string)`
- Validates minimum 200 chars to avoid accidental pastes
- Sends to `AIService.sendMessage()` with prompt adapted from `LinkedInPDFProcessor.parseTextWithAI`
- AI ignores nav bar, footer, "People also viewed", ads — returns clean markdown
- Saves structured markdown to `person.notes`, extracts location for timezone
- "Paste Photo" button reads image from clipboard (user right-clicks photo → Copy Image)

**UI consolidation:**
- LinkedIn import lives **only** on `PersonDetailView` (the main person page)
- Removed all LinkedIn UI from `PersonEditView`, `AddPersonWindow`, `AddPersonWindowView`
- Deleted `LinkedInSearchWindow.swift` (~870 lines of broken WKWebView code)
- Deleted `LinkedInCaptureWindow.swift` (dead since 2022)
- Kept `CompactLinkedInDropZone` and `LinkedInPDFProcessor` as PDF fallback below the paste button

**Advantages over Attempt 5:**
- Zero dependency on WKWebView (eliminates all 8 bug categories)
- Works with any browser the user prefers
- User sees exactly what they're copying (no hidden content issues)
- Photo capture via clipboard is more reliable than DOM image scanning
- Dramatically simpler code (~100 lines vs ~870 lines)

---

## Lessons Learned (Reference for Future Sessions)

1. **Never intercept LinkedIn's internal APIs** — they change constantly and are designed to resist this
2. **Never use CSS selectors on LinkedIn** — the frontend is rebuilt frequently with new class names
3. **`document.body.innerText` is the most robust web scraping primitive** — it returns what the user sees, period
4. **AI is better than parsing** — let the AI structure messy text rather than writing brittle parsers
5. **Manual profile selection beats automated matching** — no API can reliably match "John Smith, Director" to the right person; let the user click the right one
6. **Third-party data providers (PDL etc.) lack depth** — for pre-meeting briefings, LinkedIn is the only source with complete, current data
7. **Keep the PDF drop zone** — it's the most reliable path and serves as a fallback when the WebView approach has issues
8. **Google blocks search in WKWebView** — Google detects embedded browsers and degrades/blocks results. Always go directly to the target site or use the user agent workaround.
9. **Always set a Safari user agent on WKWebView** — without it, sites detect the embedded browser and may block or degrade functionality
10. **Never use fixed delays for WKWebView page loads** — use `WKNavigationDelegate.didFinish` to know when the page has loaded, then add a short delay for SPA JS rendering. Fixed delays (like 3 seconds) are unreliable and connection-speed-dependent.
11. **WKWebView is fundamentally broken for modern SPAs** — after 8 bug fixes, the WKWebView approach still couldn't reliably extract LinkedIn content. LinkedIn's React SPA is designed to work in real browsers, not embedded WebViews. Don't fight the platform.
12. **Let the user's browser do the hard work** — the user's real browser (Safari, Chrome) has full access to logged-in content, cookies, JavaScript execution, and rendered DOM. Clipboard paste leverages all of this without any of the WKWebView complexity.
13. **Consolidate duplicate UI** — LinkedIn import was scattered across PersonDetailView, PersonEditView, AddPersonWindow, and AddPersonWindowView. Having one canonical location (PersonDetailView) eliminates confusion and reduces maintenance burden.
