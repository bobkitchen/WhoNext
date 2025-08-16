import SwiftUI
import WebKit
import CoreData
import PDFKit
import Vision
import CoreImage

struct LinkedInCaptureWindow: View {
    let person: Person
    let onClose: () -> Void
    let onSave: (String) -> Void
    
    @State private var captureState: CaptureState = .browsing
    @State private var capturedContent: String = ""
    @State private var aiSummary: String = ""
    @State private var isProcessing: Bool = false
    @State private var processingError: String?
    @State private var currentWebView: WKWebView?
    @StateObject private var hybridAI = HybridAIService()
    
    enum CaptureState {
        case browsing
        case processing
        case reviewing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main Content
            switch captureState {
            case .browsing:
                linkedInWebView
            case .processing:
                processingView
            case .reviewing:
                reviewView
            }
            
            // Bottom Controls
            bottomControlsView
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("LinkedIn Profile Capture")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Searching for: \(person.name ?? "Unknown")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Close") {
                onClose()
            }
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .background(Color.gray.opacity(0.2))
            .cornerRadius(6)
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
    
    private var linkedInWebView: some View {
        LinkedInWebViewRepresentable(
            searchQuery: constructSearchQuery(),
            onWebViewReady: { webView in
                print("🌐 WebView ready, setting currentWebView")
                DispatchQueue.main.async {
                    currentWebView = webView
                    print("✅ currentWebView set: \(currentWebView != nil)")
                }
            }
        )
    }
    
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                
                Text("Processing LinkedIn Profile...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text("AI is extracting and summarizing profile information")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let error = processingError {
                Text("Error: \(error)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.top, 16)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial.opacity(0.5))
    }
    
    private var reviewView: some View {
        VStack(spacing: 16) {
            // AI Summary Display/Edit
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("AI-Generated Profile Summary")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text("\(aiSummary.count) characters")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Display rendered markdown
                        ProfileContentView(content: aiSummary)
                            .padding(12)
                        
                        Divider()
                            .padding(.horizontal, 12)
                        
                        // Editable text area
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Edit Summary:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            
                            TextEditor(text: $aiSummary)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .frame(minHeight: 150)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                        }
                }
            }
            .padding(16)
        }
    }
    
    private var bottomControlsView: some View {
        HStack {
            switch captureState {
            case .browsing:
                Spacer()
                
                Button("Capture Profile") {
                    print("🔍 Capture Profile button pressed")
                    if let webView = currentWebView {
                        print("✅ WebView found, starting capture")
                        captureLinkedInProfile(webView: webView)
                    } else {
                        print("❌ No WebView available for capture")
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(isProcessing)
                
            case .processing:
                Spacer()
                
                Button("Cancel") {
                    captureState = .browsing
                    isProcessing = false
                }
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
            case .reviewing:
                Button("Back to LinkedIn") {
                    captureState = .browsing
                    aiSummary = ""
                }
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Edit More") {
                        // Keep in review mode for further editing
                    }
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    
                    Button("Save & Close") {
                        onSave(aiSummary)
                        onClose()
                    }
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
    
    private func constructSearchQuery() -> String {
        var query = person.name ?? ""
        if let role = person.role, !role.isEmpty {
            query += " " + role
        }
        return query
    }
    
    private func captureLinkedInProfile(webView: WKWebView) {
        print("🎯 Starting LinkedIn profile capture")
        captureState = .processing
        isProcessing = true
        processingError = nil
        
        // First, capture the web view content
        print("📄 Attempting to capture web view content")
        captureWebViewContent(webView: webView) { result in
            print("📋 Web view capture completed")
            switch result {
            case .success(let capturedText):
                print("✅ Successfully captured text: \(capturedText.prefix(100))...")
                // Now process the actual captured content with AI
                processLinkedInText(capturedText)
            case .failure(let error):
                print("❌ Failed to capture web view content: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.processingError = error.localizedDescription
                }
            }
        }
    }
    
    private func captureWebViewContent(webView: WKWebView, completion: @escaping (Result<String, Error>) -> Void) {
        print("📄 Attempting to capture web view content")
        
        let script = """
        (function() {
            // Extract structured profile data
            var profileData = {
                name: document.querySelector('.pv-text-details__left-panel h1')?.textContent?.trim() || 
                      document.querySelector('.text-heading-xlarge')?.textContent?.trim() || '',
                headline: document.querySelector('.pv-text-details__left-panel .text-body-medium')?.textContent?.trim() || 
                         document.querySelector('.text-body-medium.break-words')?.textContent?.trim() || '',
                location: document.querySelector('.pv-text-details__left-panel .text-body-small')?.textContent?.trim() || '',
                about: document.querySelector('.pv-about-section .pv-about__summary-text')?.textContent?.trim() || '',
                experience: [],
                education: [],
                skills: [],
                photo: document.querySelector('.pv-top-card-section__photo')?.getAttribute('src') || 
                       document.querySelector('.profile-photo-edit__preview')?.getAttribute('src') ||
                       document.querySelector('img[data-anonymize="headshot"]')?.getAttribute('src') ||
                       document.querySelector('.presence-entity__image')?.getAttribute('src') || ''
            };
            
            // Extract experience
            var experienceItems = document.querySelectorAll('.pv-entity__summary-info, .pvs-entity');
            experienceItems.forEach(function(item) {
                var title = item.querySelector('.pv-entity__summary-info-v2 h3, .mr1.t-bold span[aria-hidden="true"]')?.textContent?.trim();
                var company = item.querySelector('.pv-entity__secondary-title, .t-14.t-normal span[aria-hidden="true"]')?.textContent?.trim();
                var duration = item.querySelector('.pv-entity__bullet-item-v2, .t-14.t-normal.t-black--light span[aria-hidden="true"]')?.textContent?.trim();
                
                if (title && company) {
                    profileData.experience.push({
                        title: title,
                        company: company,
                        duration: duration || ''
                    });
                }
            });
            
            // Extract education
            var educationItems = document.querySelectorAll('.pv-education-entity, .pvs-entity');
            educationItems.forEach(function(item) {
                var school = item.querySelector('.pv-entity__school-name, .mr1.hoverable-link-text.t-bold span[aria-hidden="true"]')?.textContent?.trim();
                var degree = item.querySelector('.pv-entity__degree-name, .t-14.t-normal span[aria-hidden="true"]')?.textContent?.trim();
                var field = item.querySelector('.pv-entity__fos, .t-14.t-normal span[aria-hidden="true"]:nth-child(2)')?.textContent?.trim();
                
                if (school) {
                    profileData.education.push({
                        school: school,
                        degree: degree || '',
                        field: field || ''
                    });
                }
            });
            
            // Extract skills
            var skillItems = document.querySelectorAll('.pv-skill-category-entity__name, .pvs-entity__caption-wrapper');
            skillItems.forEach(function(item) {
                var skill = item.textContent?.trim();
                if (skill && skill.length > 0) {
                    profileData.skills.push(skill);
                }
            });
            
            // Get full page text as fallback
            var fullText = document.body.innerText || document.body.textContent || '';
            
            return 'STRUCTURED PROFILE DATA:\\n' + JSON.stringify(profileData, null, 2) + '\\n\\nFULL PAGE TEXT:\\n' + fullText;
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            print("📋 Web view capture completed")
            
            if let error = error {
                print("❌ JavaScript error: \(error)")
                completion(.failure(error))
                return
            }
            
            if let capturedText = result as? String {
                print("✅ Successfully captured text: \(String(capturedText.prefix(100)))...")
                
                // Extract photo URL from the captured data
                self.extractAndSaveProfilePhoto(from: capturedText)
                
                completion(.success(capturedText))
            } else {
                print("❌ No content captured")
                completion(.failure(NSError(domain: "LinkedInCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No content captured from the page"])))
            }
        }
    }
    
    private func extractAndSaveProfilePhoto(from capturedText: String) {
        // Extract photo URL from the structured data
        if let photoURLString = extractPhotoURL(from: capturedText),
           let photoURL = URL(string: photoURLString),
           !photoURLString.isEmpty {
            
            print("🖼️ Found profile photo URL: \(photoURLString)")
            
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: photoURL)
                    
                    await MainActor.run {
                        // Save the image data to the person's avatar
                        self.person.photo = data
                        
                        // Save to Core Data
                        do {
                            try self.person.managedObjectContext?.save()
                            print("✅ Profile photo saved successfully")
                        } catch {
                            print("❌ Failed to save profile photo: \(error)")
                        }
                    }
                } catch {
                    print("❌ Failed to download profile photo: \(error)")
                }
            }
        }
    }
    
    private func extractPhotoURL(from text: String) -> String? {
        // Extract photo URL from JSON structure
        if let range = text.range(of: "\"photo\": \""),
           let endRange = text[range.upperBound...].range(of: "\"") {
            let photoURL = String(text[range.upperBound..<endRange.lowerBound])
            return photoURL.isEmpty ? nil : photoURL
        }
        return nil
    }
    
    private func processLinkedInText(_ capturedText: String) {
        let prompt = """
        Analyze the following LinkedIn profile data and create a comprehensive bullet-point summary for \(person.name ?? "this person").
        
        Format as detailed bullet points:
        
        **Current Role:**
        • [Current position and company with brief description]
        
        **Previous Experience:**
        • [List each previous role with company and brief description]
        • [Include all roles mentioned in the profile]
        • [Format: Title at Company - brief description or timeframe]
        
        **Education:**
        • [List each educational institution and degree/program]
        • [Include all education entries mentioned]
        • [Format: Degree/Program at Institution]
        
        **Skills & Expertise:**
        • [Key areas of expertise and skills mentioned]
        • [Technical skills, languages, certifications]
        
        Be comprehensive - include ALL roles and education mentioned. Keep each bullet point concise but informative. Only include information clearly present in the data.
        
        LinkedIn Profile Data:
        \(capturedText)
        """
        
        Task {
            do {
                let summary = try await hybridAI.sendMessage(prompt, context: "LinkedIn Profile Analysis")
                await MainActor.run {
                    isProcessing = false
                    aiSummary = summary
                    captureState = .reviewing
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - WebView Representative
struct LinkedInWebViewRepresentable: NSViewRepresentable {
    let searchQuery: String
    let onWebViewReady: (WKWebView) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        print("🔧 Creating WKWebView")
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        // Load LinkedIn search
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.linkedin.com/search/results/people/?keywords=\(encodedQuery)"
        
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
            print("📡 Loading LinkedIn URL: \(urlString)")
        }
        
        print("📞 Calling onWebViewReady callback")
        onWebViewReady(webView)
        print("✅ onWebViewReady callback completed")
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Updates if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LinkedInWebViewRepresentable
        
        init(_ parent: LinkedInWebViewRepresentable) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Web view finished loading
        }
    }
}
