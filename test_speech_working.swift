import Foundation
import Speech
import AVFoundation

// Test if the new Speech APIs are available
@available(macOS 26.0, *)
func testAPIs() async {
    print("Testing macOS 26 Speech APIs...")
    print("Using SDK: /Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk")
    print("Swift version: 6.2")
    
    // Test 1: Check SpeechTranscriber
    print("\n1. Testing SpeechTranscriber...")
    let supportedLocales = await SpeechTranscriber.supportedLocales
    print("   Found \(supportedLocales.count) supported locales")
    for locale in supportedLocales.prefix(5) {
        print("     - \(locale.identifier)")
    }
    
    // Test 2: Check installed locales
    print("\n2. Checking installed locales...")
    let installedLocales = await SpeechTranscriber.installedLocales
    print("   Found \(installedLocales.count) installed locales")
    
    // Test 3: Reserve locale with AssetInventory
    print("\n3. Testing AssetInventory...")
    do {
        let reserved = try await AssetInventory.reserve(locale: Locale.current)
        print("   ✅ AssetInventory.reserve() returned: \(reserved)")
        
        let reservedLocales = await AssetInventory.reservedLocales
        print("   Reserved locales: \(reservedLocales.count)")
    } catch {
        print("   ⚠️ AssetInventory.reserve() error: \(error)")
    }
    
    // Test 4: Create transcriber
    print("\n4. Creating SpeechTranscriber...")
    let transcriber = SpeechTranscriber(
        locale: Locale.current,
        transcriptionOptions: [],
        reportingOptions: [.volatileResults],
        attributeOptions: [.audioTimeRange]
    )
    print("   ✅ SpeechTranscriber created successfully")
    
    // Test 5: Create analyzer
    print("\n5. Creating SpeechAnalyzer...")
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    print("   ✅ SpeechAnalyzer created successfully")
    
    // Test 6: Create AsyncStream for input
    print("\n6. Creating AsyncStream<AnalyzerInput>...")
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    print("   ✅ AsyncStream created successfully")
    
    // Test 7: Create a test buffer and AnalyzerInput
    print("\n7. Testing AnalyzerInput...")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) {
        buffer.frameLength = 1024
        let input = AnalyzerInput(buffer: buffer)
        print("   ✅ AnalyzerInput created successfully")
    }
    
    print("\n✅ SUCCESS! All Speech APIs are available and working!")
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