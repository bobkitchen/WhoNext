# WhoNext Meeting Transcription Feature - Technical Brief & Implementation Plan

**Project**: Automatic Meeting Detection, Transcription & AI Summarization  
**Date**: June 17, 2025  
**Version**: 1.0  
**Author**: Development Team

---

## 📋 Executive Summary

This document outlines the technical implementation plan for adding automatic meeting transcription capabilities to WhoNext. The feature will detect meetings automatically, transcribe them using Apple's new SpeechAnalyzer framework with OpenAI Whisper fallback, and integrate transcripts into the existing AI summarization pipeline.

**Key Objectives:**
- Automatic meeting detection and transcription
- Privacy-first approach (process and delete transcripts)
- Hybrid local/cloud processing architecture
- Seamless integration with existing WhoNext conversation tracking

---

## 🎯 Feature Requirements

### Core Functionality
- [x] **Automatic Meeting Detection**: Detect when Teams/Zoom/FaceTime meetings start
- [x] **Real-time Transcription**: Live speech-to-text during meetings
- [x] **AI Processing**: Feed transcripts to existing OpenAI summarization pipeline
- [x] **Privacy Protection**: No transcript storage, immediate deletion after processing
- [x] **Person Linking**: Connect meetings to existing people in WhoNext database

### User Experience
- [x] **Zero-touch Operation**: Automatic start/stop based on meeting detection
- [x] **Live Feedback**: Show transcription status during meetings
- [x] **Post-meeting Summary**: Automatic conversation creation with AI insights
- [x] **Manual Override**: User control to start/stop recording

---

## 🏗️ Technical Architecture

### High-Level System Design

```
Meeting Detection → Audio Capture → Speech Recognition → AI Processing → WhoNext Integration
       ↓                 ↓              ↓                    ↓                 ↓
   Calendar API      ScreenCaptureKit  SpeechAnalyzer    OpenAI API      Core Data
   Process Monitor   Core Audio        Whisper (fallback) Existing Pipeline Person Linking
   Browser Extension                   Apple Intelligence
```

### Hybrid Processing Strategy

Following WhoNext's established pattern for AI services:

```swift
class SpeechTranscriptionService {
    enum Provider {
        case apple    // SpeechAnalyzer (primary)
        case openai   // Whisper (fallback)
    }
    
    var preferredProvider: Provider {
        return AppleIntelligenceService.shared.isAvailable ? .apple : .openai
    }
}
```

---

## 🛠️ Technology Stack

### Meeting Detection
- **NSWorkspace**: Monitor running applications (Teams, Zoom, FaceTime)
- **EventKit**: Calendar integration for meeting prediction
- **Browser Extension**: Web-based meeting detection (Chrome/Safari)
- **Process Monitoring**: Detect meeting app activity states

### Audio Capture
- **ScreenCaptureKit** (macOS 12.3+): System audio capture
- **AVAudioEngine**: Audio routing and processing
- **Core Audio**: Low-level audio management

### Speech Recognition

#### Primary: Apple SpeechAnalyzer (iOS 18/macOS 15+)
```swift
let transcriber = SpeechTranscriber(
    locale: Locale.current,
    transcriptionOptions: [],
    reportingOptions: [.volatileResults],  // Real-time results
    attributeOptions: [.audioTimeRange]    // Time synchronization
)
let analyzer = SpeechAnalyzer(modules: [transcriber])
```

**Advantages:**
- 55% faster than Whisper
- On-device processing (privacy)
- Real-time transcription
- Automatic model updates
- Zero app size increase

#### Fallback: OpenAI Whisper
- For unsupported languages
- Enhanced accuracy scenarios
- Older device compatibility
- Integration with existing OpenAI pipeline

### AI Processing
- **Existing OpenAI Integration**: Leverage current summarization pipeline
- **Apple Intelligence**: On-device processing when available
- **Hybrid Processing**: Local + cloud based on user preferences

---

## 📁 Project Structure

### New Components

```
WhoNext/
├── Speech/
│   ├── SpeechTranscriptionService.swift     # Main service coordinator
│   ├── AppleSpeechProvider.swift            # SpeechAnalyzer implementation
│   ├── WhisperSpeechProvider.swift          # OpenAI Whisper fallback
│   └── SpeechProvider.swift                 # Protocol definition
├── MeetingDetection/
│   ├── MeetingDetectionService.swift        # Meeting detection coordinator
│   ├── CalendarMeetingDetector.swift        # EventKit integration
│   ├── ProcessMeetingDetector.swift         # App monitoring
│   └── AudioMeetingDetector.swift           # Audio-based detection
├── AudioCapture/
│   ├── AudioCaptureService.swift            # Audio capture coordinator
│   ├── ScreenAudioCapture.swift             # ScreenCaptureKit implementation
│   └── MicrophoneAudioCapture.swift         # Direct microphone access
└── MeetingProcessor/
    ├── MeetingProcessor.swift               # Main processing pipeline
    ├── TranscriptProcessor.swift            # Transcript handling
    └── MeetingConversationCreator.swift     # WhoNext integration
```

---

## 🚀 Implementation Phases

### Phase 1: Foundation (Week 1-2)
**Goal**: Basic transcription capability with manual triggers

#### Tasks:
1. **Create Speech Service Architecture**
   ```swift
   // Implement hybrid provider pattern
   protocol SpeechProvider {
       func startTranscription() async
       func stopTranscription() async
       func transcribe(audioData: Data) async -> TranscriptionResult
   }
   ```

2. **Implement Apple SpeechAnalyzer Provider**
   - Initialize SpeechAnalyzer with proper configuration
   - Handle real-time transcription results
   - Manage speech model availability

3. **Implement Whisper Fallback Provider**
   - Integrate with existing OpenAI service
   - Handle audio file processing
   - Error handling and retry logic

4. **Basic Audio Capture**
   - ScreenCaptureKit integration for system audio
   - Microphone access permissions
   - Audio format handling

5. **Manual UI Controls**
   - Start/stop recording buttons
   - Live transcription display
   - Status indicators

**Deliverables:**
- Manual meeting transcription working
- Hybrid provider system functional
- Basic UI for testing

### Phase 2: Automatic Detection (Week 3-4)
**Goal**: Automatic meeting detection and recording

#### Tasks:
1. **Calendar Integration**
   ```swift
   class CalendarMeetingDetector {
       func detectUpcomingMeetings() -> [Meeting]
       func isCurrentlyInMeeting() -> Bool
       func getMeetingParticipants() -> [String]
   }
   ```

2. **Process Monitoring**
   - Monitor Teams, Zoom, FaceTime processes
   - Detect meeting state changes
   - Handle app lifecycle events

3. **Browser Extension (Optional)**
   - Chrome/Safari extension for web meetings
   - Communication with native app
   - Web meeting platform detection

4. **Audio-based Detection**
   - Detect when multiple voices are present
   - Meeting vs. non-meeting audio classification
   - Background noise analysis

5. **Automatic Workflow**
   - Auto-start transcription on meeting detection
   - Auto-stop when meeting ends
   - Graceful handling of detection failures

**Deliverables:**
- Fully automatic meeting detection
- Zero-touch transcription workflow
- Robust error handling

### Phase 3: WhoNext Integration (Week 5-6)
**Goal**: Seamless integration with existing conversation system

#### Tasks:
1. **Transcript Processing Pipeline**
   ```swift
   class MeetingProcessor {
       func processTranscript(_ transcript: String, participants: [String]) async {
           // 1. Feed to AI summarization
           // 2. Extract action items
           // 3. Identify speakers
           // 4. Create conversation record
           // 5. Link to people
           // 6. Delete transcript
       }
   }
   ```

2. **Person Identification & Linking**
   - Match calendar participants to WhoNext people
   - Fuzzy name matching algorithms
   - Handle unknown participants
   - Speaker identification from voice patterns

3. **AI Integration**
   - Feed transcripts to existing OpenAI pipeline
   - Generate meeting summaries
   - Extract action items and insights
   - Sentiment analysis

4. **Conversation Creation**
   - Auto-create conversation records
   - Link to identified people
   - Set proper timestamps and metadata
   - Trigger sync to Supabase

5. **Privacy Implementation**
   - Immediate transcript deletion
   - Secure in-memory processing
   - User consent workflows
   - Data handling transparency

**Deliverables:**
- Full WhoNext integration
- Automatic conversation creation
- Privacy-compliant processing

### Phase 4: Polish & Advanced Features (Week 7-8)
**Goal**: Production-ready feature with advanced capabilities

#### Tasks:
1. **Performance Optimization**
   - Real-time processing optimization
   - Memory management for long meetings
   - Battery usage optimization
   - CPU utilization monitoring

2. **Advanced Detection**
   - Meeting platform-specific detection
   - Screen sharing detection
   - Participant join/leave detection
   - Meeting quality assessment

3. **User Experience Enhancements**
   - Live transcription display
   - Meeting status notifications
   - Post-meeting summary previews
   - Error recovery flows

4. **Settings & Configuration**
   - Provider preference settings
   - Language selection
   - Auto-detection toggles
   - Privacy controls

5. **Testing & Quality Assurance**
   - Comprehensive testing across meeting platforms
   - Performance testing with long meetings
   - Privacy audit and validation
   - User acceptance testing

**Deliverables:**
- Production-ready feature
- Comprehensive testing coverage
- User documentation
- Privacy compliance validation

---

## 🔧 Technical Implementation Details

### SpeechAnalyzer Implementation

```swift
class AppleSpeechProvider: SpeechProvider {
    private var speechAnalyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    
    func initialize() async throws {
        // Check availability
        guard #available(macOS 15.0, *) else {
            throw SpeechError.unsupportedPlatform
        }
        
        // Configure transcriber
        transcriber = SpeechTranscriber(
            locale: Locale.current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        
        // Create analyzer
        speechAnalyzer = SpeechAnalyzer(modules: [transcriber!])
    }
    
    func startTranscription() async throws {
        // Start live transcription
        for await result in speechAnalyzer!.transcriptionResults {
            await handleTranscriptionResult(result)
        }
    }
    
    private func handleTranscriptionResult(_ result: TranscriptionResult) async {
        if result.isVolatile {
            // Update live UI
            await updateLiveTranscript(result.text)
        } else {
            // Process final segment
            await processTranscriptSegment(result.text, timeRange: result.timeRange)
        }
    }
}
```

### Meeting Detection Implementation

```swift
class MeetingDetectionService: ObservableObject {
    @Published var isInMeeting = false
    @Published var currentMeeting: Meeting?
    
    private let calendarDetector = CalendarMeetingDetector()
    private let processDetector = ProcessMeetingDetector()
    private let audioDetector = AudioMeetingDetector()
    
    func startMonitoring() {
        // Combine multiple detection methods
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await self.checkMeetingStatus() }
        }
    }
    
    private func checkMeetingStatus() async {
        let calendarMeeting = calendarDetector.isCurrentlyInMeeting()
        let processMeeting = processDetector.isMeetingAppActive()
        let audioMeeting = await audioDetector.detectMeetingAudio()
        
        let newMeetingStatus = calendarMeeting || processMeeting || audioMeeting
        
        if newMeetingStatus != isInMeeting {
            await handleMeetingStateChange(newMeetingStatus)
        }
    }
    
    private func handleMeetingStateChange(_ inMeeting: Bool) async {
        isInMeeting = inMeeting
        
        if inMeeting {
            await startMeetingTranscription()
        } else {
            await stopMeetingTranscription()
        }
    }
}
```

### Audio Capture Implementation

```swift
class AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    func startCapturingSystemAudio() async throws {
        // Request screen recording permission for system audio
        let permission = await requestScreenRecordingPermission()
        guard permission else {
            throw AudioError.permissionDenied
        }
        
        // Configure ScreenCaptureKit for system audio
        let filter = SCContentFilter(desktopIndependentWindow: SCWindow())
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        
        // Start audio stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try await stream.startCapture()
    }
    
    func startCapturingMicrophone() throws {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine!.inputNode
        
        let recordingFormat = inputNode!.outputFormat(forBus: 0)
        
        inputNode!.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.processAudioBuffer(buffer)
        }
        
        try audioEngine!.start()
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to format suitable for speech recognition
        // Send to active speech provider
    }
}
```

---

## 🔒 Privacy & Security Considerations

### Data Handling Principles
1. **No Transcript Storage**: Transcripts processed in-memory only
2. **Immediate Deletion**: Raw audio and transcripts deleted after processing
3. **User Consent**: Clear permission requests and privacy explanations
4. **Local Processing**: Prefer on-device processing when possible
5. **Minimal Data**: Only process what's necessary for functionality

### Implementation Details

```swift
class PrivacyManager {
    static func processTranscriptSecurely(_ transcript: String) async {
        // 1. Process with AI
        let summary = await AIService.shared.generateSummary(transcript)
        
        // 2. Create conversation
        let conversation = await createConversation(summary: summary)
        
        // 3. Immediately clear transcript
        transcript = "" // Clear from memory
        
        // 4. Force garbage collection
        autoreleasepool {
            // Processing complete, memory cleaned
        }
    }
    
    static func requestMeetingPermissions() async -> Bool {
        // Request microphone permission
        let micPermission = await AVAudioSession.sharedInstance().requestRecordPermission()
        
        // Request screen recording permission (for system audio)
        let screenPermission = await requestScreenRecordingPermission()
        
        return micPermission && screenPermission
    }
}
```

### User Transparency
- Clear notification when recording starts/stops
- Privacy policy updates explaining meeting transcription
- Option to disable automatic detection
- Manual override controls always available

---

## 📊 Performance Requirements

### System Requirements
- **macOS 15.0+** for SpeechAnalyzer
- **macOS 12.3+** for ScreenCaptureKit
- **8GB RAM minimum** for real-time processing
- **Apple Silicon recommended** for optimal performance

### Performance Targets
- **Transcription Latency**: < 2 seconds for live results
- **CPU Usage**: < 20% during active transcription
- **Memory Usage**: < 500MB for hour-long meetings
- **Battery Impact**: Minimal drain on laptops
- **Processing Speed**: Real-time or faster for all audio

### Optimization Strategies
- Use SpeechAnalyzer's volatile results for immediate feedback
- Process audio in chunks to manage memory
- Implement efficient audio buffering
- Optimize Core Data operations for conversation creation

---

## 🧪 Testing Strategy

### Unit Testing
- Speech provider implementations
- Meeting detection algorithms
- Audio capture functionality
- Privacy compliance validation

### Integration Testing
- End-to-end meeting transcription workflow
- AI pipeline integration
- WhoNext conversation creation
- Multi-platform meeting app compatibility

### Performance Testing
- Long meeting transcription (2+ hours)
- Multiple simultaneous meetings
- Memory leak detection
- Battery usage measurement

### User Acceptance Testing
- Real meeting scenarios across different platforms
- Privacy workflow validation
- Error handling and recovery
- User experience evaluation

---

## 🎯 Success Metrics

### Technical Metrics
- **Transcription Accuracy**: > 95% for clear audio
- **Detection Reliability**: > 98% meeting start/stop detection
- **Processing Speed**: Real-time or faster transcription
- **Privacy Compliance**: Zero transcript storage incidents

### User Experience Metrics
- **User Adoption**: % of users enabling auto-transcription
- **Feature Usage**: Meetings transcribed per user per week
- **User Satisfaction**: Post-meeting summary quality ratings
- **Error Recovery**: Successful handling of edge cases

### Business Metrics
- **Conversation Creation**: Increase in tracked conversations
- **Relationship Insights**: Enhanced meeting frequency data
- **User Engagement**: Time spent reviewing meeting summaries
- **Competitive Advantage**: Differentiation vs. other meeting tools

---

## 🚧 Risk Assessment & Mitigation

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|---------|-------------|------------|
| SpeechAnalyzer API limitations | High | Medium | Robust Whisper fallback |
| Meeting detection failures | Medium | Medium | Multiple detection methods |
| Audio capture permission issues | High | Low | Clear user education |
| Performance on older devices | Medium | Medium | Graceful degradation |

### Privacy Risks

| Risk | Impact | Probability | Mitigation |
|------|---------|-------------|------------|
| Accidental transcript storage | High | Low | Code review + testing |
| Unauthorized audio access | High | Low | System permission enforcement |
| User consent confusion | Medium | Medium | Clear privacy explanations |
| Data breach during processing | High | Very Low | In-memory only processing |

### Business Risks

| Risk | Impact | Probability | Mitigation |
|------|---------|-------------|------------|
| User privacy concerns | Medium | Medium | Transparency + local processing |
| Competitive pressure | Medium | High | Faster implementation timeline |
| Platform policy changes | Medium | Low | Multi-platform strategy |
| User adoption resistance | Low | Medium | Gradual rollout + education |

---

## 📅 Project Timeline

### Week 1-2: Foundation
- [ ] Speech service architecture
- [ ] Apple SpeechAnalyzer integration
- [ ] Whisper fallback implementation
- [ ] Basic audio capture
- [ ] Manual UI controls

### Week 3-4: Automatic Detection  
- [ ] Calendar integration
- [ ] Process monitoring
- [ ] Audio-based detection
- [ ] Automatic workflow
- [ ] Error handling

### Week 5-6: WhoNext Integration
- [ ] Transcript processing pipeline
- [ ] Person identification & linking
- [ ] AI integration
- [ ] Conversation creation
- [ ] Privacy implementation

### Week 7-8: Polish & Launch
- [ ] Performance optimization
- [ ] Advanced detection features
- [ ] User experience enhancements
- [ ] Settings & configuration
- [ ] Testing & QA

**Total Timeline**: 8 weeks to production-ready feature

---

## 💰 Resource Requirements

### Development Resources
- **1 Senior Developer**: Full-time for 8 weeks
- **UI/UX Support**: 1-2 weeks for meeting transcription interface
- **QA Testing**: 1 week comprehensive testing
- **Privacy Review**: Legal/compliance review of data handling

### Infrastructure
- **No additional infrastructure**: Leverages existing OpenAI integration
- **Development Devices**: macOS 15+ devices for testing
- **Meeting Accounts**: Teams, Zoom, etc. for testing

### External Dependencies
- **OpenAI API**: Existing integration, no additional costs
- **Apple Developer**: No additional fees
- **Meeting Platforms**: Standard user accounts for testing

---

## 🔮 Future Enhancements

### Phase 2 Features (Post-Launch)
- **Multi-language Support**: Expanded language detection
- **Speaker Identification**: Voice pattern recognition
- **Meeting Quality Metrics**: Audio quality assessment
- **Advanced AI Analysis**: Topic extraction, mood analysis
- **Integration APIs**: Third-party meeting platform APIs

### Long-term Vision
- **Mobile Support**: iPhone/iPad meeting transcription
- **Offline Capability**: Enhanced local processing
- **Team Features**: Shared meeting insights
- **Analytics Dashboard**: Meeting pattern analysis
- **Voice Commands**: Start/stop via Siri

---

## 📞 Contact & Support

### Development Team
- **Technical Lead**: [Assign]
- **UI/UX Designer**: [Assign]
- **QA Engineer**: [Assign]
- **Privacy Officer**: [Assign]

### External Resources
- **Apple Developer Support**: For SpeechAnalyzer issues
- **OpenAI Support**: For Whisper integration
- **Privacy Consultant**: For compliance review

---

## 📚 References & Documentation

### Apple Documentation
- [SpeechAnalyzer API Documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
- [WWDC 2025 Session 277: Advanced Speech-to-Text](https://developer.apple.com/videos/play/wwdc2025/277/)
- [ScreenCaptureKit Documentation](https://developer.apple.com/documentation/screencapturekit)

### Competitive Analysis
- [Quill Meetings](https://www.quillmeetings.com) - Technical approach reference
- [MacStories SpeechAnalyzer Analysis](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)

### Technical Resources
- OpenAI Whisper API documentation
- EventKit framework documentation
- AVAudioEngine best practices
- Core Data performance optimization

---

**Document Version**: 1.0  
**Last Updated**: June 17, 2025  
**Next Review**: June 24, 2025

---

*This document serves as the master technical reference for implementing meeting transcription in WhoNext. All development should follow the architecture and principles outlined here.*