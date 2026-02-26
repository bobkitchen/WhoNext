# Transcription & Diarization History

## Architecture Overview

### Pipeline
```
AudioCapturer → AudioChunkBuffer → Transcriber ↘
    ↓                                            Transcript Segments → LiveMeeting
AudioCapturer → DiarizationBuffer → DiarizationManager → SegmentAligner ↗
```

### Key Components
- **DiarizationManager** (`DiarizationManager.swift`): FluidAudio-based speaker diarization with cumulative audio processing
- **SpeakerCache** (embedded in `DiarizationManager.swift`): Arrival-order speaker cache (NVIDIA AOSC-inspired) for stable speaker IDs
- **SpeakerStabilizer** (`SpeakerStabilizer.swift`): Hysteresis-based label stabilization to prevent flip-flopping
- **SegmentAligner** (`SegmentAligner.swift`): Maps diarization results to transcript segments
- **SimpleRecordingEngine** (`SimpleRecordingEngine.swift`): Main recording orchestrator with parallel mic + system audio

### Dual Diarization Streams
Two independent DiarizationManagers run in parallel:
1. `diarizationManager` — processes microphone audio (local speaker)
2. `systemDiarizationManager` — processes system audio (remote speakers via Teams/Zoom)

Each maintains its own sliding window, speaker cache, and segment history.

---

## Configuration Values

### DiarizationManager
| Parameter | Value | Description |
|-----------|-------|-------------|
| `maxCumulativeSeconds` | **300.0** | Sliding window size (was 120.0) |
| `clusteringThreshold` | 0.78 | FluidAudio clustering threshold |
| `minSpeechDuration` | 0.3s | Minimum speech segment duration |
| `minSilenceGap` | 0.2s | Minimum silence between segments |
| `chunkDuration` | 10.0s | Audio chunk size for processing |
| `minSegmentDuration` | 0.5s | Post-processing merge threshold |
| `smoothingWindow` | 1.5s | Minimum turn duration for smoothing |

### SpeakerCache
| Parameter | Value | Description |
|-----------|-------|-------------|
| `matchThreshold` | **0.80** | Cosine similarity threshold for matching (was 0.75) |
| `maxCacheSize` | 20 | Max embeddings per speaker |
| `freezeThreshold` | **10** | Embeddings before freezing centroid (NEW) |
| `ambiguityMargin` | **0.05** | Min gap between best two matches before treating as ambiguous (NEW) |

### SpeakerStabilizer
| Parameter | Value | Description |
|-----------|-------|-------------|
| `requiredConsecutive` | 2 | Consecutive matches needed for label change |
| `hysteresisWindowSeconds` | 1.5s | Time window for hysteresis |
| High-confidence override | **true** | Commit immediately if confidence > 0.85 (NEW) |

---

## Known Issues (Pre-Fix)

### 1. Phantom Speakers Early in Recording
- **Symptom**: 5+ speakers detected with only 2-3 real people
- **Cause**: Small cumulative window (120s) + fresh embeddings creating too many cache entries
- **Fix applied**: Extended window to 300s, raised matchThreshold 0.75→0.80

### 2. Speaker Collapse Mid-Call
- **Symptom**: After ~10-15 min, everything attributed to one speaker
- **Cause**: Centroid drift — SpeakerCache keeps updating centroids indefinitely, causing them to converge
- **Fix applied**: Freeze embeddings after 10 high-quality samples; add ambiguity detection

### 3. Speaker Editing is a Stub
- **Symptom**: `TranscriptSegmentView.editSpeaker()` was a TODO
- **Fix applied**: Added `onEditSpeaker` callback; added Person search picker to ParticipantRow

### 4. Hysteresis Too Aggressive
- **Symptom**: Real speaker changes take 20+ seconds to register (requiredConsecutive=2)
- **Fix applied**: High-confidence changes (>0.85) commit immediately

---

## Change History

### 2026-02-24: Diarization Fix - Speaker Collapse, Phantom Speakers, Person Picker

**Files modified:**
- `DiarizationManager.swift` — Extended window 120→300s, freeze embeddings at 10, raise threshold 0.75→0.80, ambiguity detection
- `SpeakerStabilizer.swift` — High-confidence bypass for hysteresis
- `SimpleRecordingEngine.swift` — Temporal fallback when speaker is ambiguous
- `RecordingWindow.swift` — Person search picker in ParticipantRow, updated onRename signature
- `LiveMeeting.swift` — Added `renameSpeaker(speakerID:to:person:)` method
- `TranscriptSegmentView.swift` — Wired editSpeaker() with onEditSpeaker callback

**Rationale:**
The root cause of both phantom speakers and speaker collapse was the 120-second sliding window in DiarizationManager. When the window slides:
- All speaker embedding context from earlier is lost
- FluidAudio re-clusters from scratch using only the 120s buffer
- SpeakerCache centroids drift as they're continuously updated
- Early: too many speakers (fresh embeddings = distinct centroids)
- Late: one speaker (converged centroids match everything)

**Expected outcomes:**
- 5x more context (300s vs 120s) for speaker identity maintenance
- Frozen centroids prevent drift after stabilization
- Tighter threshold (0.80) prevents premature matching
- Ambiguity detection + temporal fallback prevents both phantom creation and collapse

### 2026-02-24: Permission Fix - AudioCapturer Error Handling & Retry

**Files modified:**
- `AudioCapturer.swift` — Replaced blanket catch with detailed error logging (domain, code, underlying error); added 500ms retry for transient SCShareableContent failures

**Rationale:**
The app was catching ALL errors from `startSystemAudioCapture()` and assuming "permission denied". In reality, SCShareableContent can transiently fail right after app launch. The new code:
1. Logs the actual error domain, code, and underlying error
2. Retries once after 500ms delay
3. Only falls back to mic-only mode if retry also fails

### 2026-02-24: "This is Me" Voice Identification Feature

**Files modified:**
- `RecordingWindow.swift` — Added `onMarkAsMe` callback to ParticipantRow; "This is me" button for non-current-user participants; "You" badge with checkmark for identified user; `markParticipantAsMe()` method that saves voice embedding to UserProfile
- `SimpleRecordingEngine.swift` — Exposed `diarizationManagerResult` accessor for voice embedding retrieval

**Rationale:**
VoicePrintManager searches Person records but the "Me" entry was only matching at 18.4% (below 70% threshold). Users need a way to self-identify during recording. The "This is me" button:
1. Sets `isCurrentUser = true` on the participant
2. Uses `UserProfile.shared.displayName` for the name
3. Unmarks other participants as current user
4. Saves the speaker's voice embedding to `UserProfile.shared.addVoiceSample()` for future auto-matching

### 2026-02-24: Fix Speaker Label Propagation to Inline Transcript

**Files modified:**
- `SimpleRecordingEngine.swift` — Three fixes:
  1. `transcribeChunk()`: Changed `namingMode == .namedByUser` to `namingMode != .unnamed`, use `participant.displayName`
  2. `backfillSpeakerLabels()`: Same fix
  3. `updateParticipants()`: When adding a new participant with a name, backfill ALL existing transcript segments with that speakerID

**Root cause:**
The `namingMode` check was too restrictive. Only `.namedByUser` was accepted, but auto-identified users get `.linkedToPerson` and voice-matched users get `.suggestedByVoice`. The fix broadens the check to accept any naming mode that's not `.unnamed`.

Additionally, when a new participant was auto-identified (e.g., "Me" via voice profile), there was NO backfill of existing transcript segments — only the participant record was updated. Now existing segments are retroactively renamed.

### 2026-02-24: Fix Naming Consistency + Auto-ID Conflict Resolution

**Files modified:**
- `RecordingWindow.swift` — `markParticipantAsMe()`: Use `participant.displayName` ("Me") for segment labels instead of raw name ("Bob Kitchen")
- `SimpleRecordingEngine.swift` — `updateParticipants()`:
  1. When DiarizationManager auto-identifies the user, if another participant was already marked as "me" (via "This is me" button), revert the incorrect marking and re-label segments
  2. Auto-save voice embedding to UserProfile when user is auto-identified (improves future recognition)

**Root cause:**
Three issues: (A) `markParticipantAsMe()` set segments to "Bob Kitchen" but `transcribeChunk()` used `displayName` → "Me", causing inconsistency. (B) If user clicked "This is me" on the wrong speaker, there was no conflict resolution when DiarizationManager later identified the correct speaker. (C) Voice embeddings were only saved via the manual "This is me" button, not on auto-identification.

---

## Test Results

### Test 1: 2026-02-24 — Log Analysis from Pre-Fix Recording

**Source**: YouTube video test (1-2 speakers), log saved as RTF

**Key observations:**
- **Diarization fixes ARE working**: Speaker 1 frozen at ~100s, only 2 speakers detected (no phantom explosion)
- **Temporal fallback activated**: At least one segment used temporal continuity fallback
- **VoicePrintManager**: Found "Me: 18.4%" but below 70% threshold → led to "This is me" feature
- **Permission issue**: Log showed OLD code (pre-fix) with blanket "Screen recording permission denied" message
- **`throwing -10877` errors**: These are from AVAudioEngine, NOT SCShareableContent — the actual SCStream error was being swallowed by the old blanket catch

**Permission error revealed:** `SCStreamErrorDomain code -3801: "The user declined TCCs for application, window, display capture"`. Even though permissions are enabled in System Settings, TCC is denying the request. Likely a stale TCC entry from a prior signing identity. Fix: `tccutil reset ScreenCapture com.bobk.WhoNext` from Terminal, then restart app.

**Speaker label bug found:** When auto-identified as "Me" (speaker 2, confidence 75%), the participant was correctly created but inline transcript labels stayed as "Speaker 1 (Local)" / "Speaker 2 (Local)" instead of showing the participant's name.

**Pending verification:**
- Real multi-speaker testing (2+ people on Teams/Zoom) still needed for 15/30/45/60 min verification
- Entitlements: App is sandboxed (`ENABLE_APP_SANDBOX = YES`), has `com.apple.security.device.audio-input` but no screen capture entitlement (shouldn't be needed on macOS 14+ for ScreenCaptureKit)

### Test 2: 2026-02-24 — Second Recording Test (Post Diarization Fixes)

**Positive observations:**
- Diarization frozen at 100s as expected
- Only 2 speakers detected (no phantom explosion)
- Auto-identified user as speaker 2 at 75% confidence
- User's own words captured in transcript: "My voice. Oh yeah it does. It's caught me."

**Bug: Speaker labels not propagating to inline transcript**

Root cause: `transcribeChunk()` and `backfillSpeakerLabels()` only used participant names when `namingMode == .namedByUser`, but auto-identification sets `.linkedToPerson`. Also, no backfill of existing segments when a new participant is auto-identified.

Fixed in same session — see change history entry below.

### Test 3: 2026-02-24 — Third Recording (Full Audio Mode, YouTube + User Speaking)

**Positive:**
- System audio WORKING ("Full Audio mode") — TCC reset fixed it
- YouTube correctly detected as "Speaker 1 (Remote)" via system audio
- Labels DID update: after "This is me" click, transcribeChunk showed "Me" (line 698)
- DiarizationManager auto-identified user as speaker 2 at 77% confidence (line 764)
- Speaker 1 frozen at 100s as expected

**Issues found:**
1. **"Bob Kitchen" then "Me" inconsistency**: `markParticipantAsMe()` backfilled segments with "Bob Kitchen", but `transcribeChunk()` used `participant.displayName` → "Me". Fixed: now both use `displayName`.
2. **Ghost Speaker 2 (Local)**: YouTube audio leaks through speakers into mic. FluidAudio correctly detects this as a different voice from the user. User clicked "This is me" on mic_1 (YouTube leak), then mic_2 (user's actual voice) appeared later. Not a diarization bug — it's correct behavior for mixed audio sources.
3. **Voice recognition low (19%)**: VoicePrintManager matched "Me" at only 19%. Possible cause: voice embedding saved from previous session may have been weak. Fixed: auto-identification now saves embeddings to UserProfile automatically.
4. **Wrong speaker marked as "me"**: User clicked "This is me" on mic_1 (YouTube leak) instead of waiting for mic_2 (their actual voice). Fixed: when DiarizationManager identifies a different speaker as the user, it now reverts the incorrect marking and re-labels transcript segments.

### Verification checklist:
1. Start recording with 2-3 speakers
2. Check speaker count stabilizes within first 2-3 minutes
3. Verify speakers continue switching correctly at 15, 30, 45, 60 minutes
4. Check debug logs for:
   - `[SpeakerCache] Speaker X frozen` events
   - `[SpeakerCache] Ambiguous match` events
   - `⚠️ Reverted ... voice ID says ... is the real user` (conflict resolution)
   - Sliding window trim messages
5. Test Person picker: search, select, verify backfill
6. Test "This is me" button: verify consistent "Me" label throughout
7. Verify voice recognition improves across sessions (should climb above 70%)
