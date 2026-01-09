import SwiftUI
import WebKit
import CoreData


// MARK: - View Model for WebView Persistence
class WebViewModel: ObservableObject {
    var webView: WKWebView = WKWebView()
    var isConfigured: Bool = false
}

struct LinkedInSearchWindow: View {
    // ... (unchanged properties)
    var personName: String = ""
    var personRole: String? = nil

    let onDataExtracted: (LinkedInProfileData) -> Void
    let onClose: () -> Void

    @State private var captureState: CaptureState = .browsing
    @State private var extractedData: LinkedInProfileData?
    @State private var isProcessing: Bool = false
    @State private var processingError: String?
    @State private var processingStatus: String = "Extracting profile..."
    
    // Use StateObject to keep WebView alive across view updates
    @StateObject private var webViewModel = WebViewModel()
    @State private var debugRawResponse: String = "" // For debugging
    @State private var extractedPhotoURL: String = "" // Captured via JS
    @State private var mainPageOCRText: String = "" // Store main page OCR text
    @State private var hasMainPageCapture: Bool = false // Track if main page was captured
    @State private var debugLog: String = "Monitoring network... (v6)" // DEBUG LOG


    private let aiService = AIService.shared

    enum CaptureState {
        case browsing
        case capturedMain  // New state: main page captured, waiting for experience
        case processing
        case reviewing
    }
    
    // ... (rest of struct)


    // Construct search query from person name and role
    private var searchQuery: String {
        var query = personName
        if let role = personRole, !role.isEmpty {
            query += " " + role
        }
        return query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Main Content
            ZStack {
                // Keep WebView alive and visible
                linkedInWebView
                    .opacity(captureState == .reviewing ? 0 : 1) 

                if captureState == .processing {
                    // Overlay processing status on top of webview (glassy look)
                    // This ensures WebView isn't considered "occluded" by the OS
                    Color.black.opacity(0.3)
                    
                    processingView
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(40)
                        .transition(.opacity)
                }
                
                if captureState == .reviewing {
                    reviewView
                        .background(Color(nsColor: .windowBackgroundColor))
                        .transition(.move(edge: .trailing))
                }
            }

            // Bottom Controls
            bottomControlsView
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LinkedIn Profile Search")
                    .font(.system(size: 18, weight: .semibold))
                if !personName.isEmpty {
                    Text("Searching for: \(personName)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                // DEBUG LOG SCROLL
                ScrollView {
                    Text(debugLog)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(height: 60)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
                .padding(.top, 4)
            }

            Spacer()

            Button("Clear Log") {
                debugLog = "Log cleared."
                debugRawResponse = ""
                extractedData = nil
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
            
            Button("Close") {
                onClose()
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var linkedInWebView: some View {
        VStack(spacing: 12) {
            LinkedInSearchWebView(
                searchQuery: searchQuery,
                viewModel: webViewModel,
                onDataIntercepted: { profile, rawJSON in
                    // NOISE FILTER: LinkedIn sends lots of background data (messenger, notifications).
                    // We only want to react if we successfully parsed a profile, OR if it looks like a profile but failed.
                    
                    if let profile = profile {
                        self.debugRawResponse = rawJSON
                        self.extractedData = profile
                        self.captureState = .reviewing
                        self.isProcessing = false
                        print("🚀 Intercepted Profile: \(profile.name)")
                    } else {
                        // It failed parsing. Is it a profile?
                        // HEURISTIC:
                        // 1. Log everything to the debug log.
                        // 2. Filter messenger/noise/obfuscated data.
                        
                        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                        let snippet = rawJSON.prefix(50).replacingOccurrences(of: "\n", with: " ")
                        
                        // NOISE FILTERS
                        let isMessengerNoise = rawJSON.contains("messengerConversationsBySyncToken") ||
                                               rawJSON.contains("messengerMailboxCounts") ||
                                               rawJSON.contains("typingIndicators")
                        
                        let isObfuscated = rawJSON.contains("\"ob\":") || rawJSON.contains("\"do\":null")
                        
                        // NEW: Ignore massive SDUI / Search Filter Noise
                        let isSDUINoise = rawJSON.contains("proto.sdui.responses") || 
                                          rawJSON.contains("SEARCH_FILTER_")
                        
                        // NEW: Ignore small fragments unless they have "included"
                        let isTooSmall = rawJSON.count < 1000 && !rawJSON.contains("\"included\":[")

                        if isMessengerNoise {
                             // let msg = "[\(timestamp)] 🛑 Ignored Messenger (\(rawJSON.count)b)"
                             // self.debugLog += "\n" + msg
                             return
                        }
                        
                        if isObfuscated {
                             // let msg = "[\(timestamp)] 🛑 Ignored Obfuscated (\(rawJSON.count)b)"
                             // self.debugLog += "\n" + msg
                             return
                        }

                        if isSDUINoise {
                             let msg = "[\(timestamp)] 🛑 Ignored SDUI/Filter Data (\(rawJSON.count)b)"
                             print(msg)
                             self.debugLog += "\n" + msg
                             return
                        }

                        // IGNORE CSS/JS/HTML (Static Assets)
                        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix(":") || trimmed.hasPrefix("@") || trimmed.hasPrefix("<") || 
                           trimmed.hasPrefix("var ") || trimmed.hasPrefix("function") {
                             // let msg = "[\(timestamp)] 🛑 Ignored Static Asset/Code (\(rawJSON.count)b)"
                             // self.debugLog += "\n" + msg
                             return
                        }

                        // Accept almost anything else that has some substance
                        // RELAXED FILTER: If it starts with { or [ and is > 2KB, capture it.
                        let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                        let isLikelyProfile = !isTooSmall && isJSON && (
                                              rawJSON.count > 2000 ||
                                              rawJSON.contains("com.linkedin.voyager.dash.identity.profile.Profile") ||
                                              rawJSON.contains("firstName") ||
                                              rawJSON.contains("\"included\":[") ||
                                              rawJSON.contains("urn:li:fsd_profile")
                        )
                        
                        if isLikelyProfile {
                             let msg = "[\(timestamp)] ✅ CAPTURED DATA (\(rawJSON.count)b): \(snippet)..."
                             print(msg)
                             self.debugLog += "\n" + msg
                             
                             // ACCUMULATE RAW RESPONSES (Don't overwrite)
                             let separator = "\n\n========== [CAPTURE \(timestamp) - \(rawJSON.count)b] ==========\n"
                             self.debugRawResponse += separator + rawJSON
                             
                             // Create dummy data to trigger "Review" state if not already reviewing
                             if self.captureState != .reviewing {
                                 var errorData = LinkedInProfileData(
                                     name: "", headline: "Multiple Captures (See Raw Data)", location: "", about: "",
                                     experience: [], education: [], skills: [], photo: "",
                                     pageUrl: nil, pageTitle: nil
                                 )
                                 self.extractedData = errorData
                                 self.captureState = .reviewing
                                 self.isProcessing = false
                             }
                        } else {
                            let msg = "[\(timestamp)] ➖ Ignored Small/Other (\(rawJSON.count)b): \(snippet)..."
                            print(msg)
                            self.debugLog += "\n" + msg
                        }
                    }
                }
            )
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(processingStatus)
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)

            if let error = processingError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data = extractedData {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Extracted Profile Data")
                            .font(.system(size: 18, weight: .semibold))

                        // Show debug info if data appears empty
                        if data.name.isEmpty && data.experience.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("⚠️ AI returned empty data")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14, weight: .medium))

                                Text("Raw AI Response:")
                                    .font(.system(size: 12, weight: .semibold))

                                ScrollView {
                                    Text(debugRawResponse.isEmpty ? "No response captured" : debugRawResponse)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 200)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                
                                Button(action: {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(debugRawResponse, forType: .string)
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Raw Data to Clipboard")
                                    }
                                }
                                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                                .padding(.top, 4)
                            }
                            .padding(.bottom, 12)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            ProfileDataRow(label: "Name", value: data.name)
                            ProfileDataRow(label: "Job Title", value: data.headline)
                            ProfileDataRow(label: "Location", value: data.location)
                        }

                        if !data.experience.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Experience (\(data.experience.count) roles)")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(Array(data.experience.enumerated()), id: \.offset) { _, exp in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("• \(exp.title)")
                                            .font(.system(size: 12, weight: .medium))
                                        if !exp.company.isEmpty {
                                            Text("  \(exp.company)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        if !exp.duration.isEmpty {
                                            Text("  \(exp.duration)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if !data.education.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Education")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(Array(data.education.enumerated()), id: \.offset) { _, edu in
                                    Text("• \(edu.school)\(edu.degree.isEmpty ? "" : " - \(edu.degree)")")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
    }

    private var bottomControlsView: some View {
        HStack {
            switch captureState {
            case .browsing:
                Spacer()
                
                // Optional manual trigger if interception misses (e.g. cached page)
                Button("Reload Page") {
                    webViewModel.webView.reload()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()

            case .processing:
                Spacer()

            case .reviewing:
                Button("Back to Profile") {
                    // Reset state and go back to browsing
                    mainPageOCRText = ""
                    hasMainPageCapture = false
                    extractedPhotoURL = ""
                    captureState = .browsing
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))

                Spacer()

                Button("Use This Data") {
                    if let data = extractedData {
                        onDataExtracted(data)
                        onClose()
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
            
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}








// MARK: - WebView
// MARK: - WebView
struct LinkedInSearchWebView: NSViewRepresentable {
    let searchQuery: String
    @ObservedObject var viewModel: WebViewModel
    
        // callback: (Profile?, RawJSON) -> Void
    var onDataIntercepted: ((LinkedInProfileData?, String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        // Only configure ONCE to avoid reloading/resetting state
        if !viewModel.isConfigured {
            print("🔧 Configuring WebView with Interceptor...")
            
            // Configure WebKit to intercept network traffic via JS
            let config = WKWebViewConfiguration()
            let userContentController = WKUserContentController()
            
            // INTERCEPTOR SCRIPT: Monkey-patch fetch AND XHR + DOM Scanner + UI Button
            let interceptorScript = """
            (function() {
                if (window.__interceptorInjected) return;
                window.__interceptorInjected = true;
                
                // 1. VISUAL DEBUG OVERLAY (Moved down to not block header)
                const debugDiv = document.createElement('div');
                debugDiv.style.cssText = "position:fixed; top:80px; left:10px; z-index:9999999; background:red; color:white; padding:8px; font-size:12px; font-family:monospace; pointer-events:none; border-radius:4px; box-shadow:0 2px 4px rgba(0,0,0,0.5); max-width:300px; max-height:400px; overflow:hidden;";
                debugDiv.innerText = "Interceptor: READY (v6)";
                document.documentElement.appendChild(debugDiv);
                
                function log(msg, success=false) {
                    console.log("[SwiftInterceptor] " + msg);
                    const line = document.createElement('div');
                    line.innerText = msg;
                    if (success) line.style.color = "#ccffcc";
                    debugDiv.appendChild(line);
                    while (debugDiv.children.length > 8) debugDiv.removeChild(debugDiv.firstChild);
                    
                    if (success) debugDiv.style.background = "#00AA00"; 
                }
                
                log("Interceptor: INJECTED");

                // --- 2. VISIBLE "FORCE SCAN" BUTTON ---
                function injectScannerButton() {
                    if (document.getElementById('gemini-scan-btn')) {
                        // Ensure it's visible
                        document.getElementById('gemini-scan-btn').style.display = 'block';
                        return;
                    }
                    
                    log("Injecting Button...");
                    
                    const btn = document.createElement('button');
                    btn.id = 'gemini-scan-btn';
                    btn.innerText = '🔍 FORCE SCAN DOM';
                    btn.style.position = 'fixed';
                    btn.style.bottom = '20px';
                    btn.style.right = '20px';
                    btn.style.zIndex = '2147483647'; // Max z-index
                    btn.style.padding = '12px 24px';
                    btn.style.backgroundColor = '#cc0000';
                    btn.style.color = 'white';
                    btn.style.border = '2px solid white';
                    btn.style.borderRadius = '8px';
                    btn.style.fontFamily = 'sans-serif';
                    btn.style.fontWeight = 'bold';
                    btn.style.fontSize = '16px';
                    btn.style.cursor = 'pointer';
                    btn.style.boxShadow = '0 6px 12px rgba(0,0,0,0.5)';
                    
                    btn.onclick = function() {
                        btn.innerText = 'Scanning...';
                        btn.style.backgroundColor = '#ff8800';
                        scanDOM('MANUAL_BUTTON');
                        setTimeout(() => {
                             btn.innerText = '🔍 FORCE SCAN DOM';
                             btn.style.backgroundColor = '#cc0000';
                        }, 1000);
                    };
                    
                    document.body.appendChild(btn);
                    log("Button INJECTED!");
                }
                
                // Inject button immediately and on intervals
                setTimeout(injectScannerButton, 500); 
                setInterval(injectScannerButton, 2000);


                // --- 3. DOM SCANNER (SSR Data) ---
                function scanDOM(source) {
                    let foundAny = false;
                    
                    // A. Look for <code> tags (Old Voyager style)
                    const codeTags = document.querySelectorAll('code');
                    codeTags.forEach(code => {
                        const text = code.innerText;
                        if (text.length > 500 && (text.includes('included') || text.includes('urn:li:fsd_profile'))) {
                             log("FOUND CODE (" + text.length + "b)", true);
                             foundAny = true;
                             window.webkit.messageHandlers.interceptor.postMessage({
                                 type: 'dom-code-block-' + source,
                                 body: text
                             });
                        }
                    });
                    
                    // B. Look for <script type="application/ld+json"> (SEO Schema)
                    const ldJsonTags = document.querySelectorAll('script[type="application/ld+json"]');
                    ldJsonTags.forEach(script => {
                        if (script.innerText.length > 100) {
                            log("FOUND LD+JSON (" + script.innerText.length + "b)", true);
                            foundAny = true;
                            window.webkit.messageHandlers.interceptor.postMessage({
                                type: 'dom-ld-json-' + source,
                                body: script.innerText
                            });
                        }
                    });
                    
                    // C. BRUTE FORCE SCRIPT SEARCH
                    const allScripts = document.querySelectorAll('script');
                    allScripts.forEach(script => {
                        const html = script.innerHTML;
                        if (!html || html.length < 500) return;
                        
                        // Look for profile signature (Relaxed: Don't require firstName)
                        if (html.includes('urn:li:fsd_profile') || html.includes('\"included\":[')) {
                             log("FOUND SCRIPT (" + html.length + "b)", true);
                             foundAny = true;
                             window.webkit.messageHandlers.interceptor.postMessage({
                                 type: 'dom-script-deep-' + source,
                                 body: html
                             });
                        }
                    });
                    
                    if (!foundAny && source === 'MANUAL_BUTTON') {
                        log("Scan finished. No new data.", false);
                    }
                }
                
                // ... (Fetch/XHR Patches - Unchanged logic, condensed for brevity) ...
                
                // 4. FETCH PATCH
                const originalFetch = window.fetch;
                window.fetch = async function(...args) {
                    const response = await originalFetch(...args);
                    const url = response.url || "unknown";
                    try {
                        const clone = response.clone();
                        clone.text().then(text => {
                            if (text.length > 500) { 
                                window.webkit.messageHandlers.interceptor.postMessage({
                                    type: 'fetch',
                                    url: url,
                                    body: text
                                });
                            }
                        }).catch(err => {});
                    } catch(e) {}
                    return response;
                };
                
                // 5. XHR PATCH
                const originalOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    this._url = url;
                    return originalOpen.apply(this, arguments);
                };
                const originalSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.send = function(body) {
                    this.addEventListener('load', function() {
                         if (this._url && this.responseText && this.responseText.length > 500) {
                             window.webkit.messageHandlers.interceptor.postMessage({
                                 type: 'xhr',
                                 url: this._url,
                                 body: this.responseText
                             });
                         }
                    });
                    return originalSend.apply(this, arguments);
                };
                
                log("Interceptor v6 LOADED");
            })();
            """
            
            let userScript = WKUserScript(source: interceptorScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
            userContentController.add(context.coordinator, name: "interceptor")
            
            config.userContentController = userContentController
            
            // RE-CREATE WebView with the correct configuration
            let newWebView = WKWebView(frame: .zero, configuration: config)
            viewModel.webView = newWebView
            viewModel.isConfigured = true
        }
        
        let webView = viewModel.webView
        webView.navigationDelegate = context.coordinator
        
        // Only load if not already loaded
        if webView.url == nil {
            var urlString = "https://www.linkedin.com/search/results/people/"
            if !searchQuery.isEmpty {
                let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                urlString += "?keywords=\(encoded)"
            }

            if let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: LinkedInSearchWebView
        
        init(parent: LinkedInSearchWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "interceptor",
                  let dict = message.body as? [String: Any],
                  let jsonString = dict["body"] as? String else { return }
            
            print("Intercepted Voyager Data! Size: \(jsonString.count)")
            
            // Parse asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let profile = self.parseVoyagerJSON(jsonString)
                DispatchQueue.main.async {
                    // Always pass back the raw string for debugging, even if profile is nil
                    self.parent.onDataIntercepted?(profile, jsonString)
                }
            }
        }
        
        // Robust Voyager JSON Parser
        private func parseVoyagerJSON(_ json: String) -> LinkedInProfileData? {
            guard let data = json.data(using: .utf8) else { return nil }
            
            do {
                // Determine structure (single object or collection)
                // Voyager usually returns a root object with 'included' array
                // We'll decode to a generic structure to traverse it
                let root = try JSONDecoder().decode(VoyagerRoot.self, from: data)
                let items = root.included ?? (root.data != nil ? [root.data!] : [])
                
                var collected = LinkedInProfileData(
                    name: "", headline: "", location: "", about: "",
                    experience: [], education: [], skills: [], photo: "",
                    pageUrl: nil, pageTitle: nil
                )
                
                var foundProfile = false
                
                for item in items {
                    // Profile
                    if item.type == "com.linkedin.voyager.dash.identity.profile.Profile" {
                        collected.name = [(item.firstName ?? ""), (item.lastName ?? "")].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        collected.headline = item.headline ?? ""
                        collected.location = item.locationName ?? ""
                        collected.about = item.summary ?? ""
                        // Photo often in 'picture' URN or similar, skipping for now or adding later
                        foundProfile = true
                    }
                    
                    // Experience
                    if item.type == "com.linkedin.voyager.dash.identity.profile.Position" {
                        collected.experience.append(LinkedInProfileData.ExperienceItem(
                            title: item.title ?? "",
                            company: item.companyName ?? "",
                            duration: formatDuration(item.dateRange)
                        ))
                    }
                    
                    // Education
                    if item.type == "com.linkedin.voyager.dash.identity.profile.Education" {
                        collected.education.append(LinkedInProfileData.EducationItem(
                            school: item.schoolName ?? "",
                            degree: item.degreeName ?? "",
                            field: item.fieldOfStudy ?? ""
                        ))
                    }
                }
                
                return foundProfile ? collected : nil
                
            } catch {
                print("Failed to decode Voyager JSON: \(error)")
                return nil
            }
        }
        
        private func formatDuration(_ range: VoyagerDateRange?) -> String {
            guard let range = range, let start = range.start else { return "" }
            let startStr = "\(start.year)\(start.month.map { "-\($0)" } ?? "")"
            let endStr: String
            if let end = range.end {
                endStr = "\(end.year)\(end.month.map { "-\($0)" } ?? "")"
            } else {
                endStr = "Present"
            }
            return "\(startStr) - \(endStr)"
        }
    }
}

// Helper structs for Voyager Decoding
private struct VoyagerRoot: Decodable {
    let included: [VoyagerItem]?
    let data: VoyagerItem?
}

private struct VoyagerItem: Decodable {
    let type: String?
    // Profile fields
    let firstName: String?
    let lastName: String?
    let headline: String?
    let locationName: String?
    let summary: String?
    // Position/Education fields
    let title: String?
    let companyName: String?
    let schoolName: String?
    let degreeName: String?
    let fieldOfStudy: String?
    let dateRange: VoyagerDateRange?
    
    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case firstName, lastName, headline, locationName, summary
        case title, companyName, schoolName, degreeName, fieldOfStudy, dateRange
    }
}

private struct VoyagerDateRange: Decodable {
    let start: VoyagerDate?
    let end: VoyagerDate?
}

private struct VoyagerDate: Decodable {
    let year: Int
    let month: Int?
}

// MARK: - Supporting Views
struct ProfileDataRow: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            HStack {
                Text("\(label):")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12))
                Spacer()
            }
        }
    }
}

// MARK: - Data Models
struct LinkedInProfileData: Codable {
    var name: String
    var headline: String
    var location: String
    var about: String
    var experience: [ExperienceItem]
    var education: [EducationItem]
    var skills: [String]
    var photo: String  // var so we can inject photo URL captured via JS
    var pageUrl: String?
    var pageTitle: String?

    struct ExperienceItem: Codable {
        let title: String
        let company: String
        let duration: String
    }

    struct EducationItem: Codable {
        let school: String
        let degree: String
        let field: String
    }
}

#Preview {
    LinkedInSearchWindow(
        personName: "John Doe",
        personRole: "Engineer",
        onDataExtracted: { _ in },
        onClose: {}
    )
}
