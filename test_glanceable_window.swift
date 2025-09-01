#!/usr/bin/env swift

import SwiftUI
import AppKit

// Test the glanceable window directly
@main
struct TestGlanceableWindow: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var testMeeting = TestLiveMeeting()
    @State private var windowController: NSWindowController?
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Glanceable Window Test")
                .font(.title)
            
            Button("Show Glanceable Window") {
                showGlanceableWindow()
            }
            .padding()
            
            HStack(spacing: 20) {
                Button("Add Transcript") {
                    addTestTranscript()
                }
                
                Button("Toggle Speaker") {
                    toggleSpeaker()
                }
                
                Button("Update Metrics") {
                    updateMetrics()
                }
            }
            .padding()
            
            Button("Start Auto Updates") {
                startAutoUpdates()
            }
            .padding()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            setupTestData()
        }
    }
    
    func setupTestData() {
        testMeeting.calendarTitle = "Team Standup"
        testMeeting.isRecording = true
        testMeeting.wordCount = 0
        testMeeting.currentFileSize = 0
        testMeeting.averageConfidence = 0.0
        testMeeting.detectedLanguage = "English"
        testMeeting.bufferHealth = .good
        
        // Add some test participants
        let alice = TestParticipant()
        alice.id = UUID()
        alice.name = "Alice Johnson"
        alice.confidence = 0.95
        alice.isSpeaking = false
        alice.speakingDuration = 0
        testMeeting.identifiedParticipants.append(alice)
        
        let bob = TestParticipant()
        bob.id = UUID()
        bob.name = "Bob Smith"
        bob.confidence = 0.88
        bob.isSpeaking = false
        bob.speakingDuration = 0
        testMeeting.identifiedParticipants.append(bob)
        
        let chris = TestParticipant()
        chris.id = UUID()
        chris.name = "Chris Taylor"
        chris.confidence = 0.82
        chris.isSpeaking = false
        chris.speakingDuration = 0
        testMeeting.identifiedParticipants.append(chris)
    }
    
    func showGlanceableWindow() {
        print("Creating GlanceableRecordingWindow...")
        
        // Create the window using the actual implementation
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Recording"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        
        // Create the test view
        let testView = NSHostingView(rootView: TestGlanceableView(meeting: testMeeting))
        window.contentView = testView
        
        // Position window
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let xPos = screenFrame.maxX - window.frame.width - 20
            let yPos = screenFrame.maxY - window.frame.height - 40
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)
        
        print("✅ Glanceable window should be visible!")
    }
    
    func addTestTranscript() {
        let speakers = ["Alice Johnson", "Bob Smith", "Chris Taylor"]
        let texts = [
            "This is another test to see if the meeting function is working.",
            "I want to see if the meeting function is working.",
            "I don't like the simplified window, it needs to be more plantable.",
            "So I can see all the data in one window or in one go.",
            "The new design shows everything at once without tabs.",
            "Perfect for glancing during meetings without interaction needed."
        ]
        
        let randomSpeaker = speakers.randomElement()!
        let randomText = texts.randomElement()!
        
        let segment = TestTranscriptSegment(
            text: randomText,
            timestamp: testMeeting.duration,
            speakerID: randomSpeaker.lowercased().replacingOccurrences(of: " ", with: "_"),
            speakerName: randomSpeaker,
            confidence: Float.random(in: 0.85...0.98),
            isFinalized: Bool.random()
        )
        
        testMeeting.addTranscriptSegment(segment)
        testMeeting.duration += Double.random(in: 3...8)
        
        // Update speaker time
        if let participant = testMeeting.identifiedParticipants.first(where: { $0.name == randomSpeaker }) {
            participant.speakingDuration += Double.random(in: 3...8)
        }
        
        print("Added transcript from \(randomSpeaker)")
    }
    
    func toggleSpeaker() {
        // Toggle a random speaker
        if let participant = testMeeting.identifiedParticipants.randomElement() {
            participant.isSpeaking.toggle()
            print("\(participant.name ?? "Unknown") is \(participant.isSpeaking ? "now" : "no longer") speaking")
        }
    }
    
    func updateMetrics() {
        testMeeting.currentFileSize += Int64.random(in: 10000...50000)
        testMeeting.averageConfidence = Float.random(in: 0.85...0.98)
        testMeeting.bufferHealth = [.good, .good, .good, .warning, .critical].randomElement()!
        print("Updated metrics")
    }
    
    func startAutoUpdates() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            addTestTranscript()
            if Bool.random() {
                toggleSpeaker()
            }
            updateMetrics()
        }
        print("Started auto updates every 3 seconds")
    }
}

// Test view that mimics the actual GlanceableRecordingView
struct TestGlanceableView: View {
    @ObservedObject var meeting: TestLiveMeeting
    
    var body: some View {
        // This would use the actual GlanceableRecordingView
        // For testing, we'll create a simplified version
        VStack {
            Text("Recording: \(meeting.displayTitle)")
                .font(.headline)
            Text("Duration: \(formatDuration(meeting.duration))")
            Text("Words: \(meeting.wordCount)")
            Text("Participants: \(meeting.identifiedParticipants.count)")
            
            ScrollView {
                ForEach(meeting.transcript) { segment in
                    HStack {
                        Text(segment.speakerName ?? "Unknown")
                            .bold()
                        Text(segment.text)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(width: 400, height: 520)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// Test models
class TestLiveMeeting: ObservableObject {
    @Published var isRecording = true
    @Published var duration: TimeInterval = 0
    @Published var transcript: [TestTranscriptSegment] = []
    @Published var identifiedParticipants: [TestParticipant] = []
    @Published var wordCount = 0
    @Published var currentFileSize: Int64 = 0
    @Published var averageConfidence: Float = 0
    @Published var detectedLanguage: String? = "English"
    @Published var bufferHealth: TestBufferHealth = .good
    @Published var transcriptionProgress: Float = 0
    
    var calendarTitle: String? = "Test Meeting"
    
    var displayTitle: String {
        calendarTitle ?? "Manual Recording"
    }
    
    var participantCount: Int {
        identifiedParticipants.count
    }
    
    func addTranscriptSegment(_ segment: TestTranscriptSegment) {
        transcript.append(segment)
        wordCount += segment.text.split(separator: " ").count
        
        if transcript.count == 1 {
            averageConfidence = segment.confidence
        } else {
            averageConfidence = ((averageConfidence * Float(transcript.count - 1)) + segment.confidence) / Float(transcript.count)
        }
    }
}

struct TestTranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
    let speakerID: String?
    let speakerName: String?
    let confidence: Float
    let isFinalized: Bool
}

class TestParticipant: ObservableObject, Identifiable {
    var id = UUID()
    @Published var name: String?
    @Published var confidence: Float = 0
    @Published var isSpeaking = false
    @Published var speakingDuration: TimeInterval = 0
    
    var color: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
        let index = abs(id.hashValue) % colors.count
        return colors[index]
    }
}

enum TestBufferHealth {
    case good, warning, critical
    
    var description: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

print("Test app ready. Run to test the glanceable window.")