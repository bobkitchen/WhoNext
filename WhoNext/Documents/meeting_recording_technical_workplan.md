# **WhoNext Meeting Recording Feature - Technical Implementation Workplan**

## **🔧 Advanced Meeting Detection Technology**

### **Modern Detection Approach (Based on Granola & Quill Meetings)**

**Primary Detection Method: Calendar-Based Intelligence**
- **EventKit Integration**: Monitor macOS Calendar.app for upcoming meetings
- **Meeting Link Analysis**: Parse calendar events for Zoom/Teams/Meet URLs  
- **Contextual Prompting**: Show recording prompts 2-5 minutes before meeting start
- **Platform Detection**: Automatically identify meeting platform from calendar data

**Secondary Detection Method: Audio Activity Analysis**
- **Voice Activity Detection**: Monitor system audio for multiple distinct speakers
- **Conversation Pattern Recognition**: Identify meeting-style dialogue patterns  
- **Real-time Audio Analysis**: Detect when impromptu meetings begin
- **Quality Assessment**: Ensure sufficient audio quality for transcription

**Tertiary Detection Method: Application Context**
- **Process Monitoring**: Track when meeting applications become active
- **Focus Detection**: Identify when users join video calls
- **Cross-reference Validation**: Combine with calendar and audio signals

### **Smart Notification System**
```swift
// Granola-style meeting detection prompt
func showMeetingPrompt(meeting: DetectedMeeting) {
    UserNotification.show(
        title: "Meeting detected: \(meeting.title)",
        subtitle: "Start recording with WhoNext?",
        actions: [
            .startRecording,
            .remindInTwoMinutes, 
            .dismiss
        ],
        style: .banner // Non-intrusive
    )
}
```

**Detection Confidence Scoring:**
- **High (95%+)**: Calendar event + active meeting app + multiple speakers
- **Medium (75%+)**: Calendar event + meeting app OR multiple speakers detected  
- **Low (50%+)**: Meeting app active only
- **Manual (100%)**: User-initiated recording

**Privacy-First Approach:**
- No audio data sent to cloud for detection
- Local-only voice activity detection  
- Calendar access with minimal permissions
- User maintains complete control over recording decisions  

---

## **🎯 Phase 1: Core Infrastructure (Weeks 1-2)**

### **Week 1: Audio Capture & Meeting Detection**

#### **Task 1.1: System Audio Capture Setup**
**Files to Create:**
- `SystemAudioCapture.swift`
- `AudioQualityManager.swift` 
- `AudioPermissionManager.swift`

**Implementation Steps:**
1. **Create SystemAudioCapture class**
   ```swift
   import AVFoundation
   import CoreAudio
   
   class SystemAudioCapture: ObservableObject {
       private var audioEngine: AVAudioEngine
       private var inputNode: AVAudioInputNode
       private var outputBuffer: AVAudioPCMBuffer
       
       @Published var isCapturing: Bool = false
       @Published var audioLevel: Float = 0.0
       
       func startCapture() async throws
       func stopCapture()
       func getAudioChunk() async -> AVAudioPCMBuffer?
   }
   ```

2. **Implement bidirectional audio routing**
   - Use `AVAudioEngine` with system audio tap
   - Ensure both input (microphone) and output (speaker) are captured
   - Test with Teams, Zoom, Google Meet to verify capture quality

3. **Add audio quality validation**
   - Implement automatic gain control
   - Add noise reduction preprocessing
   - Monitor audio levels and quality metrics

4. **Handle audio permissions**
   - Request microphone access on first use
   - Provide clear permission guidance UI
   - Handle permission denial gracefully

**Testing Criteria:**
- [ ] Audio captures both sides of conversation clearly
- [ ] Works with Teams, Zoom, Google Meet
- [ ] Handles permission requests properly
- [ ] Audio quality is sufficient for transcription

#### **Task 1.2: Advanced Meeting Detection Service**
**Files to Create:**
- `MeetingDetectionService.swift`
- `CalendarMeetingDetector.swift`
- `AudioActivityDetector.swift`
- `MeetingContext.swift`
- `MeetingNotificationService.swift`

**Implementation Steps:**

1. **Create sophisticated meeting detection service** (Based on Granola/Quill approach)
   ```swift
   class MeetingDetectionService: ObservableObject {
       @Published var currentMeetingContext: MeetingContext?
       @Published var pendingMeetingDetection: PendingMeeting?
       @Published var isInMeeting: Bool = false
       
       private let calendarDetector: CalendarMeetingDetector
       private let audioDetector: AudioActivityDetector
       private let notificationService: MeetingNotificationService
       private let calendarService: CalendarService // Use existing
       
       func startMonitoring()
       func detectMeetingOpportunity() async -> MeetingDetectionResult
       func confirmMeetingStart(for meeting: PendingMeeting) -> Bool
       func detectMeetingEnd() -> Bool
       func showMeetingPrompt(for meeting: PendingMeeting)
   }
   ```

2. **Calendar-based meeting detection** (Primary method - like Granola)
   ```swift
   class CalendarMeetingDetector {
       private let eventStore = EKEventStore()
       
       func getCurrentMeetingEvent() -> EKEvent?
       func getUpcomingMeeting(within timeframe: TimeInterval) -> EKEvent?
       func extractMeetingPlatform(from event: EKEvent) -> MeetingPlatform?
       func shouldTriggerRecording(for event: EKEvent) -> Bool
       
       // Detect meeting platforms from calendar events
       private func detectPlatformFromURL(_ url: String) -> MeetingPlatform? {
           // Zoom: zoom.us/j/ or zoom.us/my/
           // Teams: teams.microsoft.com/l/meetup-join/
           // Google Meet: meet.google.com/ or g.co/meet/
           // WebEx: *.webex.com/meet/
       }
   }
   ```

3. **Audio activity detection** (Secondary trigger - like Quill)
   ```swift
   class AudioActivityDetector: ObservableObject {
       @Published var detectedSpeakers: Int = 0
       @Published var audioQuality: AudioQuality = .unknown
       
       private var audioEngine: AVAudioEngine
       private var speechDetector: VoiceActivityDetector
       
       func startMonitoring()
       func detectMultipleSpeakers() -> Bool
       func assessAudioQuality() -> AudioQuality
       func suggestMeetingStart() -> Bool // Triggers when multiple speakers detected
       
       // Voice Activity Detection for meeting inference
       private func analyzeAudioForMeetingSignals() -> MeetingAudioSignals {
           // Detect: Multiple distinct voices, meeting-style conversation patterns
           // Quality indicators: Background noise typical of video calls
           // Timing patterns: Regular speaker alternation
       }
   }
   ```

4. **Smart notification system** (Like Granola's prompt approach)
   ```swift
   class MeetingNotificationService {
       func showMeetingDetectedPrompt(meeting: PendingMeeting) async -> UserResponse
       func showCalendarMeetingPrompt(event: EKEvent) async -> UserResponse
       func showAutoStartNotification(meeting: MeetingContext)
       
       enum UserResponse {
           case startRecording
           case dismiss
           case remindInMinutes(Int)
           case neverForThisMeeting
       }
   }
   ```

5. **Multi-layered detection logic** (Best of both approaches)
   ```swift
   struct MeetingDetectionResult {
       let confidence: DetectionConfidence
       let source: DetectionSource
       let meetingContext: MeetingContext?
       let shouldAutoStart: Bool
       let shouldPromptUser: Bool
   }
   
   enum DetectionSource {
       case calendar(EKEvent)              // High confidence
       case audioActivity                  // Medium confidence  
       case applicationFocus              // Low confidence
       case userManual                    // Absolute confidence
   }
   
   enum DetectionConfidence {
       case high      // Calendar event + detected audio activity
       case medium    // Calendar event OR multiple speakers detected
       case low       // Meeting app active but no other signals
   }
   ```

6. **Implementation of Granola/Quill detection patterns**:

   **Calendar Integration (Primary - like Granola)**:
   - Monitor EventKit for upcoming meetings (0-5 minutes before start)
   - Parse meeting links to identify platform (Zoom, Teams, Meet, etc.)
   - Show user prompt: "Meeting starting in 2 minutes. Start recording?"
   - Auto-prompt when calendar event time arrives

   **Audio Activity Detection (Secondary - like Quill)**:
   - Continuously monitor system audio for conversation patterns
   - Detect when multiple distinct speakers are present
   - Trigger recording suggestion when meeting-like audio detected
   - Handle impromptu meetings not in calendar

   **Smart Prompting System**:
   - Non-intrusive notification banners (not modal dialogs)
   - "Meeting detected - Start recording?" with one-click start
   - Remember user preferences per meeting type/participant
   - Auto-start for trusted recurring meetings

**Testing Criteria:**
- [ ] Calendar events trigger recording prompts at appropriate times
- [ ] Audio activity detection identifies multi-speaker conversations
- [ ] Meeting platform detection works from calendar links
- [ ] User prompts are non-intrusive and effective
- [ ] Auto-start works for recurring trusted meetings
- [ ] Manual override controls work correctly

#### **Task 1.3: Basic Data Models**
**Files to Modify:**
- `WhoNext.xcdatamodeld` (Core Data model)
- Create `Group.swift`
- Create `GroupMeeting.swift`
- Create `LiveMeeting.swift`

**Implementation Steps:**
1. **Add Group entity to Core Data model**
   ```swift
   // Add to WhoNext.xcdatamodel
   Entity: Group
   - identifier: UUID
   - name: String
   - groupType: String
   - createdAt: Date
   - isActive: Bool
   - members: To-Many -> Person
   - meetings: To-Many -> GroupMeeting
   ```

2. **Add GroupMeeting entity**
   ```swift
   Entity: GroupMeeting
   - identifier: UUID
   - meetingDate: Date
   - duration: Int32
   - calendarTitle: String?
   - audioFilePath: String?
   - transcriptData: Data?
   - sentimentAnalysis: Data?
   - autoDeleteDate: Date
   - group: To-One -> Group
   - participants: To-Many -> Person
   ```

3. **Create Swift classes**
   ```swift
   @objc(Group)
   public class Group: NSManagedObject {
       // Core Data properties
       // Computed properties for convenience
       // Relationship helpers
   }
   ```

4. **Create LiveMeeting model (non-persistent)**
   ```swift
   class LiveMeeting: ObservableObject {
       @Published var isRecording: Bool = false
       @Published var participants: [IdentifiedParticipant] = []
       @Published var duration: TimeInterval = 0
       @Published var transcript: [TranscriptSegment] = []
       @Published var calendarTitle: String?
       @Published var scheduledDuration: TimeInterval?
   }
   ```

**Testing Criteria:**
- [ ] Core Data migration works without data loss
- [ ] New entities save and load correctly
- [ ] Relationships between entities work properly
- [ ] LiveMeeting updates UI reactively

### **Week 2: Basic Transcription Pipeline**

#### **Task 2.1: Transcription Service Foundation**
**Files to Create:**
- `HybridTranscriptionPipeline.swift`
- `TranscriptSegment.swift`
- `ParakeetTDTProcessor.swift`
- `GPT5WhisperProcessor.swift`

**Implementation Steps:**
1. **Create core transcription models**
   ```swift
   struct TranscriptSegment: Identifiable, Codable {
       let id: UUID
       let speakerID: String?
       let text: String
       let timestamp: TimeInterval
       let confidence: Float
       let isFinalized: Bool
   }
   
   struct IdentifiedParticipant: Identifiable {
       let id: UUID
       let name: String?
       let voicePrint: VoicePrint?
       let personRecord: Person?
       let confidence: Float
   }
   ```

2. **Implement HybridTranscriptionPipeline**
   ```swift
   class HybridTranscriptionPipeline: ObservableObject {
       private let parakeetProcessor: ParakeetTDTProcessor
       private let gpt5Processor: GPT5WhisperProcessor
       private let audioQueue: AudioProcessingQueue
       
       @Published var realtimeTranscript: [TranscriptSegment] = []
       @Published var isProcessing: Bool = false
       
       func processAudioChunk(_ audio: AVAudioPCMBuffer) async -> TranscriptSegment?
       func finalizeTranscript() async -> [TranscriptSegment]
   }
   ```

3. **NVIDIA Parakeet integration (primary processor)**
   - Research available Parakeet-TDT Swift/macOS integration options
   - Implement local processing if possible, or cloud API if necessary
   - Focus on speed and real-time performance
   - Handle audio format conversion for Parakeet requirements

4. **GPT-5 Whisper integration (accuracy processor)**
   - Use OpenAI API with GPT-5 Whisper endpoint
   - Implement as background refinement process
   - Handle API rate limiting and errors gracefully
   - Use for final transcript cleanup and accuracy improvement

**Testing Criteria:**
- [ ] Basic transcription works with test audio
- [ ] Real-time processing maintains <60 second lag
- [ ] GPT-5 refinement improves accuracy
- [ ] Error handling works for API failures

#### **Task 2.2: Meeting Recording Engine**
**Files to Create:**
- `MeetingRecordingEngine.swift`
- `AudioStorageManager.swift`

**Implementation Steps:**
1. **Create main recording orchestrator**
   ```swift
   class MeetingRecordingEngine: ObservableObject {
       @Published var currentMeeting: LiveMeeting?
       @Published var isRecording: Bool = false
       
       private let audioCapture: SystemAudioCapture
       private let transcriptionPipeline: HybridTranscriptionPipeline
       private let detectionService: MeetingDetectionService
       private let storageManager: AudioStorageManager
       
       func startRecording(meetingContext: MeetingContext?)
       func stopRecording()
       func pauseRecording()
       func resumeRecording()
   }
   ```

2. **Implement audio storage and compression**
   ```swift
   class AudioStorageManager {
       private let documentsURL: URL
       private let compressionSettings: [String: Any]
       
       func saveAudioChunk(_ buffer: AVAudioPCMBuffer, meetingID: UUID) async throws
       func compressAudioFile(_ fileURL: URL) async throws
       func scheduleAutoDelete(for meetingID: UUID, after days: Int)
       func cleanupExpiredFiles()
   }
   ```

3. **Wire up automatic recording**
   - Connect meeting detection to recording engine
   - Implement auto-start when meeting detected
   - Handle manual override controls
   - Add recording persistence across app restarts

4. **Add real-time processing coordination**
   - Stream audio chunks to transcription pipeline
   - Update LiveMeeting with transcript segments
   - Handle speaker identification placeholders
   - Manage memory and performance during long meetings

**Testing Criteria:**
- [ ] Recording starts/stops automatically with meetings
- [ ] Audio is saved and compressed properly
- [ ] Real-time transcription appears in UI
- [ ] Manual controls work correctly

---

## **🎯 Phase 2: Speaker Identification & UI (Weeks 3-4)**

### **Week 3: Voice Identification System**

#### **Task 3.1: Voice Print Generation**
**Files to Create:**
- `VoiceIdentificationService.swift`
- `VoicePrint.swift`
- `SpeakerClusteringEngine.swift`

**Implementation Steps:**
1. **Create voice print system**
   ```swift
   struct VoicePrint: Codable {
       let id: UUID
       let personID: UUID?
       let mfccFeatures: [Float]
       let spectrogramData: Data
       let confidence: Float
       let sampleCount: Int
   }
   
   class VoiceIdentificationService: ObservableObject {
       private let clusteringEngine: SpeakerClusteringEngine
       private var knownVoicePrints: [VoicePrint] = []
       
       func generateVoicePrint(from audio: AVAudioPCMBuffer) -> VoicePrint
       func identifySpeaker(from audio: AVAudioPCMBuffer) -> IdentifiedParticipant?
       func trainNewSpeaker(_ voicePrint: VoicePrint, personID: UUID)
       func improveSpeakerModel(voicePrint: VoicePrint, confirmedPersonID: UUID)
   }
   ```

2. **Implement speaker clustering**
   - Use CoreML or Apple's Speech framework for voice analysis
   - Extract MFCC (Mel-frequency cepstral coefficients) features
   - Implement k-means clustering for unknown speakers
   - Build confidence scoring for speaker identification

3. **Create voice print database**
   - Extend Person entity to include voice print data
   - Store multiple voice prints per person for accuracy
   - Implement voice print similarity matching
   - Handle voice print updates and improvements over time

4. **Add speaker diarization**
   - Separate overlapping speakers in audio
   - Assign timestamps to specific speakers
   - Handle speaker transitions and silence detection
   - Manage multi-speaker conversations

**Testing Criteria:**
- [ ] Voice prints are generated consistently
- [ ] Speaker identification achieves >85% accuracy
- [ ] Unknown speakers are clustered correctly
- [ ] Multiple speakers are handled in same audio

#### **Task 3.2: Person Record Integration**
**Files to Modify:**
- `Person.swift` (add voice print support)
- Create `ParticipantMatcher.swift`
- Create `NewParticipantPrompt.swift`

**Implementation Steps:**
1. **Extend Person entity for voice data**
   ```swift
   extension Person {
       @NSManaged public var voicePrints: NSSet?
       
       var voicePrintsArray: [VoicePrint] {
           // Convert NSSet to array helper
       }
       
       func addVoicePrint(_ voicePrint: VoicePrint) {
           // Add new voice print to person
       }
       
       func matchesVoicePrint(_ voicePrint: VoicePrint) -> Float {
           // Calculate confidence score
       }
   }
   ```

2. **Create participant matching service**
   ```swift
   class ParticipantMatcher {
       func matchToExistingPerson(_ voicePrint: VoicePrint) -> Person?
       func suggestPersonMatches(_ voicePrint: VoicePrint) -> [PersonMatch]
       func createUnknownParticipant(_ voicePrint: VoicePrint) -> IdentifiedParticipant
       func promptForNewPersonCreation(_ participant: IdentifiedParticipant)
   }
   ```

3. **Implement new participant workflow**
   - Detect when unknown speaker appears
   - Show prompt: "New participant detected. Create person record?"
   - Allow user to name participant and link to existing person
   - Auto-update voice prints when user confirms matches

4. **Add calendar participant pre-identification**
   - Use existing CalendarService to get meeting attendees
   - Pre-populate expected participants
   - Match voice prints to calendar attendees by name
   - Improve accuracy with participant expectations

**Testing Criteria:**
- [ ] New participants trigger creation prompts
- [ ] Voice prints are saved to Person records correctly
- [ ] Calendar integration improves identification accuracy
- [ ] User can manually correct misidentifications

### **Week 4: Live Meeting Interface**

#### **Task 4.1: Floating Meeting Window**
**Files to Create:**
- `LiveMeetingWindow.swift`
- `LiveMeetingWindowController.swift`
- `MeetingStatsView.swift`
- `RecordingIndicatorView.swift`

**Implementation Steps:**
1. **Create floating window infrastructure**
   ```swift
   class LiveMeetingWindowController: NSWindowController {
       private var meetingWindow: LiveMeetingWindow?
       
       func showMeetingWindow(for meeting: LiveMeeting)
       func hideMeetingWindow()
       func updateMeetingStats(_ meeting: LiveMeeting)
   }
   
   class LiveMeetingWindow: NSPanel {
       override var canBecomeKey: Bool { false }
       override var canBecomeMain: Bool { false }
       
       // Always on top, non-modal panel
   }
   ```

2. **Design meeting stats interface**
   ```swift
   struct MeetingStatsView: View {
       @ObservedObject var meeting: LiveMeeting
       @State private var isExpanded: Bool = false
       
       var body: some View {
           VStack(alignment: .leading, spacing: 8) {
               RecordingIndicatorView(isActive: meeting.isRecording)
               
               if isExpanded {
                   ParticipantListView(participants: meeting.participants)
                   MeetingProgressView(meeting: meeting)
                   QuickActionsView(meeting: meeting)
               }
           }
           .onHover { hovering in
               withAnimation(.easeInOut(duration: 0.3)) {
                   isExpanded = hovering
               }
           }
       }
   }
   ```

3. **Implement recording indicator**
   - Pulsing red dot when recording
   - Meeting duration timer
   - Recording quality indicator
   - Quick pause/resume controls

4. **Add participant display**
   - Show identified participants with confidence
   - Display unknown speakers as "Speaker 1", "Speaker 2"
   - Allow quick name assignment for unknowns
   - Show speaking activity indicators

**Testing Criteria:**
- [ ] Window floats above all other applications
- [ ] Auto-hide/show on hover works smoothly
- [ ] Recording status is always visible
- [ ] Participant information updates in real-time

#### **Task 4.2: Meeting Progress & Quick Actions**
**Files to Create:**
- `MeetingProgressView.swift`
- `ParticipantListView.swift`
- `QuickActionsView.swift`

**Implementation Steps:**
1. **Create meeting progress display**
   ```swift
   struct MeetingProgressView: View {
       let meeting: LiveMeeting
       
       var progressPercentage: Double {
           guard let scheduled = meeting.scheduledDuration, scheduled > 0 else { return 0 }
           return min(meeting.duration / scheduled, 1.0)
       }
       
       var body: some View {
           VStack(alignment: .leading) {
               Text(meeting.calendarTitle ?? "Meeting in Progress")
               
               HStack {
                   Text(formatDuration(meeting.duration))
                   
                   if let scheduled = meeting.scheduledDuration {
                       Spacer()
                       Text("/ \(formatDuration(scheduled))")
                   }
               }
               
               ProgressView(value: progressPercentage)
           }
       }
   }
   ```

2. **Implement participant list with confidence**
   ```swift
   struct ParticipantListView: View {
       let participants: [IdentifiedParticipant]
       
       var body: some View {
           VStack(alignment: .leading) {
               ForEach(participants) { participant in
                   HStack {
                       Circle()
                           .fill(participant.isCurrentlySpeaking ? .green : .gray)
                           .frame(width: 8, height: 8)
                       
                       Text(participant.displayName)
                       
                       Spacer()
                       
                       if participant.confidence < 0.8 {
                           Button("?") {
                               // Show participant correction UI
                           }
                       }
                   }
               }
           }
       }
   }
   ```

3. **Add quick action controls**
   - Pause/resume recording
   - Stop recording early
   - Add quick note
   - Mark important moments
   - Quick access to participant assignment

4. **Implement smart positioning**
   - Remember window position between meetings
   - Smart edge snapping
   - Avoid blocking important screen areas
   - Handle multiple monitor setups

**Testing Criteria:**
- [ ] Meeting progress accurately reflects calendar time
- [ ] Participant list updates as speakers change
- [ ] Quick actions work without interrupting recording
- [ ] Window positioning is intelligent and remembered

---

## **🎯 Phase 3: Advanced Features & Integration (Weeks 5-6)**

### **Week 5: Group Management & Conversation Routing**

#### **Task 5.1: Group Management System**
**Files to Create:**
- `GroupManager.swift`
- `GroupCreationView.swift`
- `GroupDetailView.swift`
- `GroupSelectionSheet.swift`

**Implementation Steps:**
1. **Create group management service**
   ```swift
   class GroupManager: ObservableObject {
       @Published var groups: [Group] = []
       
       private let viewContext: NSManagedObjectContext
       
       func createGroup(name: String, type: GroupType, members: [Person]) -> Group
       func addMemberToGroup(_ person: Person, group: Group)
       func removeMemberFromGroup(_ person: Person, group: Group)
       func suggestGroupForParticipants(_ participants: [Person]) -> Group?
       func deleteGroup(_ group: Group)
   }
   ```

2. **Implement group creation UI**
   ```swift
   struct GroupCreationView: View {
       @State private var groupName: String = ""
       @State private var selectedType: GroupType = .team
       @State private var selectedMembers: Set<Person> = []
       
       var body: some View {
           Form {
               TextField("Group Name", text: $groupName)
               
               Picker("Type", selection: $selectedType) {
                   ForEach(GroupType.allCases) { type in
                       Text(type.displayName).tag(type)
                   }
               }
               
               MemberSelectionView(selectedMembers: $selectedMembers)
           }
       }
   }
   ```

3. **Add group auto-suggestion logic**
   - Analyze meeting participants to suggest existing groups
   - Auto-create groups for recurring meeting patterns
   - Handle group membership changes over time
   - Provide group templates (e.g., "Senior Management", "Development Team")

4. **Integrate with existing People tab**
   - Add group membership display to person detail views
   - Show group meetings in person conversation history
   - Allow group creation from person detail view
   - Cross-reference individual and group conversations

**Testing Criteria:**
- [ ] Groups can be created and managed correctly
- [ ] Group suggestions work for meeting participants
- [ ] Group membership displays properly in People tab
- [ ] Group data syncs with Supabase correctly

#### **Task 5.2: Conversation Routing Logic**
**Files to Create:**
- `ConversationRouter.swift`
- `ConversationSaveDecisionView.swift`
- `GroupConversationDetailView.swift`

**Implementation Steps:**
1. **Implement conversation routing decision engine**
   ```swift
   class ConversationRouter {
       func determineConversationType(participants: [Person]) -> ConversationType
       func suggestGroups(for participants: [Person]) -> [Group]
       func routeConversation(_ meeting: GroupMeeting) -> ConversationRoutingDecision
       
       enum ConversationType {
           case individual(Person)
           case smallGroup([Person])
           case largeGroup(Group)
       }
       
       struct ConversationRoutingDecision {
           let primaryDestination: ConversationType
           let shouldCreateIndividualCopies: Bool
           let suggestedGroup: Group?
       }
   }
   ```

2. **Create conversation save decision UI**
   ```swift
   struct ConversationSaveDecisionView: View {
       let meeting: GroupMeeting
       @State private var saveToGroup: Bool = true
       @State private var selectedGroup: Group?
       @State private var createIndividualCopies: Bool = false
       @State private var selectedIndividuals: Set<Person> = []
       
       var body: some View {
           VStack(alignment: .leading) {
               Text("How would you like to save this conversation?")
               
               Toggle("Save to group", isOn: $saveToGroup)
               
               if saveToGroup {
                   GroupPicker(selection: $selectedGroup)
               }
               
               Toggle("Also save individual copies", isOn: $createIndividualCopies)
               
               if createIndividualCopies {
                   PersonSelectionView(selected: $selectedIndividuals)
               }
           }
       }
   }
   ```

3. **Implement hybrid saving logic**
   - Primary save to GroupMeeting for >3 participants
   - Optional individual Conversation records for key participants
   - Extract personalized excerpts for individual saves
   - Maintain cross-references between group and individual records

4. **Add conversation type override**
   - Allow users to change conversation type after recording
   - Provide "Move to Group" and "Split to Individuals" options
   - Handle data migration between conversation types
   - Preserve sentiment analysis and other metadata

**Testing Criteria:**
- [ ] Conversation routing works automatically for different meeting sizes
- [ ] Users can override automatic decisions
- [ ] Individual excerpts are properly extracted from group conversations
- [ ] Cross-references between group and individual records work

### **Week 6: Final Integration & Polish**

#### **Task 6.1: Integration with Existing Analysis Pipeline**
**Files to Modify:**
- `SentimentAnalysisService.swift`
- `ConversationStateManager.swift`
- `AnalyticsView.swift`

**Implementation Steps:**
1. **Extend sentiment analysis for group meetings**
   ```swift
   extension SentimentAnalysisService {
       func analyzeGroupMeeting(_ meeting: GroupMeeting) async -> GroupSentimentAnalysis
       func generateParticipantInsights(_ participants: [Person], meeting: GroupMeeting) -> [ParticipantInsight]
       func updateRelationshipHealth(from meeting: GroupMeeting)
   }
   
   struct GroupSentimentAnalysis {
       let overallSentiment: SentimentScore
       let participantSentiments: [UUID: SentimentScore]
       let meetingEffectiveness: Double
       let engagementLevels: [UUID: EngagementLevel]
       let keyMoments: [TimestampedMoment]
   }
   ```

2. **Update ConversationStateManager**
   - Handle GroupMeeting entities alongside Conversation entities
   - Provide unified interface for both conversation types
   - Update relationship tracking for group interactions
   - Maintain consistent data access patterns

3. **Extend Analytics tab with meeting metrics**
   - Add meeting frequency and duration analytics
   - Show group vs individual conversation breakdowns
   - Display speaker participation analytics
   - Add meeting effectiveness trending

4. **Update existing AI processing**
   - Modify ChatContextService to include group meeting context
   - Update HybridAIService to handle group conversation summaries
   - Extend pre-meeting brief generation for group meetings
   - Maintain compatibility with existing conversation workflows

**Testing Criteria:**
- [ ] Sentiment analysis works for both group and individual conversations
- [ ] Analytics tab shows meeting metrics correctly
- [ ] Existing AI features work with recorded meetings
- [ ] ConversationStateManager handles all conversation types

#### **Task 6.2: Storage Lifecycle & Performance**
**Files to Create:**
- `StorageLifecycleManager.swift`
- `PerformanceMonitor.swift`
- `MeetingDataExporter.swift`

**Implementation Steps:**
1. **Implement automatic cleanup system**
   ```swift
   class StorageLifecycleManager {
       private let fileManager = FileManager.default
       private let calendar = Calendar.current
       
       func scheduleCleanupJob()
       func performDailyCleanup()
       func deleteExpiredAudioFiles()
       func archiveOldTranscripts()
       func optimizeStorageUsage()
       
       func calculateStorageUsage() -> StorageReport
       func estimateStorageNeeded(for duration: TimeInterval) -> Int64
   }
   ```

2. **Add performance monitoring**
   ```swift
   class PerformanceMonitor: ObservableObject {
       @Published var cpuUsage: Double = 0
       @Published var memoryUsage: Int64 = 0
       @Published var transcriptionLatency: TimeInterval = 0
       @Published var speakerIdentificationAccuracy: Double = 0
       
       func startMonitoring()
       func logPerformanceMetrics()
       func optimizePerformance()
   }
   ```

3. **Create data export functionality**
   - Export transcripts as text files
   - Export meeting data as JSON
   - Batch export for multiple meetings
   - Handle data privacy and user control

4. **Optimize memory usage**
   - Implement transcript segment buffering
   - Manage audio chunk memory lifecycle
   - Optimize Core Data fetch requests
   - Handle large meeting data efficiently

**Testing Criteria:**
- [ ] Automatic cleanup works correctly after 30 days
- [ ] Performance monitoring shows acceptable resource usage
- [ ] Data export functions work properly
- [ ] Memory usage remains stable during long meetings

#### **Task 6.3: Error Handling & Edge Cases**
**Files to Create:**
- `MeetingErrorHandler.swift`
- `RecordingFailureRecovery.swift`
- `TranscriptionFallbackService.swift`

**Implementation Steps:**
1. **Robust error handling**
   ```swift
   class MeetingErrorHandler {
       func handleAudioCaptureFailure(_ error: AudioCaptureError)
       func handleTranscriptionFailure(_ error: TranscriptionError) 
       func handleStorageFailure(_ error: StorageError)
       func handleNetworkFailure(_ error: NetworkError)
       
       func attemptRecovery(from error: MeetingError) -> RecoveryResult
       func notifyUserOfFailure(_ error: MeetingError)
   }
   ```

2. **Recording failure recovery**
   - Detect when recording stops unexpectedly
   - Attempt to restart recording automatically
   - Save partial recordings with metadata
   - Provide user feedback about recording issues

3. **Transcription fallback system**
   - Fall back to Apple Speech framework if Parakeet fails
   - Handle API rate limits gracefully
   - Provide offline transcription capabilities
   - Queue failed transcriptions for retry

4. **Edge case handling**
   - Very short meetings (<2 minutes)
   - Very long meetings (>2 hours)
   - Meetings with no identified participants
   - Poor audio quality scenarios
   - Network connectivity issues during processing

**Testing Criteria:**
- [ ] Error recovery works without data loss
- [ ] Users