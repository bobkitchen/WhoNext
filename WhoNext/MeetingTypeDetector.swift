import Foundation
import AVFoundation
import CoreData
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Integrates DiarizationManager with VoicePrintManager and LiveMeeting
/// Handles automatic meeting type detection and speaker identification
@MainActor
class MeetingTypeDetector: ObservableObject {
    
    // MARK: - Properties
    
    private let voicePrintManager: VoicePrintManager
    private let persistenceController: PersistenceController
    
    // Processing state
    @Published var isProcessing = false
    @Published var detectionConfidence: Float = 0.0
    
    // MARK: - Initialization
    
    init(voicePrintManager: VoicePrintManager = VoicePrintManager(),
         persistenceController: PersistenceController = PersistenceController.shared) {
        self.voicePrintManager = voicePrintManager
        self.persistenceController = persistenceController
    }
    
    // MARK: - Meeting Type Detection
    
    #if canImport(FluidAudio)
    /// Process diarization results to detect meeting type and update LiveMeeting
    func processDiarizationResults(_ results: DiarizationResult?, for meeting: LiveMeeting) {
        guard let results = results else {
            meeting.meetingType = .unknown
            meeting.detectedSpeakerCount = 0
            return
        }
        
        // Update speaker count by getting unique speaker IDs from segments
        let uniqueSpeakers = Set(results.segments.map { $0.speakerId })
        let speakerCount = uniqueSpeakers.count
        meeting.detectedSpeakerCount = speakerCount
        
        // Determine meeting type based on speaker count
        if speakerCount == 2 {
            meeting.meetingType = .oneOnOne
        } else if speakerCount > 2 {
            meeting.meetingType = .group
        } else if speakerCount == 1 {
            // Single speaker - could be a monologue or waiting for others
            meeting.meetingType = .unknown
        } else {
            meeting.meetingType = .unknown
        }
        
        // Set detection timestamp and confidence
        meeting.typeDetectionTimestamp = Date()
        meeting.speakerDetectionConfidence = calculateDetectionConfidence(results)
        
        // Update detection confidence
        self.detectionConfidence = meeting.speakerDetectionConfidence
        
        print("[MeetingTypeDetector] Detected \(speakerCount) speakers - Type: \(meeting.meetingType.displayName)")
    }
    
    /// Calculate confidence score for detection
    private func calculateDetectionConfidence(_ results: DiarizationResult) -> Float {
        // Base confidence on:
        // 1. Total speaking time (more data = higher confidence)
        // 2. Speaker separation quality
        // 3. Number of segments
        
        // Calculate total duration from segments
        let totalDuration = results.segments.reduce(0.0) { $0 + Double($1.endTimeSeconds - $1.startTimeSeconds) }
        let minDurationForHighConfidence: TimeInterval = 60.0 // 1 minute
        let durationConfidence = Float(min(totalDuration / minDurationForHighConfidence, 1.0))
        
        // Check speaker separation quality (distinct speakers should have different patterns)
        let separationConfidence = calculateSeparationConfidence(results.segments)
        
        // More segments = better confidence
        let totalSegments = results.segments.count
        let segmentConfidence = Float(min(Double(totalSegments) / 20.0, 1.0))
        
        // Weighted average
        return durationConfidence * 0.4 + separationConfidence * 0.4 + segmentConfidence * 0.2
    }
    
    /// Calculate how well-separated the speakers are
    private func calculateSeparationConfidence(_ segments: [TimedSpeakerSegment]) -> Float {
        guard segments.count > 1 else { return 1.0 }
        
        // Group segments by speaker and get average embeddings
        var speakerEmbeddings: [String: [[Float]]] = [:]
        for segment in segments {
            speakerEmbeddings[segment.speakerId, default: []].append(segment.embedding)
        }
        
        guard speakerEmbeddings.count >= 2 else { return 1.0 }
        
        // Compare embeddings between speakers
        var totalSimilarity: Float = 0.0
        var comparisons = 0
        
        let speakerIds = Array(speakerEmbeddings.keys)
        for i in 0..<speakerIds.count {
            for j in (i+1)..<speakerIds.count {
                if let embeddings1 = speakerEmbeddings[speakerIds[i]]?.first,
                   let embeddings2 = speakerEmbeddings[speakerIds[j]]?.first {
                    // Lower similarity between different speakers = better separation
                    let similarity = cosineSimilarity(embeddings1, embeddings2)
                    totalSimilarity += similarity
                    comparisons += 1
                }
            }
        }
        
        if comparisons > 0 {
            let avgSimilarity = totalSimilarity / Float(comparisons)
            // Convert to confidence: lower similarity = higher confidence
            return 1.0 - avgSimilarity
        }
        
        return 0.5 // Default medium confidence
    }
    
    // MARK: - Speaker Identification
    
    /// Identify speakers in real-time during meeting
    func identifySpeakers(from results: DiarizationResult?, for meeting: LiveMeeting) async {
        guard let results = results else { return }
        
        isProcessing = true
        
        // Build embeddings dictionary from segments
        var embeddings: [String: [Float]] = [:]
        // Group segments by speaker and take first embedding
        for segment in results.segments {
            if embeddings[segment.speakerId] == nil {
                embeddings[segment.speakerId] = segment.embedding
            }
        }
        
        // Try to match with expected participants if available
        let matches = voicePrintManager.matchToAttendees(embeddings, attendeeNames: meeting.expectedParticipants)
        
        // Update meeting with identified participants
        for (speakerId, person) in matches {
            let participant = IdentifiedParticipant()
            participant.name = "Speaker \(speakerId)"
            participant.personRecord = person
            participant.confidence = person.voiceConfidence
            // Create voice print with features from embeddings if available
            let mfccFeatures = embeddings[speakerId] ?? []
            participant.voicePrint = VoicePrint(
                createdAt: Date(),
                sampleCount: 1,
                mfccFeatures: mfccFeatures,
                spectrogramHash: ""
            )
            
            // Check if already in list
            // Check if person already identified
            if !meeting.identifiedParticipants.contains(where: { $0.personRecord?.id == person.id }) {
                meeting.identifiedParticipants.append(participant)
                
                print("[MeetingTypeDetector] Identified Speaker \(speakerId) as \(person.wrappedName) (confidence: \(person.voiceConfidence))")
                
                // Show notification for high-confidence matches
                if person.voiceConfidence > 0.9 {
                    showIdentificationNotification(for: person)
                }
            }
        }
        
        isProcessing = false
    }
    
    /// Pre-load voice prints for expected meeting participants
    func preloadParticipants(names: [String]) async {
        let context = persistenceController.container.viewContext
        var participantPeople: [Person] = []
        
        // Find people by name
        for name in names {
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
            
            if let people = try? context.fetch(request), let person = people.first {
                participantPeople.append(person)
            }
        }
        
        // Pre-load embeddings
        let embeddings = voicePrintManager.preloadEmbeddings(for: participantPeople)
        print("[MeetingTypeDetector] Pre-loaded \(embeddings.count) voice embeddings for expected participants")
    }
    
    // MARK: - Calendar Integration
    
    /// Prepare for upcoming meeting from calendar
    func prepareForMeeting(_ calendarEvent: UpcomingMeeting) async {
        print("[MeetingTypeDetector] Preparing for meeting: \(calendarEvent.title)")
        
        // Extract attendee names - attendees is already [String]?
        let attendeeNames = calendarEvent.attendees ?? []
        
        // Pre-load voice embeddings
        await preloadParticipants(names: attendeeNames)
        
        // Show preparation notification
        showPreparationNotification(for: calendarEvent)
    }
    
    // MARK: - Notifications
    
    private func showIdentificationNotification(for person: Person) {
        let notification = NSUserNotification()
        notification.title = "Participant Identified"
        notification.informativeText = "\(person.wrappedName) has joined the meeting"
        notification.soundName = nil // Silent notification
        notification.hasActionButton = false
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func showPreparationNotification(for meeting: UpcomingMeeting) {
        let notification = NSUserNotification()
        notification.title = "Ready to Record"
        notification.informativeText = "\(meeting.title) - Voice recognition prepared for \(meeting.attendees?.count ?? 0) participants"
        notification.soundName = nil // No sound for deprecated API
        notification.hasActionButton = true
        notification.actionButtonTitle = "Start Recording"
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Helper Methods
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    #endif
}

// MARK: - LiveMeeting Extensions

extension LiveMeeting {
    /// Add or update an identified participant
    func updateIdentifiedParticipant(_ participant: IdentifiedParticipant) {
        if let index = identifiedParticipants.firstIndex(where: { $0.id == participant.id }) {
            identifiedParticipants[index] = participant
        } else {
            identifiedParticipants.append(participant)
        }
    }
    
    /// Get participant by speaker ID
    func participant(for speakerId: Int) -> IdentifiedParticipant? {
        // Match by name pattern for speaker IDs
        return identifiedParticipants.first { $0.name?.contains("Speaker \(speakerId)") ?? false }
    }
    
    /// Check if meeting type detection is confident
    var isTypeDetectionConfident: Bool {
        return speakerDetectionConfidence > 0.8 && detectedSpeakerCount > 0
    }
}

// MARK: - Integration with MeetingRecordingEngine

#if canImport(FluidAudio)
extension MeetingRecordingEngine {
    /// Process diarization and update meeting type
    func processDiarizationUpdate(_ results: DiarizationResult?) {
        guard let meeting = currentMeeting else { return }
        
        Task { @MainActor in
            let detector = MeetingTypeDetector()
            
            // Detect meeting type
            detector.processDiarizationResults(results, for: meeting)
            
            // Identify speakers if possible
            await detector.identifySpeakers(from: results, for: meeting)
            
            // Update UI
            objectWillChange.send()
        }
    }
    
    /// Prepare for upcoming calendar meeting
    func prepareForCalendarMeeting(_ event: UpcomingMeeting) {
        Task { @MainActor in
            let detector = MeetingTypeDetector()
            await detector.prepareForMeeting(event)
        }
    }
}
#endif