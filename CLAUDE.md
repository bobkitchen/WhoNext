# Claude Development Notes for WhoNext

## Important Configuration Requirements

### macOS Deployment Target
- **CRITICAL**: The deployment target MUST remain at macOS 26.0 throughout the project
- Do NOT change deployment targets to lower versions even if build errors occur
- macOS 26 is called **macOS Tahoe** (not Sequoia - that was macOS 15)

### Build Environment
- **ALWAYS use Xcode Beta for building** - located at `/Applications/Xcode-beta.app`
- Running on macOS 26 (Tahoe)
- Uses Xcode beta for macOS 26 SDK support
- Current SDK: MacOSX26.0.sdk (symlinked to MacOSX.sdk)

### Build Commands
When building from command line, always use:
```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild
```
NOT the standard `xcodebuild` command which points to the release version.

## Project Context

### Speech Transcription - CRITICAL UPDATE
**As of August 30, 2025:**

#### CRITICAL DISCOVERY: THE NEW APIS EXIST IN COMMANDLINETOOLS SDK
After deep investigation, the actual situation is:
1. **SpeechAnalyzer, SpeechTranscriber, AssetInventory, and AnalyzerInput ARE in `/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk`**
2. **They exist in the Swift interface files** at `/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/`
3. **Xcode.app and Xcode-beta.app use different SDKs** (15.5 and 26.0 respectively) but neither has the new APIs
4. **To use these APIs, must compile with the CommandLineTools SDK**

#### How Working Apps Use the APIs

**swift-scribe (SwiftUI app) implementation:**
```swift
import Speech

// Core components that work:
let transcriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],
    attributeOptions: [.audioTimeRange]
)

let analyzer = SpeechAnalyzer(modules: [transcriber])

// Asset management
try await AssetInventory.allocate(locale: locale)
let supportedLocales = await SpeechTranscriber.supportedLocales
let installedLocales = await SpeechTranscriber.installedLocales

// Streaming with AsyncStream
let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
try await analyzer.start(inputSequence: stream)

// Process audio
let input = AnalyzerInput(buffer: convertedBuffer)
continuation.yield(input)

// Get results
for try await result in transcriber.results {
    let text = result.text
    // Process transcription
}
```

**yap (CLI tool) implementation:**
```swift
import Speech

// File-based transcription
let transcriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: censor ? [.etiquetteReplacements] : [],
    reportingOptions: [],
    attributeOptions: outputFormat.needsAudioTimeRange ? [.audioTimeRange] : []
)

let analyzer = SpeechAnalyzer(modules: [transcriber])
let audioFile = try AVAudioFile(forReading: inputFile)
try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

for try await result in transcriber.results {
    transcript += result.text
}
```

#### Key API Components That Actually Work

1. **SpeechTranscriber** - Main transcription module
   - Properties: `supportedLocales`, `installedLocales`
   - Initialization with locale, options
   - Async sequence `results` for streaming transcription

2. **SpeechAnalyzer** - Orchestrates analysis modules
   - Methods: `start(inputSequence:)`, `start(inputAudioFile:finishAfterFile:)`
   - Static: `bestAvailableAudioFormat(compatibleWith:)`

3. **AssetInventory** - Manages language models
   - Methods: `allocate(locale:)`, `deallocate(locale:)`
   - Properties: `allocatedLocales`
   - Asset installation requests

4. **AnalyzerInput** - Wraps audio buffers
   - Constructor: `AnalyzerInput(buffer:)`

5. **AsyncStream<AnalyzerInput>** - For streaming audio

### Recent Improvements
- Fixed concurrent access issues in SpeechAnalyzer by creating new instances per transcription
- Implemented 30-second audio buffer accumulation for improved transcription quality
- Added screen recording permission request flow similar to microphone permissions
- Redirected recorded meetings to transcript import UI for review before saving

## Known Issues

### Critical Recording/Transcription Issues
1. **APIs exist but aren't in SDK headers** - SpeechAnalyzer/SpeechTranscriber work at runtime but can't be found in headers
2. **ModernSpeechFramework needs proper implementation** - Current placeholder returns empty transcripts
3. **Must use the AsyncStream pattern** - The working apps use AsyncStream<AnalyzerInput> for streaming
4. **Asset management is required** - Must call AssetInventory.allocate() before transcription

### Speaker Attribution Pipeline - ALL PHASES COMPLETE (January 2026)

**Problem**: ~80% of speaker attribution data was lost between recording and save. The app built rich IdentifiedParticipant objects during recording but discarded most data at handoff.

**Phase 1 Complete - Data Handoff Fix**:
- ✅ Created `SerializableParticipant` struct in `LiveMeeting.swift` for JSON serialization
- ✅ Updated `MeetingRecordingEngine.swift` to serialize full participant data to UserDefaults
- ✅ Fixed `TranscriptImportWindowView.swift` to deserialize and use participant data
- ✅ Removed hardcoded "Known Participants:" prefix - now shows "Participants:" with "(You)" for current user
- ✅ Updated `TranscriptProcessor.swift` to accept pre-identified participants
- ✅ Added `ParticipantInfo.isCurrentUser`, `confidence`, `speakerID`, and `voiceEmbedding` fields
- ✅ Fixed hardcoded duration (was 30) - now uses actual recording duration
- ✅ Updated `TranscriptReviewView.swift` participant card to show "(You)" badge for current user

**Phase 2 Complete - Core Data Persistence**:
- ✅ Added `ConversationParticipant` entity to Core Data model with:
  - `identifier`, `name`, `speakerID`, `speakingTime`
  - `isCurrentUser`, `confidence`, `namingMode`
  - Relationship to `Conversation` (to-one, inverse: participants)
  - Relationship to `Person` (optional to-one, inverse: conversationParticipations)
- ✅ Created `ConversationParticipant.swift` NSManagedObject subclass with factory methods
- ✅ Added `participants` relationship to `Conversation` (to-many with cascade delete)
- ✅ Added `conversationParticipations` relationship to `Person` (to-many)
- ✅ Added convenience accessors: `participantsArray`, `currentUserParticipant`, `externalParticipants`
- ✅ Updated `TranscriptReviewView.saveConversation()` to create ConversationParticipant records

**Phase 3 Complete - Voice Learning**:
- ✅ Added `voiceEmbedding: [Float]?` to `SerializableParticipant` and `ParticipantInfo`
- ✅ Updated `MeetingRecordingEngine.processMeeting()` to include voice embeddings from DiarizationManager
- ✅ Added voice embedding methods to `Person`: `addVoiceEmbedding()`, `averageVoiceEmbedding`, `voiceSimilarity(to:)`
- ✅ Updated `TranscriptReviewView` to save voice embeddings to Person records when saving
- ✅ Voice confidence and sample count automatically updated on each save

**Full Data Pipeline Now**:
```
Recording                    Handoff                     Review/Save
─────────────────────────────────────────────────────────────────────
IdentifiedParticipant[]  →  SerializableParticipant[]  →  ParticipantInfo[]
  + isCurrentUser ✅           + isCurrentUser ✅           + isCurrentUser ✅
  + speakingTime ✅            + speakingTime ✅            + speakingTime ✅
  + confidence ✅              + confidence ✅              + confidence ✅
  + voiceEmbedding ✅          + voiceEmbedding ✅          + voiceEmbedding ✅
                                                                   ↓
                                                    ConversationParticipant (Core Data)
                                                    + Person.voiceEmbeddings updated
```

**Voice Learning Flow**:
1. Recording: DiarizationManager produces speaker embeddings
2. Handoff: Embeddings serialized with participant data to UserDefaults
3. Review: User confirms/links participants to Person records
4. Save: Voice embeddings added to Person.voiceEmbeddings for future matching
5. Future: Person.voiceSimilarity(to:) used to auto-identify speakers

### Build Issues
- Build may fail with standard Xcode if macOS 26 SDK is not available
- Must use Xcode beta at `/Applications/Xcode-beta.app`

## Recommended Immediate Fix

The recording/transcription pipeline needs to be rewritten following the working patterns from swift-scribe and yap:

### 1. Fix ModernSpeechFramework Implementation
Replace the placeholder with actual working code:
```swift
@available(macOS 26.0, *)
class ModernSpeechFramework {
    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    
    init() {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }
    
    func initialize() async throws {
        // Allocate locale assets
        try await AssetInventory.allocate(locale: .current)
        
        // Create transcriber
        transcriber = SpeechTranscriber(
            locale: .current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        
        // Create analyzer
        analyzer = SpeechAnalyzer(modules: [transcriber!])
        
        // Start analyzer with stream
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    func processAudioStream(_ buffer: AVAudioPCMBuffer) async throws -> String {
        // Convert buffer if needed
        let input = AnalyzerInput(buffer: buffer)
        inputBuilder.yield(input)
        
        // Get results from transcriber
        var transcript = ""
        for try await result in transcriber!.results {
            transcript = String(result.text.characters)
        }
        return transcript
    }
}
```

### 2. Key Implementation Points
- **Use AsyncStream<AnalyzerInput>** for streaming audio
- **Call AssetInventory.allocate()** before starting
- **Convert buffers to correct format** using BufferConverter
- **Handle volatile vs finalized results** appropriately
- **Check for asset downloads** and install if needed

### 3. Build Configuration - WORKING SOLUTION
- **Platform must be macOS 26** in Package.swift or project settings
- **The APIs exist in**: `/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk`
- **Swift 6.2 is available**: In Xcode-beta.app at `/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift`
- **To compile with new APIs**:
  ```bash
  SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.0.sdk \
  /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift build
  ```
- **API differences from documentation**:
  - Use `AssetInventory.reserve(locale:)` not `allocate(locale:)`
  - Use `AssetInventory.reservedLocales` not `allocatedLocales`
  - Use `AssetInventory.release(reservedLocale:)` not `deallocate(locale:)`

## Phase 2: UI/UX Overhaul and Auto-Detection (August 31, 2025)

### Overview
The app has evolved from a 1:1 meeting tool to support all meeting types, but the UI remains 1:1-focused. This phase implements:
1. Automatic meeting type detection (1:1 vs Group)
2. Voice-based participant identification
3. Unified meeting interface
4. Progressive voice learning system

### Current State Analysis

#### ✅ Already Implemented
1. **Speaker Diarization (DiarizationManager.swift)**
   - FluidAudio integration for "who spoke when"
   - Real-time speaker detection and segmentation
   - Speaker embeddings for voice identification
   - Can identify 2+ speakers automatically

2. **Voice Prints (LiveMeeting.swift)**
   - VoicePrint struct with MFCC features defined
   - IdentifiedParticipant class with voicePrint property
   - Basic infrastructure for voice-based identification

3. **Calendar Integration (CalendarService.swift)**
   - EventKit integration for Apple Calendar
   - Google Calendar provider support
   - Fetches meeting title, attendees, duration
   - Can pre-populate expected participants

4. **Group Support (Core Data)**
   - Group entity with members and meetings
   - GroupMeeting entity for non-1:1 meetings
   - Relationship tracking between groups and people

5. **Auto-Detection Infrastructure**
   - Two-way audio detection for automatic recording start
   - Meeting detection from calendar events
   - Auto-recording capability exists

#### ❌ Missing/Needs Implementation
1. **Meeting Type Auto-Classification**
   - No automatic 1:1 vs Group detection based on voice count
   - LiveMeeting lacks meetingType property
   - No logic to classify based on participant count

2. **Voice Learning & Persistence**
   - VoicePrint not connected to Person records
   - No persistent storage of voice embeddings
   - No progressive learning system
   - Speaker matching not linked to People directory

3. **Unified Meeting View**
   - Current UI is 1:1 focused
   - No unified view showing both meeting types
   - Missing visual differentiation

4. **Smart Participant Identification**
   - Diarization identifies speakers but doesn't match to people
   - Calendar attendees not correlated with detected voices
   - No post-meeting participant confirmation UI

5. **Automatic Meeting Detection**
   - Has calendar integration but not automatic start
   - No proactive meeting preparation
   - Missing real-time participant identification display

### Implementation Phases

#### Phase 1: Core Meeting Type Detection (Quick Win)
**Goal**: Automatically classify meetings as 1:1 or Group based on speaker count

1. **Add meetingType to LiveMeeting.swift**
```swift
enum MeetingType: String, Codable {
    case oneOnOne = "1:1"
    case group = "Group"
}
@Published var meetingType: MeetingType?
@Published var detectedSpeakerCount: Int = 0
```

2. **Integrate with DiarizationManager**
   - In MeetingRecordingEngine.swift, monitor diarization results
   - When speaker count changes:
     ```swift
     if let result = diarizationManager.lastResult {
         liveMeeting.detectedSpeakerCount = result.speakerCount
         liveMeeting.meetingType = result.speakerCount == 2 ? .oneOnOne : .group
     }
     ```

3. **Update Recording Windows**
   - Add meeting type badge to RefinedRecordingWindow
   - Show participant count from diarization
   - Visual differentiation: Blue for 1:1, Green for Group

#### Phase 2: Voice-Person Linking
**Goal**: Connect detected speakers to Person records

1. **Extend Person Core Data Model**
```swift
// Add to Person+CoreDataProperties.swift
@NSManaged public var voiceEmbeddings: Data? // Stores FluidAudio embeddings
@NSManaged public var lastVoiceUpdate: Date?
@NSManaged public var voiceConfidence: Float
```

2. **Create VoicePrintManager.swift**
```swift
class VoicePrintManager {
    // Store embedding from DiarizationManager
    func saveEmbedding(_ embedding: [Float], for person: Person)
    
    // Match diarization embedding to known people
    func findMatchingPerson(for embedding: [Float]) -> (Person?, Float)?
    
    // Progressive confidence improvement
    func updateConfidence(for person: Person, with newEmbedding: [Float])
}
```

3. **Post-Meeting Participant Assignment UI**
   - New view: ParticipantConfirmationView
   - Shows "Speaker 1", "Speaker 2" with audio clips
   - Allows assignment to existing Person or create new
   - Saves embeddings for future matching

#### Phase 3: Smart Calendar Integration
**Goal**: Proactive meeting preparation using calendar data

1. **Pre-Meeting Preparation (MeetingRecordingEngine)**
```swift
func prepareForUpcomingMeeting() {
    // Check calendar 5 minutes before
    if let nextMeeting = calendarService.getNextMeeting(within: 5.minutes) {
        // Load expected participants
        let participants = nextMeeting.attendees
        
        // Pre-load voice embeddings
        for participant in participants {
            if let person = findPerson(named: participant) {
                voicePrintManager.preloadEmbedding(for: person)
            }
        }
        
        // Show notification
        showNotification("Ready to record: \(nextMeeting.title)")
    }
}
```

2. **During-Meeting Correlation**
```swift
func correlateDetectedSpeakers() {
    let calendarAttendees = currentMeeting?.attendees ?? []
    let detectedSpeakers = diarizationManager.currentSpeakers
    
    // Match detected to expected
    for speaker in detectedSpeakers {
        if let match = voicePrintManager.matchToAttendee(speaker, attendees: calendarAttendees) {
            liveMeeting.identifyParticipant(match)
        } else {
            // Flag as unexpected participant
            liveMeeting.addUnexpectedParticipant(speaker)
        }
    }
}
```

#### Phase 4: UI Overhaul
**Goal**: Unified interface for all meeting types

1. **New Dashboard Structure (MeetingsView.swift)**
```swift
struct MeetingsView: View {
    @State private var filter: MeetingFilter = .all
    
    enum MeetingFilter {
        case all, oneOnOne, group
    }
    
    var body: some View {
        VStack {
            // Filter tabs
            Picker("Filter", selection: $filter) {
                Text("All").tag(MeetingFilter.all)
                Text("1:1s").tag(MeetingFilter.oneOnOne)
                Text("Groups").tag(MeetingFilter.group)
            }
            
            // Unified meeting list
            List(filteredMeetings) { meeting in
                MeetingCard(meeting: meeting)
            }
        }
    }
}
```

2. **Meeting Cards with Type Indicators**
```swift
struct MeetingCard: View {
    let meeting: Meeting
    
    var body: some View {
        HStack {
            // Type indicator
            Image(systemName: meeting.type == .oneOnOne ? "person.2" : "person.3")
                .foregroundColor(meeting.type == .oneOnOne ? .blue : .green)
            
            VStack(alignment: .leading) {
                Text(meeting.title)
                Text("\(meeting.participantCount) participants")
                    .font(.caption)
            }
            
            Spacer()
            
            // Auto-detected label
            if meeting.wasAutoDetected {
                Label("Auto", systemImage: "wand.and.stars")
                    .font(.caption)
            }
        }
    }
}
```

3. **Simplified Navigation**
   - Remove complex nested views
   - Single meetings list with smart filters
   - Progressive disclosure for details

#### Phase 5: Progressive Voice Learning
**Goal**: System improves with each confirmed meeting

1. **Automatic Improvement System**
```swift
class VoiceLearningSystem {
    func improveModels(from meeting: CompletedMeeting) {
        for participant in meeting.confirmedParticipants {
            if let person = participant.person,
               let embedding = participant.voiceEmbedding {
                // Update person's voice model
                voicePrintManager.updateModel(for: person, with: embedding)
                
                // Increase confidence
                person.voiceConfidence = min(person.voiceConfidence + 0.05, 1.0)
            }
        }
    }
}
```

2. **Voice Recognition Status in Person Profile**
```swift
struct PersonDetailView: View {
    var body: some View {
        Section("Voice Recognition") {
            HStack {
                Text("Recognition Confidence")
                Spacer()
                Text("\(Int(person.voiceConfidence * 100))%")
            }
            
            if person.voiceConfidence < 0.8 {
                Text("Needs \(3 - person.voiceSampleCount) more samples")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

3. **Smart Notifications**
```swift
func showVoiceNotifications() {
    // During meeting
    if newSpeakerDetected {
        showNotification("New voice detected in meeting")
    }
    
    // High confidence match
    if matchConfidence > 0.95 {
        showNotification("Identified as \(person.name) with 95% confidence")
    }
    
    // Post-meeting
    if hasUnconfirmedParticipants {
        showNotification("Please confirm participants for meeting")
    }
}
```

### Technical Architecture

#### Data Flow
```
Calendar Event → Pre-load Participants → Start Recording
                                             ↓
                                    DiarizationManager
                                             ↓
                                    Speaker Count → Meeting Type
                                             ↓
                                    Voice Embeddings → Match to People
                                             ↓
                                    Post-Meeting Confirmation
                                             ↓
                                    Save & Improve Models
```

#### Key Components Integration
1. **DiarizationManager** → Provides speaker count and embeddings
2. **CalendarService** → Provides expected participants
3. **VoicePrintManager** (new) → Matches embeddings to people
4. **LiveMeeting** → Enhanced with meetingType and speaker tracking
5. **Person** → Extended with voice embeddings and confidence

### Database Schema Changes

```swift
// Person entity additions
voiceEmbeddings: Binary Data // Serialized [Float] arrays
lastVoiceUpdate: Date
voiceConfidence: Float // 0.0 to 1.0
voiceSampleCount: Int32

// Meeting entity additions  
meetingType: String // "1:1" or "Group"
wasAutoDetected: Boolean
detectedSpeakerCount: Int32
confirmedParticipants: Relationship to Person (many-to-many)
```

### Migration Strategy
1. **Phase 1** can be deployed immediately (just UI changes)
2. **Phase 2** requires Core Data migration (lightweight)
3. **Phase 3-5** are progressive enhancements
4. System works without voice data (graceful degradation)

### Success Metrics
- Meeting type correctly detected 95%+ of the time
- Voice recognition accuracy improves to 90%+ after 5 meetings
- Zero manual meeting creation required
- Participant confirmation takes < 30 seconds post-meeting

### Next Steps When Resuming
1. Start with Phase 1 - Add meetingType to LiveMeeting
2. Test speaker count detection with existing DiarizationManager
3. Update UI to show meeting type badges
4. Implement VoicePrintManager for Phase 2
5. Add Core Data migrations for voice embeddings

This comprehensive plan ensures the app evolves from 1:1-focused to a smart, auto-detecting meeting recorder that handles all meeting types elegantly.

## Phase 3: UI/UX Polish & Professional Refinement (September 2025)

### Context
Following successful implementation of robust auto-recording functionality, the UI evaluation revealed that core functionality IS working (monitoring status properly displays), but the interface needs polish and refinement to match modern professional standards.

### UI/UX Evaluation Summary

#### Current State Assessment
✅ **Working Well:**
- Auto-recording monitoring status displays correctly with green pulsing indicator
- Auto-Record toggle syncs properly with engine state
- Meeting list shows recordings with transcript status
- Floating status window provides persistent visibility
- Core navigation between Insights/People/Analytics functions

⚠️ **Needs Polish:**
- Visual hierarchy could be stronger (monitoring indicator competes with other elements)
- Information density is low (too much whitespace, not enough at-a-glance info)
- Micro-interactions missing (no hover states, transitions)
- Professional polish lacking compared to apps like Quill, Krisp, Fireflies

### Improvement Priorities

#### Priority 1: Visual Polish & Micro-interactions
**Goal**: Add subtle animations and feedback that make the UI feel responsive and polished

1. **Enhanced Monitoring Indicator**
   - Add subtle glow effect when actively monitoring
   - Smooth scale animation on state changes
   - Add mini waveform visualization when detecting audio
   ```swift
   // Add to monitoring indicator
   if isDetectingAudio {
       WaveformView()
           .frame(height: 20)
           .opacity(0.6)
   }
   ```

2. **Card Hover States**
   - Add elevation changes on hover (shadow depth)
   - Subtle background color shifts
   - Scale transform: 1.02 on hover

3. **Smooth Transitions**
   - Add crossfade between view states
   - Spring animations for list items appearing
   - Matched geometry effect for expanding cards

#### Priority 2: Information Density
**Goal**: Show more useful information without clutter

1. **Meeting Cards Enhancement**
   ```swift
   struct EnhancedMeetingCard: View {
       var body: some View {
           VStack(alignment: .leading, spacing: 8) {
               // Header with type badge
               HStack {
                   MeetingTypeBadge(type: meeting.type)
                   Spacer()
                   DurationChip(duration: meeting.duration)
               }
               
               // Title and participants
               Text(meeting.title)
                   .font(.headline)
               ParticipantAvatarStack(participants: meeting.participants)
               
               // Quick stats
               HStack(spacing: 12) {
                   StatPill(icon: "mic", value: "\(meeting.speakerCount)")
                   StatPill(icon: "doc.text", value: meeting.wordCount.abbreviated)
                   StatPill(icon: "lightbulb", value: "\(meeting.actionItems)")
               }
               
               // Transcript preview on hover
               if isHovered {
                   Text(meeting.transcriptPreview)
                       .lineLimit(2)
                       .font(.caption)
                       .foregroundColor(.secondary)
                       .transition(.move(edge: .bottom).combined(with: .opacity))
               }
           }
       }
   }
   ```

2. **Status Bar Enhancement**
   - Add mini stats (Today: 3 meetings, 2.5 hrs recorded)
   - Quick access buttons (Start Manual Recording, View Today's Meetings)
   - Time until next meeting countdown

#### Priority 3: Enhanced Interactions
**Goal**: Make common tasks faster and more intuitive

1. **Quick Actions Menu**
   - Right-click context menus on meeting cards
   - Keyboard shortcuts for power users
   - Drag & drop to assign meetings to people

2. **Smart Search**
   - Instant search with live preview
   - Search across transcripts, not just titles
   - Recent searches dropdown

3. **Bulk Operations**
   - Multi-select with checkboxes
   - Batch export, delete, categorize
   - Select all/none/inverse options

#### Priority 4: Professional Polish
**Goal**: Match the sophistication of leading apps

1. **Refined Color Palette**
   ```swift
   extension Color {
       static let primaryGreen = Color(hex: "10B981")  // Emerald for active
       static let primaryBlue = Color(hex: "3B82F6")   // Blue for 1:1s
       static let primaryPurple = Color(hex: "8B5CF6") // Purple for groups
       static let surfaceElevated = Color(hex: "FAFAFA")
       static let borderSubtle = Color(hex: "E5E7EB")
   }
   ```

2. **Typography Hierarchy**
   - Consistent font weights (Regular, Medium, Semibold only)
   - Clear size hierarchy (12, 14, 16, 20, 24pt)
   - Proper line heights for readability

3. **Empty States**
   - Beautiful illustrations for no meetings
   - Helpful onboarding tips
   - Quick action buttons to get started

4. **Loading States**
   - Skeleton screens instead of spinners
   - Progressive data loading
   - Optimistic UI updates

#### Priority 5: Power User Features
**Goal**: Advanced features for frequent users

1. **Customizable Dashboard**
   - Draggable widget panels
   - Collapsible sections
   - Saved view presets

2. **Advanced Filters**
   - Filter by date range, person, duration, keywords
   - Saved filter combinations
   - Quick filter chips

3. **Keyboard Navigation**
   - Full keyboard support
   - Vim-style navigation option
   - Command palette (Cmd+K)

### Implementation Approach

#### Phase 1: Quick Wins (1-2 days)
- Add hover states to all interactive elements
- Implement smooth transitions
- Enhance meeting cards with more info
- Add loading skeletons

#### Phase 2: Core Enhancements (3-4 days)
- Implement quick actions menu
- Add smart search with preview
- Create beautiful empty states
- Refine color palette and typography

#### Phase 3: Advanced Features (5-7 days)
- Build customizable dashboard
- Add keyboard navigation
- Implement command palette
- Create bulk operations

### Design System Components

```swift
// Reusable components following the new design system

struct StatPill: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct ParticipantAvatarStack: View {
    let participants: [Person]
    let maxVisible = 3
    
    var body: some View {
        HStack(spacing: -8) {
            ForEach(participants.prefix(maxVisible)) { person in
                PersonAvatar(person: person)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
            
            if participants.count > maxVisible {
                MoreAvatar(count: participants.count - maxVisible)
            }
        }
    }
}

struct GlowingPulse: ViewModifier {
    @State private var isAnimating = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color.opacity(0.3))
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .opacity(isAnimating ? 0 : 0.5)
                    .animation(
                        .easeInOut(duration: 2)
                        .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            )
            .onAppear { isAnimating = true }
    }
}
```

### Success Metrics
- Time to find specific meeting reduced by 50%
- User engagement with transcript previews > 80%
- Keyboard shortcut adoption > 30% of power users
- Visual polish rated 4.5+ stars in user feedback

### Next Steps
1. Create Figma mockups for each enhancement
2. Implement Priority 1 items first (quick visual wins)
3. A/B test information density changes
4. Gather user feedback on power features
5. Iterate based on usage analytics