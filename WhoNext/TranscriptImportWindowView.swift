import SwiftUI
import CoreData

// MARK: - Processing Phase Enum (UI display phases)

enum ProcessingPhase: Int, CaseIterable {
    case analyzing = 0
    case participants = 1
    case summary = 2
    case actions = 3
    case sentiment = 4
    case complete = 5

    var title: String {
        switch self {
        case .analyzing: return "Analyzing transcript format"
        case .participants: return "Identifying participants"
        case .summary: return "Generating meeting summary"
        case .actions: return "Extracting action items"
        case .sentiment: return "Analyzing sentiment"
        case .complete: return "Processing complete"
        }
    }

    var icon: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        default: return "circle"
        }
    }

    /// Convert from TranscriptProcessingPhase to UI ProcessingPhase
    static func from(_ processorPhase: TranscriptProcessingPhase) -> ProcessingPhase {
        switch processorPhase {
        case .idle, .analyzing: return .analyzing
        case .participants: return .participants
        case .summary: return .summary
        case .actions: return .actions
        case .sentiment: return .sentiment
        case .finalizing, .complete: return .complete
        }
    }
}

// MARK: - Main View

struct TranscriptImportWindowView: View {
    @StateObject private var processor = TranscriptProcessor()
    @State private var transcriptText = ""
    @State private var processedTranscript: ProcessedTranscript?
    @State private var showingReviewScreen = false
    @State private var isFromRecording = false
    @State private var recordingTitle = ""
    @State private var recordingDate = Date()
    @State private var recordingDuration: TimeInterval = 0
    @State private var identifiedParticipants: [SerializableParticipant] = []
    @State private var userNotesFromRecording: String? = nil  // Granola-style notes from recording
    @State private var showRawTranscript = false
    @State private var hasStartedAutoProcessing = false
    @State private var processingError: String?
    @State private var processingStarted = false  // Guard against multiple processing calls

    @Environment(\.managedObjectContext) private var viewContext

    // Get current processing phase from processor (uses explicit phase tracking)
    private var currentPhase: ProcessingPhase {
        ProcessingPhase.from(processor.currentPhase)
    }

    var body: some View {
        NavigationStack {
            if showingReviewScreen, let processedTranscript = processedTranscript {
                // Review Phase - Show TranscriptReviewView
                TranscriptReviewView(processedTranscript: processedTranscript)
                    .environment(\.managedObjectContext, viewContext)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") {
                                showingReviewScreen = false
                                self.processedTranscript = nil
                                if !isFromRecording {
                                    transcriptText = ""
                                }
                            }
                        }
                    }
            } else if isFromRecording && (processor.isProcessing || hasStartedAutoProcessing) {
                // Processing Phase - Show progress UI for recordings
                processingPhaseView
            } else {
                // Manual Import Phase - Show traditional import UI
                manualImportView
            }
        }
        .onAppear {
            loadPendingTranscript()
        }
    }

    // MARK: - Processing Phase View (New Streamlined UI)

    private var processingPhaseView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: processor.isProcessing)

                // Show actual meeting title if available, otherwise generic "Processing Meeting"
                if !recordingTitle.isEmpty {
                    Text(recordingTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("Processing Meeting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Processing Meeting")
                        .font(.title)
                        .fontWeight(.bold)
                }

                HStack(spacing: 16) {
                    Label(formatDate(recordingDate), systemImage: "calendar")
                    Label(formatDuration(recordingDuration), systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            // Progress Steps
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ProcessingPhase.allCases.filter { $0 != .complete }, id: \.self) { phase in
                    processingStepRow(phase: phase)
                }
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .frame(maxWidth: 400)

            // Error message if processing failed
            if let error = processingError {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Processing issue")
                            .fontWeight(.medium)
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        processingError = nil
                        startProcessing()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            // Collapsible Raw Transcript
            DisclosureGroup(isExpanded: $showRawTranscript) {
                ScrollView {
                    Text(transcriptText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text("View Raw Transcript")
                    Spacer()
                    Text("\(transcriptText.split(separator: " ").count) words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Cancel button
            HStack {
                Spacer()
                Button("Cancel") {
                    // Reset and close
                    transcriptText = ""
                    isFromRecording = false
                    hasStartedAutoProcessing = false
                    processor.cancelProcessing()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Processing Step Row

    private func processingStepRow(phase: ProcessingPhase) -> some View {
        let isComplete = currentPhase.rawValue > phase.rawValue
        let isCurrent = currentPhase == phase && processor.isProcessing

        return HStack(spacing: 12) {
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else if isCurrent {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.title3)
                }
            }
            .frame(width: 24, height: 24)

            Text(phase.title)
                .foregroundColor(isComplete ? .primary : (isCurrent ? .primary : .secondary))
                .fontWeight(isCurrent ? .medium : .regular)

            Spacer()
        }
    }

    // MARK: - Manual Import View (Existing UI for paste-in imports)

    private var manualImportView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("Import Meeting Transcript")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Paste your meeting transcript below and let AI extract participants, generate summaries, and analyze sentiment.")
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
                    startProcessing()
                }
            }
            .padding(.bottom)
        }
        .padding()
        .navigationTitle("")
        .errorAlert(ErrorManager.shared)
    }

    // MARK: - Helper Functions

    private func loadPendingTranscript() {
        // Check if we have a pending recorded transcript
        if let pendingTranscript = UserDefaults.standard.string(forKey: "PendingRecordedTranscript"),
           !pendingTranscript.isEmpty {
            // Load the recorded transcript
            transcriptText = pendingTranscript
            isFromRecording = true
            hasStartedAutoProcessing = true  // Set immediately to avoid showing manual import view briefly

            // Load additional metadata
            if let title = UserDefaults.standard.string(forKey: "PendingRecordedTitle") {
                recordingTitle = title
            }
            if let date = UserDefaults.standard.object(forKey: "PendingRecordedDate") as? Date {
                recordingDate = date
            }
            recordingDuration = UserDefaults.standard.double(forKey: "PendingRecordedDuration")

            // Load user notes taken during recording (Granola-style)
            if let userNotes = UserDefaults.standard.string(forKey: "PendingRecordedUserNotes"), !userNotes.isEmpty {
                userNotesFromRecording = userNotes
                print("📝 Loaded user notes from recording: \(userNotes.prefix(100))...")
            }

            // Load full participant data from recording
            if let participantData = UserDefaults.standard.data(forKey: "PendingRecordedParticipants"),
               let participants = SerializableParticipant.deserialize(from: participantData) {
                identifiedParticipants = participants

                // Build participant info with proper labels
                var participantLabels: [String] = []
                for participant in participants {
                    if participant.isCurrentUser {
                        if let name = participant.name, !name.isEmpty {
                            participantLabels.append("\(name) (You)")
                        } else {
                            participantLabels.append("You")
                        }
                    } else if let name = participant.name {
                        participantLabels.append(name)
                    } else {
                        participantLabels.append(participant.displayName)
                    }
                }

                if !participantLabels.isEmpty {
                    let participantInfo = "Participants: \(participantLabels.joined(separator: ", "))\n\n"
                    transcriptText = participantInfo + transcriptText
                    print("📝 Including identified participants: \(participantLabels.joined(separator: ", "))")
                }
            } else {
                // Fallback to legacy name-only format
                let participantNames = UserDefaults.standard.stringArray(forKey: "PendingRecordedParticipantNames") ?? []
                if !participantNames.isEmpty {
                    let participantInfo = "Participants: \(participantNames.joined(separator: ", "))\n\n"
                    transcriptText = participantInfo + transcriptText
                    print("📝 Including participant names (legacy): \(participantNames.joined(separator: ", "))")
                }
            }

            // Clear the pending data
            UserDefaults.standard.removeObject(forKey: "PendingRecordedTranscript")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedTitle")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedDate")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedDuration")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedParticipants")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedParticipantNames")
            UserDefaults.standard.removeObject(forKey: "PendingRecordedUserNotes")

            print("📝 Loaded recorded transcript: \(transcriptText.prefix(100))...")

            // Auto-start processing for recordings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startProcessing()
            }
        } else {
            // Normal import flow
            transcriptText = ""
            processedTranscript = nil
            isFromRecording = false
        }
    }

    private func startProcessing() {
        // Guard against multiple processing calls
        guard !processingStarted else {
            print("📊 TranscriptImportView: Processing already started, ignoring duplicate call")
            return
        }
        processingStarted = true
        hasStartedAutoProcessing = true
        processingError = nil
        print("📊 TranscriptImportView: Starting processing")

        Task {
            let preIdentified = identifiedParticipants.isEmpty ? nil : identifiedParticipants
            // Pass user notes from recording to be incorporated into AI summary
            if let processed = await processor.processTranscript(transcriptText, preIdentifiedParticipants: preIdentified, userNotes: userNotesFromRecording) {
                await MainActor.run {
                    print("📊 TranscriptImportView: Processing succeeded, showing review screen")
                    processedTranscript = processed
                    showingReviewScreen = true
                }
            } else {
                await MainActor.run {
                    print("📊 TranscriptImportView: Processing failed")
                    processingError = "Failed to process transcript. Please try again."
                    hasStartedAutoProcessing = false
                    processingStarted = false  // Allow retry
                }
            }
        }
    }

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
