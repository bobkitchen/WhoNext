#!/usr/bin/env /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift

import Foundation
import AVFoundation
import ScreenCaptureKit

@available(macOS 13.0, *)
class AudioCaptureTest {
    private var stream: SCStream?
    
    func testSystemAudioCapture() async {
        print("🧪 Testing System Audio Capture...")
        print("===================================")
        
        do {
            // Test 1: Check screen recording permission
            print("\n1️⃣ Checking screen recording permission...")
            let content = try await SCShareableContent.current
            print("   ✅ Permission granted")
            print("   Available displays: \(content.displays.count)")
            print("   Available windows: \(content.windows.count)")
            
            // Test 2: Create minimal audio configuration
            print("\n2️⃣ Creating audio-only configuration...")
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000
            config.channelCount = 1
            
            // Minimal video to satisfy API requirements
            config.width = 1
            config.height = 1
            config.minimumFrameInterval = CMTime(value: 600, timescale: 1)
            config.queueDepth = 1
            config.showsCursor = false
            
            print("   ✅ Configuration created")
            print("   Audio: \(config.capturesAudio)")
            print("   Sample rate: \(config.sampleRate) Hz")
            print("   Channels: \(config.channelCount)")
            
            // Test 3: Create filter
            print("\n3️⃣ Creating content filter...")
            guard let display = content.displays.first else {
                print("   ❌ No displays available")
                return
            }
            
            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            print("   ✅ Filter created for display")
            
            // Test 4: Create stream
            print("\n4️⃣ Creating SCStream...")
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            guard stream != nil else {
                print("   ❌ Failed to create stream")
                return
            }
            print("   ✅ Stream created successfully")
            
            // Test 5: Add output handler
            print("\n5️⃣ Adding stream output handler...")
            let audioQueue = DispatchQueue(label: "test.audio", qos: .userInitiated)
            
            let outputHandler = TestStreamOutput()
            try stream?.addStreamOutput(outputHandler, type: .audio, sampleHandlerQueue: audioQueue)
            print("   ✅ Output handler added")
            
            // Test 6: Start capture
            print("\n6️⃣ Starting capture...")
            let started = await withCheckedContinuation { continuation in
                stream?.startCapture { error in
                    if let error = error {
                        print("   ❌ Start failed: \(error.localizedDescription)")
                        continuation.resume(returning: false)
                    } else {
                        print("   ✅ Capture started successfully")
                        continuation.resume(returning: true)
                    }
                }
            }
            
            if started {
                print("\n7️⃣ Capturing audio for 3 seconds...")
                try await Task.sleep(nanoseconds: 3_000_000_000)
                
                print("   Received \(outputHandler.samplesReceived) audio samples")
                
                print("\n8️⃣ Stopping capture...")
                stream?.stopCapture { error in
                    if let error = error {
                        print("   ⚠️ Stop error: \(error)")
                    } else {
                        print("   ✅ Capture stopped")
                    }
                }
                
                print("\n✅ All tests passed!")
                print("🎉 System audio capture is working!")
            }
            
        } catch {
            print("\n❌ Test failed: \(error)")
            print("Error type: \(type(of: error))")
            print("Error details: \(error.localizedDescription)")
            
            if (error as NSError).domain == "com.apple.screencapturekit" {
                print("\n⚠️ This might be a screen recording permission issue.")
                print("Please check System Settings > Privacy & Security > Screen Recording")
            }
        }
    }
}

@available(macOS 13.0, *)
class TestStreamOutput: NSObject, SCStreamOutput {
    var samplesReceived = 0
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            samplesReceived += 1
            if samplesReceived == 1 {
                print("   🎵 First audio sample received!")
            }
        }
    }
}

// Run the test
print("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

if #available(macOS 13.0, *) {
    let test = AudioCaptureTest()
    Task {
        await test.testSystemAudioCapture()
        exit(0)
    }
    RunLoop.main.run()
} else {
    print("❌ ScreenCaptureKit requires macOS 13.0 or later")
    exit(1)
}