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

#### THE NEW APIS EXIST BUT ARE NOT IN THE SDK HEADERS
After analyzing working applications (swift-scribe and yap), the situation is clear:
1. **SpeechAnalyzer, SpeechTranscriber, AssetInventory, and AnalyzerInput ARE real APIs**
2. **They work at runtime** but are NOT exposed in SDK headers
3. **Working apps import Speech framework and use these APIs directly**
4. **The APIs require macOS 26 (Tahoe) and won't compile with availability checks**

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

### 3. Build Configuration
- **Platform must be macOS 26** in Package.swift or project settings
- **No @available checks needed** - the APIs require macOS 26
- **Import Speech framework directly** - APIs work at runtime despite not being in headers