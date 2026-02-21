import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Arrival-order speaker cache inspired by NVIDIA Streaming Sortformer's AOSC.
/// Maintains stable speaker IDs by matching new embeddings against a persistent,
/// quality-weighted cache rather than comparing consecutive diarization runs.
private struct SpeakerCache {
    struct CachedEmbedding {
        let embedding: [Float]
        let quality: Float
        let timestamp: Float
    }

    struct CachedSpeaker {
        let stableId: String           // "1", "2", "3" — arrival order
        let arrivalTime: Float
        var embeddings: [CachedEmbedding]

        /// Quality-weighted centroid embedding
        var centroid: [Float] {
            guard !embeddings.isEmpty else { return [] }
            let dim = embeddings[0].embedding.count
            var result = [Float](repeating: 0, count: dim)
            var totalWeight: Float = 0
            for cached in embeddings {
                totalWeight += cached.quality
                for i in 0..<dim {
                    result[i] += cached.embedding[i] * cached.quality
                }
            }
            guard totalWeight > 0 else { return result }
            for i in 0..<dim { result[i] /= totalWeight }
            return result
        }

        /// Add embedding and prune cache to keep best recent entries
        mutating func addEmbedding(_ embedding: [Float], quality: Float, timestamp: Float, recencyBoost: Float = 0.05) {
            embeddings.append(CachedEmbedding(embedding: embedding, quality: quality, timestamp: timestamp))

            guard embeddings.count > maxCacheSize else { return }

            // Score by quality * recency, keep top maxCacheSize
            let now = embeddings.last?.timestamp ?? timestamp
            var scored = embeddings.map { emb -> (entry: CachedEmbedding, score: Float) in
                let recency = exp(-recencyBoost * (now - emb.timestamp))
                return (emb, emb.quality * recency)
            }
            scored.sort { $0.score > $1.score }
            embeddings = scored.prefix(maxCacheSize).map { $0.entry }
        }

        private let maxCacheSize = 20
    }

    private(set) var speakers: [CachedSpeaker] = []
    private var nextId: Int = 1
    let matchThreshold: Float = 0.75  // Slightly below FluidAudio's 0.78

    /// Match a speaker embedding against the cache.
    /// Returns the stable ID of the matched (or newly created) speaker.
    mutating func matchOrCreate(embedding: [Float], quality: Float, timestamp: Float) -> String {
        var bestMatch: (index: Int, similarity: Float)? = nil

        for (index, speaker) in speakers.enumerated() {
            let sim = Self.cosineSimilarity(embedding, speaker.centroid)
            if sim > matchThreshold, (bestMatch == nil || sim > bestMatch!.similarity) {
                bestMatch = (index, sim)
            }
        }

        if let match = bestMatch {
            speakers[match.index].addEmbedding(embedding, quality: quality, timestamp: timestamp)
            return speakers[match.index].stableId
        }

        // New speaker — assign next arrival-order ID
        let newId = String(nextId)
        nextId += 1
        speakers.append(CachedSpeaker(
            stableId: newId,
            arrivalTime: timestamp,
            embeddings: [CachedEmbedding(embedding: embedding, quality: quality, timestamp: timestamp)]
        ))
        print("🆕 [SpeakerCache] New speaker \(newId) at \(String(format: "%.1f", timestamp))s")
        return newId
    }

    /// Remap all segments from a FluidAudio result using the cache.
    /// Two FluidAudio IDs that match the same cache entry are automatically merged.
    mutating func remapSegments(
        _ segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?
    ) -> [TimedSpeakerSegment] {
        guard let db = speakerDatabase, !db.isEmpty else { return segments }

        // Build mapping: FluidAudio ID → stable cache ID
        var idMapping: [String: String] = [:]

        // Calculate average quality per FluidAudio speaker from segments
        var speakerQualities: [String: (total: Float, count: Int)] = [:]
        var speakerFirstTime: [String: Float] = [:]
        for seg in segments {
            speakerQualities[seg.speakerId, default: (0, 0)].total += seg.qualityScore
            speakerQualities[seg.speakerId, default: (0, 0)].count += 1
            if speakerFirstTime[seg.speakerId] == nil {
                speakerFirstTime[seg.speakerId] = seg.startTimeSeconds
            }
        }

        // Sort FluidAudio speakers by first appearance time for deterministic ordering
        let sortedSpeakers = db.keys.sorted { a, b in
            (speakerFirstTime[a] ?? 0) < (speakerFirstTime[b] ?? 0)
        }

        for fluidId in sortedSpeakers {
            guard let embedding = db[fluidId] else { continue }
            let avgQuality = speakerQualities[fluidId].map { $0.total / Float($0.count) } ?? 0.5
            let firstTime = speakerFirstTime[fluidId] ?? 0

            let stableId = matchOrCreate(embedding: embedding, quality: avgQuality, timestamp: firstTime)
            if stableId != fluidId {
                idMapping[fluidId] = stableId
            }
        }

        guard !idMapping.isEmpty else { return segments }

        print("🔄 [SpeakerCache] Remap: \(idMapping)")
        return segments.map { seg in
            guard let mapped = idMapping[seg.speakerId] else { return seg }
            return TimedSpeakerSegment(
                speakerId: mapped,
                embedding: seg.embedding,
                startTimeSeconds: seg.startTimeSeconds,
                endTimeSeconds: seg.endTimeSeconds,
                qualityScore: seg.qualityScore
            )
        }
    }

    mutating func reset() {
        speakers.removeAll()
        nextId = 1
    }

    var speakerCount: Int { speakers.count }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}

/// Manages speaker diarization using FluidAudio framework
/// Identifies "who spoke when" in audio recordings
#if canImport(FluidAudio)
@MainActor
class DiarizationManager: ObservableObject {
    
    // MARK: - Properties
    
    private var fluidDiarizer: DiarizerManager?
    private var isInitialized = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Float = 16000.0

    /// Cached converter for proper anti-aliased resampling to 16kHz
    private var resamplingConverter: AVAudioConverter?
    private var resamplingSourceFormat: AVAudioFormat?

    // Configuration
    private let config: DiarizerConfig
    @Published var isEnabled: Bool = true
    @Published var enableRealTimeProcessing: Bool = false
    
    // State
    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var processingProgress: Double = 0.0
    
    // Results
    @Published private(set) var lastResult: DiarizationResult?
    @Published private(set) var currentSpeakers: [String] = []
    @Published private(set) var totalSpeakerCount: Int = 0  // Track total unique speakers seen
    
    // Chunk management for streaming
    // Increased to 10 seconds for better speaker consistency across chunks
    private let chunkDuration: TimeInterval = 10.0
    private var streamPosition: TimeInterval = 0.0
    
    // Dynamic threshold adjustment
    private var adaptiveThreshold: Float = 0.75
    private var speakerDistances: [Float] = []
    
    // IMPORTANT: Maintain speaker continuity across chunks
    private var cumulativeAudioBuffer: [Float] = [] // Accumulate all audio
    private var speakerCache = SpeakerCache() // Arrival-order speaker cache
    private var allSegments: [TimedSpeakerSegment] = [] // All segments from all chunks
    private let maxCumulativeSeconds: Float = 120.0 // Keep last 120 seconds for better speaker continuity
    private var knownSpeakers: Set<String> = [] // Track all speakers we've seen
    private var bufferAbsoluteStartTime: TimeInterval = 0.0 // Tracks how much audio has been trimmed from the start

    // Post-processing configuration
    private let minSegmentDuration: Float = 0.5 // Merge segments shorter than this
    private let smoothingWindow: Float = 1.5 // Minimum turn duration for smoothing
    
    // MARK: - Initialization
    
    init(isEnabled: Bool = true, enableRealTimeProcessing: Bool = false, clusteringThreshold: Float = 0.78) {
        // Configure for optimal speaker separation in real-world desk microphone conditions:
        // - 0.78 = Conservative threshold for real-world audio (reduces phantom speakers)
        // - 0.70 = Optimal for clean benchmark audio (AMI dataset) but over-segments noisy audio
        // - 0.9+ = Under-clustering (speakers merge - BAD)
        // - 0.5- = Over-clustering (one person split into multiple - BAD)
        //
        // FluidAudio threshold semantics:
        // - Higher threshold = more lenient clustering (accepts higher speaker distances as "same")
        // - Lower threshold = stricter clustering (requires closer embeddings to merge)
        //
        // Industry reference: diart uses conservative new-speaker detection;
        // NeMo uses max_rp_threshold=0.25. Higher threshold = fewer phantom speakers.
        self.config = DiarizerConfig(
            clusteringThreshold: clusteringThreshold,  // Default 0.78 for real-world audio
            minSpeechDuration: 0.3,     // Capture shorter utterances (was 0.5)
            minSilenceGap: 0.2,         // Natural conversation flow (was 0.3)
            debugMode: true             // Enable to get speaker embeddings
        )
        self.isEnabled = isEnabled
        self.enableRealTimeProcessing = enableRealTimeProcessing

        print("🎙️ [DiarizationManager] Initialized:")
        print("   - Clustering threshold: \(clusteringThreshold) (default: 0.78)")
        print("   - Min speech duration: 0.3s")
        print("   - Min silence gap: 0.2s")
        print("   - Real-time processing: \(enableRealTimeProcessing)")
        if clusteringThreshold > 0.80 {
            print("   ⚠️ WARNING: Threshold > 0.80 may cause under-clustering (speakers merging)")
        } else if clusteringThreshold < 0.60 {
            print("   ⚠️ WARNING: Threshold < 0.60 may cause over-clustering (one person split)")
        }
    }
    
    // MARK: - Configuration
    
    /// Get the current clustering threshold
    var currentThreshold: Float {
        return config.clusteringThreshold
    }
    
    /// Create a new DiarizationManager with custom threshold
    static func withThreshold(_ threshold: Float, enableRealTimeProcessing: Bool = false) -> DiarizationManager {
        let manager = DiarizationManager(isEnabled: true, enableRealTimeProcessing: enableRealTimeProcessing)
        // We'll set the threshold through a custom init
        return manager
    }
    
    // MARK: - Setup
    
    /// Initialize the diarizer and download models if needed
    func initialize() async throws {
        print("🔄 [DiarizationManager] Initializing FluidAudio diarizer...")
        
        guard isEnabled else {
            print("⚠️ [DiarizationManager] Diarization is disabled")
            return
        }
        
        do {
            // Download models if needed (one-time setup)
            let models = try await DiarizerModels.downloadIfNeeded()
            print("✅ [DiarizationManager] Models downloaded/verified")
            
            // Create FluidAudio diarizer with our config
            fluidDiarizer = DiarizerManager(config: config)
            fluidDiarizer?.initialize(models: models)
            
            isInitialized = true
            print("✅ [DiarizationManager] FluidAudio diarizer initialized successfully")
        } catch {
            print("❌ [DiarizationManager] Failed to initialize: \(error)")
            lastError = error
            throw DiarizationError.initializationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process an audio buffer for diarization
    /// - Parameter buffer: Audio buffer from recording (will be converted to 16kHz mono)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isEnabled, isInitialized else { return }
        
        // Convert audio buffer to Float array at 16kHz
        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            print("⚠️ [DiarizationManager] Failed to convert audio buffer")
            return
        }
        
        // Accumulate audio for batch processing
        audioBuffer.append(contentsOf: floatSamples)
        
        // Check if we have enough audio for a chunk (10 seconds)
        let chunkSamples = Int(sampleRate * Float(chunkDuration))
        
        // Process complete chunks
        while audioBuffer.count >= chunkSamples {
            let chunk = Array(audioBuffer.prefix(chunkSamples))
            audioBuffer = Array(audioBuffer.dropFirst(chunkSamples))
            
            // Process in real-time if enabled
            if enableRealTimeProcessing {
                await processChunk(chunk, at: streamPosition)
                streamPosition += chunkDuration
            }
        }
    }
    
    /// Process a single chunk of audio
    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let diarizer = fluidDiarizer else { return }
        
        do {
            let startTime = Date()
            
            // CRITICAL FIX: Accumulate audio and process cumulatively
            // This maintains speaker continuity across chunks
            cumulativeAudioBuffer.append(contentsOf: audioSamples)
            
            // Implement sliding window to limit memory usage
            // Use suffix() instead of removeFirst() to avoid O(n) array shifting
            let maxSamples = Int(maxCumulativeSeconds * sampleRate)
            if cumulativeAudioBuffer.count > maxSamples {
                let samplesDropped = cumulativeAudioBuffer.count - maxSamples
                bufferAbsoluteStartTime += Double(samplesDropped) / Double(sampleRate)
                cumulativeAudioBuffer = Array(cumulativeAudioBuffer.suffix(maxSamples))
                print("🔄 [DiarizationManager] Sliding window: trimmed \(samplesDropped) samples, bufferAbsoluteStartTime=\(String(format: "%.1f", bufferAbsoluteStartTime))s")
            }
            
            // Process the entire accumulated audio to maintain speaker continuity
            // This ensures speakers identified in earlier chunks are recognized in later chunks
            print("🔄 [DiarizationManager] Processing cumulative audio: \(cumulativeAudioBuffer.count) samples (\(Float(cumulativeAudioBuffer.count) / sampleRate)s)")
            
            let result = try diarizer.performCompleteDiarization(
                cumulativeAudioBuffer, atTime: bufferAbsoluteStartTime)
            let processingTime = Date().timeIntervalSince(startTime)

            // FluidAudio's atTime: parameter handles absolute timestamp conversion natively
            let absoluteSegments = result.segments

            // Diagnostic: validate absolute timestamps are in expected range
            if let lastSeg = absoluteSegments.last {
                let expectedMax = Float(bufferAbsoluteStartTime) + Float(cumulativeAudioBuffer.count) / sampleRate
                if lastSeg.endTimeSeconds > expectedMax + 1.0 {
                    print("⚠️ [DiarizationManager] Timestamp anomaly: segment end \(lastSeg.endTimeSeconds)s > expected max \(expectedMax)s")
                }
            }

            // Arrival-order speaker cache: matches FluidAudio's IDs against persistent
            // quality-weighted embeddings, producing stable IDs and auto-merging
            // speakers whose embeddings converge to the same cache entry.
            let remapped = speakerCache.remapSegments(absoluteSegments, speakerDatabase: result.speakerDatabase)

            // Extract segments that overlap with the current chunk time window
            let chunkStartTime = Float(position)
            let chunkEndTime = Float(position + chunkDuration)

            // Get segments that overlap with this chunk (not just ones that start in it)
            let chunkSegments = remapped.filter { segment in
                // Include segment if it overlaps with the chunk window at all
                segment.endTimeSeconds > chunkStartTime && segment.startTimeSeconds < chunkEndTime
            }

            let uniqueSpeakersInChunk = Set(chunkSegments.map { $0.speakerId })
            let totalUniqueSpeakers = Set(remapped.map { $0.speakerId })

            // Use the speaker cache as the source of truth for stable speaker IDs.
            knownSpeakers = Set(speakerCache.speakers.map { $0.stableId })
            totalSpeakerCount = speakerCache.speakerCount

            print("📊 [DiarizationManager] Processed \(chunkDuration)s chunk in \(String(format: "%.2f", processingTime))s")
            print("👥 [DiarizationManager] Found \(uniqueSpeakersInChunk.count) speakers in chunk, \(knownSpeakers.count) total speakers (historical)")
            print("📈 [DiarizationManager] Cumulative audio: \(String(format: "%.1f", Float(cumulativeAudioBuffer.count) / sampleRate))s, Known speakers: \(knownSpeakers), bufferAbsoluteStartTime: \(String(format: "%.1f", bufferAbsoluteStartTime))s")

            // Log speaker distances for adaptive threshold
            if totalUniqueSpeakers.count > 1 {
                print("📊 [DiarizationManager] Multiple speakers detected, tracking for optimization")
            }

            // Fix 2: Preserve historical segments from before the current buffer window
            let bufferWindowStart = Float(bufferAbsoluteStartTime)
            let newBufferSegments = postProcessSegments(remapped)

            // Keep historical segments from before the current buffer window
            let historicalSegments = allSegments.filter { $0.endTimeSeconds <= bufferWindowStart }
            allSegments = historicalSegments + newBufferSegments

            // Cap segment history to prevent unbounded growth in very long meetings
            if allSegments.count > 5000 {
                allSegments = Array(allSegments.suffix(4000))
            }

            // Log details for current chunk segments only
            for segment in chunkSegments {
                let duration = segment.endTimeSeconds - segment.startTimeSeconds
                print("  - Speaker \(segment.speakerId): \(String(format: "%.1f", segment.startTimeSeconds))s - \(String(format: "%.1f", segment.endTimeSeconds))s (duration: \(String(format: "%.1f", duration))s, quality: \(String(format: "%.2f", segment.qualityScore)))")
            }

            // Update results with ALL segments (maintains complete speaker history)
            let adjustedResult = DiarizationResult(
                segments: allSegments,
                speakerDatabase: result.speakerDatabase,
                timings: result.timings
            )
            
            // Check if any detected speakers match the current user's voice
            identifyUserSpeaker(in: adjustedResult)

            await MainActor.run {
                self.lastResult = adjustedResult
                self.updateCurrentSpeakers(from: adjustedResult)
            }
            
        } catch {
            print("❌ [DiarizationManager] Chunk processing failed: \(error)")
            await MainActor.run {
                self.lastError = error
            }
        }
    }
    
    /// Finish processing and get final diarization results.
    /// Routes remaining audio through the same cumulative pipeline as processChunk()
    /// so it benefits from speaker context and correct timestamp handling.
    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized else { return nil }

        // Process remaining audio through the same cumulative pipeline
        if !audioBuffer.isEmpty {
            let minSamples = Int(sampleRate * 3.0)
            if audioBuffer.count >= minSamples {
                await processChunk(audioBuffer, at: streamPosition)
            }
            audioBuffer.removeAll()
        }

        return lastResult
    }
    
    // MARK: - Speaker Management
    
    /// Update the list of current speakers from results
    private func updateCurrentSpeakers(from result: DiarizationResult) {
        let uniqueSpeakers = Set(result.segments.map { $0.speakerId })
        currentSpeakers = Array(uniqueSpeakers).sorted()
    }

    /// Identify if any detected speakers match the current user's voice profile
    private func identifyUserSpeaker(in result: DiarizationResult) {
        // Check if user has a trained voice profile
        guard UserProfile.shared.hasVoiceProfile,
              UserProfile.shared.voiceEmbedding != nil else {
            return
        }

        // Check each speaker's embedding against the user's voice profile
        for segment in result.segments {
            let (matches, confidence) = UserProfile.shared.matchesUserVoice(segment.embedding)

            if matches {
                print("🎤 [DiarizationManager] ✅ IDENTIFIED USER SPEAKING!")
                print("   Speaker ID: \(segment.speakerId)")
                print("   Confidence: \(String(format: "%.1f%%", confidence * 100))")
                print("   Time: \(String(format: "%.1f", segment.startTimeSeconds))s - \(String(format: "%.1f", segment.endTimeSeconds))s")

                // TODO: Mark this segment as belonging to the user
                // This could be used to:
                // 1. Automatically exclude user from participant list
                // 2. Show "You" instead of speaker number in transcript
                // 3. Filter out user's speaking time from meeting analytics
            }
        }
    }

    /// Compare two audio segments to determine if they're the same speaker
    /// Note: This functionality requires implementation once FluidAudio provides speaker comparison
    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        guard let _ = fluidDiarizer else {
            throw DiarizationError.notInitialized
        }
        
        // TODO: Implement when FluidAudio provides speaker comparison API
        // For now, return a placeholder similarity score
        return 0.5
    }
    
    // MARK: - Utility Methods
    
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
    
    // MARK: - Timestamp & Speaker ID Correction

    /// Convert buffer-relative timestamps to absolute recording timestamps.
    /// NOTE: Now superseded by FluidAudio's native `atTime:` parameter on
    /// `performCompleteDiarization(_:atTime:)`, which handles this offset internally.
    /// Retained as documentation of the conversion logic and potential manual fallback.
    private func convertToAbsoluteTime(_ segments: [TimedSpeakerSegment]) -> [TimedSpeakerSegment] {
        let offset = Float(bufferAbsoluteStartTime)
        guard offset > 0 else { return segments }
        return segments.map { segment in
            TimedSpeakerSegment(
                speakerId: segment.speakerId,
                embedding: segment.embedding,
                startTimeSeconds: segment.startTimeSeconds + offset,
                endTimeSeconds: segment.endTimeSeconds + offset,
                qualityScore: segment.qualityScore
            )
        }
    }

    // MARK: - Post-Processing

    /// Apply post-processing to smooth diarization results
    /// - Merges very short segments (< minSegmentDuration) with neighbors
    /// - Removes rapid back-and-forth changes (likely same person)
    private func postProcessSegments(_ segments: [TimedSpeakerSegment]) -> [TimedSpeakerSegment] {
        guard segments.count > 1 else { return segments }

        var smoothedSegments: [TimedSpeakerSegment] = []
        var currentSegment = segments[0]

        for i in 1..<segments.count {
            let nextSegment = segments[i]
            let currentDuration = currentSegment.endTimeSeconds - currentSegment.startTimeSeconds

            // If current segment is very short and next segment is same speaker as previous
            // merge with next segment (treat short segment as noise)
            if currentDuration < minSegmentDuration {
                if smoothedSegments.isEmpty {
                    // No previous segment, just extend current to next
                    currentSegment = TimedSpeakerSegment(
                        speakerId: nextSegment.speakerId,
                        embedding: nextSegment.embedding,
                        startTimeSeconds: currentSegment.startTimeSeconds,
                        endTimeSeconds: nextSegment.endTimeSeconds,
                        qualityScore: nextSegment.qualityScore
                    )
                    continue
                } else if let lastSegment = smoothedSegments.last,
                          lastSegment.speakerId == nextSegment.speakerId {
                    // Previous and next are same speaker, merge all three
                    smoothedSegments.removeLast()
                    currentSegment = TimedSpeakerSegment(
                        speakerId: lastSegment.speakerId,
                        embedding: lastSegment.embedding,
                        startTimeSeconds: lastSegment.startTimeSeconds,
                        endTimeSeconds: nextSegment.endTimeSeconds,
                        qualityScore: max(lastSegment.qualityScore, nextSegment.qualityScore)
                    )
                    continue
                }
            }

            // Check for same speaker continuing (merge adjacent same-speaker segments)
            if currentSegment.speakerId == nextSegment.speakerId {
                // Extend current segment
                currentSegment = TimedSpeakerSegment(
                    speakerId: currentSegment.speakerId,
                    embedding: currentSegment.embedding,
                    startTimeSeconds: currentSegment.startTimeSeconds,
                    endTimeSeconds: nextSegment.endTimeSeconds,
                    qualityScore: max(currentSegment.qualityScore, nextSegment.qualityScore)
                )
            } else {
                // Different speaker, save current and start new
                smoothedSegments.append(currentSegment)
                currentSegment = nextSegment
            }
        }

        // Add final segment
        smoothedSegments.append(currentSegment)

        let removed = segments.count - smoothedSegments.count
        if removed > 0 {
            print("🔄 [DiarizationManager] Post-processing: merged \(removed) short segments")
        }

        return smoothedSegments
    }

    /// Cosine similarity between two embedding vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }

    // MARK: - Reset and Cleanup

    /// Reset the diarization state
    func reset() {
        audioBuffer.removeAll()
        cumulativeAudioBuffer.removeAll()  // Clear cumulative buffer
        allSegments.removeAll()  // Clear all segments
        speakerCache.reset()  // Clear speaker cache
        knownSpeakers.removeAll()  // Clear known speakers
        totalSpeakerCount = 0  // Reset speaker count
        bufferAbsoluteStartTime = 0.0  // Reset absolute time offset
        lastResult = nil
        lastError = nil
        processingProgress = 0.0
        isProcessing = false
        streamPosition = 0.0
        currentSpeakers.removeAll()
        speakerDistances.removeAll()
        resamplingConverter = nil
        resamplingSourceFormat = nil

        print("🔄 [DiarizationManager] Reset complete")
    }

    /// Process an audio file and return diarization result
    /// Used for voice training: processes short audio samples to extract voice embeddings
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: DiarizationResult containing speaker segments with embeddings
    func processAudioFile(_ fileURL: URL) async throws -> DiarizationResult {
        guard isEnabled, isInitialized else {
            throw DiarizationError.notInitialized
        }

        print("🎤 [DiarizationManager] Processing audio file: \(fileURL.lastPathComponent)")

        // Load audio file
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            throw DiarizationError.processingFailed("Could not read audio file")
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.processingFailed("Could not create audio buffer")
        }

        try audioFile.read(into: buffer)

        // Convert to float array at 16kHz
        guard let floatSamples = convertBufferToFloatArray(buffer) else {
            throw DiarizationError.processingFailed("Could not convert audio format")
        }

        // Process the audio with FluidAudio
        guard let diarizer = fluidDiarizer else {
            throw DiarizationError.notInitialized
        }

        isProcessing = true

        do {
            // Use the same method as processChunk
            let result = try diarizer.performCompleteDiarization(floatSamples)

            // Create DiarizationResult with the same structure as processChunk
            let diarizationResult = DiarizationResult(
                segments: result.segments,
                speakerDatabase: result.speakerDatabase,
                timings: result.timings
            )

            lastResult = diarizationResult
            isProcessing = false

            let speakerCount = Set(result.segments.map { $0.speakerId }).count
            print("✅ [DiarizationManager] File processing complete. Found \(speakerCount) speaker(s)")

            return diarizationResult

        } catch {
            isProcessing = false
            lastError = error
            throw DiarizationError.processingFailed(error.localizedDescription)
        }
    }

    /// Clean up resources
    deinit {
        // Clean up non-MainActor properties only
        audioBuffer.removeAll()
        cumulativeAudioBuffer.removeAll()
        allSegments.removeAll()
        streamPosition = 0.0
        bufferAbsoluteStartTime = 0.0
        print("🧹 [DiarizationManager] Cleaned up")
    }
}

// MARK: - Error Types

enum DiarizationError: LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case processingFailed(String)
    case invalidAudioFormat
    case insufficientAudio
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Diarization manager not initialized"
        case .initializationFailed(let message):
            return "Failed to initialize diarization: \(message)"
        case .processingFailed(let message):
            return "Diarization processing failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for diarization"
        case .insufficientAudio:
            return "Not enough audio for reliable diarization (minimum 3 seconds required)"
        }
    }
}

// MARK: - Diarization Result Extensions

extension DiarizationResult {
    /// Number of unique speakers identified in the diarization result
    var speakerCount: Int {
        let uniqueSpeakers = Set(segments.map { $0.speakerId })
        return uniqueSpeakers.count
    }
    
    /// Get segments for a specific time range
    func segments(between startTime: TimeInterval, and endTime: TimeInterval) -> [TimedSpeakerSegment] {
        segments.filter { segment in
            Double(segment.endTimeSeconds) >= startTime && Double(segment.startTimeSeconds) <= endTime
        }
    }
    
    /// Get the dominant speaker in a time range
    func dominantSpeaker(between startTime: TimeInterval, and endTime: TimeInterval) -> String? {
        let relevantSegments = segments(between: startTime, and: endTime)
        
        // Calculate speaking time per speaker
        var speakerTimes: [String: TimeInterval] = [:]
        
        for segment in relevantSegments {
            let overlapStart = max(Double(segment.startTimeSeconds), startTime)
            let overlapEnd = min(Double(segment.endTimeSeconds), endTime)
            let duration = overlapEnd - overlapStart
            
            speakerTimes[segment.speakerId, default: 0] += duration
        }
        
        // Return speaker with most time
        return speakerTimes.max(by: { $0.value < $1.value })?.key
    }
}
#endif