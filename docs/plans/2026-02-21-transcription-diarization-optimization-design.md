# Transcription & Diarization Optimization Design

**Date:** 2026-02-21
**Status:** Approved
**Approach:** Bottom-up (fix foundation, then expand scope)

## Problem Summary

The WhoNext meeting recording pipeline has several issues affecting transcription and diarization quality, performance, and completeness:

1. **Remote participants are not diarized** — only mic audio feeds the diarization pipeline, so Zoom/Teams participants get transcribed but never speaker-separated
2. **Naive audio downsampling** degrades diarization quality
3. **O(n) backfill** on every diarization update wastes CPU
4. **Unbounded memory** in SegmentAligner
5. **Synchronous Core Data queries** block the main thread
6. **Unimplemented features** (`compareSpeakers()`, user speaker marking, disk flush)
7. **Thread safety gaps** and type mismatches

## Architecture

### Current Pipeline

```
Mic Audio ──► Transcription ──► TranscriptSegment
         └──► Diarization  ──► SegmentAligner ──► Speaker labels

System Audio ──► Transcription ──► TranscriptSegment
              (NO diarization — remote speakers unattributed)
```

### Target Pipeline

```
Mic Audio ──────► Transcription ──► TranscriptSegment
             └──► Mic Diarization ──┐
                                     ├──► SegmentAligner ──► Speaker labels
System Audio ──► Transcription ──►  │    (merged, prefixed IDs)
             └──► Sys Diarization ──┘
```

---

## Section 1: Audio Quality Foundation

### 1a. Fix downsampling in DiarizationManager

**File:** `DiarizationManager.swift` — `convertBufferToFloatArray()` (lines 505-541)

**Problem:** Uses naive stride-based decimation (picks every Nth sample) with no anti-aliasing filter. This introduces aliasing artifacts that degrade speaker embedding quality.

**Fix:** Replace manual downsampling with `AVAudioConverter`, matching the pattern `AudioCapturer` already uses for the transcription path. Since buffers arriving from `DiarizationBuffer` are already 16kHz (converted by `AudioCapturer`), the downsampling path rarely fires — but when it does (e.g., `processAudioFile()`), it must be correct.

**Implementation:**
- Add a lazily-created `AVAudioConverter` property to `DiarizationManager`
- In `convertBufferToFloatArray()`, when `sourceSampleRate != 16000`:
  - Create source format from buffer
  - Use converter to resample to 16kHz mono
  - Extract float samples from converted buffer
- When already at 16kHz, keep the existing fast path (just downmix channels to mono)

### 1b. Dynamic embedding dimension validation in VoicePrintManager

**File:** `VoicePrintManager.swift`

**Problem:** Hard-codes `embeddingDimension = 256` without verifying what FluidAudio actually produces. If the dimension changes, all voice matching silently fails.

**Fix:**
- On first embedding save for any person, record the actual dimension
- Change `embeddingDimension` from a constant to a computed property that reads from UserDefaults (with 256 as default)
- In `findMatchingPerson()`, when comparing embeddings of different dimensions, log a warning and skip the comparison instead of returning a false 0.0 similarity
- In `saveEmbedding()`, if the incoming dimension differs from stored, log a migration warning and update the stored dimension

---

## Section 2: Performance Fixes

### 2a. Backfill cursor

**File:** `SimpleRecordingEngine.swift` — `backfillSpeakerLabels()` (lines 444-478)

**Problem:** Iterates ALL transcript segments every time diarization produces a result, checking each for `speakerID == nil`. This is O(n) where n is total segments.

**Fix:**
- Add `private var backfillCursor: Int = 0` to `SimpleRecordingEngine`
- In `backfillSpeakerLabels()`, iterate from `backfillCursor` instead of 0
- After each pass, advance the cursor to the first remaining nil-speakerID segment
- Reset cursor to 0 in `startRecording()` along with other state

### 2b. SegmentAligner history cap

**File:** `SegmentAligner.swift`

**Problem:** `allSegments` is replaced wholesale from DiarizationManager (which caps at 5000), so it's implicitly bounded. But `knownSpeakers` grows unboundedly for very long meetings.

**Fix:**
- Add explicit cap to `allSegments` at 5000 (defensive, matching DiarizationManager)
- Cap `knownSpeakers` at 100 (no meeting has 100 real speakers — prune oldest if exceeded)
- Log warnings when caps are hit

### 2c. VoicePrintManager async Core Data

**File:** `VoicePrintManager.swift` — `refreshEmbeddingsCache()` (lines 91-114)

**Problem:** Synchronous `context.fetch()` on the view context blocks the main thread during recording.

**Fix:**
- Use `persistenceController.container.performBackgroundTask` for the fetch
- Make `refreshEmbeddingsCache()` async
- Make `findMatchingPerson()` async (callers already in async context)
- Pre-warm the cache in `SimpleRecordingEngine.preWarm()` so it's ready before the first diarization chunk

---

## Section 3: System Audio Diarization

### Overview

Add a second diarization pipeline for system audio (ScreenCaptureKit output). This captures remote meeting participants independently from the local mic.

### 3a. SimpleRecordingEngine changes

**File:** `SimpleRecordingEngine.swift`

Add second diarization instances:
```swift
#if canImport(FluidAudio)
private let diarizationManager = DiarizationManager(enableRealTimeProcessing: true)
private let systemDiarizationManager = DiarizationManager(enableRealTimeProcessing: true)
private let diarizationBuffer = DiarizationBuffer()
private let systemDiarizationBuffer = DiarizationBuffer()
private let segmentAligner = SegmentAligner()
private let voicePrintManager = VoicePrintManager()
#endif
```

In `processAudioStreams()`, update the system stream task:
```swift
// System stream processor (for transcription AND diarization)
group.addTask {
    for await audioBuffer in systemStream {
        guard !Task.isCancelled else { break }

        // Transcription (existing)
        if let chunk = await buffer.addBuffer(audioBuffer, isMic: false) {
            await self.transcribeChunk(chunk)
        }

        // NEW: Also feed to system diarization buffer
        let elapsed = await MainActor.run { self.recordingDuration }
        if let (diarChunk, startTime) = await systemDiarBuffer.addBuffer(audioBuffer, recordingElapsed: elapsed) {
            await self.processSystemDiarizationChunk(diarChunk, startTime: startTime)
        }
    }
}
```

Add `processSystemDiarizationChunk()` — mirrors `processDiarizationChunk()` but uses `systemDiarizationManager` and calls `segmentAligner.updateSystemDiarizationResults()`.

Initialize, reset, flush, and finalize the system diarization manager at all the same points as the mic diarization manager.

### 3b. SegmentAligner dual-stream support

**File:** `SegmentAligner.swift`

- Maintain two segment arrays: `micSegments` and `systemSegments`
- Add `updateSystemDiarizationResults(_ result:)` method
- Speaker IDs are prefixed on ingestion:
  - Mic speakers: `"mic_1"`, `"mic_2"`, etc.
  - System speakers: `"sys_1"`, `"sys_2"`, etc.
- `dominantSpeaker()` queries both arrays, computing overlap-weighted time across both sources
- `getUniqueSpeakers()` and `getSpeakingTimes()` merge both arrays
- `SpeakerStabilizer` works unchanged (just sees prefixed IDs)
- `formatSpeakerName()` updated to strip prefixes for display, optionally showing "(Local)"/"(Remote)"

### 3c. Participant reconciliation

**File:** `SimpleRecordingEngine.swift` — `updateParticipants()`

- Handle both namespaces when creating `IdentifiedParticipant` records
- Mic speaker matching against `UserProfile.shared` identifies the local user
- System speakers are remote participants
- Voice embeddings from both managers feed into `VoicePrintManager` for matching

### 3d. Graceful degradation

If screen recording permission is denied (`captureMode == .microphoneOnly`):
- `systemDiarizationManager` is never fed audio
- Everything works exactly as before (mic-only diarization)
- No code path changes needed — the system stream simply produces no buffers

---

## Section 4: Missing Feature Implementations

### 4a. compareSpeakers() implementation

**File:** `DiarizationManager.swift` (lines 492-500)

**Problem:** Returns hardcoded `0.5`.

**Fix:** Use existing infrastructure:
1. Process each audio buffer through `fluidDiarizer.performCompleteDiarization()` to extract speaker embeddings
2. Compute cosine similarity between the resulting embeddings using `SpeakerCache.cosineSimilarity()`
3. Return the real similarity score

### 4b. User speaker marking

**File:** `DiarizationManager.swift` (lines 481-487)

**Problem:** `identifyUserSpeaker()` detects the user but doesn't act on it.

**Fix:**
- Add `@Published var userSpeakerId: String?` property
- When `matchesUserVoice()` returns true, set `userSpeakerId = segment.speakerId`
- In `SimpleRecordingEngine.updateParticipants()`, check `diarizationManager.userSpeakerId` and auto-set `IdentifiedParticipant.isCurrentUser = true` with the user's profile name

### 4c. Disk flush for long meetings

**File:** `LiveMeeting.swift` (lines 218-232)

**Problem:** `flushOldSegments()` comment says "In production, write to disk here" but doesn't.

**Fix:**
- On flush, JSON-encode old segments to `{cacheDir}/meeting_{id}_segments.jsonl` (append mode)
- `getFullTranscriptText()` reads from disk + in-memory segments
- On meeting finalization, read the file for complete transcript, then delete temp file
- If the file doesn't exist (short meeting), just use in-memory segments

### 4d. Remove deprecated synchronize()

**File:** `SimpleRecordingEngine.swift` (line 617)

Delete `defaults.synchronize()` — it's been a no-op since macOS 10.14.

---

## Section 5: Thread Safety & Housekeeping

### 5a. AudioStreamOutput converter thread safety

**File:** `AudioCapturer.swift` (lines 296-297)

**Problem:** `cachedConverter` and `cachedSourceFormat` accessed from SCStream callback queue without synchronization.

**Fix:** Protect with `NSLock`, same pattern as `SegmentAligner`.

### 5b. Speaker ID type consistency — String everywhere

**Problem:** `DiarizationManager` uses `String` IDs, `IdentifiedParticipant.speakerID` is `Int`, bridged by regex. With dual-stream prefixed IDs (`"mic_1"`, `"sys_1"`), `Int` can't represent them.

**Changes:**
- `IdentifiedParticipant.speakerID`: `Int` → `String`
- `SerializableParticipant.speakerID`: `Int` → `String`
- `LiveMeeting.syncParticipants(withSpeakerIDs:)`: `Set<Int>` → `Set<String>`
- All call sites in `SimpleRecordingEngine` that call `parseNumericId()` for participant lookup switch to direct string comparison
- `SegmentAligner.parseNumericId()` retained only for display formatting

### 5c. Core Data migration for ConversationParticipant

The `speakerID` attribute in `ConversationParticipant` (Core Data) is `Int32`. Add a new model version with `speakerID` as `String`. Use lightweight migration — existing int values convert to strings automatically.

---

## Implementation Order

Build sequence follows the bottom-up approach, where each phase builds on the previous:

| Phase | Section | What | Files |
|-------|---------|------|-------|
| 1 | 1a | Fix downsampling | DiarizationManager.swift |
| 2 | 1b | Dynamic embedding dims | VoicePrintManager.swift |
| 3 | 2a | Backfill cursor | SimpleRecordingEngine.swift |
| 4 | 2b | Aligner history cap | SegmentAligner.swift |
| 5 | 2c | Async Core Data | VoicePrintManager.swift |
| 6 | 5b | String speaker IDs | IdentifiedParticipant, SerializableParticipant, LiveMeeting, SimpleRecordingEngine |
| 7 | 5c | Core Data migration | WhoNext.xcdatamodeld, ConversationParticipant.swift |
| 8 | 3a-d | Dual-stream diarization | SimpleRecordingEngine.swift, SegmentAligner.swift, DiarizationBuffer (reused) |
| 9 | 4a | compareSpeakers() | DiarizationManager.swift |
| 10 | 4b | User speaker marking | DiarizationManager.swift, SimpleRecordingEngine.swift |
| 11 | 4c | Disk flush | LiveMeeting.swift |
| 12 | 4d | Remove synchronize() | SimpleRecordingEngine.swift |
| 13 | 5a | Converter thread safety | AudioCapturer.swift |

**Note:** Phase 6 (String speaker IDs) is deliberately placed before Phase 8 (dual-stream diarization) because the prefixed IDs (`"mic_1"`, `"sys_1"`) require String-typed speaker IDs throughout.

## Testing Strategy

- After Phase 1-2: Verify audio quality improvement by comparing diarization accuracy on a test recording
- After Phase 3-5: Measure backfill time, memory usage, UI responsiveness during long recordings
- After Phase 6-7: Verify existing recordings still load correctly after Core Data migration
- After Phase 8: Test with a Zoom/Teams call — verify remote speakers get separate IDs
- After Phase 9-11: Verify user auto-identification, speaker comparison, and disk flush on 1hr+ recordings
- After Phase 13: Full regression — record with mic + system audio, verify no thread safety issues
