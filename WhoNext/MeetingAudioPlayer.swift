import SwiftUI
import AVFoundation
import Combine

/// Full-featured audio player for meeting recordings with speed control and timeline scrubbing
struct MeetingAudioPlayer: View {
    let audioFileURL: URL
    let transcript: [TranscriptSegment]?
    @StateObject private var player = AudioPlayerViewModel()
    @State private var showingTranscript = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Meeting Recording")
                        .font(.headline)
                    Text(audioFileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            // Waveform visualization (placeholder)
            WaveformView(player: player)
                .frame(height: 100)
                .padding(.horizontal)
            
            // Timeline scrubber
            VStack(spacing: 8) {
                Slider(
                    value: $player.currentTime,
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            player.startScrubbing()
                        } else {
                            player.seek(to: player.currentTime)
                        }
                    }
                )
                
                HStack {
                    Text(formatTime(player.currentTime))
                        .font(.caption)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    Text(formatTime(player.duration))
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Current speaker indicator
            if let currentSpeaker = getCurrentSpeaker() {
                HStack {
                    Image(systemName: "person.wave.2")
                    Text(currentSpeaker)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Playback controls
            HStack(spacing: 30) {
                // Skip backward
                Button(action: { player.skip(by: -10) }) {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Play/Pause
                Button(action: { player.togglePlayPause() }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Skip forward
                Button(action: { player.skip(by: 10) }) {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Speed control
            HStack {
                Text("Speed:")
                    .font(.caption)
                
                Picker("Speed", selection: $player.playbackRate) {
                    Text("0.5×").tag(Float(0.5))
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2.0))
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)
            }
            .padding(.horizontal)
            
            // Volume control
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 200)
                
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Action buttons
            HStack(spacing: 20) {
                Button(action: showTranscript) {
                    Label("Show Transcript", systemImage: "doc.text")
                }
                
                Button(action: exportAudio) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                
                if let currentSegment = getCurrentSegment() {
                    Button(action: { jumpToTranscript(currentSegment) }) {
                        Label("Jump to Text", systemImage: "text.cursor")
                    }
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            player.loadAudio(from: audioFileURL)
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showingTranscript) {
            if let transcript = transcript {
                TranscriptSyncView(
                    segments: transcript,
                    currentTime: player.currentTime,
                    onSeek: { time in
                        player.seek(to: time)
                    }
                )
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func getCurrentSpeaker() -> String? {
        guard let segments = transcript else { return nil }
        
        for segment in segments {
            if player.currentTime >= segment.timestamp &&
               player.currentTime < segment.timestamp + 5 { // Assume 5 second segments
                return segment.speakerName
            }
        }
        return nil
    }
    
    private func getCurrentSegment() -> TranscriptSegment? {
        guard let segments = transcript else { return nil }
        
        for segment in segments {
            if player.currentTime >= segment.timestamp &&
               player.currentTime < segment.timestamp + 5 {
                return segment
            }
        }
        return nil
    }
    
    private func showTranscript() {
        showingTranscript = true
    }
    
    private func exportAudio() {
        // Will be handled by ExportManager
        print("Export audio requested")
    }
    
    private func jumpToTranscript(_ segment: TranscriptSegment) {
        // Will open transcript at specific location
        showingTranscript = true
    }
}

/// Waveform visualization for audio
struct WaveformView: View {
    @ObservedObject var player: AudioPlayerViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background waveform
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                
                // Progress overlay
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: geometry.size.width * CGFloat(player.progress))
                
                // Playhead
                if player.duration > 0 {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(player.progress))
                }
                
                // Mock waveform bars
                HStack(spacing: 2) {
                    ForEach(0..<50, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2, height: CGFloat.random(in: 20...80))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Synchronized transcript view
struct TranscriptSyncView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        HStack(alignment: .top, spacing: 12) {
                            // Timestamp
                            Text(segment.formattedTimestamp)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 50)
                            
                            // Speaker
                            if let speaker = segment.speakerName {
                                Text(speaker)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 100, alignment: .leading)
                            }
                            
                            // Text
                            Text(segment.text)
                                .font(.body)
                                .foregroundColor(isCurrentSegment(segment) ? .primary : .secondary)
                                .onTapGesture {
                                    onSeek(segment.timestamp)
                                }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(
                            isCurrentSegment(segment) ?
                            Color.accentColor.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(8)
                        .id(segment.id)
                    }
                }
                .padding()
            }
            .onChange(of: currentTime) { _ in
                if let currentSegment = getCurrentSegment() {
                    withAnimation {
                        proxy.scrollTo(currentSegment.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
    }
    
    private func isCurrentSegment(_ segment: TranscriptSegment) -> Bool {
        currentTime >= segment.timestamp &&
        currentTime < segment.timestamp + 5
    }
    
    private func getCurrentSegment() -> TranscriptSegment? {
        segments.first { segment in
            currentTime >= segment.timestamp &&
            currentTime < segment.timestamp + 5
        }
    }
}

/// Audio player view model
class AudioPlayerViewModel: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published var isScrubbing = false
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = volume
        }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet {
            audioPlayer?.rate = playbackRate
        }
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.enableRate = true
            duration = audioPlayer?.duration ?? 0
            
            // Start timer for progress updates
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if !self.isScrubbing {
                    self.currentTime = self.audioPlayer?.currentTime ?? 0
                }
            }
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        audioPlayer?.play()
        isPlaying = true
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        timer?.invalidate()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        isScrubbing = false
    }
    
    func skip(by seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }
    
    func startScrubbing() {
        isScrubbing = true
        let wasPlaying = isPlaying
        pause()
        
        // Resume after scrubbing if was playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if wasPlaying && self.isScrubbing {
                self.play()
            }
        }
    }
}