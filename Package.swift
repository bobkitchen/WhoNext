// swift-tools-version: 5.9
// This file documents the Swift Package Manager dependencies needed for Google Calendar integration
// To add these to your Xcode project:
// 1. Open WhoNext.xcodeproj in Xcode
// 2. Select the project in the navigator
// 3. Go to Package Dependencies tab
// 4. Click the + button
// 5. Add each package URL listed below

import PackageDescription

let package = Package(
    name: "WhoNextDependencies",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Existing dependencies (already in project):
        .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.5.0"),
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0"),
        
        // New dependencies for Google Calendar:
        // Google API Client for REST - Calendar
        .package(
            url: "https://github.com/google/google-api-objectivec-client-for-rest.git",
            from: "3.0.0"
        ),
        
        // GTM App Auth for OAuth 2.0
        .package(
            url: "https://github.com/google/GTMAppAuth.git", 
            from: "4.0.0"
        ),
        
        // AppAuth for OAuth (dependency of GTMAppAuth)
        .package(
            url: "https://github.com/openid/AppAuth-iOS.git",
            from: "1.6.0"
        )
    ],
    targets: [
        .target(
            name: "WhoNextDependencies",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Down", package: "Down"),
                .product(name: "GoogleAPIClientForREST_Calendar", package: "google-api-objectivec-client-for-rest"),
                .product(name: "GTMAppAuth", package: "GTMAppAuth"),
                .product(name: "AppAuth", package: "AppAuth-iOS")
            ]
        )
    ]
)

// INSTRUCTIONS FOR ADDING TO XCODE:
// 
// 1. Google API Client:
//    - URL: https://github.com/google/google-api-objectivec-client-for-rest.git
//    - Product: GoogleAPIClientForREST_Calendar
//
// 2. GTMAppAuth:
//    - URL: https://github.com/google/GTMAppAuth.git
//    - Product: GTMAppAuth
//
// 3. AppAuth:
//    - URL: https://github.com/openid/AppAuth-iOS.git
//    - Product: AppAuth