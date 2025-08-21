#!/usr/bin/env swift

import Foundation
import ScreenCaptureKit
import AVFoundation

@available(macOS 13.0, *)
class SCStreamTest {
    func testAudioOnlyCapture() async {
        print("Testing SCStream audio-only configuration...")
        
        do {
            // Get available content
            let content = try await SCShareableContent.current
            
            // Create minimal filter
            let filter: SCContentFilter
            if let window = content.windows.first {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else if let display = content.displays.first {
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            } else {
                print("❌ No content available")
                return
            }
            
            // Audio-only configuration
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000
            config.channelCount = 1
            
            // Minimal video to prevent errors
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.queueDepth = 1
            config.showsCursor = false
            
            print("✅ Configuration created successfully")
            print("   Audio: \(config.capturesAudio)")
            print("   Video: \(config.width)x\(config.height)")
            print("   Frame interval: \(config.minimumFrameInterval.seconds)s")
            
            // Create stream
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            print("✅ Stream created successfully")
            
            // Start capture
            try await stream.startCapture()
            print("✅ Stream started successfully")
            
            // Run for 2 seconds
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Stop capture
            await stream.stopCapture()
            print("✅ Stream stopped successfully")
            print("🎉 Test completed without SCStream errors!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// Run test
if #available(macOS 13.0, *) {
    let test = SCStreamTest()
    Task {
        await test.testAudioOnlyCapture()
        exit(0)
    }
    RunLoop.main.run()
} else {
    print("ScreenCaptureKit requires macOS 13.0 or later")
    exit(1)
}