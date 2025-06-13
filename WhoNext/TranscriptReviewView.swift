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
    @State private var searchResults: [String: [Person]] = [:]
    @State private var showSummaryEditor = false
    
    init(processedTranscript: ProcessedTranscript) {
        self.processedTranscript = processedTranscript
        self._editedTitle = State(initialValue: processedTranscript.suggestedTitle)
        self._editedSummary = State(initialValue: processedTranscript.summary)
        self._selectedParticipants = State(initialValue: Set(processedTranscript.participants))
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
                
                // Participants Section
                if !processedTranscript.participants.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Participants (\(selectedParticipants.count))")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(processedTranscript.participants, id: \.name) { participant in
                                ParticipantCard(
                                    participant: participant,
                                    replacementPerson: participantReplacements[participant.name],
                                    searchQuery: searchQueries[participant.name] ?? "",
                                    searchResults: searchResults[participant.name] ?? [],
                                    onToggle: { isSelected in
                                        if isSelected {
                                            selectedParticipants.insert(participant)
                                        } else {
                                            selectedParticipants.remove(participant)
                                        }
                                    },
                                    onSearchQueryChanged: { query in
                                        searchQueries[participant.name] = query
                                        searchPeople(for: participant.name, query: query)
                                    },
                                    onPersonSelected: { person in
                                        participantReplacements[participant.name] = person
                                        searchQueries[participant.name] = ""
                                        searchResults[participant.name] = []
                                    },
                                    onClearReplacement: {
                                        participantReplacements[participant.name] = nil
                                        searchQueries[participant.name] = ""
                                        searchResults[participant.name] = []
                                    }
                                )
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Participants")
                            .font(.headline)
                        
                        Text("No participants detected in transcript. You can manually add participants below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        
                        // Simple manual participant addition
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Participants Manually")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Use the search function in the main app to find and add people to this conversation after saving.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(6)
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
                                Text(AttributedString(MarkdownHelper.attributedString(from: editedSummary)))
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Divider()
                                    .padding(.vertical, 8)
                                
                                // Edit button to switch to text editor
                                Button("Edit Summary") {
                                    showSummaryEditor.toggle()
                                }
                                .buttonStyle(.bordered)
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
                            .buttonStyle(.borderedProminent)
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
                
                Spacer(minLength: 100)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            // Bottom Action Bar
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save Conversation") {
                    saveConversation()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedTitle.isEmpty || selectedParticipants.isEmpty)
            }
            .padding()
            .background(.regularMaterial)
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
        conversation.date = Date()
        conversation.summary = editedSummary
        // Store the detailed notes properly (not the title)
        conversation.notes = editedSummary // The detailed meeting notes
        conversation.duration = 30 // Default duration
        
        print("🔧 Created conversation with:")
        print("🔧   UUID: \(conversation.uuid?.uuidString ?? "nil")")
        print("🔧   Date: \(conversation.date?.description ?? "nil")")
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
            conversation.notes = editedSummary + "\n\n[SENTIMENT_DATA]\n" + jsonString
        }
        
        // Link to participants using the same context
        print("🔗 Linking conversation to \(selectedParticipants.count) participants")
        for participant in selectedParticipants {
            print("🔗 Processing participant: \(participant.name)")
            let person = participantReplacements[participant.name] ?? findOrCreatePerson(named: participant.name, context: context)
            print("🔗 Found/created person: \(person.name ?? "Unknown") (ID: \(person.objectID))")
            
            // For the primary person relationship (maintaining backward compatibility)
            if conversation.person == nil {
                conversation.person = person
                print("🔗 Set as primary person for conversation")
            }
            
            // TODO: Add support for multiple participants when Core Data model is updated
        }
        
        // Save context
        do {
            try context.save()
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
            
            // Refresh the context to ensure UI updates
            context.refreshAllObjects()
            
            // Post notification to refresh any PersonDetailViews
            NotificationCenter.default.post(name: NSNotification.Name("ConversationSaved"), object: nil)
            
            showingSaveConfirmation = true
        } catch {
            print("❌ Error saving conversation: \(error)")
        }
    }
    
    private func findOrCreatePerson(named name: String, context: NSManagedObjectContext) -> Person {
        print("👤 Finding or creating person: '\(name)'")
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

// MARK: - ParticipantCard

struct ParticipantCard: View {
    let participant: ParticipantInfo
    let replacementPerson: Person?
    let searchQuery: String
    let searchResults: [Person]
    let onToggle: (Bool) -> Void
    let onSearchQueryChanged: (String) -> Void
    let onPersonSelected: (Person) -> Void
    let onClearReplacement: () -> Void
    @State private var isSelected = true
    @State private var localSearchQuery = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(participant.name.prefix(1).uppercased())
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(participant.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let replacementPerson = replacementPerson {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                            Text(replacementPerson.name ?? "Unknown")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Text(participant.detectedSentiment.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isSelected)
                    .labelsHidden()
                    .onChange(of: isSelected) { _, newValue in
                        onToggle(newValue)
                    }
            }
            
            // Search section
            if replacementPerson == nil {
                HStack(spacing: 8) {
                    TextField("Search for correct person...", text: $localSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            print("🔍 ParticipantCard onSubmit triggered with: '\(localSearchQuery)'")
                            onSearchQueryChanged(localSearchQuery)
                        }
                        .onChange(of: localSearchQuery) { _, newValue in
                            print("🔍 ParticipantCard search query changed: '\(newValue)'")
                            if newValue.count > 2 {
                                print("🔍 Triggering search for: '\(newValue)'")
                                onSearchQueryChanged(newValue)
                            }
                        }
                    
                    if !searchResults.isEmpty {
                        Menu {
                            ForEach(searchResults.indices, id: \.self) { index in
                                Button(action: {
                                    onPersonSelected(searchResults[index])
                                    localSearchQuery = ""
                                }) {
                                    Text(searchResults[index].name ?? "Unknown")
                                }
                            }
                        } label: {
                            Text("Select (\(searchResults.count))")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            } else {
                HStack {
                    Button("Change Person") {
                        onClearReplacement()
                        localSearchQuery = ""
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            localSearchQuery = searchQuery
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
            )
        )
        
        TranscriptReviewView(processedTranscript: sampleTranscript)
    }
}
