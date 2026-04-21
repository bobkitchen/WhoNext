#!/usr/bin/env swift

import SwiftUI
import AppKit

// Test the enhanced window directly
@main
struct TestEnhancedWindow: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var testMeeting = LiveMeeting()
    @State private var windowController: NSWindowController?
    
    var body: some View {
        VStack {
            Text("Enhanced Window Test")
                .font(.title)
            
            Button("Show Enhanced Window") {
                showEnhancedWindow()
            }
            .padding()
            
            Button("Add Test Transcript") {
                addTestTranscript()
            }
            .padding()
        }
        .frame(width: 300, height: 200)
        .onAppear {
            setupTestData()
        }
    }
    
    func setupTestData() {
        testMeeting.calendarTitle = "Test Meeting"
        testMeeting.isRecording = true
        testMeeting.wordCount = 42
        testMeeting.currentFileSize = 1024 * 1024
        testMeeting.averageConfidence = 0.92
        testMeeting.detectedLanguage = "English"
        testMeeting.speakerTurnCount = 5
        testMeeting.cpuUsage = 12.5
        testMeeting.memoryUsage = 256 * 1024 * 1024
        testMeeting.bufferHealth = .good
        
        // Add some test participants
        let participant1 = IdentifiedParticipant()
        participant1.name = "Alice Johnson"
        participant1.confidence = 0.95
        participant1.isCurrentlySpeaking = true
        participant1.totalSpeakingTime = 125
        testMeeting.identifiedParticipants.append(participant1)
        
        let participant2 = IdentifiedParticipant()
        participant2.name = "Bob Smith"
        participant2.confidence = 0.78
        participant2.totalSpeakingTime = 87
        testMeeting.identifiedParticipants.append(participant2)
    }
    
    func showEnhancedWindow() {
        print("Creating EnhancedLiveMeetingWindowController...")
        
        // Load the EnhancedLiveMeetingWindow
        let windowFile = "/Users/bobkitchen/Documents/GitHub/WhoNext/WhoNext/EnhancedLiveMeetingWindow.swift"
        print("Window file exists: \(FileManager.default.fileExists(atPath: windowFile))")
        
        // Try to create the window directly
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Recording Status - Test"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        
        // Create a simple test view
        let testView = NSHostingView(rootView: TestRecordingView(meeting: testMeeting))
        window.contentView = testView
        
        // Position window
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let xPos = screenFrame.maxX - window.frame.width - 20
            let yPos = screenFrame.maxY - window.frame.height - 20
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        
        print("✅ Enhanced window should be visible!")
    }
    
    func addTestTranscript() {
        let segment = TranscriptSegment(
            text: "This is a test transcript segment at \(Date().formatted())",
            timestamp: testMeeting.duration,
            speakerID: "speaker1",
            speakerName: "Alice Johnson",
            confidence: 0.95,
            isFinalized: true
        )
        testMeeting.addTranscriptSegment(segment)
        testMeeting.duration += 5
        testMeeting.wordCount += 7
        print("Added test transcript segment")
    }
}

// Simplified test view
struct TestRecordingView: View {
    @ObservedObject var meeting: LiveMeeting
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                
                Text("Recording: \(meeting.displayTitle)")
                    .font(.headline)
                
                Spacer()
                
                Text(meeting.formattedDuration)
                    .font(.system(size: 16, design: .monospaced))
            }
            .padding()
            
            // Stats
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(meeting.wordCount) words", systemImage: "text.word.spacing")
                    Spacer()
                    Label("\(meeting.participantCount) speakers", systemImage: "person.2")
                }
                
                if !meeting.transcript.isEmpty {
                    Text("Latest: \(meeting.transcript.last?.text ?? "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 400, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Minimal versions of required models
class LiveMeeting: ObservableObject {
    @Published var isRecording = true
    @Published var duration: TimeInterval = 0
    @Published var transcript: [TranscriptSegment] = []
    @Published var identifiedParticipants: [IdentifiedParticipant] = []
    @Published var wordCount = 0
    @Published var currentFileSize: Int64 = 0
    @Published var averageConfidence: Float = 0
    @Published var detectedLanguage: String?
    @Published var speakerTurnCount = 0
    @Published var overlapCount = 0
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Int64 = 0
    @Published var bufferHealth: BufferHealth = .good
    @Published var droppedFrames = 0
    
    var calendarTitle: String?
    var startTime = Date()
    
    var displayTitle: String {
        calendarTitle ?? "Test Meeting"
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var participantCount: Int {
        identifiedParticipants.count
    }
    
    func addTranscriptSegment(_ segment: TranscriptSegment) {
        transcript.append(segment)
    }
}

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
    let speakerID: String?
    let speakerName: String?
    let confidence: Float
    let isFinalized: Bool
}

class IdentifiedParticipant: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String?
    @Published var confidence: Float = 0
    @Published var isCurrentlySpeaking = false
    @Published var totalSpeakingTime: TimeInterval = 0
}

enum BufferHealth {
    case good, warning, critical
}

print("Test script ready. Run the app to test the enhanced window.")