# **WhoNext: Automatic Meeting Recording & Transcription Feature**
## **Project Brief & Technical Specification**

---

## **🎯 Executive Summary**

Implement intelligent meeting recording and transcription capabilities to automatically capture, process, and integrate team conversations into WhoNext's existing relationship management system. This feature will provide real-time transcription with speaker identification, seamless integration with existing AI analysis, and a new Group entity system for team meetings.

---

## **📋 Core Requirements**

### **Recording Capabilities**
- **Audio-only capture** via system-level audio routing
- **Universal platform support** (Teams, Zoom, Google Meet, etc.)
- **Calendar-based automatic detection** with smart recording initiation
- **Manual override controls** with auto-record as default
- **Bidirectional audio capture** ensuring all participants are recorded clearly
- **Extended meeting support** up to 2.5 hours duration
- **Multi-participant tracking** for up to 20 speakers per meeting

### **Real-time Processing**
- **Live transcription** with ~1-minute lag tolerance
- **Real-time speaker identification** and participant tracking
- **Floating recording window** with meeting statistics
- **Calendar integration** for meeting context and participant pre-identification
- **Scalable performance** across different meeting sizes and durations

### **Data Management**
- **Local storage only** with 30-day automatic deletion
- **Compressed audio storage** to optimize disk usage (~15MB per hour)
- **Searchable transcription database** across historical meetings
- **No version history** - single source of truth approach
- **Flexible conversation routing** (individual vs group) based on meeting size and user preference

---

## **🏗️ Technical Architecture**

### **New Core Components**

#### **1. Meeting Recording Engine**
```swift
class MeetingRecordingEngine: ObservableObject {
    private let audioCapture: SystemAudioCapture
    private let meetingDetector: MeetingDetectionService
    private let transcriptionPipeline: HybridTranscriptionPipeline
    private let speakerIdentification: VoiceIdentificationService
    
    @Published var isRecording: Bool = false
    @Published var currentMeeting: LiveMeeting?
    @Published var realtimeTranscript: [TranscriptSegment] = []
}
```

#### **2. Hybrid Transcription Pipeline**
```swift
class HybridTranscriptionPipeline {
    private let parakeetEngine: ParakeetTDTProcessor  // Primary: Speed
    private let gpt5Whisper: GPT5WhisperProcessor    // Secondary: Accuracy
    private let fallbackProcessor: AppleSpeechProcessor
    
    func processAudioChunk(_ audio: AudioBuffer) async -> TranscriptSegment
}
```

#### **3. New Core Data Entities**

**Group Entity:**
```swift
@objc(Group)
public class Group: NSManagedObject {
    @NSManaged public var identifier: UUID
    @NSManaged public var name: String
    @NSManaged public var groupType: String // "team", "project", "department"
    @NSManaged public var members: NSSet? // Person entities
    @NSManaged public var meetings: NSSet? // GroupMeeting entities
    @NSManaged public var createdAt: Date
    @NSManaged public var isActive: Bool
}
```

**GroupMeeting Entity:**
```swift
@objc(GroupMeeting)
public class GroupMeeting: NSManagedObject {
    @NSManaged public var identifier: UUID
    @NSManaged public var group: Group
    @NSManaged public var participants: NSSet? // Person entities
    @NSManaged public var audioFilePath: String?
    @NSManaged public var transcriptData: Data? // JSON transcript
    @NSManaged public var meetingDate: Date
    @NSManaged public var duration: Int32
    @NSManaged public var calendarTitle: String?
    @NSManaged public var sentimentAnalysis: Data? // JSON sentiment data
    @NSManaged public var autoDeleteDate: Date // 30 days from creation
}
```

#### **4. Live Meeting Window**
```swift
class LiveMeetingWindow: NSWindow {
    private let meetingStats: MeetingStatsView
    private let participantsList: IdentifiedParticipantsView
    private let recordingIndicator: RecordingStatusView
    private let meetingProgress: MeetingProgressView
}
```

---

## **🔄 Implementation Phases**

### **Phase 1: Core Infrastructure (Week 1-2)**

#### **System Audio Capture**
- Implement `AVAudioEngine` with system audio routing
- Create bidirectional audio capture ensuring all participants are recorded
- Build audio quality validation and enhancement pipeline
- Implement automatic gain control for consistent recording levels

#### **Meeting Detection Service**
- Monitor running applications for meeting platforms
- Integrate with existing calendar service for meeting context
- Create smart meeting start/end detection algorithms
- Build manual override controls with persistent preferences

#### **Basic Transcription Pipeline**
- Integrate NVIDIA Parakeet-TDT-0.6B-v2 for primary transcription
- Implement GPT-5 Whisper as accuracy fallback
- Create real-time audio chunking and processing queue
- Build transcript segment timestamping and threading

### **Phase 2: Speaker Identification & UI (Week 3-4)**

#### **Voice Identification System**
- Create voice print generation and matching algorithms
- Build speaker clustering for unknown participants
- Implement existing Person record matching by voice
- Create new participant detection and prompt system

#### **Live Meeting Interface**
- Design and implement floating meeting window
- Build real-time participant identification display
- Create meeting progress tracking with calendar integration
- Implement recording controls and status indicators

#### **Group Management System**
- Design Group entity with relationship management
- Create group creation and member assignment interfaces
- Build group meeting association and tracking
- Implement group-based conversation workflows

### **Phase 3: Advanced Features & Integration (Week 5-6)**

#### **Enhanced Processing**
- Integrate with existing sentiment analysis pipeline
- Build automatic Conversation record creation
- Implement Person relationship updates from meeting data
- Create Group vs Individual conversation decision logic

#### **Storage & Lifecycle Management**
- Implement local audio file compression and storage
- Build 30-day automatic deletion system
- Create searchable transcript database
- Implement data export and backup capabilities

#### **Analytics Integration**
- Extend existing Analytics tab with meeting metrics
- Build meeting effectiveness scoring
- Create participant interaction analysis
- Implement meeting frequency and pattern insights

---

## **🎨 User Experience Design**

### **Live Meeting Window Specifications**

**Window Properties:**
- **Always on top** floating window
- **Minimal, non-intrusive design** with Liquid Glass styling
- **Draggable positioning** with smart screen edge snapping
- **Auto-hide after 5 seconds** of no interaction (with hover to reveal)

**Core Information Display:**
```swift
struct LiveMeetingStatsView: View {
    @ObservedObject var meeting: LiveMeeting
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recording status with pulsing indicator
            RecordingIndicatorView(isActive: meeting.isRecording)
            
            // Identified participants with confidence scores
            ParticipantListView(participants: meeting.identifiedParticipants)
            
            // Meeting progress
            MeetingProgressView(
                elapsed: meeting.duration,
                scheduled: meeting.scheduledDuration,
                title: meeting.calendarTitle
            )
            
            // Quick actions
            QuickActionsView(meeting: meeting)
        }
    }
}
```

### **Group vs Individual Conversation Logic**

**Recommendation: Hybrid Approach**

1. **Large Group Meetings (4+ participants)**:
   - Primary save to `GroupMeeting` entity
   - **Optional individual saves** for key participants
   - User prompted: "Save key insights to individual records?"
   - Individual saves contain personalized excerpts, not full transcript

2. **Small Meetings (1-3 participants)**:
   - Save to individual `Conversation` records for each participant
   - Cross-reference conversations for relationship mapping
   - Full transcript available in each person's record

3. **User Control**:
   - Meeting type classification can be overridden
   - Post-meeting workflow allows moving between Group/Individual
   - Bulk individual save option for important group meetings

**Meeting Duration Support**:
- **Standard meetings**: Up to 2.5 hours (150 minutes)
- **Most common**: 30-60 minute meetings optimized for best performance
- **Extended meetings**: System handles longer meetings with potential performance considerations
- **No arbitrary time limits**: Users can record as long as needed within system capabilities

---

## **🧠 AI Processing Workflow**

### **Real-time Transcription Pipeline**
```swift
class RealtimeTranscriptionWorkflow {
    func processAudioStream() async {
        // 1. Capture 10-second audio chunks
        let audioChunk = await audioCapture.getNextChunk()
        
        // 2. Parallel processing for speed
        async let parakeetResult = parakeetEngine.transcribe(audioChunk)
        async let speakerID = voiceIdentification.identifySpeaker(audioChunk)
        
        // 3. Combine results and update UI
        let transcript = await parakeetResult
        let speaker = await speakerID
        
        // 4. Update live transcript with speaker attribution
        updateLiveTranscript(transcript: transcript, speaker: speaker)
        
        // 5. Background GPT-5 refinement for accuracy
        Task.detached {
            let refinedTranscript = await gpt5Whisper.refine(transcript)
            updateFinalTranscript(refinedTranscript)
        }
    }
}
```

### **Post-Meeting Processing**
```swift
class PostMeetingProcessor {
    func processMeetingComplete(_ meeting: RecordedMeeting) async {
        // 1. Final transcript cleanup with GPT-5
        let finalTranscript = await gpt5Processor.finalizeTranscript(meeting.rawTranscript)
        
        // 2. Generate meeting summary using existing pipeline
        let summary = await conversationSummarizer.generateSummary(finalTranscript)
        
        // 3. Perform sentiment analysis
        let sentiment = await sentimentAnalyzer.analyze(finalTranscript)
        
        // 4. Create appropriate records (Group vs Individual)
        await createConversationRecords(meeting, summary, sentiment)
        
        // 5. Update Person relationships and analytics
        await updateRelationshipData(meeting.participants)
    }
}
```

---

## **🔧 Technical Implementation Details**

### **System Requirements**
- **macOS 15+** with Apple Silicon optimization
- **Neural Engine acceleration** for voice processing
- **Metal 4 integration** for audio signal processing
- **AVAudioEngine** for system-level audio capture
- **Meeting duration support**: Up to 2.5 hours per meeting
- **Concurrent participant support**: Up to 20 speakers per meeting
- **Storage requirements**: ~15MB per hour of meeting audio (compressed)

### **Performance Targets**
- **Real-time transcription lag**: <60 seconds
- **Speaker identification accuracy**: >85%
- **CPU usage during recording**: <15%
- **Memory footprint**: <500MB during active recording
- **Post-meeting processing**: <5 minutes for 60-minute meeting
- **Extended meeting support**: Up to 150 minutes (2.5 hours) with stable performance
- **Participant capacity**: Support for up to 20 distinct speakers in a single meeting
- **Storage efficiency**: ~15MB per hour of compressed audio

### **Meeting Duration & Capacity Specifications**
- **Target meeting length**: 30-90 minutes (optimal performance range)
- **Maximum supported duration**: 150 minutes (2.5 hours)
- **Participant tracking**: Up to 20 distinct speakers per meeting
- **No artificial time limits**: System adapts to meeting length as needed
- **Performance scaling**: Maintains quality across different meeting sizes

### **Storage Management**
- **Audio compression**: 32kbps mono for voice optimization
- **Transcript storage**: JSON format with speaker timestamps
- **Automatic cleanup**: Daily maintenance job removes expired files
- **Storage estimation**: ~15MB per hour of meeting audio

---

## **🚀 Success Metrics**

### **Technical Metrics**
- **Transcription accuracy**: >90% word accuracy rate
- **Speaker identification**: >85% correct attribution
- **System reliability**: <1% meeting recording failures
- **Performance**: No user-perceptible lag during normal operation

### **User Experience Metrics**
- **Adoption rate**: >80% of users enable automatic recording
- **Workflow integration**: >70% of meetings result in saved conversations
- **User satisfaction**: >4.5/5 rating for meeting intelligence features

---

## **🔄 Future Enhancement Roadmap**

### **Phase 4: Advanced AI (Future)**
- **Multi-language support** with automatic detection
- **Meeting outcome prediction** based on sentiment trends
- **Smart meeting scheduling** based on participant dynamics
- **Integration with email/Slack** for complete communication tracking

### **Phase 5: Enterprise Features (Future)**
- **Admin controls** for compliance and privacy
- **Team analytics** and communication pattern insights
- **Integration APIs** for CRM and project management tools
- **Advanced reporting** with meeting effectiveness metrics

---

### **📝 Implementation Notes for Claude Code**

### **Key Integration Points**
1. **Existing Services to Leverage**:
   - `ConversationStateManager` for conversation management
   - `HybridAIService` for AI processing
   - `SentimentAnalysisService` for post-meeting analysis
   - `CalendarService` for meeting context
   - `AppStateManager` for application state

2. **Existing UI Patterns to Follow**:
   - Liquid Glass design system throughout the app
   - Person detail view patterns for UI consistency
   - Existing conversation workflow for post-meeting processing
   - Analytics tab integration patterns

3. **Core Data Migration**:
   - Add Group and GroupMeeting entities to existing model
   - Ensure backward compatibility with existing Conversation records
   - Implement proper relationship mapping between new and existing entities

4. **Audio Permissions**:
   - Request microphone permissions on first use
   - Handle permission denial gracefully
   - Provide clear user guidance for system audio access

### **Critical Success Factors**
- **Seamless integration** with existing workflow - users shouldn't need to change their habits
- **Reliable audio capture** - missing recordings will destroy user trust
- **Fast, accurate transcription** - real-time updates are essential for user engagement
- **Smart participant identification** - automatic linking to existing Person records is crucial
- **Intuitive Group vs Individual decision making** - users need clear control over data organization
- **Scalable performance** - system must handle both quick 15-minute check-ins and 2+ hour strategy sessions
- **Flexible meeting size support** - accommodate 1-on-1s through large team meetings

### **Meeting Size & Duration Clarifications**
- **No fixed meeting duration limits** - system should gracefully handle any reasonable meeting length
- **Optimal performance range**: 15 minutes to 2.5 hours
- **Participant scaling**: 1-20 speakers (most meetings have 2-8 participants)
- **Group vs Individual logic**: Based on participant count and user preference, not fixed rules
- **Performance considerations**: Longer meetings may require additional memory management but should not be artificially limited

### **Development Priority Order**
1. Calendar-based meeting detection with EventKit integration
2. System audio capture and basic recording infrastructure
3. Real-time transcription pipeline with NVIDIA Parakeet + GPT-5
4. Live meeting window with recording status and participant display
5. Speaker identification and Person record linking
6. Group entity system and flexible conversation routing
7. Integration with existing sentiment analysis pipeline
8. Analytics and reporting features for meeting insights

This comprehensive feature will transform WhoNext into a complete meeting intelligence platform while maintaining its core focus on relationship management. The flexible approach ensures it works for any meeting size or duration while the hybrid Group/Individual approach provides maximum utility for different use cases.