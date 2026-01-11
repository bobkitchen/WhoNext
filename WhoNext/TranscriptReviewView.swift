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
    @State private var participantReplacements: [String: Person] = [:]
    @State private var searchQueries: [String: String] = [:]
    @State private var selectedSearchIndex: [String: Int] = [:]  // For keyboard navigation in dropdowns
    @State private var searchResults: [String: [Person]] = [:]
    @State private var showSummaryEditor = false
    @State private var manualSearchQuery: String = ""
    @State private var manualSearchResults: [Person] = []
    @State private var manualParticipants: [ParticipantInfo] = []
    @State private var manualSearchSelectedIndex: Int = 0  // For keyboard navigation in Add dropdown
    @State private var autoMatchConfirmed: [String: Bool] = [:]
    @State private var showFullTranscript: Bool = false

    // Action items
    @State private var actionItems: [EditableActionItem] = []

    // Meeting date handling
    @State private var meetingDate: Date = Date()
    @State private var useCurrentDate: Bool = false
    @State private var showDateWarning: Bool = false

    // Photo popover
    @State private var selectedPersonForPhoto: Person? = nil
    @State private var showingPhotoPopover: Bool = false

    // MARK: - Computed Properties

    /// Returns the transcript text with speaker labels replaced by actual participant names
    private var transcriptWithNames: String {
        replaceSpeakerLabels(in: processedTranscript.originalTranscript.rawText)
    }

    /// Replaces "Speaker N:" labels with actual participant names in the given text
    private func replaceSpeakerLabels(in text: String) -> String {
        var result = text

        // Build a mapping of speakerID to display name
        for participant in selectedParticipants {
            let displayName: String
            if participant.isCurrentUser {
                displayName = UserProfile.shared.name.isEmpty ? "Me" : UserProfile.shared.name
            } else if let replacement = participantReplacements[participant.name] {
                displayName = replacement.name ?? participant.name
            } else {
                displayName = participant.name
            }

            // Replace "Speaker N:" patterns with actual name
            // The speakerID corresponds to "Speaker N" where N is speakerID
            let speakerLabel = "Speaker \(participant.speakerID):"
            let nameLabel = "\(displayName):"

            if speakerLabel != nameLabel {
                result = result.replacingOccurrences(of: speakerLabel, with: nameLabel)
            }

            // Also handle patterns like "[Speaker N]" just in case
            let bracketSpeakerLabel = "[Speaker \(participant.speakerID)]"
            let bracketNameLabel = "[\(displayName)]"
            if bracketSpeakerLabel != bracketNameLabel {
                result = result.replacingOccurrences(of: bracketSpeakerLabel, with: bracketNameLabel)
            }

            // Handle references like "Speaker N said" or "Speaker N mentioned" in summaries
            let speakerRef = "Speaker \(participant.speakerID)"
            if result.contains(speakerRef) {
                result = result.replacingOccurrences(of: speakerRef, with: displayName)
            }
        }

        return result
    }

    /// Returns the name of the primary person (non-current-user participant) for action item assignment
    private var primaryPersonName: String? {
        // Find the first non-current-user participant
        for participant in selectedParticipants {
            if !participant.isCurrentUser {
                // Check if there's a replacement person
                if let replacement = participantReplacements[participant.name] {
                    return replacement.name
                }
                return participant.name
            }
        }
        return nil
    }

    init(processedTranscript: ProcessedTranscript) {
        self.processedTranscript = processedTranscript
        self._editedTitle = State(initialValue: processedTranscript.suggestedTitle)
        self._editedSummary = State(initialValue: processedTranscript.summary)
        self._selectedParticipants = State(initialValue: Set(processedTranscript.participants))

        // Initialize action items from processed transcript
        let editableItems = processedTranscript.actionItems.map { EditableActionItem(title: $0) }
        self._actionItems = State(initialValue: editableItems)

        // Try to infer meeting date (default to 1 hour ago if imported transcript)
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
        self._meetingDate = State(initialValue: oneHourAgo)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review & Edit")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Review the AI-generated summary and make any adjustments before saving.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // MARK: - Meeting Title (Full Width)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter meeting title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }

                // MARK: - Two-Column: Date/Time | Participants
                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Date & Time (Compact)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date & Time")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            Toggle("Now", isOn: $useCurrentDate)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .onChange(of: useCurrentDate) { _, newValue in
                                    if newValue {
                                        meetingDate = Date()
                                    }
                                }

                            if !useCurrentDate {
                                DatePicker(
                                    "",
                                    selection: $meetingDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                            } else {
                                Text(Date().formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if showDateWarning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text("Future/recent date")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(width: 280)

                    // Right Column: Participants (Flexible, Scrollable)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Participants (\(selectedParticipants.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()

                            // Add Participant button/search - more prominent
                            addParticipantControl
                        }

                        // Scrollable participant grid (handles many participants)
                        let allParticipants = processedTranscript.participants + manualParticipants
                        if !allParticipants.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allParticipants, id: \.name) { participant in
                                        compactParticipantCard(for: participant)
                                    }
                                }
                            }
                        } else {
                            Text("No participants detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
                }

                // Summary Section (with inline editing toggle)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Meeting Summary")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSummaryEditor.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showSummaryEditor ? "checkmark" : "pencil")
                                Text(showSummaryEditor ? "Done" : "Edit")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.textBackgroundColor))
                            .stroke(Color(.separatorColor), lineWidth: 0.5)

                        if showSummaryEditor {
                            // Editable TextEditor
                            TextEditor(text: $editedSummary)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                        } else {
                            // Read-only view
                            ScrollView {
                                ProfileContentView(content: editedSummary)
                                    .padding(12)
                            }
                        }
                    }
                    .frame(minHeight: 150)
                }

                // MARK: - Two-Column: Action Items | Meeting Intelligence
                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Action Items
                    ActionItemsSectionView(actionItems: $actionItems, personName: primaryPersonName)
                        .frame(maxWidth: .infinity)

                    // Right Column: Meeting Intelligence (Compact)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Meeting Intelligence")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Spacer()

                            // Sentiment score circle
                            ZStack {
                                Circle()
                                    .stroke(Color(.separatorColor), lineWidth: 3)
                                    .frame(width: 40, height: 40)

                                Circle()
                                    .trim(from: 0, to: processedTranscript.sentimentAnalysis.sentimentScore)
                                    .stroke(sentimentColor(processedTranscript.sentimentAnalysis.overallSentiment), lineWidth: 3)
                                    .frame(width: 40, height: 40)
                                    .rotationEffect(.degrees(-90))

                                Text("\(Int(processedTranscript.sentimentAnalysis.sentimentScore * 100))")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                        }

                        // Overall sentiment
                        HStack {
                            Text("Sentiment:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(processedTranscript.sentimentAnalysis.overallSentiment.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Divider()

                        // Inline metrics (vertical list, compact)
                        VStack(alignment: .leading, spacing: 6) {
                            InlineMetricRow(
                                icon: "heart.fill",
                                label: "Relationship",
                                value: processedTranscript.sentimentAnalysis.relationshipHealth.capitalized,
                                color: relationshipHealthColor(processedTranscript.sentimentAnalysis.relationshipHealth)
                            )
                            InlineMetricRow(
                                icon: "person.2.fill",
                                label: "Engagement",
                                value: processedTranscript.sentimentAnalysis.engagementLevel.capitalized,
                                color: engagementColor(processedTranscript.sentimentAnalysis.engagementLevel)
                            )
                            InlineMetricRow(
                                icon: "bubble.left.and.bubble.right.fill",
                                label: "Style",
                                value: processedTranscript.sentimentAnalysis.communicationStyle.capitalized,
                                color: .blue
                            )
                            InlineMetricRow(
                                icon: "bolt.fill",
                                label: "Energy",
                                value: processedTranscript.sentimentAnalysis.energyLevel.capitalized,
                                color: energyColor(processedTranscript.sentimentAnalysis.energyLevel)
                            )
                        }
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(width: 260)
                }

                // MARK: - Actionable Insights (2x2 Grid)
                if !processedTranscript.sentimentAnalysis.keyObservations.isEmpty ||
                   !processedTranscript.sentimentAnalysis.followUpRecommendations.isEmpty ||
                   !processedTranscript.sentimentAnalysis.supportNeeds.isEmpty ||
                   !processedTranscript.sentimentAnalysis.riskFactors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actionable Insights")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
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
                    }
                }

                // Full Transcript Section (Minimal Collapsed State)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullTranscript.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Full Transcript")
                                .font(.caption)
                                .foregroundColor(.primary)
                            Text("(\(transcriptWithNames.count) chars)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: showFullTranscript ? "chevron.up" : "chevron.down")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)

                    if showFullTranscript {
                        ScrollView {
                            Text(transcriptWithNames)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(maxHeight: 300)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(16)
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            // Bottom Action Bar
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                
                Spacer()
                
                Button("Save Conversation") {
                    saveConversation()
                    dismiss()
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                .disabled(editedTitle.isEmpty || selectedParticipants.isEmpty)
            }
            .padding()
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showingPhotoPopover) {
            if let person = selectedPersonForPhoto {
                PersonPhotoPopover(person: person)
            }
        }
    }

    // MARK: - Helper Methods
    
    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive", "happy", "excited":
            return .green
        case "negative", "sad", "angry", "frustrated":
            return .red
        case "concerned", "worried":
            return .orange
        default:
            return .blue
        }
    }
    
    private func saveConversation() {
        // Use a consistent context for all operations
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        print("🔧 Using context: \(context)")
        print("🔧 Context has coordinator: \(context.persistentStoreCoordinator != nil)")

        let conversation = Conversation(context: context)
        conversation.uuid = UUID()

        // ✅ FIX: Use the user-selected date, not current time
        let selectedDate = useCurrentDate ? Date() : meetingDate
        conversation.date = selectedDate

        // Store the title in the summary field (this is what shows in conversation lists)
        conversation.summary = editedTitle
        // Store the detailed meeting content in the notes field with proper speaker names
        let summaryWithNames = replaceSpeakerLabels(in: editedSummary)
        conversation.notes = summaryWithNames
        // Use actual duration from transcript or recording, default to 30 minutes
        let duration = processedTranscript.originalTranscript.estimatedDuration ?? 1800
        conversation.duration = Int32(duration)

        // Add audit metadata to track when record was created
        conversation.createdAt = Date()

        // Validate and log date integrity
        let now = Date()
        let hoursDifference = selectedDate.timeIntervalSince(now) / 3600
        let isInFuture = selectedDate > now
        let isVeryRecent = abs(hoursDifference) < 0.5 // Within 30 minutes

        if isInFuture {
            print("⚠️ WARNING: Meeting date is in the FUTURE (\(selectedDate.formatted()))")
        } else if isVeryRecent && !useCurrentDate {
            print("⚠️ NOTICE: Meeting date is very recent but user opted not to use current time")
        }

        print("🔧 Created conversation with:")
        print("🔧   UUID: \(conversation.uuid?.uuidString ?? "nil")")
        print("🔧   Meeting Date: \(conversation.date?.description ?? "nil") (selected by user: \(!useCurrentDate))")
        print("🔧   Created At: \(conversation.createdAt?.description ?? "nil")")
        print("🔧   Time difference from now: \(String(format: "%.1f", hoursDifference)) hours")
        print("🔧   Summary length: \(conversation.summary?.count ?? 0)")
        print("🔧   Notes length: \(conversation.notes?.count ?? 0)")
        
        // Save basic sentiment data that exists in the Core Data model
        let sentiment = processedTranscript.sentimentAnalysis
        conversation.engagementLevel = sentiment.engagementLevel
        conversation.sentimentScore = sentiment.sentimentScore
        
        // For now, store additional sentiment data in notes field as JSON
        // TODO: Update Core Data model to include all sentiment fields
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
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: additionalSentimentData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Append sentiment data to notes without overwriting the main content
            conversation.notes = summaryWithNames + "\n\n[SENTIMENT_DATA]\n" + jsonString
        }

        // Save user notes from recording (Granola-style notes taken during meeting)
        if let userNotes = processedTranscript.userNotes, !userNotes.isEmpty {
            // Convert plain text to attributed string and store as RTF
            let attributedNotes = NSAttributedString(string: userNotes, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            conversation.notesAttributedString = attributedNotes
            print("📝 Saved user notes from recording: \(userNotes.prefix(100))...")
        }

        // Create ConversationParticipant records for ALL participants (including current user)
        print("🔗 Creating \(selectedParticipants.count) participant records")

        var voiceEmbeddingsSaved = 0

        for participant in selectedParticipants {
            // Find or create the linked Person (skip for current user)
            var linkedPerson: Person? = nil

            if !participant.isCurrentUser {
                linkedPerson = participantReplacements[participant.name] ??
                              (participant.existingPersonId != nil ? findPersonById(participant.existingPersonId!) : nil) ??
                              findOrCreatePerson(named: participant.name, context: context)

                // For backward compatibility - set the first external person as the primary person
                if conversation.person == nil, let person = linkedPerson {
                    conversation.person = person
                    print("🔗 Set as primary person for conversation: \(person.name ?? "Unknown")")
                }

                // Save voice embedding to Person for future voice recognition
                // Use feedback-aware learning: boost if user confirmed a voice suggestion
                if let person = linkedPerson, let embedding = participant.voiceEmbedding, !embedding.isEmpty {
                    // Check if this was a confirmed voice match (user accepted the suggestion)
                    // High confidence (>= 0.7) indicates it was auto-suggested by voice
                    let wasVoiceSuggestion = participant.confidence >= 0.7
                    let userAcceptedSuggestion = wasVoiceSuggestion && (participantReplacements[participant.name] == nil)

                    // Use feedback-aware saving for boosted learning
                    let voicePrintManager = VoicePrintManager()
                    voicePrintManager.saveEmbeddingWithFeedback(embedding, for: person, wasConfirmed: userAcceptedSuggestion)

                    voiceEmbeddingsSaved += 1
                    let feedbackType = userAcceptedSuggestion ? "confirmed" : "new"
                    print("🎤 Saved voice embedding for \(person.name ?? "Unknown") (\(feedbackType), confidence: \(person.voiceConfidence), samples: \(person.voiceSampleCount))")
                }
            }

            // Create the ConversationParticipant record
            let conversationParticipant = ConversationParticipant.create(
                from: participant,
                in: context,
                linkedPerson: linkedPerson
            )
            // Only set ONE side of the relationship - Core Data handles the inverse automatically
            // Setting both causes an infinite loop through KVO/KVC machinery
            conversation.addToParticipants(conversationParticipant)

            let linkStatus = linkedPerson != nil ? "linked to \(linkedPerson!.name ?? "Unknown")" : (participant.isCurrentUser ? "current user" : "no person link")
            print("🔗 Created participant: \(participant.name) (\(linkStatus))")
        }

        print("✅ Created \(conversation.participantsArray.count) ConversationParticipant records")
        if voiceEmbeddingsSaved > 0 {
            print("🎤 Saved \(voiceEmbeddingsSaved) voice embeddings for future recognition")
        }

        // Create ActionItem records for included action items
        let includedActionItems = actionItems.filter { $0.isIncluded && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        print("📋 Creating \(includedActionItems.count) action item records")

        for editableItem in includedActionItems {
            let actionItem = ActionItem.create(
                in: context,
                title: editableItem.title.trimmingCharacters(in: .whitespaces),
                dueDate: editableItem.dueDate,
                priority: editableItem.priority,
                assignee: editableItem.assignee.isEmpty ? nil : editableItem.assignee,
                isMyTask: editableItem.isMyTask,
                conversation: conversation,
                person: conversation.person
            )
            print("📋 Created action item: \(actionItem.title ?? "Untitled") (owner: \(editableItem.isMyTask ? "me" : "them"))")
        }

        // Save context
        do {
            try context.save()
            // CloudKit sync happens automatically via NSPersistentCloudKitContainer
            print("✅ Conversation saved successfully with enhanced sentiment data")
            
            // Debug: Verify the conversation was actually saved
            print("🔧 After save - conversation details:")
            print("🔧   Object ID: \(conversation.objectID)")
            print("🔧   UUID: \(conversation.uuid?.uuidString ?? "nil")")
            print("🔧   Date: \(conversation.date?.description ?? "nil")")
            print("🔧   Summary: \(conversation.summary?.prefix(50) ?? "nil")...")
            print("🔧   Notes length: \(conversation.notes?.count ?? 0)")
            
            // Debug: Verify the relationship was established
            if let savedPerson = conversation.person {
                print("✅ Conversation linked to person: \(savedPerson.name ?? "Unknown")")
                print("✅ Person now has \(savedPerson.conversations?.count ?? 0) conversations")
                
                // Debug: Check if the person's conversations include our new one
                if let conversations = savedPerson.conversations?.allObjects as? [Conversation] {
                    print("🔧 Person's conversations:")
                    for conv in conversations {
                        print("🔧   - \(conv.uuid?.uuidString ?? "no-uuid") on \(conv.date?.description ?? "no-date")")
                    }
                }
            } else {
                print("❌ WARNING: Conversation was not linked to any person!")
            }
            
            // NOTE: Don't call refreshAllObjects() as it can cause crashes with CloudKit sync
            // The save() and notification below will trigger UI updates automatically

            // Post notification to refresh any PersonDetailViews
            NotificationCenter.default.post(name: NSNotification.Name("ConversationSaved"), object: nil)
            
            showingSaveConfirmation = true
        } catch {
            print("❌ Error saving conversation: \(error)")
        }
    }
    
    private func findOrCreatePerson(named name: String, context: NSManagedObjectContext) -> Person? {
        print("👤 Finding or creating person: '\(name)'")

        // Check if this is the current user - should not create Person record for user
        if UserProfile.shared.isCurrentUser(name) {
            print("⚠️ Attempted to create Person record for current user '\(name)' - skipping")
            return nil
        }

        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "name == %@", name)

        do {
            let people = try context.fetch(request)
            if let existingPerson = people.first {
                print("👤 Found existing person: \(existingPerson.name ?? "Unknown") (ID: \(existingPerson.objectID))")
                return existingPerson
            }
        } catch {
            print("👤 Error fetching person: \(error)")
        }

        // Create new person
        print("👤 Creating new person: '\(name)'")
        let newPerson = Person(context: context)
        newPerson.identifier = UUID()
        newPerson.name = name
        print("👤 Created new person: \(newPerson.name ?? "Unknown") (ID: \(newPerson.objectID))")
        return newPerson
    }
    
    private func searchPeople(for participantName: String, query: String) {
        print("🔍 Searching for participant: \(participantName), query: '\(query)'")
        
        // Use consistent context - same logic as saveConversation
        let context = viewContext.persistentStoreCoordinator != nil ? viewContext : PersistenceController.shared.container.viewContext
        
        print("🔍 Using context: \(context == viewContext ? "viewContext" : "sharedContext")")
        
        if query.isEmpty {
            searchResults[participantName] = []
            return
        }
        
        let request = NSFetchRequest<Person>(entityName: "Person")
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 10
        
        do {
            print("🔍 Executing Core Data fetch request...")
            let results = try context.fetch(request)
            print("🔍 Found \(results.count) results")
            for person in results {
                print("🔍 - \(person.name ?? "Unknown") (\(person.role ?? "No role"))")
            }
            searchResults[participantName] = results
        } catch {
            print("🔍 Error searching people: \(error)")
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
            print("🔍 Error searching manual people: \(error)")
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
            print("❌ Error finding person by ID: \(error)")
            return nil
        }
    }

    /// Mark a participant as the current user and update user profile
    private func markAsCurrentUser(_ participant: ParticipantInfo) {
        print("🙋 User identified themselves as: \(participant.name)")

        // Update UserProfile with the participant's name if not already set
        if UserProfile.shared.name.isEmpty {
            UserProfile.shared.name = participant.name
            print("✅ Updated UserProfile name to: \(participant.name)")
        }

        // Remove the participant from selected participants (users don't appear in their own meetings)
        selectedParticipants.remove(participant)

        // Show notification about voice training
        print("💡 Voice training from meetings will be available in a future update")
        print("💡 For now, use Settings > General > Voice Recognition to train your voice")

        // TODO: In the future, if this participant has a voice embedding from diarization,
        // we could save it to UserProfile.shared.addVoiceSample(embedding)
        // This would require:
        // 1. Extending ParticipantInfo to include voiceEmbedding: [Float]?
        // 2. Having DiarizationManager populate those embeddings
        // 3. Passing them through the TranscriptProcessor pipeline
    }

    private func participantCard(for participant: ParticipantInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Avatar - blue for current user, sentiment color for others
                ZStack {
                    Circle()
                        .fill(participant.isCurrentUser ? Color.blue : sentimentColor(participant.detectedSentiment))
                        .frame(width: 40, height: 40)
                    if participant.isCurrentUser {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    } else {
                        Text(String(participant.name.prefix(1)))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(participant.name)
                            .font(.headline)
                        if participant.isCurrentUser {
                            Text("(You)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    // Show status for current user or auto-match/replacement for others
                    if participant.isCurrentUser {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Identified as you during recording")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    } else if let replacementPerson = participantReplacements[participant.name] {
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
                            selectedSearchIndex[participant.name] = 0  // Reset selection
                            searchPeople(for: participant.name, query: newValue)
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .onKeyPress(.downArrow) {
                        if let results = searchResults[participant.name], !results.isEmpty {
                            let current = selectedSearchIndex[participant.name] ?? 0
                            selectedSearchIndex[participant.name] = min(current + 1, results.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        let current = selectedSearchIndex[participant.name] ?? 0
                        selectedSearchIndex[participant.name] = max(current - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let results = searchResults[participant.name], !results.isEmpty {
                            let index = selectedSearchIndex[participant.name] ?? 0
                            if index < results.count {
                                participantReplacements[participant.name] = results[index]
                                searchQueries[participant.name] = ""
                                searchResults[participant.name] = []
                                selectedSearchIndex[participant.name] = 0
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        searchQueries[participant.name] = ""
                        searchResults[participant.name] = []
                        return .handled
                    }
                }

                // Search results - visible dropdown with keyboard navigation
                if let results = searchResults[participant.name], !results.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.objectID) { index, person in
                            let isSelected = (selectedSearchIndex[participant.name] ?? 0) == index
                            Button(action: {
                                participantReplacements[participant.name] = person
                                searchQueries[participant.name] = ""
                                searchResults[participant.name] = []
                                selectedSearchIndex[participant.name] = 0
                            }) {
                                HStack {
                                    Text(person.name ?? "Unknown")
                                        .foregroundColor(isSelected ? .white : .primary)
                                    Spacer()
                                    Text(person.role ?? "")
                                        .font(.caption)
                                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.blue : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)
                }
            }

            // "This is me" button - for user self-identification and voice training
            // Skip if already identified as current user during recording OR in UserProfile
            if !participant.isCurrentUser && !UserProfile.shared.isCurrentUser(participant.name) {
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
            }
            // Note: If participant.isCurrentUser is true, the "(You)" badge is already shown above

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

    // MARK: - Add Participant Control
    /// A more prominent, keyboard-navigable control for adding participants
    @ViewBuilder
    private var addParticipantControl: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.caption)
                    .foregroundColor(.blue)

                TextField("Add participant...", text: $manualSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 150)
                    .onChange(of: manualSearchQuery) { _, newValue in
                        manualSearchSelectedIndex = 0  // Reset selection
                        if newValue.count >= 2 {
                            searchPeopleManual(query: newValue)
                        } else {
                            manualSearchResults = []
                        }
                    }
                    .onKeyPress(.downArrow) {
                        if !manualSearchResults.isEmpty {
                            manualSearchSelectedIndex = min(manualSearchSelectedIndex + 1, manualSearchResults.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        manualSearchSelectedIndex = max(manualSearchSelectedIndex - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if !manualSearchResults.isEmpty && manualSearchSelectedIndex < manualSearchResults.count {
                            let person = manualSearchResults[manualSearchSelectedIndex]
                            addManualParticipant(for: person)
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        manualSearchQuery = ""
                        manualSearchResults = []
                        return .handled
                    }

                if !manualSearchQuery.isEmpty {
                    Button(action: {
                        manualSearchQuery = ""
                        manualSearchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Visible dropdown list with keyboard navigation (matching primary dropdown style)
            if !manualSearchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(manualSearchResults.enumerated()), id: \.element.objectID) { index, person in
                        let isSelected = manualSearchSelectedIndex == index
                        Button(action: {
                            addManualParticipant(for: person)
                        }) {
                            HStack(spacing: 8) {
                                // Avatar
                                if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text(String((person.name ?? "?").prefix(1)).uppercased())
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .foregroundColor(.blue)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name ?? "Unknown")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    if let role = person.role, !role.isEmpty {
                                        Text(role)
                                            .font(.caption2)
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // Keyboard hint for selected item
                                if isSelected {
                                    Text("↵")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue : Color.clear)
                            .foregroundColor(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .frame(width: 220)
            }

            // Helper text when empty
            if manualSearchQuery.isEmpty {
                Text("Type to search contacts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Compact Participant Card (for horizontal scroll)
    private func compactParticipantCard(for participant: ParticipantInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Small avatar - show photo if linked person has one
                participantAvatar(for: participant, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(participant.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if participant.isCurrentUser {
                            Text("You")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }

                    // Status indicator
                    if let replacement = participantReplacements[participant.name] {
                        Text("→ \(replacement.name ?? "Linked")")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .lineLimit(1)
                    } else if participant.existingPersonId != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // Selection checkbox
                Button(action: {
                    if selectedParticipants.contains(where: { $0.name == participant.name }) {
                        selectedParticipants.remove(participant)
                    } else {
                        selectedParticipants.insert(participant)
                    }
                }) {
                    Image(systemName: selectedParticipants.contains(where: { $0.name == participant.name }) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedParticipants.contains(where: { $0.name == participant.name }) ? .blue : .gray)
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Link to contact field with visible dropdown
            if participantReplacements[participant.name] == nil && !participant.isCurrentUser {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Link contact...", text: Binding(
                        get: { searchQueries[participant.name] ?? "" },
                        set: { newValue in
                            searchQueries[participant.name] = newValue
                            selectedSearchIndex[participant.name] = 0  // Reset selection
                            searchPeople(for: participant.name, query: newValue)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .frame(width: 140)
                    .onKeyPress(.downArrow) {
                        if let results = searchResults[participant.name], !results.isEmpty {
                            let current = selectedSearchIndex[participant.name] ?? 0
                            selectedSearchIndex[participant.name] = min(current + 1, results.count - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        let current = selectedSearchIndex[participant.name] ?? 0
                        selectedSearchIndex[participant.name] = max(current - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let results = searchResults[participant.name], !results.isEmpty {
                            let index = selectedSearchIndex[participant.name] ?? 0
                            if index < results.count {
                                participantReplacements[participant.name] = results[index]
                                searchQueries[participant.name] = ""
                                searchResults[participant.name] = []
                                selectedSearchIndex[participant.name] = 0
                            }
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        searchQueries[participant.name] = ""
                        searchResults[participant.name] = []
                        return .handled
                    }

                    // Visible dropdown list
                    if let results = searchResults[participant.name], !results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.objectID) { index, person in
                                let isSelected = (selectedSearchIndex[participant.name] ?? 0) == index
                                Button(action: {
                                    participantReplacements[participant.name] = person
                                    searchQueries[participant.name] = ""
                                    searchResults[participant.name] = []
                                    selectedSearchIndex[participant.name] = 0
                                }) {
                                    HStack {
                                        Text(person.name ?? "Unknown")
                                            .font(.caption2)
                                            .lineLimit(1)
                                        Spacer()
                                        if let role = person.role, !role.isEmpty {
                                            Text(role)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.blue : Color.clear)
                                    .foregroundColor(isSelected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(.separatorColor), lineWidth: 0.5)
                        )
                        .frame(width: 140)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
        .frame(minWidth: 160)
    }

    // MARK: - Participant Avatar

    /// Shows the person's photo if linked and available, otherwise shows initials
    /// Photos are clickable and show a larger popover view
    @ViewBuilder
    private func participantAvatar(for participant: ParticipantInfo, size: CGFloat) -> some View {
        let linkedPerson = participantReplacements[participant.name]

        ZStack {
            if participant.isCurrentUser {
                // Current user - blue circle with person icon
                Circle()
                    .fill(Color.blue)
                    .frame(width: size, height: size)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            } else if let person = linkedPerson, let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                // Linked person with photo - clickable to show larger version
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        selectedPersonForPhoto = person
                        showingPhotoPopover = true
                    }
                    .help("Click to see larger photo")
            } else {
                // Fallback to initials
                Circle()
                    .fill(sentimentColor(participant.detectedSentiment))
                    .frame(width: size, height: size)
                Text(participantInitials(for: participant, linkedPerson: linkedPerson))
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }

    /// Get initials for participant - use linked person's name if available
    private func participantInitials(for participant: ParticipantInfo, linkedPerson: Person?) -> String {
        let name = linkedPerson?.name ?? participant.name
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Person Photo Popover

/// A popover view showing a larger version of a person's photo
struct PersonPhotoPopover: View {
    let person: Person
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Header with name and close button
            HStack {
                Text(person.name ?? "Contact")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)

            // Large photo
            if let photoData = person.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                // Fallback if no photo (shouldn't happen since we only show this for people with photos)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 200, height: 200)
                    Image(systemName: "person.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                }
            }

            // Person details
            if let role = person.role, !role.isEmpty {
                Text(role)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            } else {
                Spacer()
                    .frame(height: 8)
            }
        }
        .frame(minWidth: 320, minHeight: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

extension TranscriptReviewView {
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

    struct InlineMetricRow: View {
        let icon: String
        let label: String
        let value: String
        let color: Color

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                    .frame(width: 14)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
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

// MARK: - Editable Action Item

/// Represents an action item that can be edited before saving
struct EditableActionItem: Identifiable {
    let id = UUID()
    var title: String
    var isIncluded: Bool = true
    var priority: ActionItem.Priority = .medium
    var dueDate: Date? = nil
    var isMyTask: Bool = false
    var assignee: String = ""
}

// MARK: - Action Items Section View

struct ActionItemsSectionView: View {
    @Binding var actionItems: [EditableActionItem]
    var personName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Action Items", systemImage: "checkmark.circle")
                    .font(.headline)

                Spacer()

                Button(action: addNewItem) {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if actionItems.isEmpty {
                Text("No action items extracted from this meeting")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.vertical, 8)
            } else {
                ForEach($actionItems) { $item in
                    ActionItemEditRow(item: $item, personName: personName, onDelete: {
                        actionItems.removeAll { $0.id == item.id }
                    })
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func addNewItem() {
        actionItems.append(EditableActionItem(title: ""))
    }
}

struct ActionItemEditRow: View {
    @Binding var item: EditableActionItem
    var personName: String?
    let onDelete: () -> Void

    @State private var showingDetails = false
    @State private var ownerSelection: String = "them"

    private var ownerBindingValue: String {
        if item.isMyTask {
            return "me"
        } else if !item.assignee.isEmpty && item.assignee != personName {
            return "other"
        } else {
            return "them"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Include checkbox
                Toggle("", isOn: $item.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                // Title field
                TextField("Action item...", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .opacity(item.isIncluded ? 1 : 0.5)

                // Owner picker
                Picker("Owner", selection: $ownerSelection) {
                    Text("Me").tag("me")
                    if let name = personName, !name.isEmpty {
                        Text(name).tag("them")
                    } else {
                        Text("Them").tag("them")
                    }
                    Text("Other...").tag("other")
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .disabled(!item.isIncluded)
                .onChange(of: ownerSelection) { newValue in
                    item.isMyTask = (newValue == "me")
                    if newValue == "me" {
                        item.assignee = ""
                    } else if newValue == "them" {
                        item.assignee = personName ?? ""
                    }
                }

                // Priority picker
                Picker("", selection: $item.priority) {
                    Text("High").tag(ActionItem.Priority.high)
                    Text("Med").tag(ActionItem.Priority.medium)
                    Text("Low").tag(ActionItem.Priority.low)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .disabled(!item.isIncluded)

                // Expand/collapse
                Button(action: { showingDetails.toggle() }) {
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // Expanded details
            if showingDetails {
                HStack(spacing: 16) {
                    // Custom assignee field (only shown when "Other" is selected)
                    if ownerSelection == "other" {
                        HStack {
                            Image(systemName: "person")
                                .foregroundColor(.secondary)
                            TextField("Assignee name", text: $item.assignee)
                                .textFieldStyle(.plain)
                                .font(.caption)
                        }
                        .frame(maxWidth: 150)
                    }

                    // Due date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { item.dueDate ?? Date() },
                                set: { item.dueDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .font(.caption)

                        if item.dueDate != nil {
                            Button(action: { item.dueDate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                }
                .padding(.leading, 28)
            }
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            ownerSelection = ownerBindingValue
        }
        .cornerRadius(8)
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
            userNotes: nil
        )

        TranscriptReviewView(processedTranscript: sampleTranscript)
    }
}
