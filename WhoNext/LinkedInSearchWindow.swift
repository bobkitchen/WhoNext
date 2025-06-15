import SwiftUI
import WebKit
import CoreData

struct LinkedInSearchWindow: View {
    let onDataExtracted: (LinkedInProfileData) -> Void
    let onClose: () -> Void
    
    @State private var captureState: CaptureState = .browsing
    @State private var extractedData: LinkedInProfileData?
    @State private var isProcessing: Bool = false
    @State private var processingError: String?
    @State private var currentWebView: WKWebView?
    @State private var isWebViewReady: Bool = false
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
            Text("LinkedIn Profile Search")
                .font(.system(size: 18, weight: .semibold))
            
            Spacer()
            
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
            HStack {
                Text("Search for a LinkedIn profile, then click 'Extract Profile Data' when you find the right person.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            LinkedInWebViewRepresentable(searchQuery: "", onWebViewReady: { webView in
                DispatchQueue.main.async {
                    currentWebView = webView
                    isWebViewReady = true
                    print("🔧 WebView ready, stored reference")
                    print("🔧 isWebViewReady set to: \(isWebViewReady)")
                    print("🔧 currentWebView is nil: \(currentWebView == nil)")
                }
            })
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Extracting profile data...")
                .font(.system(size: 16, weight: .medium))
            
            if let error = processingError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
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
                        
                        Group {
                            ProfileDataRow(label: "Name", value: data.name)
                            ProfileDataRow(label: "Job Title", value: data.headline)
                            ProfileDataRow(label: "Location", value: data.location)
                        }
                        
                        if !data.experience.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Experience")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(data.experience.prefix(3), id: \.title) { exp in
                                    Text("• \(exp.title) at \(exp.company)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                if data.experience.count > 3 {
                                    Text("... and \(data.experience.count - 3) more")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if !data.education.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Education")
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(data.education.prefix(2), id: \.school) { edu in
                                    Text("• \(edu.degree) at \(edu.school)")
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
                
                Button("Extract Profile Data") {
                    print("🔍 Extract Profile Data button clicked")
                    if let webView = currentWebView {
                        print("✅ WebView found, starting extraction")
                        print("🔍 isWebViewReady: \(isWebViewReady)")
                        print("🔍 captureState: \(captureState)")
                        extractProfileData()
                    } else {
                        print("❌ No WebView available for extraction")
                        print("🔍 isWebViewReady: \(isWebViewReady)")
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(
                    variant: isWebViewReady ? .primary : .secondary, 
                    size: .medium
                ))
                .disabled(isProcessing)
                
            case .processing:
                Spacer()
                
            case .reviewing:
                Button("Back to Search") {
                    captureState = .browsing
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()
                
                Button("Use This Data") {
                    if let data = extractedData {
                        onDataExtracted(data)
                        onClose() // Close the LinkedIn window after using the data
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                .disabled(extractedData == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func extractProfileData() {
        print("🚀 Starting profile data extraction...")
        guard let webView = currentWebView else { 
            print("❌ Error: currentWebView is nil")
            processingError = "WebView not ready"
            return 
        }
        
        captureState = .processing
        isProcessing = true
        processingError = nil
        
        print("🔍 Current web view: \(String(describing: webView))")
        print("🔍 Current web view URL: \(String(describing: webView.url))")
        
        captureWebViewContent(webView: webView) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                switch result {
                case .success(let content):
                    print("✅ Extracted content: \(content)")
                    self.parseLinkedInData(content)
                case .failure(let error):
                    print("❌ Error extracting profile data: \(error.localizedDescription)")
                    self.processingError = error.localizedDescription
                    self.captureState = .browsing
                }
            }
        }
    }
    
    private func captureWebViewContent(webView: WKWebView, completion: @escaping (Result<String, Error>) -> Void) {
        print("📄 Attempting to capture web view content")
        
        let script = """
        (function() {
            try {
                console.log('Starting LinkedIn profile extraction...');
                
                // Debug: Log page structure
                console.log('Page URL:', window.location.href);
                console.log('Page title:', document.title);
                
                // Debug: Look for common LinkedIn containers
                var mainContent = document.querySelector('main');
                if (mainContent) {
                    console.log('Found main content area');
                    var headings = mainContent.querySelectorAll('h1, h2');
                    console.log('Found headings:', headings.length);
                    for (var h = 0; h < Math.min(headings.length, 3); h++) {
                        console.log('Heading ' + h + ':', headings[h].textContent.trim());
                    }
                }
                
                // More comprehensive selectors for different LinkedIn page layouts
                var profileData = {
                    name: '',
                    headline: '',
                    location: '',
                    about: '',
                    experience: [],
                    education: [],
                    skills: [],
                    photo: ''
                };
                
                // Try multiple selectors for name
                var nameSelectors = [
                    'h1.text-heading-xlarge',
                    '.text-heading-xlarge',
                    '.pv-text-details__left-panel h1',
                    '.pv-top-card-section__name',
                    '.pv-top-card--list li:first-child',
                    '[data-anonymize="person-name"]',
                    'h1[data-anonymize="person-name"]',
                    '.artdeco-entity-lockup__title h1'
                ];
                
                console.log('Searching for name with selectors:', nameSelectors);
                for (var i = 0; i < nameSelectors.length; i++) {
                    var nameElement = document.querySelector(nameSelectors[i]);
                    console.log('Selector', nameSelectors[i], ':', nameElement ? nameElement.textContent.trim() : 'not found');
                    if (nameElement && nameElement.textContent) {
                        profileData.name = nameElement.textContent.trim();
                        console.log('Found name:', profileData.name);
                        break;
                    }
                }
                
                // Fallback: Extract name from page title
                if (!profileData.name && document.title) {
                    var titleMatch = document.title.match(/^\\(\\d+\\)\\s*(.+?)\\s*\\|\\s*LinkedIn$/);
                    if (titleMatch && titleMatch[1]) {
                        profileData.name = titleMatch[1].trim();
                        console.log('Extracted name from title:', profileData.name);
                    }
                }
                
                // Try multiple selectors for headline
                var headlineSelectors = [
                    '.pv-text-details__left-panel .text-body-medium',
                    '.text-body-medium.break-words',
                    '.pv-top-card-section__headline',
                    '.pv-top-card--list-bullet li:first-child'
                ];
                
                for (var i = 0; i < headlineSelectors.length; i++) {
                    var headlineElement = document.querySelector(headlineSelectors[i]);
                    if (headlineElement && headlineElement.textContent) {
                        profileData.headline = headlineElement.textContent.trim();
                        console.log('Found headline:', profileData.headline);
                        break;
                    }
                }
                
                // Try multiple selectors for location
                var locationSelectors = [
                    '.text-body-small.inline.t-black--light.break-words',
                    '.pv-text-details__left-panel .text-body-small',
                    '.pv-top-card-section__location',
                    '.pv-top-card--list-bullet li:last-child',
                    '.text-body-small[data-anonymize="location"]',
                    '.artdeco-entity-lockup__subtitle .text-body-small'
                ];
                
                console.log('Searching for location with selectors:', locationSelectors);
                for (var i = 0; i < locationSelectors.length; i++) {
                    var locationElement = document.querySelector(locationSelectors[i]);
                    console.log('Location selector', locationSelectors[i], ':', locationElement ? locationElement.textContent.trim() : 'not found');
                    if (locationElement && locationElement.textContent) {
                        profileData.location = locationElement.textContent.trim();
                        console.log('Found location:', profileData.location);
                        break;
                    }
                }
                
                // Try to get about section
                var aboutSelectors = [
                    '.pv-about-section .pv-about__summary-text',
                    '.pv-about__summary-text',
                    '.pv-about-section .inline-show-more-text'
                ];
                
                for (var i = 0; i < aboutSelectors.length; i++) {
                    var aboutElement = document.querySelector(aboutSelectors[i]);
                    if (aboutElement && aboutElement.textContent) {
                        profileData.about = aboutElement.textContent.trim();
                        console.log('Found about:', profileData.about.substring(0, 100) + '...');
                        break;
                    }
                }
                
                // Extract photo using modern LinkedIn selectors
                profileData.photo = document.querySelector('img.pv-top-card-profile-picture__image')?.getAttribute('src') || 
                       document.querySelector('img[data-anonymize="headshot"]')?.getAttribute('src') ||
                       document.querySelector('.profile-photo-edit__preview')?.getAttribute('src') ||
                       document.querySelector('.pv-top-card-section__photo')?.getAttribute('src') ||
                       document.querySelector('.presence-entity__image')?.getAttribute('src') || '';
                
                // Extract experience using modern LinkedIn selectors
                console.log('🔍 Starting experience extraction...');
                var experienceItems = document.querySelectorAll('[data-view-name="profile-component-entity"]');
                console.log('Found', experienceItems.length, 'profile component entities');
                
                experienceItems.forEach(function(item, index) {
                    // Check if this is an experience item
                    var hasExperienceIndicator = item.querySelector('[data-field="experience_company_logo"]') || 
                                               item.querySelector('[aria-label*="Experience"]') ||
                                               item.textContent.includes('Experience');
                    
                    console.log('Item', index, 'has experience indicator:', !!hasExperienceIndicator);
                    
                    if (hasExperienceIndicator) {
                        // Try multiple selectors for title
                        var titleElement = item.querySelector('h3[data-generated-suggestion-target]') ||
                                         item.querySelector('.mr1.t-bold span[aria-hidden="true"]') ||
                                         item.querySelector('h3') ||
                                         item.querySelector('.t-16.t-black.t-bold');
                        
                        // Try multiple selectors for company  
                        var companyElement = item.querySelector('.t-14.t-normal span[aria-hidden="true"]:first-child') ||
                                           item.querySelector('.pv-entity__secondary-title') ||
                                           item.querySelector('.t-14.t-normal.t-black--light span[aria-hidden="true"]');
                        
                        // Try multiple selectors for duration
                        var durationElement = item.querySelector('.t-14.t-normal.t-black--light span[aria-hidden="true"]') ||
                                            item.querySelector('.pv-entity__bullet-item-v2') ||
                                            item.querySelector('.t-12.t-black--light.t-normal span[aria-hidden="true"]');
                        
                        var title = titleElement ? titleElement.textContent.trim() : '';
                        var company = companyElement ? companyElement.textContent.trim() : '';
                        var duration = durationElement ? durationElement.textContent.trim() : '';
                        
                        console.log('Experience item:', { title, company, duration });
                        
                        if (title || company) {
                            profileData.experience.push({
                                title: title,
                                company: company,
                                duration: duration || ''
                            });
                        }
                    }
                });
                
                // Extract education - try multiple approaches
                console.log('Starting education extraction...');
                
                // First try traditional selectors
                var educationSections = document.querySelectorAll('[data-view-name="profile-component-entity"]');
                var foundEducation = false;
                
                educationSections.forEach(function(section) {
                    var sectionText = section.textContent || '';
                    if (sectionText.includes('Education') || 
                        sectionText.includes('University') || 
                        sectionText.includes('College') || 
                        sectionText.includes('School')) {
                        
                        var items = section.querySelectorAll('.pvs-entity');
                        items.forEach(function(item) {
                            var schoolElement = item.querySelector('span[aria-hidden="true"]');
                            var school = schoolElement ? schoolElement.textContent.trim() : '';
                            
                            if (school && school.length > 3 && school.length < 100 && 
                                !school.includes('notifications') && 
                                !school.includes('data') &&
                                !school.includes('{')) {
                                
                                console.log('Found education (traditional):', school);
                                profileData.education.push({
                                    school: school,
                                    degree: '',
                                    field: ''
                                });
                                foundEducation = true;
                            }
                        });
                    }
                });
                
                // If no education found, try text-based approach
                if (!foundEducation) {
                    console.log('No education found with traditional selectors, trying text approach...');
                    
                    var textElements = document.querySelectorAll('span, div');
                    var educationKeywords = ['University', 'College', 'School', 'Institute', 'Academy'];
                    
                    for (var i = 0; i < textElements.length; i++) {
                        var element = textElements[i];
                        var text = element.textContent ? element.textContent.trim() : '';
                        
                        // Look for education institution names
                        for (var j = 0; j < educationKeywords.length; j++) {
                            if (text.includes(educationKeywords[j]) && 
                                text.length > 10 && 
                                text.length < 80 &&
                                !text.includes('notifications') &&
                                !text.includes('data') &&
                                !text.includes('{') &&
                                !text.includes('urn:') &&
                                !text.includes('$type')) {
                                
                                console.log('Found education (text):', text);
                                profileData.education.push({
                                    school: text,
                                    degree: '',
                                    field: ''
                                });
                                foundEducation = true;
                                break;
                            }
                        }
                        
                        if (profileData.education.length >= 5) break; // Limit to 5 entries
                    }
                }
                
                // Remove duplicates
                var uniqueEducation = [];
                var seenSchools = {};
                for (var i = 0; i < profileData.education.length; i++) {
                    var edu = profileData.education[i];
                    if (!seenSchools[edu.school.toLowerCase()]) {
                        seenSchools[edu.school.toLowerCase()] = true;
                        uniqueEducation.push(edu);
                    }
                }
                profileData.education = uniqueEducation;
                
                // Extract skills - look for skills section
                console.log('Starting skills extraction...');
                
                // First try to find the skills section specifically
                var skillsSections = document.querySelectorAll('[data-view-name="profile-component-entity"]');
                var foundSkills = false;
                
                skillsSections.forEach(function(section) {
                    var sectionText = section.textContent || '';
                    if (sectionText.toLowerCase().includes('skills')) {
                        var skillItems = section.querySelectorAll('.pvs-entity span[aria-hidden="true"]');
                        
                        skillItems.forEach(function(item) {
                            var skill = item.textContent ? item.textContent.trim() : '';
                            
                            if (skill && 
                                skill.length > 2 && 
                                skill.length < 40 && 
                                !skill.includes('Skills') &&
                                !skill.includes('endorsement') &&
                                !skill.includes('Show all') &&
                                !skill.includes('·') &&
                                !skill.includes('followers') &&
                                !skill.includes('connections') &&
                                !skill.includes('notifications') &&
                                !skill.includes('data') &&
                                !skill.includes('{') &&
                                !/\\d{4}/.test(skill)) {
                                
                                console.log('Found skill (traditional):', skill);
                                profileData.skills.push(skill);
                                foundSkills = true;
                            }
                        });
                    }
                });
                
                // If no skills found with traditional approach, try alternative
                if (!foundSkills || profileData.skills.length === 0) {
                    console.log('No skills found with traditional selectors, trying alternative approach...');
                    
                    // Look for elements that might contain skills near "Skills" text
                    var allSpans = document.querySelectorAll('span');
                    var skillsContext = false;
                    
                    for (var i = 0; i < allSpans.length; i++) {
                        var span = allSpans[i];
                        var text = span.textContent ? span.textContent.trim() : '';
                        
                        // Check if we're in a skills context
                        if (text.toLowerCase() === 'skills') {
                            skillsContext = true;
                            continue;
                        }
                        
                        // If we're in skills context, look for potential skills
                        if (skillsContext && text && 
                            text.length > 2 && 
                            text.length < 30 &&
                            !text.includes('Show all') &&
                            !text.includes('endorsement') &&
                            !text.includes('·') &&
                            !text.includes('followers') &&
                            !text.includes('connections') &&
                            !text.includes('years') &&
                            !text.includes('months') &&
                            !text.includes('@') &&
                            !text.includes('http') &&
                            !text.includes('notifications') &&
                            !text.includes('data') &&
                            !text.includes('{') &&
                            !/\\d{4}/.test(text) &&
                            !/\\d+\\s*(yr|mo)/.test(text)) {
                            
                            console.log('Found skill (alternative):', text);
                            profileData.skills.push(text);
                        }
                        
                        // Reset context if we've moved too far
                        if (skillsContext && profileData.skills.length > 0 && 
                            (text.includes('Experience') || text.includes('Education') || text.includes('About'))) {
                            break;
                        }
                        
                        if (profileData.skills.length >= 15) break; // Limit to 15 skills
                    }
                }
                
                // Remove duplicates and clean up
                var uniqueSkills = [...new Set(profileData.skills)];
                profileData.skills = uniqueSkills.slice(0, 15); // Limit to 15 skills
                
                // Get current page URL and title for debugging
                profileData.pageUrl = window.location.href;
                profileData.pageTitle = document.title;
                
                console.log('Profile extraction completed:', profileData);
                return JSON.stringify(profileData);
                
            } catch (error) {
                console.error('Error extracting profile data:', error);
                return JSON.stringify({ 
                    error: error.message,
                    pageUrl: window.location.href,
                    pageTitle: document.title
                });
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("❌ JavaScript execution error: \(error)")
                completion(.failure(error))
            } else if let jsonString = result as? String {
                print("📊 JavaScript result: \(jsonString)")
                
                // Check if it's an error response
                if let errorData = try? JSONDecoder().decode([String: String].self, from: Data(jsonString.utf8)),
                   let errorMessage = errorData["error"] {
                    print("❌ JavaScript error: \(errorMessage)")
                    completion(.failure(NSError(domain: "LinkedInSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "JavaScript error: \(errorMessage)"])))
                } else {
                    completion(.success(jsonString))
                }
            } else {
                print("❌ No result from JavaScript")
                completion(.failure(NSError(domain: "LinkedInSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "No result from JavaScript execution"])))
            }
        }
    }
    
    private func parseLinkedInData(_ jsonString: String) {
        print("🔍 Parsing LinkedIn data: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert JSON string to data")
            processingError = "Failed to parse extracted data"
            captureState = .browsing
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let data = try decoder.decode(LinkedInProfileData.self, from: jsonData)
            print("✅ Successfully decoded profile data:")
            print("   📝 Name: '\(data.name)'")
            print("   💼 Headline: '\(data.headline)'")
            print("   📍 Location: '\(data.location)'")
            print("   📄 About: '\(data.about.prefix(100))...'")
            print("   💼 Experience: \(data.experience.count) items")
            print("   🎓 Education: \(data.education.count) items")
            print("   🔧 Skills: \(data.skills.count) items")
            print("   📸 Photo: '\(data.photo.isEmpty ? "No photo" : "Has photo")'")
            print("   📊 Page URL: '\(data.pageUrl ?? "No URL")'")
            print("   📊 Page Title: '\(data.pageTitle ?? "No title")'")
            extractedData = data
            captureState = .reviewing
        } catch {
            print("❌ Failed to decode profile data: \(error)")
            processingError = "Failed to decode profile data: \(error.localizedDescription)"
            captureState = .browsing
        }
    }
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
    let name: String
    let headline: String
    let location: String
    let about: String
    let experience: [ExperienceItem]
    let education: [EducationItem]
    let skills: [String]
    let photo: String
    
    // Optional debugging fields
    let pageUrl: String?
    let pageTitle: String?
    
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
        onDataExtracted: { data in
            print("Extracted: \(data.name)")
        },
        onClose: {
            print("Closed")
        }
    )
}
