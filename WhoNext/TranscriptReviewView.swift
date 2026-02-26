import SwiftUI
import CoreData

struct TranscriptReviewView: View {
    let processedTranscript: ProcessedTranscript
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var editedTitle: String
    @State private var editedSummary: String
    @State private var selectedParticipants: Set<ParticipantInfo>
    @State private var showingSaveConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var participantReplacements: [String: Person] = [:]
    @State private var searchQueries: [String: String] = [:]
    @State private var searchResults: [String: [Person]] = [:]
    @State private var showSummaryEditor = false
    @State private var manualSearchQuery: String = ""
    @State private var manualSearchResults: [Person] = []
    @State private var manualParticipants: [ParticipantInfo] = []
    @State private var autoMatchConfirmed: [String: Bool] = [:]
    @State private var showFullTranscript: Bool = false
    @State private var markedAsCurrentUserNames: Set<String> = []

    // Meeting type handling
    @State private var isGroupMeeting: Bool = false
    @State private var selectedGroup: WhoNext.Group? = nil
    @State private var newGroupName: String = ""

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WhoNext.Group.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO")
    ) private var existingGroups: FetchedResults<WhoNext.Group>

    // Meeting date handling
    @State private var meetingDate: Date = Date()
    @State private var useCurrentDate: Bool = false
    @State private var showDateWarning: Bool = false

    init(processedTranscript: ProcessedTranscript) {
        self.processedTranscript = processedTranscript
        self._editedTitle = State(initialValue: processedTranscript.suggestedTitle)
        self._editedSummary = State(initialValue: processedTranscript.summary)
        self._selectedParticipants = State(initialValue: Set(processedTranscript.participants))

        // Use actual recording timestamp from the processed transcript
        self._meetingDate = State(initialValue: processedTranscript.originalTranscript.timestamp)

        // Seed markedAsCurrentUserNames from pre-identified current users
        let currentUserNames = Set(processedTranscript.participants.filter { $0.isCurrentUser }.map { $0.name })
        self._markedAsCurrentUserNames = State(initialValue: currentUserNames)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review & Edit")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Review the AI-generated summary and make any adjustments before saving.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Meeting Title
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meeting Title")
                        .font(.headline)

                    TextField("Enter meeting title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }

                // Meeting Date Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meeting Date & Time")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use current date/time", isOn: $useCurrentDate)
                            .toggleStyle(.switch)
                            .onChange(of: useCurrentDate) { _, newValue in
                                if newValue {
                                    meetingDate = Date()
                                }
                            }

                        if !useCurrentDate {
                            DatePicker(
                                "When did this meeting occur?",
                                selection: $meetingDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                        } else {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text("Will be saved as: \(Date().formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Warning if date is suspicious
                        if showDateWarning {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("This date is in the future or very recent. Please verify.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Accurate dates are important for meeting history and insights.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Meeting Type Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meeting Type")
                        .font(.headline)

                    Picker("Meeting Type", selection: $isGroupMeeting) {
                        Text("1:1 Conversation").tag(false)
                        Text("Group Meeting").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if isGroupMeeting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select or Create Group")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if !existingGroups.isEmpty {
                                Picker("Group", selection: $selectedGroup) {
                                    Text("Create new group...").tag(nil as WhoNext.Group?)
                                    ForEach(existingGroups) { group in
                                        Text(group.name ?? "Unnamed Group").tag(group as WhoNext.Group?)
                                    }
                                }
                                .labelsHidden()
                            }

                            if selectedGroup == nil {
                                TextField("New group name", text: $newGroupName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }

                // Participants Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Participants (\(selectedParticipants.count))")
                        .font(.headline)
                    
                    if !processedTranscript.participants.isEmpty {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(processedTranscript.participants, id: \.name) { participant in
                                participantCard(for: participant)
                            }
                        }
                    }
                    
                    if selectedParticipants.isEmpty && processedTranscript.participants.isEmpty {
                        Text("No participants detected in transcript. Add participants manually below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Manual search and add section
                    if !processedTranscript.participants.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Additional Participants")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("Search your contacts to add more people...", text: $manualSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    if manualSearchQuery.count > 2 {
                                        searchPeopleManual(query: manualSearchQuery)
                                    }
                                }
                                .onChange(of: manualSearchQuery) { _, newValue in
                                    if newValue.count > 2 {
                                        searchPeopleManual(query: newValue)
                                    } else {
                                        manualSearchResults = []
                                    }
                                }

                            if !manualSearchResults.isEmpty {
                                Menu {
                                    ForEach(manualSearchResults.indices, id: \.self) { idx in
                                        Button(action: {
                                            let person = manualSearchResults[idx]
                                            addManualParticipant(for: person)
                                        }) {
                                            HStack {
                                                Text(manualSearchResults[idx].name ?? "Unknown")
                                                if let role = manualSearchResults[idx].role, !role.isEmpty {
                                                    Text("·")
                                                        .foregroundColor(.secondary)
                                                    Text(role)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Add Person (\(manualSearchResults.count))")
                                        .font(.caption)
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                    }
                    
                    // Display manually added participants
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(manualParticipants, id: \.name) { participant in
                            participantCard(for: participant)
                        }
                    }
                }
                
                // Summary Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meeting Summary")
                        .font(.headline)
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.textBackgroundColor))
                            .stroke(Color(.separatorColor), lineWidth: 1)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ProfileContentView(content: editedSummary)
                                
                                Divider()
                                    .padding(.vertical, 8)
                                
                                // Edit button to switch to text editor
                                Button("Edit Summary") {
                                    showSummaryEditor.toggle()
                                }
                                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                            }
                            .padding(12)
                        }
                    }
                    .frame(minHeight: 200)
                }
                
                // Summary Editor (when editing)
                if showSummaryEditor {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Edit Summary")
                                .font(.headline)
                            Spacer()
                            Button("Done") {
                                showSummaryEditor = false
                            }
                            .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .small))
                        }
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.textBackgroundColor))
                                .stroke(Color(.separatorColor), lineWidth: 1)
                            
                            TextEditor(text: $editedSummary)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                        }
                        .frame(minHeight: 200)
                    }
                }
                
                // Key Points Section
                if !processedTranscript.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Discussion Points")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(processedTranscript.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.blue)
                                        .padding(.top, 6)
                                    
                                    Text(point)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
                
                // Sentiment Analysis Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Meeting Intelligence")
                        .font(.headline)
                    
                    // Main sentiment overview card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overall Sentiment")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(processedTranscript.sentimentAnalysis.overallSentiment.capitalized)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            // Sentiment score as progress circle
                            ZStack {
                                Circle()
                                    .stroke(Color(.separatorColor), lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                
                                Circle()
                                    .trim(from: 0, to: processedTranscript.sentimentAnalysis.sentimentScore)
                                    .stroke(sentimentColor(processedTranscript.sentimentAnalysis.overallSentiment), lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                    .rotationEffect(.degrees(-90))
                                
                                Text("\(Int(processedTranscript.sentimentAnalysis.sentimentScore * 100))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                        }
                        
                        // Key metrics grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            // Relationship Health
                            MetricCard(
                                icon: "heart.fill",
                                title: "Relationship",
                                value: processedTranscript.sentimentAnalysis.relationshipHealth.capitalized,
                                color: relationshipHealthColor(processedTranscript.sentimentAnalysis.relationshipHealth)
                            )
                            
                            // Engagement Level
                            MetricCard(
                                icon: "person.2.fill",
                                title: "Engagement",
                                value: processedTranscript.sentimentAnalysis.engagementLevel.capitalized,
                                color: engagementColor(processedTranscript.sentimentAnalysis.engagementLevel)
                            )
                            
                            // Communication Style
                            MetricCard(
                                icon: "bubble.left.and.bubble.right.fill",
                                title: "Style",
                                value: processedTranscript.sentimentAnalysis.communicationStyle.capitalized,
                                color: .blue
                            )
                            
                            // Energy Level
                            MetricCard(
                                icon: "bolt.fill",
                                title: "Energy",
                                value: processedTranscript.sentimentAnalysis.energyLevel.capitalized,
                                color: energyColor(processedTranscript.sentimentAnalysis.energyLevel)
                            )
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Actionable insights
                    if !processedTranscript.sentimentAnalysis.keyObservations.isEmpty ||
                       !processedTranscript.sentimentAnalysis.followUpRecommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Actionable Insights")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if !processedTranscript.sentimentAnalysis.keyObservations.isEmpty {
                                InsightSection(
                                    title: "Key Observations",
                                    items: processedTranscript.sentimentAnalysis.keyObservations,
                                    icon: "eye.fill",
                                    color: .blue
                                )
                            }
                            
                            if !processedTranscript.sentimentAnalysis.followUpRecommendations.isEmpty {
                                InsightSection(
                                    title: "Recommended Actions",
                                    items: processedTranscript.sentimentAnalysis.followUpRecommendations,
                                    icon: "lightbulb.fill",
                                    color: .orange
                                )
                            }
                            
                            if !processedTranscript.sentimentAnalysis.supportNeeds.isEmpty {
                                InsightSection(
                                    title: "Support Needs",
                                    items: processedTranscript.sentimentAnalysis.supportNeeds,
                                    icon: "hands.sparkles.fill",
                                    color: .green
                                )
                            }
                            
                            if !processedTranscript.sentimentAnalysis.riskFactors.isEmpty {
                                InsightSection(
                                    title: "Risk Factors",
                                    items: processedTranscript.sentimentAnalysis.riskFactors,
                                    icon: "exclamationmark.triangle.fill",
                                    color: .red
                                )
                            }
                        }
                        .padding()
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(12)
                    }
                }

                // Full Transcript Section (Collapsible)
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        withAnimation {
                            showFullTranscript.toggle()
                        }
                    }) {
                        HStack {
                            Text("Full Transcript")
                                .font(.headline)

                            Spacer()

                            Image(systemName: showFullTranscript ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)

                    if showFullTranscript {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.secondary)
                                Text("Complete conversation record")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(processedTranscript.originalTranscript.rawText.count) characters")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            Divider()

                            ScrollView {
                                Text(processedTranscript.originalTranscript.rawText)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .padding()
                            }
                            .frame(maxHeight: 400)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(24)
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onChange(of: selectedParticipants) { _, newValue in
            // Auto-suggest group meeting when more than 2 participants selected
            if newValue.count > 2 && !isGroupMeeting {
                isGroupMeeting = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Bottom Action Bar
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()
                
                Button(isGroupMeeting ? "Save Group Meeting" : "Save Conversation") {
                    if isGroupMeeting {
                        saveAsGroupMeeting()
                    } else {
                        saveConversation()
                    }
                    if !showingSaveError {
                        dismiss()
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                .disabled(editedTitle.isEmpty || selectedParticipants.isEmpty || (isGroupMeeting && selectedGroup == nil && newGroupName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .padding()
            .background(.regularMaterial)
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    // MARK: - Helper Methods
    
    private func sentimentColor(_ sentiment: String) -> Color {
        SentimentColors.color(for: sentiment)
    }
    
    private func saveConversation() {
        // Use a consistent context for all operations
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        debugLog("🔧 Using context: \(context)")
        debugLog("🔧 Context has coordinator: \(context.persistentStoreCoordinator != nil)")

        let conversation = Conversation(context: context)
        conversation.uuid = UUID()

        // ✅ FIX: Use the user-selected date, not current time
        let selectedDate = useCurrentDate ? Date() : meetingDate
        conversation.date = selectedDate

        // Store the title in the summary field (this is what shows in conversation lists)
        conversation.summary = editedTitle
        // Store the detailed meeting content in the notes field
        conversation.notes = editedSummary
        conversation.duration = Int32(processedTranscript.recordingDuration)

        // Add audit metadata to track when record was created
        conversation.createdAt = Date()

        // Validate and log date integrity
        let now = Date()
        let hoursDifference = selectedDate.timeIntervalSince(now) / 3600
        let isInFuture = selectedDate > now
        let isVeryRecent = abs(hoursDifference) < 0.5 // Within 30 minutes

        if isInFuture {
            debugLog("⚠️ WARNING: Meeting date is in the FUTURE (\(selectedDate.formatted()))")
        } else if isVeryRecent && !useCurrentDate {
            debugLog("⚠️ NOTICE: Meeting date is very recent but user opted not to use current time")
        }

        debugLog("🔧 Created conversation with:")
        debugLog("🔧   UUID: \(conversation.uuid?.uuidString ?? "nil")")
        debugLog("🔧   Meeting Date: \(conversation.date?.description ?? "nil") (selected by user: \(!useCurrentDate))")
        debugLog("🔧   Created At: \(conversation.createdAt?.description ?? "nil")")
        debugLog("🔧   Time difference from now: \(String(format: "%.1f", hoursDifference)) hours")
        debugLog("🔧   Summary length: \(conversation.summary?.count ?? 0)")
        debugLog("🔧   Notes length: \(conversation.notes?.count ?? 0)")
        
        // Save basic sentiment data to Core Data fields
        let sentiment = processedTranscript.sentimentAnalysis
        conversation.engagementLevel = sentiment.engagementLevel
        conversation.sentimentScore = sentiment.sentimentScore
        conversation.sentimentLabel = sentiment.overallSentiment

        // Store detailed sentiment JSON in app support directory (keeps notes field clean)
        let additionalSentimentData: [String: Any] = [
            "overallSentiment": sentiment.overallSentiment,
            "confidence": sentiment.confidence,
            "relationshipHealth": sentiment.relationshipHealth,
            "communicationStyle": sentiment.communicationStyle,
            "energyLevel": sentiment.energyLevel,
            "keyObservations": sentiment.keyObservations,
            "supportNeeds": sentiment.supportNeeds,
            "followUpRecommendations": sentiment.followUpRecommendations,
            "riskFactors": sentiment.riskFactors,
            "strengths": sentiment.strengths
        ]

        if let conversationId = conversation.uuid,
           let jsonData = try? JSONSerialization.data(withJSONObject: additionalSentimentData, options: .prettyPrinted) {
            saveSentimentData(jsonData, forConversation: conversationId)
        }
        
        // Link ALL participants to conversation and save voice embeddings
        debugLog("🔗 Linking conversation to \(selectedParticipants.count) participants")
        for participant in selectedParticipants {
            if participant.isCurrentUser {
                debugLog("⏭️ Skipping current user: \(participant.name)")
                continue
            }
            debugLog("🔗 Processing participant: \(participant.name)")
            guard let person = participantReplacements[participant.name] ??
                                (participant.existingPersonId != nil ? findPersonById(participant.existingPersonId!) : nil) ??
                                findOrCreatePerson(named: participant.name, context: context) else {
                debugLog("⚠️ Could not find/create person for: \(participant.name)")
                continue
            }
            debugLog("🔗 Found/created person: \(person.name ?? "Unknown") (ID: \(person.objectID))")

            // Set first non-current-user as primary person (backward compat with to-one relationship)
            if conversation.person == nil && !participant.isCurrentUser {
                conversation.person = person
                debugLog("🔗 Set as primary person for conversation")
            }

            // Voice learning: save voice embedding to Person record for future matching
            if let embedding = participant.voiceEmbedding, !embedding.isEmpty {
                person.addVoiceEmbedding(embedding)
                debugLog("🎤 Saved voice embedding to \(person.wrappedName) (samples: \(person.voiceSampleCount))")
            }
        }

        // Save context
        do {
            try context.save()
            
            // Sync happens automatically via CloudKit
            
            debugLog("✅ Conversation saved successfully with enhanced sentiment data")
            
            // Debug: Verify the conversation was actually saved
            debugLog("🔧 After save - conversation details:")
            debugLog("🔧   Object ID: \(conversation.objectID)")
            debugLog("🔧   UUID: \(conversation.uuid?.uuidString ?? "nil")")
            debugLog("🔧   Date: \(conversation.date?.description ?? "nil")")
            debugLog("🔧   Summary: \(conversation.summary?.prefix(50) ?? "nil")...")
            debugLog("🔧   Notes length: \(conversation.notes?.count ?? 0)")
            
            // Debug: Verify the relationship was established
            if let savedPerson = conversation.person {
                debugLog("✅ Conversation linked to person: \(savedPerson.name ?? "Unknown")")
                debugLog("✅ Person now has \(savedPerson.conversations?.count ?? 0) conversations")
                
                // Debug: Check if the person's conversations include our new one
                if let conversations = savedPerson.conversations?.allObjects as? [Conversation] {
                    debugLog("🔧 Person's conversations:")
                    for conv in conversations {
                        debugLog("🔧   - \(conv.uuid?.uuidString ?? "no-uuid") on \(conv.date?.description ?? "no-date")")
                    }
                }
            } else {
                debugLog("❌ WARNING: Conversation was not linked to any person!")
            }
            
            // Post notification to refresh any PersonDetailViews
            NotificationCenter.default.post(name: .conversationSaved, object: nil)
            
            showingSaveConfirmation = true
        } catch {
            debugLog("❌ Error saving conversation: \(error)")
            saveErrorMessage = "Failed to save conversation: \(error.localizedDescription)"
            showingSaveError = true
        }
    }

    private func saveAsGroupMeeting() {
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        debugLog("🔧 [GroupMeeting] Using context: \(context)")

        // 1. Resolve or create the Group
        let group: WhoNext.Group
        if let existing = selectedGroup {
            group = existing
        } else {
            let trimmedName = newGroupName.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else {
                debugLog("❌ [GroupMeeting] No group name provided")
                return
            }
            group = WhoNext.Group(context: context)
            group.identifier = UUID()
            group.name = trimmedName
            group.createdAt = Date()
            debugLog("👥 [GroupMeeting] Created new group: \(trimmedName)")
        }

        // 2. Create GroupMeeting
        let meeting = GroupMeeting(context: context)
        meeting.identifier = UUID()
        let selectedDate = useCurrentDate ? Date() : meetingDate
        meeting.date = selectedDate
        meeting.title = editedTitle
        meeting.summary = editedSummary
        meeting.notes = editedSummary
        meeting.transcript = processedTranscript.originalTranscript.rawText
        meeting.duration = Int32(processedTranscript.recordingDuration)
        meeting.sentimentScore = Double(processedTranscript.sentimentAnalysis.sentimentScore)
        meeting.createdAt = Date()

        // 3. Link to Group
        meeting.group = group

        // 4. For each selected participant, link to meeting and group
        debugLog("🔗 [GroupMeeting] Linking \(selectedParticipants.count) participants")
        for participant in selectedParticipants {
            if participant.isCurrentUser {
                debugLog("⏭️ [GroupMeeting] Skipping current user: \(participant.name)")
                continue
            }
            guard let person = participantReplacements[participant.name] ??
                                (participant.existingPersonId != nil ? findPersonById(participant.existingPersonId!) : nil) ??
                                findOrCreatePerson(named: participant.name, context: context) else {
                debugLog("⚠️ [GroupMeeting] Could not find/create person for: \(participant.name)")
                continue
            }

            meeting.addToAttendees(person)
            group.addToMembers(person)
            debugLog("🔗 [GroupMeeting] Added \(person.wrappedName) as attendee and group member")

            // Save voice embeddings (same as existing flow)
            if let embedding = participant.voiceEmbedding, !embedding.isEmpty {
                person.addVoiceEmbedding(embedding)
                debugLog("🎤 [GroupMeeting] Saved voice embedding to \(person.wrappedName)")
            }
        }

        // 5. Update group.lastMeetingDate
        if group.lastMeetingDate == nil || selectedDate > (group.lastMeetingDate ?? .distantPast) {
            group.lastMeetingDate = selectedDate
        }

        // 6. Save sentiment data file (reuse existing helper)
        let sentiment = processedTranscript.sentimentAnalysis
        let additionalSentimentData: [String: Any] = [
            "overallSentiment": sentiment.overallSentiment,
            "confidence": sentiment.confidence,
            "relationshipHealth": sentiment.relationshipHealth,
            "communicationStyle": sentiment.communicationStyle,
            "energyLevel": sentiment.energyLevel,
            "keyObservations": sentiment.keyObservations,
            "supportNeeds": sentiment.supportNeeds,
            "followUpRecommendations": sentiment.followUpRecommendations,
            "riskFactors": sentiment.riskFactors,
            "strengths": sentiment.strengths
        ]

        if let meetingId = meeting.identifier,
           let jsonData = try? JSONSerialization.data(withJSONObject: additionalSentimentData, options: .prettyPrinted) {
            saveSentimentData(jsonData, forConversation: meetingId)
        }

        // Save context
        do {
            try context.save()
            debugLog("✅ [GroupMeeting] Saved successfully: \(editedTitle)")
            debugLog("✅ [GroupMeeting] Group: \(group.name ?? "Unknown"), Attendees: \(meeting.attendeeCount)")

            // 7. Post notification to refresh views
            NotificationCenter.default.post(name: .groupMeetingSaved, object: nil)
            NotificationCenter.default.post(name: .conversationSaved, object: nil)

            showingSaveConfirmation = true
        } catch {
            debugLog("❌ [GroupMeeting] Error saving: \(error)")
            saveErrorMessage = "Failed to save group meeting: \(error.localizedDescription)"
            showingSaveError = true
        }
    }

    private func saveSentimentData(_ data: Data, forConversation id: UUID) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SentimentData", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(id.uuidString).json")
            try data.write(to: file)
            debugLog("📊 Saved sentiment data to \(file.lastPathComponent)")
        } catch {
            debugLog("⚠️ Failed to save sentiment data: \(error)")
        }
    }

    private func findOrCreatePerson(named name: String, context: NSManagedObjectContext) -> Person? {
        debugLog("👤 Finding or creating person: '\(name)'")

        // Check if this is the current user - should not create Person record for user
        if UserProfile.shared.isCurrentUser(name) {
            debugLog("⚠️ Attempted to create Person record for current user '\(name)' - skipping")
            return nil
        }

        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "name == %@", name)

        do {
            let people = try context.fetch(request)
            if let existingPerson = people.first {
                debugLog("👤 Found existing person: \(existingPerson.name ?? "Unknown") (ID: \(existingPerson.objectID))")
                return existingPerson
            }
        } catch {
            debugLog("👤 Error fetching person: \(error)")
        }

        // Create new person
        debugLog("👤 Creating new person: '\(name)'")
        let newPerson = Person(context: context)
        newPerson.identifier = UUID()
        newPerson.name = name
        debugLog("👤 Created new person: \(newPerson.name ?? "Unknown") (ID: \(newPerson.objectID))")
        return newPerson
    }
    
    private func searchPeople(for participantName: String, query: String) {
        debugLog("🔍 Searching for participant: \(participantName), query: '\(query)'")
        
        // Use consistent context - same logic as saveConversation
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        
        debugLog("🔍 Using context: \(context == viewContext ? "viewContext" : "sharedContext")")
        
        if query.isEmpty {
            searchResults[participantName] = []
            return
        }
        
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 10
        
        do {
            debugLog("🔍 Executing Core Data fetch request...")
            let results = try context.fetch(request)
            debugLog("🔍 Found \(results.count) results")
            for person in results {
                debugLog("🔍 - \(person.name ?? "Unknown") (\(person.role ?? "No role"))")
            }
            searchResults[participantName] = results
        } catch {
            debugLog("🔍 Error searching people: \(error)")
            searchResults[participantName] = []
        }
    }
    
    private func searchPeopleManual(query: String) {
        // Reuse existing Core Data search logic without participant-specific dictionaries
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        if query.isEmpty {
            manualSearchResults = []
            return
        }
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 10
        do {
            manualSearchResults = try context.fetch(request)
        } catch {
            debugLog("🔍 Error searching manual people: \(error)")
            manualSearchResults = []
        }
    }
    
    private func addManualParticipant(for person: Person) {
        let name = person.name ?? "Unknown"
        let newParticipant = ParticipantInfo(name: name, speakingTime: 0, messageCount: 0, detectedSentiment: "neutral", existingPersonId: person.identifier)
        // Avoid duplicates
        guard !manualParticipants.contains(newParticipant) else { return }
        manualParticipants.append(newParticipant)
        selectedParticipants.insert(newParticipant)
        participantReplacements[name] = person // mark as resolved so inner search hidden
        // Clear search state
        manualSearchQuery = ""
        manualSearchResults = []
    }
    
    private func findPersonById(_ id: UUID) -> Person? {
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "identifier == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            debugLog("❌ Error finding person by ID: \(error)")
            return nil
        }
    }

    /// Mark a participant as the current user and update user profile
    private func markAsCurrentUser(_ participant: ParticipantInfo) {
        markedAsCurrentUserNames.insert(participant.name)
        debugLog("🙋 User identified themselves as: \(participant.name)")

        // Update UserProfile with the participant's name if not already set
        if UserProfile.shared.name.isEmpty {
            UserProfile.shared.name = participant.name
            debugLog("✅ Updated UserProfile name to: \(participant.name)")
        }

        // Save voice embedding to UserProfile for future auto-identification.
        // This enables DiarizationManager.identifyUserSpeaker() which checks UserProfile.
        if let embedding = participant.voiceEmbedding, !embedding.isEmpty {
            UserProfile.shared.addVoiceSample(embedding)
            debugLog("🎤 Saved voice embedding to UserProfile (samples: \(UserProfile.shared.voiceSampleCount))")
        } else {
            debugLog("💡 No voice embedding available for this participant.")
            debugLog("💡 Use Settings > General > Voice Recognition to train your voice")
        }
    }

    private func participantCard(for participant: ParticipantInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Avatar
                Circle()
                    .fill(sentimentColor(participant.detectedSentiment))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(participant.name.prefix(1)))
                            .font(.headline)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(participant.name)
                        .font(.headline)
                    
                    // Show auto-match status or replacement person
                    if let replacementPerson = participantReplacements[participant.name] {
                        Text("Linked to: \(replacementPerson.name ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if let existingPersonId = participant.existingPersonId {
                        // Show auto-matched person
                        if let autoMatchedPerson = findPersonById(existingPersonId) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Auto-matched: \(autoMatchedPerson.name ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    } else {
                        Text("Neutral")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Checkbox
                Button(action: {
                    if selectedParticipants.contains(where: { $0.name == participant.name }) {
                        selectedParticipants.remove(participant)
                    } else {
                        selectedParticipants.insert(participant)
                    }
                }) {
                    Image(systemName: selectedParticipants.contains(where: { $0.name == participant.name }) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedParticipants.contains(where: { $0.name == participant.name }) ? .blue : .gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Search field for this participant (only show if no replacement is set and no auto-match confirmed)
            if participantReplacements[participant.name] == nil &&
               !(participant.existingPersonId != nil && autoMatchConfirmed[participant.name] == true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Link to existing contact:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    TextField("Search your contacts to link this participant...", text: Binding(
                        get: { searchQueries[participant.name] ?? "" },
                        set: { newValue in
                            searchQueries[participant.name] = newValue
                            searchPeople(for: participant.name, query: newValue)
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                }
                
                // Search results
                if let results = searchResults[participant.name], !results.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(results, id: \.objectID) { person in
                            Button(action: {
                                participantReplacements[participant.name] = person
                                searchQueries[participant.name] = ""
                                searchResults[participant.name] = []
                            }) {
                                HStack {
                                    Text(person.name ?? "Unknown")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(person.role ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // "This is me" button - for user self-identification and voice training
            if !participant.isCurrentUser && !markedAsCurrentUserNames.contains(participant.name) {
                HStack(spacing: 8) {
                    Button {
                        markAsCurrentUser(participant)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                            Text("This is me")
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .tertiary, size: .small))
                    .help("Identify yourself and optionally train voice recognition")
                }
                .padding(.horizontal)
                .padding(.top, 4)
            } else {
                // Show that this is the current user
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                    Text("This is you")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            // Auto-match confirmation buttons (only show if auto-matched but not confirmed)
            if let existingPersonId = participant.existingPersonId,
               participantReplacements[participant.name] == nil,
               autoMatchConfirmed[participant.name] != true,
               let autoMatchedPerson = findPersonById(existingPersonId) {
                HStack {
                    Button("Use \(autoMatchedPerson.name ?? "Unknown")") {
                        autoMatchConfirmed[participant.name] = true
                        // Set the replacement to the auto-matched person
                        participantReplacements[participant.name] = autoMatchedPerson
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .small))
                    
                    Button("Find Different Person") {
                        // Clear auto-match and show search field
                        autoMatchConfirmed[participant.name] = false
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Views
    
    struct MetricCard: View {
        let icon: String
        let title: String
        let value: String
        let color: Color
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(value)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding(12)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    struct InsightSection: View {
        let title: String
        let items: [String]
        let icon: String
        let color: Color
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.caption)
                    
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(color)
                                .font(.caption)
                            
                            Text(item)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding(12)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Color Helpers
    
    private func relationshipHealthColor(_ health: String) -> Color {
        switch health.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "concerning": return .red
        default: return .gray
        }
    }
    
    private func engagementColor(_ engagement: String) -> Color {
        switch engagement.lowercased() {
        case "high": return .green
        case "medium": return .blue
        case "low": return .orange
        default: return .gray
        }
    }
    
    private func energyColor(_ energy: String) -> Color {
        switch energy.lowercased() {
        case "high": return .yellow
        case "medium": return .blue
        case "low": return .gray
        default: return .gray
        }
    }
}

// MARK: - Preview

struct TranscriptReviewView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTranscript = ProcessedTranscript(
            summary: "Discussion about Q4 planning and budget allocation.",
            participants: [
                ParticipantInfo(name: "John Smith", speakingTime: 120.0, messageCount: 5, detectedSentiment: "positive", existingPersonId: nil),
                ParticipantInfo(name: "Sarah Johnson", speakingTime: 95.0, messageCount: 3, detectedSentiment: "concerned", existingPersonId: nil)
            ],
            keyPoints: ["Budget review", "Timeline concerns", "Resource allocation"],
            actionItems: ["Follow up on budget", "Schedule next meeting"],
            sentimentAnalysis: ContextualSentiment(
                overallSentiment: "neutral",
                sentimentScore: 0.5,
                confidence: 0.5,
                engagementLevel: "medium",
                relationshipHealth: "good",
                communicationStyle: "collaborative",
                energyLevel: "medium",
                participantDynamics: ParticipantDynamics(
                    dominantSpeaker: "balanced",
                    collaborationLevel: "medium",
                    conflictIndicators: "none"
                ),
                keyObservations: ["Sample meeting analysis"],
                supportNeeds: [],
                followUpRecommendations: [],
                riskFactors: [],
                strengths: ["Good collaboration"]
            ),
            suggestedTitle: "Q4 Planning Meeting",
            originalTranscript: TranscriptData(
                rawText: "Sample transcript",
                detectedFormat: .zoom,
                participants: ["John Smith", "Sarah Johnson"],
                timestamp: Date(),
                estimatedDuration: 1800
            ),
            preIdentifiedParticipants: nil,
            userNotes: nil,
            recordingDuration: 1800
        )
        
        TranscriptReviewView(processedTranscript: sampleTranscript)
    }
}
