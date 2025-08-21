# Claude Development Notes for WhoNext

## Important Configuration Requirements

### macOS Deployment Target
- **CRITICAL**: The deployment target MUST remain at macOS 26.0 throughout the project
- Do NOT change deployment targets to lower versions even if build errors occur
- This project uses experimental macOS 26 APIs (Speech framework with SpeechAnalyzer and SpeechTranscriber)

### Build Environment
- **ALWAYS use Xcode Beta for building** - located at `/Applications/Xcode-beta.app`
- Running on macOS 26 (Sequoia)
- Uses Xcode beta for macOS 26 SDK support
- Project intentionally uses cutting-edge APIs for speech transcription

### Build Commands
When building from command line, always use:
```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild
```
NOT the standard `xcodebuild` command which points to the release version.

## Project Context

### Speech Transcription
- Using modern Speech framework APIs (SpeechAnalyzer, SpeechTranscriber) available in macOS 26+
- Audio buffer duration optimized to 30 seconds (with 60-second maximum) for better transcription context
- Plans to add OpenAI Whisper integration alongside Apple's local model for comparison

### Recent Improvements
- Fixed concurrent access issues in SpeechAnalyzer by creating new instances per transcription
- Implemented 30-second audio buffer accumulation for improved transcription quality
- Added screen recording permission request flow similar to microphone permissions
- Redirected recorded meetings to transcript import UI for review before saving

## Known Issues
- Build may fail with standard Xcode if macOS 26 SDK is not available
- May need Xcode beta or special SDK installation for macOS 26 support