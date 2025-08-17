# Meeting Recording Feature - Quick Start Guide

## How to Access the Feature

### 1. Via Menu Bar
- Look for the **"Recording"** menu in the menu bar (when WhoNext is running)
- Click **"Show Recording Dashboard..."** to open the main interface

### 2. Via Keyboard Shortcuts
- **⌘R** - Start monitoring for meetings
- **⌘⇧R** - Stop monitoring

## Main Features

### Automatic Meeting Detection
The system automatically detects meetings based on:
- **Two-way audio patterns** - Detects when you're in a conversation
- **Conversation confidence scoring** - Starts recording when confidence exceeds threshold
- **No calendar dependency** - Catches ad hoc meetings automatically

### Recording Dashboard
The dashboard shows:
- **Recording Status** - Current state (Idle/Monitoring/Recording)
- **Live Transcription** - Real-time transcription during meetings
- **Quick Settings** - Adjust confidence threshold and auto-recording
- **Manual Controls** - Start/stop recording manually if needed

### Key Components

1. **Auto-Recording Toggle** - Enable/disable automatic recording
2. **Confidence Threshold** - Adjust sensitivity (default 70%)
3. **Manual Recording** - Override automatic detection when needed
4. **Live Meeting Window** - Floating window shows active recording

## Storage & Privacy

- **Local-only storage** - All recordings stay on your Mac
- **30-day retention** - Automatic cleanup of old recordings
- **Recording indicator** - Visual notification when recording
- **Privacy controls** - Configurable notifications and indicators

## Technical Details

### Transcription Pipeline
1. **Parakeet-MLX** - Local real-time transcription (placeholder)
2. **Whisper API** - Refinement for accuracy (when configured)
3. **Speaker diarization** - Identifies different speakers

### Audio Capture
- **Microphone** - Your voice via AVAudioEngine
- **System audio** - Other participants via ScreenCaptureKit
- **VAD** - Voice Activity Detection for conversation patterns

## Getting Started

1. Open WhoNext
2. Go to Recording → Show Recording Dashboard
3. Click "Start Monitoring" or press ⌘R
4. The system will now automatically detect and record meetings
5. Adjust the confidence threshold if needed (lower = more sensitive)

## Troubleshooting

- **No recordings starting?** - Check if monitoring is enabled
- **Too many false positives?** - Increase confidence threshold
- **Missing recordings?** - Decrease confidence threshold
- **Permissions needed** - Grant microphone and screen recording permissions

## Files Created

All meeting recordings are stored in:
- Audio files: `~/Library/Application Support/WhoNext/Recordings/`
- Transcripts: Stored in Core Data with the GroupMeeting entity
- Automatic cleanup after 30 days