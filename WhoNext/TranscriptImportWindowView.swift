import SwiftUI
import CoreData

struct TranscriptImportWindowView: View {
    @StateObject private var processor = TranscriptProcessor()
    @State private var transcriptText = ""
    @State private var processedTranscript: ProcessedTranscript?
    @State private var showingReviewScreen = false
    @State private var isFromRecording = false
    @State private var recordingTitle = ""
    @State private var recordingDate = Date()
    @State private var recordingDuration: TimeInterval = 0
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationStack {
            if showingReviewScreen, let processedTranscript = processedTranscript {
                TranscriptReviewView(processedTranscript: processedTranscript)
                    .environment(\.managedObjectContext, viewContext)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") {
                                showingReviewScreen = false
                                self.processedTranscript = nil
                                transcriptText = ""
                            }
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: isFromRecording ? "mic.circle.fill" : "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(isFromRecording ? .red : .blue)
                        
                        Text(isFromRecording ? "Review Recorded Meeting" : "Import Meeting Transcript")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if isFromRecording {
                            VStack(spacing: 4) {
                                if !recordingTitle.isEmpty {
                                    Text(recordingTitle)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                HStack(spacing: 16) {
                                    Label(formatDate(recordingDate), systemImage: "calendar")
                                    Label(formatDuration(recordingDuration), systemImage: "clock")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        
                        Text(isFromRecording ? 
                             "Review the transcription below, then process it to extract participants and generate summaries." :
                             "Paste your meeting transcript below and let AI extract participants, generate summaries, and analyze sentiment.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Transcript Input
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Meeting Transcript")
                                .font(.headline)
                            
                            if isFromRecording {
                                Label("Live Recording", systemImage: "mic.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(10)
                            }
                            
                            Spacer()
                            
                            if !transcriptText.isEmpty {
                                Text("\(transcriptText.split(separator: " ").count) words")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TextEditor(text: $transcriptText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .frame(minHeight: 200)
                        
                        if transcriptText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supported formats:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("• Zoom transcripts")
                                    Text("• Microsoft Teams transcripts")
                                    Text("• Generic timestamped transcripts")
                                    Text("• Manual notes")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        
                        // Format Detection
                        if !transcriptText.isEmpty {
                            let detectedFormat = processor.detectTranscriptFormat(transcriptText)
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Detected format: \(detectedFormat.rawValue.capitalized)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Processing Status
                    if processor.isProcessing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(processor.processingStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        Button("Clear") {
                            transcriptText = ""
                        }
                        .disabled(transcriptText.isEmpty || processor.isProcessing)
                        
                        Spacer()
                        
                        LoadingButton(
                            title: "Process Transcript",
                            loadingTitle: "Processing...",
                            isLoading: processor.isProcessing,
                            style: .primary,
                            isDisabled: transcriptText.isEmpty
                        ) {
                            Task {
                                if let processed = await processor.processTranscript(transcriptText) {
                                    processedTranscript = processed
                                    showingReviewScreen = true
                                }
                            }
                        }
                    }
                    .padding(.bottom)
                }
                .padding()
                .navigationTitle("")
                .errorAlert(ErrorManager.shared)
            }
        }
        .onAppear {
            // Check if we have a pending recorded transcript
            if let pendingTranscript = UserDefaults.standard.string(forKey: "PendingRecordedTranscript"),
               !pendingTranscript.isEmpty {
                // Load the recorded transcript
                transcriptText = pendingTranscript
                isFromRecording = true
                
                // Load additional metadata
                if let title = UserDefaults.standard.string(forKey: "PendingRecordedTitle") {
                    recordingTitle = title
                }
                if let date = UserDefaults.standard.object(forKey: "PendingRecordedDate") as? Date {
                    recordingDate = date
                }
                recordingDuration = UserDefaults.standard.double(forKey: "PendingRecordedDuration")
                
                // Load participant names from recording window
                let participantNames = UserDefaults.standard.stringArray(forKey: "PendingRecordedParticipantNames") ?? []
                if !participantNames.isEmpty {
                    // Prepend participant names to transcript for AI processing
                    let participantInfo = "Known Participants: \(participantNames.joined(separator: ", "))\n\n"
                    transcriptText = participantInfo + transcriptText
                    print("📝 Including participant names: \(participantNames.joined(separator: ", "))")
                }
                
                // Clear the pending data
                UserDefaults.standard.removeObject(forKey: "PendingRecordedTranscript")
                UserDefaults.standard.removeObject(forKey: "PendingRecordedTitle")
                UserDefaults.standard.removeObject(forKey: "PendingRecordedDate")
                UserDefaults.standard.removeObject(forKey: "PendingRecordedDuration")
                UserDefaults.standard.removeObject(forKey: "PendingRecordedParticipantNames")
                
                print("📝 Loaded recorded transcript: \(transcriptText.prefix(100))...")
            } else {
                // Normal import flow
                transcriptText = ""
                processedTranscript = nil
                isFromRecording = false
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
