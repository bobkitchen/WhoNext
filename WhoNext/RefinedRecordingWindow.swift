import SwiftUI
import AppKit

/// Refined recording window with improved UI/UX
class RefinedRecordingWindowController: NSWindowController {
    
    private var hostingController: NSHostingController<RefinedRecordingView>?
    private var meeting: LiveMeeting?
    
    init(meeting: LiveMeeting) {
        self.meeting = meeting
        
        // Create the SwiftUI view
        let contentView = RefinedRecordingView(meeting: meeting)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController
        
        // Create a floating panel with better default size
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        
        // Set size constraints
        panel.minSize = NSSize(width: 420, height: 540)
        panel.maxSize = NSSize(width: 600, height: 900)
        
        super.init(window: panel)
        
        // Position window
        positionWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 480
        let windowHeight: CGFloat = 640
        
        // Position in the right side of the screen with proper margin
        // Ensure window is fully visible on screen
        let rightMargin: CGFloat = 40
        let topMargin: CGFloat = 80
        
        let xPos = max(screenFrame.minX + 20, min(screenFrame.maxX - windowWidth - rightMargin, screenFrame.maxX - windowWidth - rightMargin))
        let yPos = max(screenFrame.minY + 20, min(screenFrame.maxY - windowHeight - topMargin, screenFrame.maxY - windowHeight - topMargin))
        
        window.setFrame(NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight), display: true)
    }
}

/// Refined recording view with improved design
struct RefinedRecordingView: View {
    @ObservedObject var meeting: LiveMeeting
    @ObservedObject private var recordingEngine = MeetingRecordingEngine.shared
    // speakerColors, speakerNumbers and nextSpeakerNumber removed as they are no longer used
    // speakerNumbers and nextSpeakerNumber removed as they are no longer used
    @State private var speakerNames: [String: String] = [:] // Maps speaker ID to custom names
    @State private var speakerNamingModes: [String: NamingMode] = [:] // Track naming mode per speaker
    @State private var speakerPersonLinks: [String: Person] = [:] // Maps speaker ID to Person record
    @State private var editingSpeaker: String? = nil // Speaker ID being edited
    @State private var editingName: String = "" // Temporary name during editing
    @State private var editingPerson: Person? = nil // Selected person during editing
    @State private var editingNamingMode: NamingMode = .unnamed // Naming mode during editing
    @State private var unnamedSpeakers: Set<String> = [] // Track speakers that need naming
    @State private var showSpeakerAlert = false
    @State private var newSpeakerDetected: String? = nil
    
    // Design constants
    private let spacing: CGFloat = 8
    private let cornerRadius: CGFloat = 8
    private let cardBackground = Color(NSColor.controlBackgroundColor).opacity(0.5)
    
    var body: some View {
        VStack(spacing: 0) {
            // New speaker notification banner
            if !unnamedSpeakers.isEmpty {
                speakerNotificationBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Refined header
            refinedHeader
                .padding(spacing * 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            
            // Main content with cards
            VStack(spacing: spacing) {
                // Transcript card
                transcriptCard
                    .frame(maxHeight: .infinity)
                
                // Dashboard cards
                dashboardCards
                    .frame(height: 100)
            }
            .padding(spacing)
            
            // Simplified status bar
            statusBar
                .padding(.horizontal, spacing * 2)
                .padding(.vertical, spacing)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            checkForUnnamedSpeakers()
        }
        .onChange(of: meeting.transcript.count) { _, _ in
            checkForUnnamedSpeakers()
        }
    }
    
    // MARK: - Speaker Detection
    private func checkForUnnamedSpeakers() {
        var detectedSpeakers = Set<String>()
        var namedSpeakers = Set<String>()
        
        // Go through all transcript segments
        for segment in meeting.transcript {
            if let speakerID = segment.speakerID {
                detectedSpeakers.insert(speakerID)
                
                // Check if this speaker has been named
                if speakerNames[speakerID] != nil || segment.speakerName != nil {
                    namedSpeakers.insert(speakerID)
                }
            }
        }
        
        // Update unnamed speakers
        let previousUnnamed = unnamedSpeakers
        unnamedSpeakers = detectedSpeakers.subtracting(namedSpeakers)
        
        // Check if new speakers were detected
        let newSpeakers = unnamedSpeakers.subtracting(previousUnnamed)
        if !newSpeakers.isEmpty {
            // Animate the appearance of the notification
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showSpeakerAlert = true
            }
            
            // Play a subtle sound or haptic feedback if desired
            NSSound.beep()
        }
    }
    
    // MARK: - Speaker Notification Banner
    private var speakerNotificationBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.orange)
                
                Text("\(unnamedSpeakers.count) new speaker\(unnamedSpeakers.count > 1 ? "s" : "") detected")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Button("Name Speakers") {
                    if let firstUnnamed = unnamedSpeakers.first {
                        // Find the first segment with this speaker
                        if let segment = meeting.transcript.first(where: { 
                            ($0.speakerID == firstUnnamed || $0.speakerName == "Speaker \(firstUnnamed)")
                        }) {
                            startEditingSpeaker(segment)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(.horizontal, spacing)
        .padding(.top, spacing)
    }
    
    // MARK: - Refined Header
    private var refinedHeader: some View {
        HStack {
            // Combined status and title
            HStack(spacing: 8) {
                // Recording indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            .scaleEffect(2)
                            .opacity(0)
                            .animation(
                                Animation.easeOut(duration: 2)
                                    .repeatForever(autoreverses: false),
                                value: meeting.isRecording
                            )
                    )
                
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                
                // Meeting type badge
                if meeting.meetingType != .unknown {
                    HStack(spacing: 4) {
                        Image(systemName: meeting.meetingType.icon)
                            .font(.system(size: 10))
                        Text(meeting.meetingType.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(meeting.meetingType.color.opacity(0.2))
                    .foregroundColor(meeting.meetingType.color)
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.3), value: meeting.meetingType)
                }
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Recording")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration and controls
            HStack(spacing: 12) {
                Text(formatDuration(meeting.duration))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                
                Button(action: { recordingEngine.manualStopRecording() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Transcript Card
    private var transcriptCard: some View {
        VStack(spacing: 0) {
            // Card content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if meeting.transcript.isEmpty {
                            emptyTranscriptState
                        } else {
                            transcriptContent
                        }
                    }
                }
                .onChange(of: meeting.transcript.count) { _, _ in
                    if let last = meeting.transcript.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 36))
                .foregroundColor(Color.secondary.opacity(0.3))
            
            Text("Listening...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Transcript will appear here")
                .font(.system(size: 11))
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
    
    private var transcriptContent: some View {
        VStack(spacing: 0) {
            let recentSegments = Array(meeting.transcript.suffix(15))
            
            ForEach(Array(recentSegments.enumerated()), id: \.element.id) { index, segment in
                let showTimestamp = shouldShowTimestamp(for: index, segment: segment)
                let speakerInfo = getSpeakerInfo(for: segment)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Show timestamp if needed
                    if showTimestamp {
                        Text(formatTimestamp(segment.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.secondary.opacity(0.5))
                            .padding(.top, 8)
                    }
                    
                    // Segment with speaker
                    HStack(alignment: .top, spacing: 10) {
                        // Speaker avatar with naming mode indicator
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .fill(speakerInfo.color.opacity(0.15))
                                .frame(width: 24, height: 24)
                            
                            Text(speakerInfo.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(speakerInfo.color)
                            
                            // Naming mode indicator
                            if let speakerID = segment.speakerID,
                               let namingMode = speakerNamingModes[speakerID] {
                                Image(systemName: namingModeIcon(namingMode))
                                    .font(.system(size: 8))
                                    .foregroundColor(namingModeColor(namingMode))
                                    .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                                    .offset(x: 5, y: -5)
                            }
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 2) {
                            // Editable speaker name with autocomplete
                            if editingSpeaker == (segment.speakerID ?? segment.speakerName ?? "unknown") {
                                PersonSearchField(
                                    text: $editingName,
                                    selectedPerson: $editingPerson,
                                    namingMode: $editingNamingMode,
                                    placeholder: "Speaker Name",
                                    onCommit: {
                                        saveSpeakerNameWithMode()
                                    }
                                )
                                .font(.system(size: 11))
                            } else {
                                Text(speakerInfo.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(speakerInfo.color)
                                    .onTapGesture {
                                        startEditingSpeaker(segment)
                                    }
                                    .help("Click to rename speaker")
                            }
                            
                            Text(segment.text)
                                .font(.system(size: 14))
                                .foregroundColor(segment.isFinalized ? .primary : Color.primary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .id(segment.id)
                }
                
                // Add separator between different speakers
                if index < recentSegments.count - 1 {
                    let nextSegment = recentSegments[index + 1]
                    if segment.speakerID != nextSegment.speakerID {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            
            // Processing indicator
            if meeting.transcriptionProgress > 0 && meeting.transcriptionProgress < 1 {
                processingIndicator
                    .padding(.vertical, 12)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var processingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 5, height: 5)
                    .scaleEffect(1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: meeting.transcriptionProgress
                    )
            }
        }
        .padding(.leading, 46)
    }
    
    // MARK: - Dashboard Cards
    private var dashboardCards: some View {
        HStack(spacing: spacing) {
            // Speakers card
            speakersCard
                .frame(maxWidth: .infinity)
            
            // Stats card
            statsCard
                .frame(maxWidth: .infinity)
        }
    }
    
    private var speakersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE SPEAKERS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if meeting.detectedSpeakerCount > 0 {
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.wave.2")
                            .font(.system(size: 9))
                        Text("\(meeting.detectedSpeakerCount)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(meeting.meetingType.color)
                    .animation(.easeInOut(duration: 0.3), value: meeting.detectedSpeakerCount)
                }
            }
            
            if meeting.identifiedParticipants.isEmpty {
                HStack {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 14))
                        .foregroundColor(Color.secondary.opacity(0.4))
                    
                    Text("Awaiting first speaker...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(meeting.identifiedParticipants.prefix(2)) { participant in
                        CompactSpeakerRow(
                            participant: participant,
                            totalDuration: meeting.duration,
                            speakerNames: $speakerNames
                        )
                    }
                    
                    if meeting.identifiedParticipants.count > 2 {
                        Text("+\(meeting.identifiedParticipants.count - 2) more speakers")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MEETING STATS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    StatItem(
                        value: "\(meeting.wordCount)",
                        label: "words",
                        icon: "text.word.spacing"
                    )
                    
                    StatItem(
                        value: "\(Int(meeting.averageConfidence * 100))%",
                        label: "confidence",
                        icon: "checkmark.circle"
                    )
                }
                
                HStack(spacing: 16) {
                    StatItem(
                        value: formatFileSize(meeting.currentFileSize),
                        label: "size",
                        icon: "doc"
                    )
                    
                    StatItem(
                        value: meeting.detectedLanguage ?? "Auto",
                        label: "language",
                        icon: "globe"
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .cornerRadius(cornerRadius)
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack(spacing: 12) {
            // Quality indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(meeting.bufferHealth.color)
                    .frame(width: 5, height: 5)
                Text(meeting.bufferHealth.description + " quality")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Speaking status
            if let activeSpeaker = meeting.identifiedParticipants.first(where: { $0.isSpeaking }) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text("\(activeSpeaker.name ?? "Someone") speaking")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No one speaking")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func shouldShowTimestamp(for index: Int, segment: TranscriptSegment) -> Bool {
        // Show timestamp for first segment
        if index == 0 { return true }
        
        let segments = Array(meeting.transcript.suffix(15))
        
        // Safety check - ensure index is valid
        if index >= segments.count || index <= 0 { return false }
        
        let previousSegment = segments[index - 1]
        
        // Show if speaker changed
        if segment.speakerID != previousSegment.speakerID { return true }
        
        // Show if 30+ seconds elapsed
        if segment.timestamp - previousSegment.timestamp > 30 { return true }
        
        return false
    }
    
    private func getSpeakerInfo(for segment: TranscriptSegment) -> (name: String, label: String, color: Color) {
        // Check for custom speaker name first
        if let speakerID = segment.speakerID,
           let customName = speakerNames[speakerID] {
            let initials = customName.split(separator: " ")
                .compactMap { $0.first }
                .prefix(2)
                .map { String($0) }
                .joined()
                .uppercased()
            
            // Use color based on naming mode
            let namingMode = speakerNamingModes[speakerID] ?? .unnamed
            let baseColor = getColorForSpeaker(speakerID)
            let color = namingMode == .linkedToPerson ? baseColor : 
                       namingMode == .transcriptOnly ? baseColor.opacity(0.8) : baseColor
            return (customName, initials.isEmpty ? "?" : initials, color)
        } else if let speakerName = segment.speakerName, !speakerName.isEmpty {
            // Named speaker
            let initials = speakerName.split(separator: " ")
                .compactMap { $0.first }
                .prefix(2)
                .map { String($0) }
                .joined()
                .uppercased()
            
            let color = getColorForSpeaker(speakerName)
            return (speakerName, initials.isEmpty ? "?" : initials, color)
        } else if let speakerID = segment.speakerID {
            // Check if we have a saved name for this speaker ID first
            if let savedName = speakerNames[speakerID] {
                let initials = savedName.split(separator: " ")
                    .compactMap { $0.first }
                    .prefix(2)
                    .map { String($0) }
                    .joined()
                    .uppercased()
                
                let color = getColorForSpeaker(speakerID)
                return (savedName, initials.isEmpty ? "?" : initials, color)
            }
            
            // Unnamed speaker with ID
            // Calculate number deterministically based on appearance order in transcript
            // This avoids modifying state during view update
            let allSpeakerIDs = Set(meeting.transcript.compactMap { $0.speakerID }).sorted()
            let number = (allSpeakerIDs.firstIndex(of: speakerID) ?? 0) + 1
            
            let color = getColorForSpeaker(speakerID)
            return ("Speaker \(number)", "\(number)", color)
        } else {
            // Completely unknown
            return ("Speaker", "?", .gray)
        }
    }
    
    private func getColorForSpeaker(_ identifier: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, 
            .pink, .cyan, .indigo, .mint
        ]
        
        // Deterministic color based on identifier hash
        // This avoids modifying state during view update
        let hash = abs(identifier.hashValue)
        let color = colors[hash % colors.count]
        
        return color
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - Speaker Editing Functions
    
    private func startEditingSpeaker(_ segment: TranscriptSegment) {
        let speakerID = segment.speakerID ?? segment.speakerName ?? "unknown"
        editingSpeaker = speakerID
        editingName = speakerNames[speakerID] ?? getSpeakerInfo(for: segment).name
    }
    
    // MARK: - Three-Path Speaker Naming
    
    private func saveSpeakerNameWithMode() {
        guard let speakerID = editingSpeaker else { return }
        
        switch editingNamingMode {
        case .linkedToPerson:
            if let person = editingPerson {
                linkSpeakerToPerson(speakerID: speakerID, person: person)
            } else if !editingName.isEmpty {
                // Create new person and link
                createNewPersonAndLink(speakerID: speakerID, name: editingName)
            }
        case .transcriptOnly:
            saveTranscriptOnlyName(speakerID: speakerID, name: editingName)
        case .unnamed:
            // Should not happen in normal flow
            break
        }
        
        // Clean up editing state
        editingSpeaker = nil
        editingName = ""
        editingPerson = nil
        editingNamingMode = .unnamed
    }
    
    private func linkSpeakerToPerson(speakerID: String, person: Person) {
        // Store the name and link
        speakerNames[speakerID] = person.wrappedName
        speakerNamingModes[speakerID] = .linkedToPerson
        speakerPersonLinks[speakerID] = person
        
        // Remove from unnamed speakers
        unnamedSpeakers.remove(speakerID)
        hideAlertIfNeeded()
        
        // Update or create identified participant with Person link
        // Update or create identified participant with Person link
        let parsedID = parseSpeakerID(speakerID)
        if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == parsedID }) {
            existingParticipant.name = person.wrappedName
            existingParticipant.person = person
            existingParticipant.namingMode = .linkedToPerson
            existingParticipant.confidence = person.voiceConfidence
        } else {
            let newParticipant = IdentifiedParticipant()
            newParticipant.speakerID = parsedID
            newParticipant.name = person.wrappedName
            newParticipant.person = person
            newParticipant.namingMode = .linkedToPerson
            newParticipant.confidence = person.voiceConfidence
            meeting.identifyParticipant(newParticipant)
        }
        
        // Save voice embedding to Person if available
        saveVoiceEmbeddingToPerson(speakerID: speakerID, person: person)
        
        // Update transcript segments
        updateTranscriptSegments(speakerID: speakerID, name: person.wrappedName)
        
        print("🔗 Linked speaker \(speakerID) to person: \(person.wrappedName)")
        promptNextUnnamedSpeaker()
    }
    
    private func createNewPersonAndLink(speakerID: String, name: String) {
        let context = PersistenceController.shared.container.viewContext
        let person = Person(context: context)
        person.name = name
        person.identifier = UUID()
        person.createdAt = Date()
        person.modifiedAt = Date()
        
        do {
            try context.save()
            linkSpeakerToPerson(speakerID: speakerID, person: person)
            print("➕ Created new person and linked: \(name)")
        } catch {
            print("❌ Error creating new person: \(error)")
        }
    }
    
    private func saveTranscriptOnlyName(speakerID: String, name: String) {
        guard !name.isEmpty else { return }
        
        // Store the name without Person link
        speakerNames[speakerID] = name
        speakerNamingModes[speakerID] = .transcriptOnly
        
        // Remove from unnamed speakers
        unnamedSpeakers.remove(speakerID)
        hideAlertIfNeeded()
        
        // Update or create identified participant without Person link
        // Update or create identified participant without Person link
        let parsedID = parseSpeakerID(speakerID)
        if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == parsedID }) {
            existingParticipant.name = name
            existingParticipant.namingMode = .transcriptOnly
            existingParticipant.confidence = 1.0 // High confidence since user manually entered
        } else {
            let newParticipant = IdentifiedParticipant()
            newParticipant.speakerID = parsedID
            newParticipant.name = name
            newParticipant.namingMode = .transcriptOnly
            newParticipant.confidence = 1.0
            meeting.identifyParticipant(newParticipant)
        }
        
        // Update transcript segments
        updateTranscriptSegments(speakerID: speakerID, name: name)
        
        print("📝 Saved transcript-only name: \(name) for speaker \(speakerID)")
        promptNextUnnamedSpeaker()
    }
    
    // Helper functions
    private func updateTranscriptSegments(speakerID: String, name: String) {
        for i in 0..<meeting.transcript.count {
            if meeting.transcript[i].speakerID == speakerID {
                meeting.transcript[i].speakerName = name
            }
        }
        meeting.objectWillChange.send()
    }
    
    private func hideAlertIfNeeded() {
        if unnamedSpeakers.isEmpty {
            withAnimation {
                showSpeakerAlert = false
            }
        }
    }
    
    private func promptNextUnnamedSpeaker() {
        if !unnamedSpeakers.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let nextUnnamed = unnamedSpeakers.first,
                   let segment = meeting.transcript.first(where: { 
                       $0.speakerID == nextUnnamed
                   }) {
                    startEditingSpeaker(segment)
                }
            }
        }
    }
    
    private func saveVoiceEmbeddingToPerson(speakerID: String, person: Person) {
        // Get embeddings from diarization if available
        #if canImport(FluidAudio)
        Task { @MainActor in
            if let diarizationManager = MeetingRecordingEngine.shared.diarizationManager,
               let lastResult = diarizationManager.lastResult {
                
                // Find segments for this speaker
                let speakerSegments = lastResult.segments.filter { segment in
                    segment.speakerId == speakerID
                }
                
                if !speakerSegments.isEmpty {
                    // Collect embeddings if available
                    var embeddings: [[Float]] = []
                    for segment in speakerSegments {
                        // Check if embedding exists and is not empty
                        if !segment.embedding.isEmpty {
                            embeddings.append(segment.embedding)
                        }
                    }
                    
                    if !embeddings.isEmpty {
                        // Use VoicePrintManager to save embeddings
                        let voicePrintManager = VoicePrintManager()
                        voicePrintManager.addEmbeddings(embeddings, for: person)
                        print("🎤 Saved \(embeddings.count) voice embeddings for \(person.wrappedName)")
                    } else {
                        print("⚠️ No embeddings available for speaker \(speakerID)")
                    }
                } else {
                    print("⚠️ No segments found for speaker \(speakerID)")
                }
            }
        }
        #else
        print("🎤 Voice embedding saving not available (FluidAudio not imported)")
        #endif
    }
    
    private func namingModeIcon(_ mode: NamingMode) -> String {
        switch mode {
        case .linkedToPerson:
            return "link.circle.fill"
        case .transcriptOnly:
            return "doc.text.fill"
        case .unnamed:
            return "questionmark.circle"
        }
    }
    
    private func namingModeColor(_ mode: NamingMode) -> Color {
        switch mode {
        case .linkedToPerson:
            return .green
        case .transcriptOnly:
            return .gray
        case .unnamed:
            return .yellow
        }
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func parseSpeakerID(_ idString: String) -> Int {
        if let id = Int(idString) {
            return id
        }
        if idString.hasPrefix("speaker_") {
            return Int(idString.replacingOccurrences(of: "speaker_", with: "")) ?? 0
        }
        return 0
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.0fKB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Supporting Views

struct CompactSpeakerRow: View {
    let participant: IdentifiedParticipant
    let totalDuration: TimeInterval
    @Binding var speakerNames: [String: String]
    @State private var isEditing = false
    @State private var editingName = ""
    
    private var percentage: Double {
        guard totalDuration > 0 else { return 0 }
        return min(participant.speakingDuration / totalDuration, 1.0)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Active indicator
            Circle()
                .fill(participant.isSpeaking ? Color.green : Color.clear)
                .frame(width: 4, height: 4)
                .overlay(
                    Circle()
                        .stroke(participant.isSpeaking ? Color.green : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            
            // Editable Name
            if isEditing {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: participant.isSpeaking ? .medium : .regular))
                    .onSubmit {
                        saveEditedName()
                    }
                    .frame(maxWidth: 80)
                
                Button("✓") {
                    saveEditedName()
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            } else {
                Text(speakerNames["\(participant.speakerID)"] ?? participant.name ?? "Unknown")
                    .font(.system(size: 11, weight: participant.isSpeaking ? .medium : .regular))
                    .lineLimit(1)
                    .onTapGesture {
                        startEditing()
                    }
                    .help("Click to rename")
                
                Image(systemName: "pencil.circle")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
                    .onTapGesture {
                        startEditing()
                    }
            }
            
            Spacer()
            
            // Time bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(participant.color.opacity(0.5))
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                }
            }
            .frame(width: 60, height: 8)
            
            // Percentage
            Text("\(Int(percentage * 100))%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
    
    // Helper methods for editing
    private func startEditing() {
        isEditing = true
        editingName = speakerNames["\(participant.speakerID)"] ?? participant.name ?? "Unknown"
    }
    
    private func saveEditedName() {
        if !editingName.isEmpty {
            speakerNames["\(participant.speakerID)"] = editingName
            participant.name = editingName
        }
        isEditing = false
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}