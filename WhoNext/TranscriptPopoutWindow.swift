import SwiftUI
import AppKit

/// Manages the popout transcript window
class TranscriptPopoutWindowManager: NSObject, ObservableObject {
    
    static let shared = TranscriptPopoutWindowManager()
    private var transcriptWindow: NSWindow?
    
    /// Show transcript in a separate window
    func showTranscript(for meeting: GroupMeeting) {
        // Close existing window if open
        transcriptWindow?.close()
        
        // Create new window
        let contentView = TranscriptPopoutView(meeting: meeting)
        
        transcriptWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        transcriptWindow?.center()
        transcriptWindow?.setFrameAutosaveName("TranscriptWindow")
        transcriptWindow?.contentView = NSHostingView(rootView: contentView)
        transcriptWindow?.title = "Transcript: \(meeting.displayTitle)"
        transcriptWindow?.makeKeyAndOrderFront(nil)
        
        // Optional: Make window float on top
        transcriptWindow?.level = .floating
    }
    
    /// Close the transcript window
    func closeTranscript() {
        transcriptWindow?.close()
        transcriptWindow = nil
    }
}

/// Full transcript view with search and annotation capabilities
struct TranscriptPopoutView: View {
    let meeting: GroupMeeting
    @State private var searchText = ""
    @State private var selectedSegment: TranscriptSegment?
    @State private var fontSize: CGFloat = 14
    @State private var showTimestamps = true
    @State private var showSpeakers = true
    @State private var colorCodeSpeakers = true
    @State private var annotations: [String: String] = [:] // segment.id: annotation
    @State private var exportFormat: TranscriptExportFormat = .markdown
    @State private var isDarkMode = false
    @State private var scrollToSegmentID: String?
    
    // Audio playback integration
    @State private var showAudioPlayer = false
    @State private var currentPlaybackTime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView(
                searchText: $searchText,
                fontSize: $fontSize,
                showTimestamps: $showTimestamps,
                showSpeakers: $showSpeakers,
                colorCodeSpeakers: $colorCodeSpeakers,
                isDarkMode: $isDarkMode,
                onExport: exportTranscript,
                onPlayAudio: { showAudioPlayer.toggle() },
                hasAudio: meeting.hasAudioFile
            )
            
            Divider()
            
            // Main content
            HSplitView {
                // Transcript view
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Meeting header
                            MeetingHeaderView(meeting: meeting)
                                .padding()
                            
                            Divider()
                            
                            // Transcript segments
                            if let segments = meeting.parsedTranscript {
                                ForEach(segments.filter(matchesSearch)) { segment in
                                    PopoutTranscriptSegmentView(
                                        segment: segment,
                                        isSelected: selectedSegment?.id == segment.id,
                                        showTimestamp: showTimestamps,
                                        showSpeaker: showSpeakers,
                                        colorCodeSpeaker: colorCodeSpeakers,
                                        fontSize: fontSize,
                                        searchText: searchText,
                                        annotation: annotations[segment.id.uuidString],
                                        isCurrentlyPlaying: isSegmentPlaying(segment),
                                        onSelect: { selectedSegment = segment },
                                        onAnnotate: { text in
                                            annotations[segment.id.uuidString] = text
                                        },
                                        onJumpToAudio: { jumpToAudio(segment) }
                                    )
                                    .id(segment.id)
                                }
                            } else if let transcript = meeting.transcript {
                                Text(transcript)
                                    .font(.system(size: fontSize))
                                    .padding()
                            } else {
                                Text("No transcript available")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                    }
                    .onChange(of: scrollToSegmentID) { segmentID in
                        if let id = segmentID {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(minWidth: 500)
                
                // Side panel
                if selectedSegment != nil || !annotations.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Annotations")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(annotations.keys.sorted()), id: \.self) { segmentID in
                                    if let annotation = annotations[segmentID],
                                       let segment = meeting.parsedTranscript?.first(where: { $0.id.uuidString == segmentID }) {
                                        AnnotationView(
                                            segment: segment,
                                            annotation: annotation,
                                            onDelete: {
                                                annotations.removeValue(forKey: segmentID)
                                            },
                                            onJump: {
                                                scrollToSegmentID = segment.id.uuidString
                                                selectedSegment = segment
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .frame(width: 300)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            
            // Audio player (if available)
            if showAudioPlayer, let audioPath = meeting.audioFilePath {
                Divider()
                MiniAudioPlayer(
                    audioURL: URL(fileURLWithPath: audioPath),
                    currentTime: $currentPlaybackTime,
                    onTimeUpdate: { time in
                        updateCurrentSegment(at: time)
                    }
                )
                .frame(height: 100)
            }
        }
        .background(isDarkMode ? Color.black : Color(NSColor.textBackgroundColor))
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    // Helper functions
    
    private func matchesSearch(_ segment: TranscriptSegment) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        let searchLower = searchText.lowercased()
        return segment.text.lowercased().contains(searchLower) ||
               (segment.speakerName?.lowercased().contains(searchLower) ?? false)
    }
    
    private func isSegmentPlaying(_ segment: TranscriptSegment) -> Bool {
        showAudioPlayer &&
        currentPlaybackTime >= segment.timestamp &&
        currentPlaybackTime < segment.timestamp + 5 // Assume 5 second segments
    }
    
    private func jumpToAudio(_ segment: TranscriptSegment) {
        if !showAudioPlayer {
            showAudioPlayer = true
        }
        currentPlaybackTime = segment.timestamp
    }
    
    private func updateCurrentSegment(at time: TimeInterval) {
        if let segments = meeting.parsedTranscript {
            for segment in segments {
                if time >= segment.timestamp && time < segment.timestamp + 5 {
                    scrollToSegmentID = segment.id.uuidString
                    break
                }
            }
        }
    }
    
    private func exportTranscript() {
        let options = TranscriptExportOptions(
            includeTimestamps: showTimestamps,
            includeSpeakers: showSpeakers,
            includeSummary: true
        )
        
        ExportManager.shared.exportTranscript(
            meeting: meeting,
            format: exportFormat,
            options: options
        ) { result in
            switch result {
            case .success(let url):
                NSWorkspace.shared.open(url)
            case .failure(let error):
                print("Export failed: \(error)")
            }
        }
    }
}

/// Toolbar for transcript controls
struct ToolbarView: View {
    @Binding var searchText: String
    @Binding var fontSize: CGFloat
    @Binding var showTimestamps: Bool
    @Binding var showSpeakers: Bool
    @Binding var colorCodeSpeakers: Bool
    @Binding var isDarkMode: Bool
    let onExport: () -> Void
    let onPlayAudio: () -> Void
    let hasAudio: Bool
    
    var body: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcript...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }
            
            Divider()
                .frame(height: 20)
            
            // Display options
            Toggle("Timestamps", isOn: $showTimestamps)
            Toggle("Speakers", isOn: $showSpeakers)
            Toggle("Color Code", isOn: $colorCodeSpeakers)
                .disabled(!showSpeakers)
            
            Divider()
                .frame(height: 20)
            
            // Font size
            HStack {
                Text("Size:")
                Stepper("", value: $fontSize, in: 10...24, step: 2)
                Text("\(Int(fontSize))pt")
                    .monospacedDigit()
                    .frame(width: 40)
            }
            
            Spacer()
            
            // Actions
            if hasAudio {
                Button(action: onPlayAudio) {
                    Label("Play Audio", systemImage: "play.circle")
                }
            }
            
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            
            Toggle("", isOn: $isDarkMode)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
        }
        .padding()
    }
}

/// Meeting header information
struct MeetingHeaderView: View {
    let meeting: GroupMeeting
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.displayTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                if let date = meeting.date {
                    Label(date.formatted(), systemImage: "calendar")
                }
                
                Label(meeting.formattedDuration, systemImage: "clock")
                
                if meeting.attendeeCount > 0 {
                    Label("\(meeting.attendeeCount) attendees", systemImage: "person.2")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if let summary = meeting.summary {
                Text(summary)
                    .font(.body)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
        }
    }
}

/// Individual transcript segment view for popout window
struct PopoutTranscriptSegmentView: View {
    let segment: TranscriptSegment
    let isSelected: Bool
    let showTimestamp: Bool
    let showSpeaker: Bool
    let colorCodeSpeaker: Bool
    let fontSize: CGFloat
    let searchText: String
    let annotation: String?
    let isCurrentlyPlaying: Bool
    let onSelect: () -> Void
    let onAnnotate: (String) -> Void
    let onJumpToAudio: () -> Void
    
    @State private var isHovering = false
    @State private var showAnnotationEditor = false
    
    var speakerColor: Color {
        guard colorCodeSpeaker, let speaker = segment.speakerName else {
            return .primary
        }
        
        // Generate consistent color based on speaker name
        let hash = speaker.hashValue
        let hue = Double(abs(hash) % 360) / 360
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            if showTimestamp {
                Text(segment.formattedTimestamp)
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            
            // Speaker
            if showSpeaker, let speaker = segment.speakerName {
                Text(speaker)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(speakerColor)
                    .frame(width: 100, alignment: .leading)
            }
            
            // Transcript text
            VStack(alignment: .leading, spacing: 4) {
                highlightedText
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                
                if let annotation = annotation {
                    HStack {
                        Image(systemName: "note.text")
                            .font(.caption)
                        Text(annotation)
                            .font(.caption)
                            .italic()
                    }
                    .foregroundColor(.orange)
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Actions (shown on hover)
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: { showAnnotationEditor = true }) {
                        Image(systemName: annotation != nil ? "note.text.badge.plus" : "note.text")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: onJumpToAudio) {
                        Image(systemName: "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 0)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .sheet(isPresented: $showAnnotationEditor) {
            AnnotationEditor(
                initialText: annotation ?? "",
                onSave: onAnnotate
            )
        }
    }
    
    private var highlightedText: Text {
        guard !searchText.isEmpty else {
            return Text(segment.text)
        }
        
        var result = Text("")
        let text = segment.text
        let searchLower = searchText.lowercased()
        let textLower = text.lowercased()
        
        var currentIndex = text.startIndex
        
        while let range = textLower[currentIndex...].range(of: searchLower) {
            // Add text before match
            let beforeRange = currentIndex..<text.index(text.startIndex, offsetBy: textLower.distance(from: textLower.startIndex, to: range.lowerBound))
            result = result + Text(text[beforeRange])
            
            // Add highlighted match
            let matchRange = text.index(text.startIndex, offsetBy: textLower.distance(from: textLower.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: textLower.distance(from: textLower.startIndex, to: range.upperBound))
            result = result + Text(text[matchRange])
                .foregroundColor(.yellow)
                .bold()
            
            currentIndex = text.index(text.startIndex, offsetBy: textLower.distance(from: textLower.startIndex, to: range.upperBound))
        }
        
        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(text[currentIndex...])
        }
        
        return result
    }
    
    private var backgroundColor: Color {
        if isCurrentlyPlaying {
            return Color.accentColor.opacity(0.1)
        } else if isSelected {
            return Color.accentColor.opacity(0.05)
        } else if isHovering {
            return Color.gray.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        } else {
            return Color.clear
        }
    }
}

/// Annotation view in side panel
struct AnnotationView: View {
    let segment: TranscriptSegment
    let annotation: String
    let onDelete: () -> Void
    let onJump: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(segment.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let speaker = segment.speakerName {
                    Text(speaker)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text(annotation)
                .font(.caption)
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            
            Button(action: onJump) {
                Text("Jump to segment")
                    .font(.caption)
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

/// Annotation editor sheet
struct AnnotationEditor: View {
    let initialText: String
    let onSave: (String) -> Void
    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Annotation")
                .font(.headline)
            
            TextEditor(text: $text)
                .font(.body)
                .frame(height: 100)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        .onAppear {
            text = initialText
        }
    }
}

/// Mini audio player for transcript sync
struct MiniAudioPlayer: View {
    let audioURL: URL
    @Binding var currentTime: TimeInterval
    let onTimeUpdate: (TimeInterval) -> Void
    
    @StateObject private var player = AudioPlayerViewModel()
    
    var body: some View {
        HStack {
            Button(action: { player.togglePlayPause() }) {
                Image(systemName: player.isPlaying ? "pause.circle" : "play.circle")
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            Slider(
                value: $currentTime,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: currentTime)
                        onTimeUpdate(currentTime)
                    }
                }
            )
            
            Text("\(formatTime(currentTime)) / \(formatTime(player.duration))")
                .font(.caption)
                .monospacedDigit()
            
            Picker("Speed", selection: $player.playbackRate) {
                Text("1×").tag(Float(1.0))
                Text("1.5×").tag(Float(1.5))
                Text("2×").tag(Float(2.0))
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 150)
        }
        .padding()
        .onAppear {
            player.loadAudio(from: audioURL)
        }
        .onChange(of: player.currentTime) { time in
            if !player.isScrubbing {
                currentTime = time
                onTimeUpdate(time)
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}