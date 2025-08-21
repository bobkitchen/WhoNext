import Speech
import Foundation

@available(macOS 26.0, *)
func testSpeechAPIs() async {
    print("Testing macOS 26 Speech APIs...")
    
    // Test if SpeechTranscriber exists
    if let transcriber = NSClassFromString("SpeechTranscriber") {
        print("✅ SpeechTranscriber class found: \(transcriber)")
    } else {
        print("❌ SpeechTranscriber class not found")
    }
    
    // Test if SpeechAnalyzer exists
    if let analyzer = NSClassFromString("SpeechAnalyzer") {
        print("✅ SpeechAnalyzer class found: \(analyzer)")
    } else {
        print("❌ SpeechAnalyzer class not found")
    }
    
    // Test if AssetInventory exists
    if let inventory = NSClassFromString("AssetInventory") {
        print("✅ AssetInventory class found: \(inventory)")
    } else {
        print("❌ AssetInventory class not found")
    }
}

// Run the test
if #available(macOS 26.0, *) {
    Task {
        await testSpeechAPIs()
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
} else {
    print("macOS 26 not available")
}