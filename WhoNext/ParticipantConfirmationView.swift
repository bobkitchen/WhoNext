import SwiftUI
import AVFoundation
import CoreData

/// Post-meeting view for confirming speaker identities and assigning them to Person records
struct ParticipantConfirmationView: View {
    
    // MARK: - Properties
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var voicePrintManager = VoicePrintManager()
    @StateObject private var audioPlayer = MeetingAudioPlayer()
    
    // Meeting data
    let meeting: LiveMeeting
    let diarizationResults: DiarizationResult?
    let audioFileURL: URL?
    
    // UI State
    @State private var speakerAssignments: [Int: Person?] = [:]
    @State private var showingPersonPicker = false
    @State private var selectedSpeakerId: Int?
    @State private var isProcessing = false
    @State private var showingNewPersonSheet = false
    @State private var newPersonName = ""
    
    // Fetch existing people
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    )
    private var people: FetchedResults<Person>
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Meeting summary
                    meetingSummaryCard
                    
                    // Speaker cards
                    if let results = diarizationResults {
                        ForEach(results.speakers, id: \.speakerId) { speaker in
                            speakerCard(for: speaker)
                        }
                    } else {
                        noSpeakersDetectedView
                    }
                    
                    // Action buttons
                    actionButtons
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingPersonPicker) {
            personPickerSheet
        }
        .sheet(isPresented: $showingNewPersonSheet) {
            newPersonSheet
        }
        .onAppear {
            initializeAssignments()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Meeting Participants")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Assign speakers to people to improve voice recognition")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var meetingSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: meeting.meetingType.icon)
                    .foregroundColor(meeting.meetingType.color)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(meeting.displayTitle)
                        .font(.headline)
                    
                    HStack {
                        Label(meeting.formattedDuration, systemImage: "clock")
                        
                        if meeting.detectedSpeakerCount > 0 {
                            Label("\(meeting.detectedSpeakerCount) speakers", systemImage: "person.2")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Meeting type badge
                Text(meeting.meetingType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(meeting.meetingType.color.opacity(0.2))
                    .foregroundColor(meeting.meetingType.color)
                    .cornerRadius(4)
            }
            
            if !meeting.expectedParticipants.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected Participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ForEach(meeting.expectedParticipants, id: \.self) { name in
                            Text(name)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func speakerCard(for speaker: DiarizationSpeaker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Speaker icon with number
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Text("\(speaker.speakerId)")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speaker \(speaker.speakerId)")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Label(formatDuration(speaker.totalSpeakingTime), systemImage: "mic")
                        Label("\(speaker.segmentCount) segments", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Assignment status
                if let person = speakerAssignments[speaker.speakerId] as? Person {
                    assignedPersonView(person)
                } else {
                    unassignedView(speakerId: speaker.speakerId)
                }
            }
            
            // Voice sample player
            if let audioURL = audioFileURL, !speaker.segments.isEmpty {
                voiceSamplePlayer(for: speaker, audioURL: audioURL)
            }
            
            // Confidence indicator
            if let confidence = speaker.voiceMatchConfidence {
                confidenceIndicator(confidence: confidence)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(speakerAssignments[speaker.speakerId] != nil ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func assignedPersonView(_ person: Person) -> some View {
        HStack(spacing: 8) {
            // Person avatar
            if let photoData = person.photo, let image = NSImage(data: photoData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Text(person.initials)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(person.wrappedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if person.voiceConfidence > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        
                        Text("\(Int(person.voiceConfidence * 100))% match")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Button(action: {
                speakerAssignments[person.id.hashValue] = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func unassignedView(speakerId: Int) -> some View {
        Button(action: {
            selectedSpeakerId = speakerId
            showingPersonPicker = true
        }) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundColor(.accentColor)
                
                Text("Assign Person")
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func voiceSamplePlayer(for speaker: DiarizationSpeaker, audioURL: URL) -> some View {
        HStack {
            Button(action: {
                playVoiceSample(for: speaker, from: audioURL)
            }) {
                Label("Play Voice Sample", systemImage: audioPlayer.isPlaying ? "pause.circle" : "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            
            if audioPlayer.isPlaying {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
    }
    
    private func confidenceIndicator(confidence: Float) -> some View {
        HStack {
            Text("Voice Match Confidence:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: Double(confidence))
                .frame(width: 100)
            
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(confidence > 0.8 ? .green : confidence > 0.5 ? .orange : .red)
        }
    }
    
    private var noSpeakersDetectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No speakers detected")
                .font(.headline)
            
            Text("Speaker diarization data is not available for this meeting")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: skipConfirmation) {
                Label("Skip", systemImage: "forward")
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(action: autoAssign) {
                Label("Auto-Assign", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .disabled(diarizationResults == nil)
            
            Button(action: confirmAndSave) {
                Label("Confirm & Save", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || speakerAssignments.isEmpty)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Sheets
    
    private var personPickerSheet: some View {
        NavigationView {
            VStack {
                List(people, id: \.id) { person in
                    Button(action: {
                        if let speakerId = selectedSpeakerId {
                            speakerAssignments[speakerId] = person
                        }
                        showingPersonPicker = false
                    }) {
                        HStack {
                            // Person info
                            PersonRow(person: person)
                            
                            Spacer()
                            
                            // Voice recognition status
                            if person.voiceSampleCount > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Label("\(person.voiceSampleCount) samples", systemImage: "waveform")
                                        .font(.caption)
                                    
                                    Text("\(Int(person.voiceConfidence * 100))% confidence")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                
                Button(action: {
                    showingPersonPicker = false
                    showingNewPersonSheet = true
                }) {
                    Label("Create New Person", systemImage: "person.badge.plus")
                }
                .padding()
            }
            .navigationTitle("Select Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingPersonPicker = false
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
    
    private var newPersonSheet: some View {
        NavigationView {
            Form {
                TextField("Name", text: $newPersonName)
                
                Button(action: createNewPerson) {
                    Label("Create & Assign", systemImage: "person.badge.plus")
                }
                .disabled(newPersonName.isEmpty)
            }
            .padding()
            .navigationTitle("New Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewPersonSheet = false
                        newPersonName = ""
                    }
                }
            }
        }
        .frame(width: 350, height: 200)
    }
    
    // MARK: - Actions
    
    private func initializeAssignments() {
        guard let results = diarizationResults else { return }
        
        // Try to auto-match based on voice prints
        Task {
            for speaker in results.speakers {
                if let embedding = speaker.averageEmbedding,
                   let match = voicePrintManager.findMatchingPerson(for: embedding) {
                    await MainActor.run {
                        speakerAssignments[speaker.speakerId] = match.0
                    }
                }
            }
        }
    }
    
    private func autoAssign() {
        guard let results = diarizationResults else { return }
        
        isProcessing = true
        
        Task {
            // Build embeddings dictionary
            var embeddings: [Int: [Float]] = [:]
            for speaker in results.speakers {
                if let embedding = speaker.averageEmbedding {
                    embeddings[speaker.speakerId] = embedding
                }
            }
            
            // Match to expected attendees
            let matches = voicePrintManager.matchToAttendees(embeddings, attendeeNames: meeting.expectedParticipants)
            
            await MainActor.run {
                for (speakerId, person) in matches {
                    speakerAssignments[speakerId] = person
                }
                isProcessing = false
            }
        }
    }
    
    private func confirmAndSave() {
        guard let results = diarizationResults else { return }
        
        isProcessing = true
        
        Task {
            // Save voice embeddings for assigned people
            for speaker in results.speakers {
                if let person = speakerAssignments[speaker.speakerId] as? Person,
                   let embeddings = speaker.embeddings {
                    voicePrintManager.addEmbeddings(embeddings, for: person)
                }
            }
            
            // Update meeting with confirmed participants
            let confirmedParticipants = speakerAssignments.compactMap { (speakerId, person) -> ConfirmedParticipant? in
                guard let person = person as? Person,
                      let speaker = results.speakers.first(where: { $0.speakerId == speakerId }) else {
                    return nil
                }
                
                return ConfirmedParticipant(
                    person: person,
                    speakerId: speakerId,
                    voiceEmbeddings: speaker.embeddings,
                    speakingDuration: speaker.totalSpeakingTime
                )
            }
            
            // Improve voice models
            let completedMeeting = CompletedMeeting(
                id: meeting.id,
                date: meeting.startTime,
                duration: meeting.duration,
                confirmedParticipants: confirmedParticipants
            )
            
            let learningSystem = VoiceLearningSystem(voicePrintManager: voicePrintManager)
            learningSystem.improveModels(from: completedMeeting)
            
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
    
    private func skipConfirmation() {
        dismiss()
    }
    
    private func createNewPerson() {
        let newPerson = Person(context: viewContext)
        newPerson.name = newPersonName
        newPerson.identifier = UUID()
        newPerson.createdAt = Date()
        newPerson.modifiedAt = Date()
        
        do {
            try viewContext.save()
            
            if let speakerId = selectedSpeakerId {
                speakerAssignments[speakerId] = newPerson
            }
            
            showingNewPersonSheet = false
            newPersonName = ""
        } catch {
            print("Error creating new person: \(error)")
        }
    }
    
    private func playVoiceSample(for speaker: DiarizationSpeaker, from audioURL: URL) {
        // Get first segment for sample
        guard let firstSegment = speaker.segments.first else { return }
        
        audioPlayer.playSegment(
            from: audioURL,
            startTime: firstSegment.startTime,
            duration: min(firstSegment.duration, 5.0) // Max 5 seconds sample
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

struct PersonRow: View {
    let person: Person
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            if let photoData = person.photo, let image = NSImage(data: photoData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Text(person.initials)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(person.wrappedName)
                    .font(.subheadline)
                
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Audio Player Helper

class MeetingAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    private var audioPlayer: AVAudioPlayer?
    
    func playSegment(from url: URL, startTime: TimeInterval, duration: TimeInterval) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.currentTime = startTime
            audioPlayer?.play()
            isPlaying = true
            
            // Stop after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.stop()
            }
        } catch {
            print("Error playing audio: \(error)")
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }
}

// MARK: - Diarization Result Types (Placeholder)

struct DiarizationResult {
    let speakers: [DiarizationSpeaker]
    let totalDuration: TimeInterval
}

struct DiarizationSpeaker {
    let speakerId: Int
    let segments: [DiarizationSpeakerSegment]
    let totalSpeakingTime: TimeInterval
    let segmentCount: Int
    let averageEmbedding: [Float]?
    let embeddings: [[Float]]?
    let voiceMatchConfidence: Float?
}

struct DiarizationSpeakerSegment {
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String?
}