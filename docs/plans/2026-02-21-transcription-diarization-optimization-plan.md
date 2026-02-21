# Transcription & Diarization Optimization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix audio quality, performance, thread safety, and add dual-stream diarization so remote meeting participants get proper speaker attribution.

**Architecture:** Bottom-up — fix the audio quality and performance foundation first, then change speaker ID types to String, then add the second diarization pipeline for system audio, then implement missing features and housekeeping.

**Tech Stack:** Swift 6.2, SwiftUI, AVFoundation, ScreenCaptureKit, FluidAudio, Core Data, Xcode Beta (`/Applications/Xcode-beta.app`)

**Build command:** `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build`

**Test command:** `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' test`

**Design doc:** `docs/plans/2026-02-21-transcription-diarization-optimization-design.md`

---

## Task 1: Fix naive downsampling in DiarizationManager

**Files:**
- Modify: `WhoNext/DiarizationManager.swift` (lines 505-541, plus add property near line 172)

**Context:** `convertBufferToFloatArray()` uses stride-based decimation (picks every Nth sample) with no anti-aliasing. `AudioCapturer` already uses proper `AVAudioConverter` for the transcription path. We need to match that quality for diarization.

**Step 1: Add a lazy converter property**

Add near the other properties (after line 175):

```swift
/// Cached converter for proper anti-aliased resampling to 16kHz
private var resamplingConverter: AVAudioConverter?
private var resamplingSourceFormat: AVAudioFormat?
```

**Step 2: Replace convertBufferToFloatArray() implementation**

Replace lines 505-541 with:

```swift
/// Convert AVAudioPCMBuffer to Float array at 16kHz mono
/// Uses AVAudioConverter for proper anti-aliased resampling (not naive decimation)
private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
    guard let channelData = buffer.floatChannelData else { return nil }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let sourceSampleRate = buffer.format.sampleRate

    // Fast path: already at 16kHz — just downmix to mono
    if abs(sourceSampleRate - Double(sampleRate)) < 1.0 {
        var samples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            memcpy(&samples, channelData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            for frame in 0..<frameCount {
                var sample: Float = 0.0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                samples[frame] = sample / Float(channelCount)
            }
        }
        return samples
    }

    // Slow path: need resampling — use AVAudioConverter for proper anti-aliasing
    guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
        return nil
    }

    // Create mono source buffer first (downmix channels)
    guard let sourceMonoFormat = AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1) else {
        return nil
    }
    guard let sourceMonoBuffer = AVAudioPCMBuffer(pcmFormat: sourceMonoFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
        return nil
    }
    sourceMonoBuffer.frameLength = AVAudioFrameCount(frameCount)
    if let monoData = sourceMonoBuffer.floatChannelData {
        if channelCount == 1 {
            memcpy(monoData[0], channelData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            for frame in 0..<frameCount {
                var sample: Float = 0.0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                monoData[0][frame] = sample / Float(channelCount)
            }
        }
    }

    // Create or reuse converter
    if resamplingConverter == nil || resamplingSourceFormat?.sampleRate != sourceSampleRate {
        resamplingConverter = AVAudioConverter(from: sourceMonoFormat, to: targetFormat)
        resamplingSourceFormat = sourceMonoFormat
    }
    guard let converter = resamplingConverter else { return nil }

    // Convert with proper anti-aliasing
    let ratio = Double(sampleRate) / sourceSampleRate
    let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
        return nil
    }

    var error: NSError?
    let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return sourceMonoBuffer
    }

    guard status != .error, error == nil, let outputData = outputBuffer.floatChannelData else {
        print("⚠️ [DiarizationManager] Resampling failed: \(error?.localizedDescription ?? "unknown"), falling back to source")
        return nil
    }

    let outputCount = Int(outputBuffer.frameLength)
    var samples = [Float](repeating: 0, count: outputCount)
    memcpy(&samples, outputData[0], outputCount * MemoryLayout<Float>.size)
    return samples
}
```

**Step 3: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add WhoNext/DiarizationManager.swift
git commit -m "fix: Replace naive downsampling with AVAudioConverter in DiarizationManager

Uses proper anti-aliased resampling via AVAudioConverter instead of
stride-based decimation. Matches the quality of AudioCapturer's
transcription path. Fast path preserved for already-16kHz buffers."
```

---

## Task 2: Dynamic embedding dimension validation in VoicePrintManager

**Files:**
- Modify: `WhoNext/VoicePrintManager.swift` (lines 12, 36-39, 123-127)

**Step 1: Replace hard-coded dimension with dynamic lookup**

Replace line 12:
```swift
private let embeddingDimension = 256 // Standard dimension for speaker embeddings
```
With:
```swift
/// Embedding dimension — learned from the first embedding saved, defaults to 256
private var embeddingDimension: Int {
    UserDefaults.standard.integer(forKey: "VoicePrintEmbeddingDimension").nonZeroOrDefault(256)
}
```

Add this extension at the bottom of the file (before the closing of the file):
```swift
// MARK: - Int Helper

private extension Int {
    func nonZeroOrDefault(_ defaultValue: Int) -> Int {
        self != 0 ? self : defaultValue
    }
}
```

**Step 2: Update saveEmbedding to record dimension**

In `saveEmbedding()` (line 36), replace the guard:
```swift
guard embedding.count == embeddingDimension else {
    print("[VoicePrintManager] Invalid embedding dimension: \(embedding.count), expected \(embeddingDimension)")
    return
}
```
With:
```swift
// Record actual dimension on first save; warn on mismatch
let storedDim = embeddingDimension
if embedding.count != storedDim {
    if UserDefaults.standard.integer(forKey: "VoicePrintEmbeddingDimension") == 0 {
        // First embedding ever — record the dimension
        UserDefaults.standard.set(embedding.count, forKey: "VoicePrintEmbeddingDimension")
        print("[VoicePrintManager] 📐 Learned embedding dimension: \(embedding.count)")
    } else {
        print("[VoicePrintManager] ⚠️ Embedding dimension changed: \(embedding.count) vs stored \(storedDim). Updating.")
        UserDefaults.standard.set(embedding.count, forKey: "VoicePrintEmbeddingDimension")
        invalidateCache()
    }
}
```

**Step 3: Update findMatchingPerson to handle dimension mismatches gracefully**

In `findMatchingPerson()` (line 123), replace the guard:
```swift
guard embedding.count == embeddingDimension else {
    print("[VoicePrintManager] ❌ Invalid embedding dimension: \(embedding.count), expected \(embeddingDimension)")
    return nil
}
```
With:
```swift
guard !embedding.isEmpty else {
    print("[VoicePrintManager] ❌ Empty embedding")
    return nil
}
```

And in the comparison loop (inside `for (person, storedEmbedding) in cached`), add a dimension check before cosine similarity:
```swift
// Skip mismatched dimensions instead of crashing
guard embedding.count == storedEmbedding.count else {
    print("[VoicePrintManager] ⚠️ Dimension mismatch for \(person.wrappedName): \(embedding.count) vs \(storedEmbedding.count), skipping")
    continue
}
```

**Step 4: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add WhoNext/VoicePrintManager.swift
git commit -m "fix: Dynamic embedding dimension validation in VoicePrintManager

Learn actual dimension from first embedding save instead of hard-coding
256. Gracefully handle dimension mismatches by skipping comparisons
with a warning instead of silently returning 0.0 similarity."
```

---

## Task 3: Backfill cursor in SimpleRecordingEngine

**Files:**
- Modify: `WhoNext/SimpleRecordingEngine.swift` (add property, modify `backfillSpeakerLabels()`, modify `startRecording()`)

**Step 1: Add backfillCursor property**

Add near the other private state (after line 58):
```swift
/// Cursor tracking the first transcript segment that may still need speaker backfill.
/// Avoids re-scanning already-attributed segments on every diarization update.
private var backfillCursor: Int = 0
```

**Step 2: Update backfillSpeakerLabels() to use cursor**

Replace the `backfillSpeakerLabels()` method (lines 444-478) with:

```swift
/// Backfill speaker labels into transcript segments that arrived before diarization caught up.
/// Uses backfillCursor to skip already-attributed segments (O(new) instead of O(all)).
private func backfillSpeakerLabels() {
    guard let meeting = currentMeeting else { return }

    var backfilledCount = 0
    var newCursor = meeting.transcript.count // Assume all done unless we find a nil

    for i in backfillCursor..<meeting.transcript.count {
        let segment = meeting.transcript[i]
        guard segment.speakerID == nil else { continue }

        // Query the aligner for who was speaking at this segment's time
        if let speaker = segmentAligner.dominantSpeaker(for: segment.timestamp, duration: 5.0) {
            // Use user-assigned name if available
            let numericId = SegmentAligner.parseNumericId(speaker)
            let speakerName: String
            if let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == numericId }),
               let userName = participant.name, participant.namingMode == .namedByUser {
                speakerName = userName
            } else {
                speakerName = SegmentAligner.formatSpeakerName(speaker)
            }
            meeting.transcript[i] = TranscriptSegment(
                id: segment.id,
                text: segment.text,
                timestamp: segment.timestamp,
                speakerID: speaker,
                speakerName: speakerName,
                confidence: segment.confidence,
                isFinalized: segment.isFinalized
            )
            backfilledCount += 1
        } else {
            // First segment still nil — this is the new cursor position
            newCursor = min(newCursor, i)
        }
    }

    backfillCursor = newCursor

    if backfilledCount > 0 {
        print("[SimpleRecordingEngine] Backfilled speaker labels for \(backfilledCount) transcript segments (cursor at \(backfillCursor))")
    }
}
```

**Step 3: Reset cursor in startRecording()**

In `startRecording()`, after `detectedSpeakerCount = 0` (line 171), add:
```swift
backfillCursor = 0
```

**Step 4: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add WhoNext/SimpleRecordingEngine.swift
git commit -m "perf: Add backfill cursor to avoid O(n) scan on every diarization update

Track the first unattributed transcript segment index. Subsequent
backfill passes start from the cursor instead of index 0."
```

---

## Task 4: SegmentAligner history cap

**Files:**
- Modify: `WhoNext/SegmentAligner.swift`

**Step 1: Add caps to updateDiarizationResults()**

In `updateDiarizationResults()` (line 40-53), after `allSegments = result.segments`, add:

```swift
// Defensive cap matching DiarizationManager's 5000
if allSegments.count > 5000 {
    allSegments = Array(allSegments.suffix(5000))
    print("[SegmentAligner] ⚠️ Segment cap hit: trimmed to 5000")
}

// Cap known speakers (no real meeting has 100 speakers)
if knownSpeakers.count > 100 {
    // Keep only speakers present in current segments
    let activeIds = Set(allSegments.map { $0.speakerId })
    knownSpeakers = knownSpeakers.intersection(activeIds)
    print("[SegmentAligner] ⚠️ Speaker cap hit: pruned to \(knownSpeakers.count) active speakers")
}
```

**Step 2: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add WhoNext/SegmentAligner.swift
git commit -m "perf: Add history caps to SegmentAligner

Cap allSegments at 5000 (matching DiarizationManager) and
knownSpeakers at 100 to prevent unbounded memory growth."
```

---

## Task 5: VoicePrintManager async Core Data fetch

**Files:**
- Modify: `WhoNext/VoicePrintManager.swift` (lines 91-114, 123-177)
- Modify: `WhoNext/SimpleRecordingEngine.swift` (preWarm and updateParticipants)

**Step 1: Make refreshEmbeddingsCache() async**

Replace `refreshEmbeddingsCache()` (lines 91-114) with:

```swift
/// Refresh the embeddings cache from Core Data on a background context
private func refreshEmbeddingsCache() async {
    await withCheckedContinuation { continuation in
        persistenceController.container.performBackgroundTask { context in
            let request: NSFetchRequest<Person> = Person.fetchRequest()
            request.predicate = NSPredicate(format: "voiceEmbeddings != nil")

            do {
                let people = try context.fetch(request)
                var cached: [(personId: UUID, name: String, embedding: [Float], confidence: Float)] = []

                for person in people {
                    if let storedData = person.voiceEmbeddings,
                       let embedding = self.deserializeEmbedding(from: storedData),
                       let id = person.identifier {
                        cached.append((
                            personId: id,
                            name: person.wrappedName,
                            embedding: embedding,
                            confidence: person.voiceConfidence
                        ))
                    }
                }

                // Update cache on calling context (not main thread specific)
                self.cachedEmbeddingsData = cached
                self.cacheTimestamp = Date()
                print("[VoicePrintManager] 📦 Refreshed cache with \(cached.count) people (background)")
            } catch {
                print("[VoicePrintManager] ❌ Error refreshing cache: \(error)")
                self.cachedEmbeddingsData = nil
            }
            continuation.resume()
        }
    }
}
```

**Step 2: Update cache type and findMatchingPerson()**

Replace the cache property (line 17):
```swift
private var cachedPeopleEmbeddings: [(person: Person, embedding: [Float])]?
```
With:
```swift
/// Cache stores value types (not managed objects) so it's safe across contexts
private var cachedEmbeddingsData: [(personId: UUID, name: String, embedding: [Float], confidence: Float)]?
```

Update `findMatchingPerson()` to be async and use the new cache format. Replace the method:

```swift
/// Find matching person for a given embedding (uses caching to avoid repeated Core Data fetches)
func findMatchingPerson(for embedding: [Float]) async -> (Person?, Float)? {
    guard !embedding.isEmpty else {
        print("[VoicePrintManager] ❌ Empty embedding")
        return nil
    }

    // Check if cache needs refresh
    let now = Date()
    if cachedEmbeddingsData == nil || now.timeIntervalSince(cacheTimestamp) > cacheValidityInterval {
        await refreshEmbeddingsCache()
    }

    guard let cached = cachedEmbeddingsData, !cached.isEmpty else {
        print("[VoicePrintManager] ⚠️ No people with voice embeddings in database")
        return nil
    }

    print("[VoicePrintManager] 🔍 Searching \(cached.count) cached voice embeddings...")

    var bestMatch: (personId: UUID, name: String, similarity: Float)?

    for entry in cached {
        // Skip mismatched dimensions
        guard embedding.count == entry.embedding.count else {
            print("[VoicePrintManager] ⚠️ Dimension mismatch for \(entry.name): \(embedding.count) vs \(entry.embedding.count), skipping")
            continue
        }

        let similarity = cosineSimilarity(embedding, entry.embedding)
        let weightedSimilarity = similarity * entry.confidence

        if weightedSimilarity > minimumConfidenceThreshold {
            if bestMatch == nil || weightedSimilarity > bestMatch!.similarity {
                bestMatch = (personId: entry.personId, name: entry.name, similarity: weightedSimilarity)
            }
        }
    }

    if let match = bestMatch {
        lastMatchConfidence = match.similarity
        print("[VoicePrintManager] ✅ Best match: \(match.name) with confidence \(String(format: "%.1f%%", match.similarity * 100))")

        // Fetch the actual Person on the view context for the caller
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<Person> = Person.fetchRequest()
        request.predicate = NSPredicate(format: "identifier == %@", match.personId as CVarArg)
        let person = try? context.fetch(request).first
        return (person, match.similarity)
    }

    print("[VoicePrintManager] ❌ No match above \(String(format: "%.0f%%", minimumConfidenceThreshold * 100)) threshold")
    return nil
}
```

**Step 3: Update callers in SimpleRecordingEngine**

In `updateParticipants()` (line 519), the call to `voicePrintManager.findMatchingPerson()` needs `await`:

```swift
if let embedding = result.speakerDatabase?[speakerId] {
    if let match = await voicePrintManager.findMatchingPerson(for: embedding),
```

**Step 4: Add cache pre-warming to preWarm()**

In `preWarm()` (after line 108), add:
```swift
#if canImport(FluidAudio)
// Pre-warm voice print cache
await voicePrintManager.warmCache()
#endif
```

Add to VoicePrintManager:
```swift
/// Pre-warm the cache so first diarization chunk doesn't block
func warmCache() async {
    await refreshEmbeddingsCache()
}
```

**Step 5: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add WhoNext/VoicePrintManager.swift WhoNext/SimpleRecordingEngine.swift
git commit -m "perf: Move VoicePrintManager Core Data fetch to background context

Cache stores value types instead of managed objects for thread safety.
findMatchingPerson() is now async. Cache is pre-warmed during engine
preWarm() to avoid blocking the first diarization chunk."
```

---

## Task 6: String speaker IDs everywhere

**Files:**
- Modify: `WhoNext/LiveMeeting.swift` — `IdentifiedParticipant.speakerID`, `SerializableParticipant.speakerID`, `syncParticipants()`
- Modify: `WhoNext/SimpleRecordingEngine.swift` — all `parseNumericId()` calls for identity matching

**Context:** Currently `IdentifiedParticipant.speakerID` is `Int` while `DiarizationManager` uses `String` IDs. With dual-stream diarization adding prefixed IDs like `"mic_1"` and `"sys_1"`, we need `String` throughout.

**Step 1: Change IdentifiedParticipant.speakerID to String**

In `LiveMeeting.swift`, change line 409:
```swift
@Published var speakerID: Int = 0
```
To:
```swift
@Published var speakerID: String = ""
```

**Step 2: Change SerializableParticipant.speakerID to String**

In `LiveMeeting.swift`, change line 350:
```swift
let speakerID: Int
```
To:
```swift
let speakerID: String
```

**Step 3: Update syncParticipants()**

In `LiveMeeting.swift`, change `syncParticipants` (line 286):
```swift
func syncParticipants(withSpeakerIDs validSpeakerIDs: Set<Int>) {
```
To:
```swift
func syncParticipants(withSpeakerIDs validSpeakerIDs: Set<String>) {
```

**Step 4: Update displayName fallback in IdentifiedParticipant**

Change the `displayName` computed property (line 424):
```swift
return SegmentAligner.formatSpeakerName("\(speakerID)")
```
To:
```swift
return SegmentAligner.formatSpeakerName(speakerID)
```

**Step 5: Update SimpleRecordingEngine to use String comparisons**

In `updateParticipants()` (line 503), change:
```swift
let numericId = SegmentAligner.parseNumericId(speakerId)
if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == numericId }) {
```
To:
```swift
if let existingParticipant = meeting.identifiedParticipants.first(where: { $0.speakerID == speakerId }) {
```

And where the new participant is created (line 512):
```swift
participant.speakerID = numericId
```
To:
```swift
participant.speakerID = speakerId
```

In `processDiarizationChunk()` (line 430), change:
```swift
let validSpeakerIDs = Set(result.segments.map { SegmentAligner.parseNumericId($0.speakerId) })
```
To:
```swift
let validSpeakerIDs = Set(result.segments.map { $0.speakerId })
```

In `backfillSpeakerLabels()`, update the participant lookup:
```swift
let numericId = SegmentAligner.parseNumericId(speaker)
...
if let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == numericId }),
```
To:
```swift
if let participant = meeting.identifiedParticipants.first(where: { $0.speakerID == speaker }),
```
(Remove the `numericId` line.)

In `transcribeChunk()`, similarly update:
```swift
let numericId = SegmentAligner.parseNumericId(speaker)
if let participant = currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == numericId }),
```
To:
```swift
if let participant = currentMeeting?.identifiedParticipants.first(where: { $0.speakerID == speaker }),
```

In `saveToUserDefaults()` (line 594), change:
```swift
let speakerIdString = "\(participant.speakerID)"
let embedding = speakerEmbeddings[speakerIdString]
```
To:
```swift
let embedding = speakerEmbeddings[participant.speakerID]
```

**Step 6: Update SerializableParticipant.serialize with embeddings**

In `LiveMeeting.swift`, the `serialize(_:withEmbeddingsFrom:)` method (line 382) takes `[Int: [Float]]`. Change to `[String: [Float]]`:
```swift
static func serialize(_ participants: [IdentifiedParticipant], withEmbeddingsFrom speakerDatabase: [String: [Float]]) -> Data? {
```

**Step 7: Build and fix any remaining compile errors**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | grep 'error:' | head -20`

Fix any additional type mismatches that surface. The compiler will find them all.

**Step 8: Commit**

```bash
git add WhoNext/LiveMeeting.swift WhoNext/SimpleRecordingEngine.swift
git commit -m "refactor: Change speaker IDs from Int to String throughout

Prepares for dual-stream diarization where speaker IDs will be prefixed
('mic_1', 'sys_1'). Removes lossy parseNumericId() calls for identity
matching — now uses direct String comparison."
```

---

## Task 7: Dual-stream diarization — SegmentAligner

**Files:**
- Modify: `WhoNext/SegmentAligner.swift`

**Context:** The SegmentAligner needs to support two streams of diarization results (mic and system) with prefixed speaker IDs.

**Step 1: Replace single segment array with dual arrays**

Replace the properties section (lines 12-24):

```swift
#if canImport(FluidAudio)
/// Mic diarization segments (local speakers)
private var micSegments: [TimedSpeakerSegment] = []

/// System audio diarization segments (remote speakers)
private var systemSegments: [TimedSpeakerSegment] = []

/// All segments merged (computed from both arrays)
private var allSegments: [TimedSpeakerSegment] {
    (micSegments + systemSegments).sorted { $0.startTimeSeconds < $1.startTimeSeconds }
}

/// Speaker stabilizer to prevent rapid label switching
private let stabilizer = SpeakerStabilizer()

/// Track unique speakers seen
private var knownSpeakers: Set<String> = []

/// Track last returned speaker for stabilizer continuity
private var lastReturnedSpeaker: String?
#endif
```

**Step 2: Update updateDiarizationResults to prefix mic IDs**

Replace `updateDiarizationResults()` (lines 40-53):

```swift
/// Update with new mic diarization results (local speakers)
func updateDiarizationResults(_ result: DiarizationResult) {
    lock.lock()
    defer { lock.unlock() }

    // Prefix mic speaker IDs to avoid collision with system speaker IDs
    micSegments = result.segments.map { segment in
        TimedSpeakerSegment(
            speakerId: "mic_\(segment.speakerId)",
            embedding: segment.embedding,
            startTimeSeconds: segment.startTimeSeconds,
            endTimeSeconds: segment.endTimeSeconds,
            qualityScore: segment.qualityScore
        )
    }

    // Defensive cap
    if micSegments.count > 5000 {
        micSegments = Array(micSegments.suffix(5000))
        print("[SegmentAligner] ⚠️ Mic segment cap hit: trimmed to 5000")
    }

    updateKnownSpeakers()
    print("[SegmentAligner] Updated mic segments: \(micSegments.count), \(knownSpeakers.count) total speakers")
}
```

**Step 3: Add updateSystemDiarizationResults**

```swift
/// Update with new system audio diarization results (remote speakers)
func updateSystemDiarizationResults(_ result: DiarizationResult) {
    lock.lock()
    defer { lock.unlock() }

    // Prefix system speaker IDs
    systemSegments = result.segments.map { segment in
        TimedSpeakerSegment(
            speakerId: "sys_\(segment.speakerId)",
            embedding: segment.embedding,
            startTimeSeconds: segment.startTimeSeconds,
            endTimeSeconds: segment.endTimeSeconds,
            qualityScore: segment.qualityScore
        )
    }

    if systemSegments.count > 5000 {
        systemSegments = Array(systemSegments.suffix(5000))
        print("[SegmentAligner] ⚠️ System segment cap hit: trimmed to 5000")
    }

    updateKnownSpeakers()
    print("[SegmentAligner] Updated system segments: \(systemSegments.count), \(knownSpeakers.count) total speakers")
}

/// Rebuild known speakers from both arrays
private func updateKnownSpeakers() {
    for segment in micSegments { knownSpeakers.insert(segment.speakerId) }
    for segment in systemSegments { knownSpeakers.insert(segment.speakerId) }

    // Cap known speakers
    if knownSpeakers.count > 100 {
        let activeIds = Set(allSegments.map { $0.speakerId })
        knownSpeakers = knownSpeakers.intersection(activeIds)
    }
}
```

**Step 4: Update dominantSpeaker() to use merged allSegments**

The existing `dominantSpeaker()` already uses `allSegments` via `DiarizationResult(segments: allSegments, ...)`. Since `allSegments` is now a computed property merging both arrays, this works automatically. No change needed.

**Step 5: Update reset()**

In `reset()`, replace:
```swift
allSegments.removeAll()
```
With:
```swift
micSegments.removeAll()
systemSegments.removeAll()
```

**Step 6: Update formatSpeakerName() to handle prefixed IDs**

Replace `formatSpeakerName()` (line 159):

```swift
/// Format speaker ID for display
/// Handles prefixed IDs: "mic_1" -> "Speaker 1", "sys_2" -> "Speaker 2 (Remote)"
static func formatSpeakerName(_ speakerId: String) -> String {
    if speakerId.hasPrefix("mic_") {
        let num = String(speakerId.dropFirst(4))
        return "Speaker \(num)"
    } else if speakerId.hasPrefix("sys_") {
        let num = String(speakerId.dropFirst(4))
        return "Speaker \(num) (Remote)"
    } else if let num = Int(speakerId) {
        return "Speaker \(num)"
    }
    // Legacy format
    let numericId = parseNumericId(speakerId)
    return "Speaker \(numericId + 1)"
}
```

**Step 7: Build and verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add WhoNext/SegmentAligner.swift
git commit -m "feat: Dual-stream diarization support in SegmentAligner

Maintain separate mic and system segment arrays with prefixed speaker
IDs (mic_1, sys_1). Merged via computed property for dominant speaker
queries. formatSpeakerName() shows '(Remote)' for system speakers."
```

---

## Task 8: Dual-stream diarization — SimpleRecordingEngine

**Files:**
- Modify: `WhoNext/SimpleRecordingEngine.swift`

**Step 1: Add system diarization components**

After line 48, add:
```swift
private let systemDiarizationManager = DiarizationManager(enableRealTimeProcessing: true)
private let systemDiarizationBuffer = DiarizationBuffer()
```

**Step 2: Initialize system diarization in preWarm() and startRecording()**

In `preWarm()` (after line 108), add:
```swift
try await systemDiarizationManager.initialize()
print("[SimpleRecordingEngine] Pre-warmed system diarization manager")
```

In `startRecording()` (after line 167), add:
```swift
do {
    try await systemDiarizationManager.initialize()
    print("[SimpleRecordingEngine] System diarization manager initialized")
} catch {
    print("[SimpleRecordingEngine] System diarization initialization failed: \(error)")
}
await systemDiarizationBuffer.reset()
systemDiarizationManager.reset()
```

**Step 3: Update processAudioStreams() system stream task**

Replace the system stream task (lines 289-299):

```swift
// System stream processor (for transcription AND diarization)
group.addTask {
    for await audioBuffer in systemStream {
        guard !Task.isCancelled else { break }

        // Add to chunk buffer for transcription
        if let chunk = await buffer.addBuffer(audioBuffer, isMic: false) {
            await self.transcribeChunk(chunk)
        }

        #if canImport(FluidAudio)
        // Also feed to system diarization buffer
        let elapsed = await MainActor.run { self.recordingDuration }
        if let (diarChunk, startTime) = await systemDiarBuffer.addBuffer(audioBuffer, recordingElapsed: elapsed) {
            await self.processSystemDiarizationChunk(diarChunk, startTime: startTime)
        }
        #endif
    }
}
```

Also capture `systemDiarBuffer` at the top of the method (after line 264):
```swift
let systemDiarBuffer = systemDiarizationBuffer
```

**Step 4: Add processSystemDiarizationChunk()**

Add after `processDiarizationChunk()`:

```swift
/// Process a system audio diarization chunk (remote speakers)
private func processSystemDiarizationChunk(_ chunk: [Float], startTime: TimeInterval) async {
    print("[SimpleRecordingEngine] Processing system diarization chunk: \(chunk.count) samples at \(String(format: "%.1f", startTime))s")

    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else {
        print("[SimpleRecordingEngine] Failed to create audio buffer for system diarization")
        return
    }

    buffer.frameLength = AVAudioFrameCount(chunk.count)
    if let channelData = buffer.floatChannelData {
        for i in 0..<chunk.count {
            channelData[0][i] = chunk[i]
        }
    }

    await systemDiarizationManager.processAudioBuffer(buffer)

    if let error = systemDiarizationManager.lastError {
        print("[SimpleRecordingEngine] System diarization error: \(error.localizedDescription)")
    }

    if let result = systemDiarizationManager.lastResult {
        print("[SimpleRecordingEngine] System diarization result: \(result.segments.count) segments, \(result.speakerCount) speakers")
        segmentAligner.updateSystemDiarizationResults(result)

        // Update total speaker count from both managers
        let totalSpeakers = diarizationManager.totalSpeakerCount + systemDiarizationManager.totalSpeakerCount
        if totalSpeakers != detectedSpeakerCount {
            print("[SimpleRecordingEngine] Total speaker count changed: \(detectedSpeakerCount) -> \(totalSpeakers)")
        }
        detectedSpeakerCount = totalSpeakers
        updateMeetingType(speakerCount: totalSpeakers)

        // Update participants from system diarization (remote speakers)
        updateParticipants(from: result)

        // Sync and backfill
        let micIds = Set((diarizationManager.lastResult?.segments ?? []).map { "mic_\($0.speakerId)" })
        let sysIds = Set(result.segments.map { "sys_\($0.speakerId)" })
        let validSpeakerIDs = micIds.union(sysIds)
        currentMeeting?.syncParticipants(withSpeakerIDs: validSpeakerIDs)
        backfillSpeakerLabels()
    }
}
```

**Step 5: Update stopRecording() to flush system diarization**

After line 239, add:
```swift
if let (finalSysDiarChunk, startTime) = await systemDiarizationBuffer.flush() {
    await processSystemDiarizationChunk(finalSysDiarChunk, startTime: startTime)
}
_ = await systemDiarizationManager.finishProcessing()
```

**Step 6: Update processDiarizationChunk() to use prefixed IDs for sync**

In `processDiarizationChunk()`, update the syncParticipants call (line 430):
```swift
let validSpeakerIDs = Set(result.segments.map { SegmentAligner.parseNumericId($0.speakerId) })
```
To:
```swift
let micIds = Set(result.segments.map { "mic_\($0.speakerId)" })
let sysIds = Set((systemDiarizationManager.lastResult?.segments ?? []).map { "sys_\($0.speakerId)" })
let validSpeakerIDs = micIds.union(sysIds)
```

**Step 7: Update saveToUserDefaults() to include both managers' embeddings**

In `saveToUserDefaults()`, after the mic embeddings loop (line 588), add system embeddings:
```swift
if let sysResult = systemDiarizationManager.lastResult {
    for segment in sysResult.segments {
        let prefixedId = "sys_\(segment.speakerId)"
        if speakerEmbeddings[prefixedId] == nil {
            speakerEmbeddings[prefixedId] = segment.embedding
        }
    }
}
```

And prefix mic embeddings too:
```swift
if let result = diarizationManager.lastResult {
    for segment in result.segments {
        let prefixedId = "mic_\(segment.speakerId)"
        if speakerEmbeddings[prefixedId] == nil {
            speakerEmbeddings[prefixedId] = segment.embedding
        }
    }
}
```

**Step 8: Build, fix compile errors, verify**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | grep 'error:' | head -20`

Fix any remaining issues the compiler finds.

**Step 9: Commit**

```bash
git add WhoNext/SimpleRecordingEngine.swift
git commit -m "feat: Add system audio diarization for remote meeting participants

Second DiarizationManager instance processes ScreenCaptureKit audio
separately from mic. Remote speakers get 'sys_' prefixed IDs, local
speakers get 'mic_' prefixed IDs. Both feed into SegmentAligner for
unified speaker attribution. Gracefully degrades to mic-only when
screen recording permission is denied."
```

---

## Task 9: Implement compareSpeakers()

**Files:**
- Modify: `WhoNext/DiarizationManager.swift` (lines 492-500)

**Step 1: Replace placeholder with real implementation**

Replace `compareSpeakers()`:

```swift
/// Compare two audio segments to determine if they're the same speaker
/// Processes each through FluidAudio to extract embeddings, then computes cosine similarity
func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
    guard let diarizer = fluidDiarizer else {
        throw DiarizationError.notInitialized
    }

    // Both samples need minimum length for reliable embeddings
    let minSamples = Int(sampleRate * 3.0)
    guard audio1.count >= minSamples, audio2.count >= minSamples else {
        throw DiarizationError.insufficientAudio
    }

    // Extract embeddings via FluidAudio
    let result1 = try diarizer.performCompleteDiarization(audio1)
    let result2 = try diarizer.performCompleteDiarization(audio2)

    // Get the dominant speaker embedding from each
    guard let emb1 = result1.speakerDatabase?.values.first,
          let emb2 = result2.speakerDatabase?.values.first else {
        throw DiarizationError.processingFailed("Could not extract speaker embeddings")
    }

    return SpeakerCache.cosineSimilarity(emb1, emb2)
}
```

**Step 2: Build and verify**

Run build command. Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add WhoNext/DiarizationManager.swift
git commit -m "feat: Implement compareSpeakers() using FluidAudio embeddings

Replaces hardcoded 0.5 placeholder. Processes both audio samples
through FluidAudio to extract speaker embeddings, then computes
cosine similarity for a real comparison score."
```

---

## Task 10: User speaker marking

**Files:**
- Modify: `WhoNext/DiarizationManager.swift`
- Modify: `WhoNext/SimpleRecordingEngine.swift`

**Step 1: Add userSpeakerId property to DiarizationManager**

After line 190, add:
```swift
@Published private(set) var userSpeakerId: String?
```

**Step 2: Update identifyUserSpeaker() to set the property**

Replace the TODO block (lines 481-486) with:
```swift
if matches {
    print("🎤 [DiarizationManager] ✅ IDENTIFIED USER SPEAKING!")
    print("   Speaker ID: \(segment.speakerId)")
    print("   Confidence: \(String(format: "%.1f%%", confidence * 100))")

    // Set the user's speaker ID for downstream use
    if userSpeakerId == nil || confidence > 0.9 {
        userSpeakerId = segment.speakerId
    }
}
```

**Step 3: Reset userSpeakerId in reset()**

In `reset()`, add:
```swift
userSpeakerId = nil
```

**Step 4: Use userSpeakerId in SimpleRecordingEngine.updateParticipants()**

In `updateParticipants()`, after creating a new participant and before appending it, add:
```swift
// Auto-identify the current user via voice profile
if let micUserSpeaker = diarizationManager.userSpeakerId,
   speakerId == micUserSpeaker || speakerId == "mic_\(micUserSpeaker)" {
    participant.isCurrentUser = true
    participant.name = UserProfile.shared.name
    participant.namingMode = .linkedToPerson
    print("[SimpleRecordingEngine] 🎤 Auto-identified current user as \(speakerId)")
}
```

**Step 5: Build and verify**

Run build command. Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add WhoNext/DiarizationManager.swift WhoNext/SimpleRecordingEngine.swift
git commit -m "feat: Auto-mark current user speaker from voice profile

DiarizationManager.userSpeakerId is set when voice profile matches.
SimpleRecordingEngine uses it to auto-set isCurrentUser and name
on the corresponding IdentifiedParticipant."
```

---

## Task 11: Disk flush for long meetings

**Files:**
- Modify: `WhoNext/LiveMeeting.swift` (lines 211-233, 236-245)

**Step 1: Add file path property and flush-to-disk logic**

Replace the memory management section (lines 211-245):

```swift
// MARK: - Memory Management

private var flushedSegmentCount: Int = 0
private var flushFilePath: URL?
private let maxSegmentsInMemory = 100

/// Get or create the flush file path for this meeting
private func getFlushFilePath() -> URL {
    if let path = flushFilePath { return path }
    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let path = cacheDir.appendingPathComponent("meeting_\(id.uuidString)_segments.json")
    flushFilePath = path
    return path
}

/// Flush old transcript segments to disk to reduce memory usage during long meetings
func flushOldSegments() {
    guard transcript.count > maxSegmentsInMemory else { return }

    let segmentsToFlush = transcript.count - maxSegmentsInMemory
    let oldSegments = Array(transcript.prefix(segmentsToFlush))

    // Write to disk
    let filePath = getFlushFilePath()
    do {
        var existing: [TranscriptSegment] = []
        if FileManager.default.fileExists(atPath: filePath.path) {
            let data = try Data(contentsOf: filePath)
            existing = (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
        }
        existing.append(contentsOf: oldSegments)
        let data = try JSONEncoder().encode(existing)
        try data.write(to: filePath, options: .atomic)
        flushedSegmentCount = existing.count
    } catch {
        print("⚠️ [LiveMeeting] Failed to flush segments to disk: \(error)")
        return // Don't remove from memory if disk write failed
    }

    // Keep only recent segments in memory
    transcript = Array(transcript.suffix(maxSegmentsInMemory))
    print("💾 [LiveMeeting] Flushed \(segmentsToFlush) segments to disk (\(flushedSegmentCount) total on disk), keeping \(transcript.count) in memory")
}

/// Get full transcript including flushed segments from disk
func getFullTranscriptText() -> String {
    var allSegments: [TranscriptSegment] = []

    // Read flushed segments from disk
    if let filePath = flushFilePath,
       FileManager.default.fileExists(atPath: filePath.path) {
        do {
            let data = try Data(contentsOf: filePath)
            let flushed = try JSONDecoder().decode([TranscriptSegment].self, from: data)
            allSegments.append(contentsOf: flushed)
        } catch {
            print("⚠️ [LiveMeeting] Failed to read flushed segments: \(error)")
        }
    }

    allSegments.append(contentsOf: transcript)

    return allSegments.map { segment in
        if let speaker = segment.speakerName {
            return "\(speaker): \(segment.text)"
        } else {
            return segment.text
        }
    }.joined(separator: "\n")
}

/// Clean up flush file after meeting is finalized
func cleanupFlushFile() {
    guard let filePath = flushFilePath else { return }
    try? FileManager.default.removeItem(at: filePath)
    flushFilePath = nil
    flushedSegmentCount = 0
}
```

**Step 2: Call cleanupFlushFile in SimpleRecordingEngine.finalizeMeeting()**

In `SimpleRecordingEngine.finalizeMeeting()`, after `saveToUserDefaults(meeting)`, add:
```swift
meeting.cleanupFlushFile()
```

**Step 3: Build and verify**

Run build command. Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add WhoNext/LiveMeeting.swift WhoNext/SimpleRecordingEngine.swift
git commit -m "feat: Flush transcript segments to disk for long meetings

Segments beyond 100 in-memory are JSON-encoded to a temp file in
caches directory. getFullTranscriptText() reads from disk + memory.
Temp file cleaned up after meeting finalization."
```

---

## Task 12: Remove deprecated synchronize() and add converter thread safety

**Files:**
- Modify: `WhoNext/SimpleRecordingEngine.swift` (line 617)
- Modify: `WhoNext/AudioCapturer.swift` (AudioStreamOutput class)

**Step 1: Remove defaults.synchronize()**

In `SimpleRecordingEngine.swift`, delete line 617:
```swift
defaults.synchronize()
```

**Step 2: Add NSLock to AudioStreamOutput**

In `AudioCapturer.swift`, in the `AudioStreamOutput` class (around line 291), add a lock property:
```swift
private let converterLock = NSLock()
```

Then wrap the converter access in `convertToPCMBuffer()` (around line 446):

Replace:
```swift
if cachedConverter == nil || cachedSourceFormat?.sampleRate != sourceSampleRate {
    cachedConverter = AVAudioConverter(from: sourceMonoFormat, to: targetFormat)
    cachedSourceFormat = sourceMonoFormat
}

guard let converter = cachedConverter else {
```

With:
```swift
converterLock.lock()
if cachedConverter == nil || cachedSourceFormat?.sampleRate != sourceSampleRate {
    cachedConverter = AVAudioConverter(from: sourceMonoFormat, to: targetFormat)
    cachedSourceFormat = sourceMonoFormat
}
let converter = cachedConverter
converterLock.unlock()

guard let converter else {
```

**Step 3: Build and verify**

Run build command. Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add WhoNext/SimpleRecordingEngine.swift WhoNext/AudioCapturer.swift
git commit -m "fix: Remove deprecated synchronize(), add converter thread safety

Delete no-op UserDefaults.synchronize() call. Protect
AudioStreamOutput's cached converter with NSLock to prevent
races on the SCStream callback queue."
```

---

## Task 13: Final build verification and push

**Step 1: Full build**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Run tests**

Run: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project WhoNext.xcodeproj -scheme WhoNext -destination 'platform=macOS' test 2>&1 | tail -10`
Expected: Tests pass (or at minimum, no new failures)

**Step 3: Push all commits**

```bash
git push origin main
```

**Step 4: Verify commit history**

```bash
git log --oneline -15
```

Expected: 12 new commits on top of the backup commit, each focused on one concern.
