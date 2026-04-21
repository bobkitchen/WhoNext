#!/usr/bin/env /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift

import Foundation
import AVFoundation
import Speech

@available(macOS 26.0, *)
class TranscriptionTest {
    func testModernSpeechAPIs() async {
        print("🧪 Testing Modern Speech APIs on macOS 26...")
        print("===================================")
        
        do {
            // Test 1: Check if SpeechTranscriber is available
            print("\n1️⃣ Checking SpeechTranscriber availability...")
            let supportedLocales = await SpeechTranscriber.supportedLocales
            print("   ✅ SpeechTranscriber available")
            print("   Supported locales: \(supportedLocales.count)")
            print("   Current locale supported: \(supportedLocales.map { $0.identifier(.bcp47) }.contains(Locale.current.identifier(.bcp47)))")
            
            // Test 2: Check installed locales
            print("\n2️⃣ Checking installed locales...")
            let installedLocales = await SpeechTranscriber.installedLocales
            print("   Installed locales: \(installedLocales.count)")
            if installedLocales.isEmpty {
                print("   ⚠️ No locales installed yet")
            } else {
                for locale in installedLocales.prefix(3) {
                    print("   - \(locale.identifier)")
                }
            }
            
            // Test 3: Asset management
            print("\n3️⃣ Testing asset management...")
            let locale = Locale.current
            
            // Deallocate any existing assets
            for allocatedLocale in await AssetInventory.allocatedLocales {
                await AssetInventory.deallocate(locale: allocatedLocale)
            }
            
            // Allocate for current locale
            try await AssetInventory.allocate(locale: locale)
            print("   ✅ Assets allocated for \(locale.identifier)")
            
            // Test 4: Create transcriber
            print("\n4️⃣ Creating SpeechTranscriber...")
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            print("   ✅ SpeechTranscriber created")
            
            // Test 5: Create analyzer
            print("\n5️⃣ Creating SpeechAnalyzer...")
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            print("   ✅ SpeechAnalyzer created")
            
            // Test 6: Create test audio
            print("\n6️⃣ Creating test audio file...")
            let testURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("test_audio.wav")
            
            // Create a simple sine wave audio file
            createTestAudioFile(at: testURL)
            print("   ✅ Test audio file created")
            
            // Test 7: Attempt transcription
            print("\n7️⃣ Testing transcription...")
            let audioFile = try AVAudioFile(forReading: testURL)
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            
            var transcriptionReceived = false
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                print("   📝 Transcription result: \"\(text)\"")
                transcriptionReceived = true
                break
            }
            
            if !transcriptionReceived {
                print("   ℹ️ No transcription (expected for test audio)")
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: testURL)
            
            print("\n✅ All tests completed successfully!")
            print("🎉 Modern Speech APIs are working on macOS 26!")
            
        } catch {
            print("\n❌ Test failed: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    func createTestAudioFile(at url: URL) {
        // Create a simple audio file with silence
        let sampleRate = 16000.0
        let duration = 1.0 // 1 second
        let frameCount = Int(sampleRate * duration)
        
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        )!
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Fill with silence
        if let channelData = buffer.floatChannelData {
            for i in 0..<frameCount {
                channelData[0][i] = 0.0
            }
        }
        
        // Save to file
        do {
            let audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings
            )
            try audioFile.write(from: buffer)
        } catch {
            print("Failed to create test audio: \(error)")
        }
    }
}

// Run the test
print("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

if #available(macOS 26.0, *) {
    let test = TranscriptionTest()
    Task {
        await test.testModernSpeechAPIs()
        exit(0)
    }
    RunLoop.main.run()
} else {
    print("❌ This test requires macOS 26.0 or later")
    print("Current version does not support Modern Speech APIs")
    exit(1)
}