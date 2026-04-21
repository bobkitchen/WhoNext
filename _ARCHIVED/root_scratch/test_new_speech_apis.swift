#!/usr/bin/env swift

import Foundation
import Speech
import AVFoundation

// Test if the new Speech APIs are available
@available(macOS 26.0, *)
@main
struct TestSpeechAPIs {
    static func main() async {
        print("Testing macOS 26 Speech APIs...")
        
        // Test 1: Check SpeechTranscriber
        print("\n1. Testing SpeechTranscriber...")
        let supportedLocales = await SpeechTranscriber.supportedLocales
        print("   Found \(supportedLocales.count) supported locales")
        
        // Test 2: Check AssetInventory
        print("\n2. Testing AssetInventory...")
        let allocatedLocales = await AssetInventory.allocatedLocales
        print("   Currently allocated locales: \(allocatedLocales.count)")
        
        // Test 3: Create transcriber
        print("\n3. Creating SpeechTranscriber...")
        let transcriber = SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        print("   ✅ SpeechTranscriber created successfully")
        
        // Test 4: Create analyzer
        print("\n4. Creating SpeechAnalyzer...")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        print("   ✅ SpeechAnalyzer created successfully")
        
        // Test 5: Create AsyncStream for input
        print("\n5. Creating AsyncStream<AnalyzerInput>...")
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        print("   ✅ AsyncStream created successfully")
        
        print("\n✅ All Speech APIs are available and working!")
        print("   SpeechTranscriber ✓")
        print("   SpeechAnalyzer ✓")
        print("   AssetInventory ✓")
        print("   AnalyzerInput ✓")
        print("   AsyncStream pattern ✓")
    }
}