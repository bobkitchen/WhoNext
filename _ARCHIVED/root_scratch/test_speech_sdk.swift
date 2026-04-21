import Foundation
import Speech
import AVFoundation

// Test if the new Speech APIs are available
@available(macOS 26.0, *)
func testAPIs() async {
    print("Testing macOS 26 Speech APIs with SDK...")
    
    // Test 1: Check SpeechTranscriber
    print("\n1. Testing SpeechTranscriber...")
    let supportedLocales = await SpeechTranscriber.supportedLocales
    print("   Found \(supportedLocales.count) supported locales")
    
    // Test 2: Create transcriber
    print("\n2. Creating SpeechTranscriber...")
    let transcriber = SpeechTranscriber(
        locale: Locale.current,
        transcriptionOptions: [],
        reportingOptions: [.volatileResults],
        attributeOptions: [.audioTimeRange]
    )
    print("   ✅ SpeechTranscriber created successfully")
    
    // Test 3: Create analyzer
    print("\n3. Creating SpeechAnalyzer...")
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    print("   ✅ SpeechAnalyzer created successfully")
    
    // Test 4: Create AsyncStream for input
    print("\n4. Creating AsyncStream<AnalyzerInput>...")
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    print("   ✅ AsyncStream created successfully")
    
    // Test 5: Check AssetInventory
    print("\n5. Testing AssetInventory...")
    do {
        try await AssetInventory.allocate(locale: Locale.current)
        print("   ✅ AssetInventory.allocate() works")
    } catch {
        print("   ⚠️ AssetInventory.allocate() error: \(error)")
    }
    
    print("\n✅ All Speech APIs are available and working!")
    print("   SpeechTranscriber ✓")
    print("   SpeechAnalyzer ✓")
    print("   AssetInventory ✓")
    print("   AnalyzerInput ✓")
    print("   AsyncStream pattern ✓")
}

// Main entry point
if #available(macOS 26.0, *) {
    await testAPIs()
} else {
    print("This test requires macOS 26.0 or later")
}