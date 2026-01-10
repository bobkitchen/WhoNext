import CoreData
import SwiftUI

struct ConversationDetailView: View {
    var conversation: Conversation
    var conversationManager: ConversationStateManager?
    var isInitiallyEditing: Bool = false

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedSummary: String = ""
    @State private var editedDuration: Double = 30.0
    @State private var editedDate: Date = Date()
    @State private var showingDeleteAlert = false
    @State private var showingSaveConfirmation = false
    @State private var sentimentData: ContextualSentiment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Meeting Details title and buttons
                HStack(alignment: .top) {
                    Text("Meeting Details")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this conversation")
                        
                        if isEditing {
                            Button(action: {
                                loadConversationData() // Reset to original values
                                isEditing = false
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Cancel editing and discard changes")
                        }
                        
                        Button(action: {
                            if isEditing {
                                saveChanges()
                            } else {
                                isEditing.toggle()
                            }
                        }) {
                            Text(isEditing ? "Done" : "Edit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(isEditing ? "Save changes and finish editing" : "Edit conversation details")
                    }
                }
                
                // Meeting Details Content
                meetingDetailsContent
                
                // Summary Section
                summarySection
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadConversationData()
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteConversation()
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
        .alert("Conversation Updated", isPresented: $showingSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Your changes have been saved successfully.")
        }
    }
    
    // MARK: - Meeting Details Content
    private var meetingDetailsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isEditing {
                        TextField("Enter conversation title", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    } else {
                        Text(editedTitle.isEmpty ? "Untitled Conversation" : editedTitle)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
                
                HStack(spacing: 24) {
                    // Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isEditing {
                            DatePicker("", selection: $editedDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        } else {
                            Text(editedDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                        }
                    }
                    
                    // Duration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Duration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isEditing {
                            HStack {
                                TextField("Duration", value: $editedDuration, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("minutes")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("\(Int(editedDuration)) minutes")
                                .font(.body)
                        }
                    }
                    
                    // Sentiment Analysis (when available and not editing)
                    if let sentiment = sentimentData, !isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sentiment")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 8) {
                                // Sentiment indicator circle
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                        .frame(width: 24, height: 24)
                                    
                                    Circle()
                                        .trim(from: 0, to: sentiment.sentimentScore)
                                        .stroke(sentimentColor(sentiment.overallSentiment), lineWidth: 3)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 24, height: 24)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sentiment.overallSentiment.capitalized)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(sentimentColor(sentiment.overallSentiment))
                                    
                                    Text("\(Int(sentiment.sentimentScore * 100))% • \(sentiment.relationshipHealth.capitalized)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Summary Section
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)
            
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit the conversation summary below:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $editedSummary)
                        .font(.body)
                        .padding(12)
                        .frame(minHeight: 200)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if editedSummary.isEmpty {
                            Text("No summary available.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ProfileContentView(content: editedSummary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Helper Functions
    private func loadConversationData() {
        editedTitle = Self.extractTitle(from: conversation.summary)
        editedSummary = extractCleanSummary(from: conversation.notes)
        editedDuration = Double(conversation.duration)
        editedDate = conversation.date ?? Date()
        isEditing = isInitiallyEditing
        
        // Parse sentiment data from notes
        sentimentData = parseSentimentData(from: conversation.notes)
    }
    
    private static func extractTitle(from summary: String?) -> String {
        guard let summary = summary, !summary.isEmpty else { return "" }
        return summary.components(separatedBy: .newlines).first ?? ""
    }
    
    private func extractCleanSummary(from notes: String?) -> String {
        guard let notes = notes else { return "" }
        
        // Remove sentiment data section if it exists
        if let sentimentRange = notes.range(of: "\n\n[SENTIMENT_DATA]\n") {
            return String(notes[..<sentimentRange.lowerBound])
        }
        
        return notes
    }
    
    private func parseSentimentData(from notes: String?) -> ContextualSentiment? {
        guard let notes = notes,
              let sentimentRange = notes.range(of: "\n\n[SENTIMENT_DATA]\n") else {
            // Create basic sentiment from Core Data fields
            return ContextualSentiment(
                overallSentiment: conversation.sentimentScore > 0.6 ? "positive" : (conversation.sentimentScore < 0.4 ? "negative" : "neutral"),
                sentimentScore: conversation.sentimentScore,
                confidence: 0.8,
                engagementLevel: conversation.engagementLevel ?? "medium",
                relationshipHealth: "good",
                communicationStyle: "collaborative",
                energyLevel: "medium",
                participantDynamics: ParticipantDynamics(
                    dominantSpeaker: "balanced",
                    collaborationLevel: "high",
                    conflictIndicators: "none"
                ),
                keyObservations: [],
                supportNeeds: [],
                followUpRecommendations: [],
                riskFactors: [],
                strengths: []
            )
        }
        
        let jsonString = String(notes[sentimentRange.upperBound...])
        
        guard let jsonData = jsonString.data(using: .utf8),
              let sentimentDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        return ContextualSentiment(
            overallSentiment: sentimentDict["overallSentiment"] as? String ?? "neutral",
            sentimentScore: sentimentDict["sentimentScore"] as? Double ?? conversation.sentimentScore,
            confidence: sentimentDict["confidence"] as? Double ?? 0.8,
            engagementLevel: sentimentDict["engagementLevel"] as? String ?? conversation.engagementLevel ?? "medium",
            relationshipHealth: sentimentDict["relationshipHealth"] as? String ?? "good",
            communicationStyle: sentimentDict["communicationStyle"] as? String ?? "collaborative",
            energyLevel: sentimentDict["energyLevel"] as? String ?? "medium",
            participantDynamics: ParticipantDynamics(
                dominantSpeaker: "balanced",
                collaborationLevel: "high",
                conflictIndicators: "none"
            ),
            keyObservations: sentimentDict["keyObservations"] as? [String] ?? [],
            supportNeeds: sentimentDict["supportNeeds"] as? [String] ?? [],
            followUpRecommendations: sentimentDict["followUpRecommendations"] as? [String] ?? [],
            riskFactors: sentimentDict["riskFactors"] as? [String] ?? [],
            strengths: sentimentDict["strengths"] as? [String] ?? []
        )
    }
    
    private func saveChanges() {
        // Update conversation with edited values
        conversation.summary = editedTitle.isEmpty ? "Untitled Meeting" : editedTitle
        conversation.duration = Int32(editedDuration)
        conversation.date = editedDate
        
        // Reconstruct notes with sentiment data
        var updatedNotes = editedSummary
        
        if let sentiment = sentimentData {
            let sentimentDict: [String: Any] = [
                "overallSentiment": sentiment.overallSentiment,
                "sentimentScore": sentiment.sentimentScore,
                "confidence": sentiment.confidence,
                "relationshipHealth": sentiment.relationshipHealth,
                "communicationStyle": sentiment.communicationStyle,
                "engagementLevel": sentiment.engagementLevel,
                "energyLevel": sentiment.energyLevel,
                "keyObservations": sentiment.keyObservations,
                "supportNeeds": sentiment.supportNeeds,
                "followUpRecommendations": sentiment.followUpRecommendations,
                "riskFactors": sentiment.riskFactors,
                "strengths": sentiment.strengths
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: sentimentDict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                updatedNotes += "\n\n[SENTIMENT_DATA]\n" + jsonString
            }
        }
        
        conversation.notes = updatedNotes
        conversation.modifiedAt = Date() // Mark as modified for sync
        
        // Save to Core Data
        do {
            try viewContext.save()
            // CloudKit sync happens automatically via NSPersistentCloudKitContainer
            isEditing = false
            showingSaveConfirmation = true

            // Post notification to refresh PersonDetailView
            NotificationCenter.default.post(name: NSNotification.Name("ConversationUpdated"), object: nil)
        } catch {
            print("Failed to save conversation changes: \(error)")
        }
    }

    private func deleteConversation() {
        // Delete locally - CloudKit sync handles propagation automatically
        viewContext.delete(conversation)
        try? viewContext.save()
        dismiss()
    }
    
    // MARK: - Static Methods
    
    static func formattedWindowTitle(for conversation: Conversation, person: Person) -> String {
        let title = Self.extractTitle(from: conversation.summary)
        let personName = person.name ?? "Unknown"
        return "\(title) - \(personName)"
    }
    
    // MARK: - Helper Methods
    
    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive": return .green
        case "negative": return .red
        case "neutral": return .orange
        default: return .gray
        }
    }
    
    private func relationshipHealthColor(_ health: String) -> Color {
        switch health.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "poor": return .red
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
        case "high": return .green
        case "medium": return .blue
        case "low": return .orange
        default: return .gray
        }
    }
}

// MARK: - Helper Views

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
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
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
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
