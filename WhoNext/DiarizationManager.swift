import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

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
    
    // Chunk management for streaming - TUNED TO REDUCE OVER-SEGMENTATION
    // - 5 seconds: more stable embeddings per chunk (increased from 3s)
    // - Longer chunks produce more reliable speaker identification
    private let chunkDuration: TimeInterval = 5.0
    private var streamPosition: TimeInterval = 0.0

    // Overlap between chunks to avoid missing speaker changes at boundaries
    private let chunkOverlap: TimeInterval = 1.5 // 1.5 second overlap for better continuity
    private var overlapBuffer: [Float] = []

    // Dynamic threshold adjustment
    private var adaptiveThreshold: Float = 0.75
    private var speakerDistances: [Float] = []

    // IMPORTANT: Maintain speaker continuity across chunks
    private var cumulativeAudioBuffer: [Float] = [] // Accumulate all audio
    private var previousSpeakerDatabase: [String: [Float]]? // Track speakers across chunks
    private var allSegments: [TimedSpeakerSegment] = [] // All segments from all chunks
    private let maxCumulativeSeconds: Float = 60.0 // More context = better speaker consistency
    private var knownSpeakers: Set<String> = [] // Track all speakers we've seen

    // PHASE 3: Speaker embedding accumulation - build profiles over time
    private var accumulatedSpeakerEmbeddings: [String: [[Float]]] = [:] // Speaker ID -> list of embeddings
    private var speakerProfileEmbeddings: [String: [Float]] = [:] // Speaker ID -> averaged profile embedding
    private let maxEmbeddingsPerSpeaker: Int = 20 // Keep last N embeddings for averaging

    // PHASE 3: Confidence tracking
    @Published private(set) var speakerConfidence: Float = 0.0 // 0-1 confidence in speaker count
    @Published private(set) var speakerCountRange: (min: Int, max: Int) = (0, 0) // Estimated range

    // Store complete audio for post-recording refinement
    private var completeRecordingAudio: [Float] = []
    private let maxCompleteAudioSeconds: Float = 3600.0 // 1 hour max
    
    // MARK: - Initialization
    
    init(isEnabled: Bool = true, enableRealTimeProcessing: Bool = false, clusteringThreshold: Float = 0.75) {
        // Configure for speaker separation - TUNED TO REDUCE OVER-SEGMENTATION
        // Problem: Same speaker being split into multiple identities
        // Solution: Increase threshold to be more lenient about merging speakers
        //
        // FluidAudio threshold semantics:
        // - Higher threshold = more lenient clustering (accepts higher speaker distances as "same")
        // - Lower threshold = stricter clustering (requires closer embeddings to merge)
        //
        // Benchmark reference:
        // - 0.70 = Benchmark optimal (but can over-segment in real-world noisy conditions)
        // - 0.75 = TUNED: Balanced for speaker separation while allowing quick turn-taking
        // - 0.78 = Previous value - too lenient, caused some speaker confusion
        // - 0.85+ = Risk of under-clustering (different speakers merged)
        self.config = DiarizerConfig(
            clusteringThreshold: clusteringThreshold,  // Increased from 0.70 to reduce over-segmentation
            minSpeechDuration: 0.5,     // Increased from 0.3 - longer segments have more reliable embeddings
            minSilenceGap: 0.4,         // Increased from 0.2 - less aggressive splitting of continuous speech
            debugMode: true             // Enable to get speaker embeddings
        )
        self.isEnabled = isEnabled
        self.enableRealTimeProcessing = enableRealTimeProcessing

        print("🎙️ [DiarizationManager] Initialized:")
        print("   - Clustering threshold: \(clusteringThreshold) (tuned: 0.75)")
        print("   - Min speech duration: 0.5s")
        print("   - Min silence gap: 0.4s")
        print("   - Real-time processing: \(enableRealTimeProcessing)")
        if clusteringThreshold > 0.85 {
            print("   ⚠️ WARNING: Threshold > 0.85 may cause under-clustering (speakers merging)")
        } else if clusteringThreshold < 0.65 {
            print("   ⚠️ WARNING: Threshold < 0.65 may cause over-clustering (one person split)")
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
    
    /// Initialize the diarizer - loads from bundle for instant startup, falls back to download
    func initialize() async throws {
        print("🔄 [DiarizationManager] Initializing FluidAudio diarizer...")

        guard isEnabled else {
            print("⚠️ [DiarizationManager] Diarization is disabled")
            return
        }

        do {
            // Try to load from app bundle first (instant startup)
            let models: DiarizerModels
            if let bundledModels = try? await loadBundledModels() {
                models = bundledModels
                print("✅ [DiarizationManager] Loaded models from app bundle (instant)")
            } else {
                // Fall back to download if bundle models not found
                print("📥 [DiarizationManager] Bundle models not found, downloading...")
                models = try await DiarizerModels.downloadIfNeeded()
                print("✅ [DiarizationManager] Models downloaded/verified")
            }

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

    /// Load diarization models from app bundle for instant startup
    private func loadBundledModels() async throws -> DiarizerModels {
        guard let segmentationURL = Bundle.main.url(forResource: "pyannote_segmentation", withExtension: "mlmodelc"),
              let embeddingURL = Bundle.main.url(forResource: "wespeaker_v2", withExtension: "mlmodelc") else {
            throw DiarizationError.initializationFailed("Bundled models not found")
        }

        return try await DiarizerModels.load(
            localSegmentationModel: segmentationURL,
            localEmbeddingModel: embeddingURL
        )
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

        // Calculate samples for chunk and overlap
        let chunkSamples = Int(sampleRate * Float(chunkDuration))
        let overlapSamples = Int(sampleRate * Float(chunkOverlap))

        // Process chunks with overlap to catch speaker changes at boundaries
        // Instead of removing the full chunk, we keep the overlap portion for the next chunk
        while audioBuffer.count >= chunkSamples {
            // Create chunk by prepending any overlap from previous chunk
            var chunk: [Float]
            if !overlapBuffer.isEmpty {
                // Include overlap from previous chunk for continuity
                chunk = overlapBuffer + Array(audioBuffer.prefix(chunkSamples - overlapSamples))
            } else {
                chunk = Array(audioBuffer.prefix(chunkSamples))
            }

            // Save overlap for next chunk (last portion of audio)
            overlapBuffer = Array(audioBuffer.prefix(chunkSamples).suffix(overlapSamples))

            // Remove the non-overlapped portion from buffer
            audioBuffer.removeFirst(chunkSamples - overlapSamples)

            // Process in real-time if enabled
            if enableRealTimeProcessing {
                await processChunk(chunk, at: streamPosition)
                // Advance by chunk duration minus overlap to account for overlapping
                streamPosition += chunkDuration - chunkOverlap
            }
        }
    }
    
    /// Process a single chunk of audio
    private func processChunk(_ audioSamples: [Float], at position: TimeInterval) async {
        guard let diarizer = fluidDiarizer else { return }

        do {
            let startTime = Date()

            // Store audio for post-recording refinement pass
            completeRecordingAudio.append(contentsOf: audioSamples)
            let maxSamplesComplete = Int(maxCompleteAudioSeconds * sampleRate)
            if completeRecordingAudio.count > maxSamplesComplete {
                completeRecordingAudio.removeFirst(completeRecordingAudio.count - maxSamplesComplete)
            }

            // CRITICAL FIX: Accumulate audio and process cumulatively
            // This maintains speaker continuity across chunks
            cumulativeAudioBuffer.append(contentsOf: audioSamples)
            
            // Implement sliding window to limit memory usage
            let maxSamples = Int(maxCumulativeSeconds * sampleRate)
            if cumulativeAudioBuffer.count > maxSamples {
                let samplesToRemove = cumulativeAudioBuffer.count - maxSamples
                cumulativeAudioBuffer.removeFirst(samplesToRemove)
                print("🔄 [DiarizationManager] Sliding window: removed \(samplesToRemove) samples, keeping last \(maxCumulativeSeconds)s")
            }
            
            // Process the entire accumulated audio to maintain speaker continuity
            // This ensures speakers identified in earlier chunks are recognized in later chunks
            print("🔄 [DiarizationManager] Processing cumulative audio: \(cumulativeAudioBuffer.count) samples (\(Float(cumulativeAudioBuffer.count) / sampleRate)s)")
            
            let result = try diarizer.performCompleteDiarization(cumulativeAudioBuffer)
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Extract segments that overlap with the current chunk time window
            let chunkStartTime = Float(position)
            let chunkEndTime = Float(position + chunkDuration)
            
            // Get segments that overlap with this chunk (not just ones that start in it)
            let chunkSegments = result.segments.filter { segment in
                // Include segment if it overlaps with the chunk window at all
                segment.endTimeSeconds > chunkStartTime && segment.startTimeSeconds < chunkEndTime
            }
            
            let uniqueSpeakersInChunk = Set(chunkSegments.map { $0.speakerId })
            let totalUniqueSpeakers = Set(result.segments.map { $0.speakerId })
            
            // Track all speakers we've ever seen
            knownSpeakers.formUnion(totalUniqueSpeakers)
            totalSpeakerCount = knownSpeakers.count
            
            print("📊 [DiarizationManager] Processed \(chunkDuration)s chunk in \(String(format: "%.2f", processingTime))s")
            print("👥 [DiarizationManager] Found \(uniqueSpeakersInChunk.count) speakers in chunk, \(knownSpeakers.count) total speakers (historical)")
            print("📈 [DiarizationManager] Cumulative audio: \(String(format: "%.1f", Float(cumulativeAudioBuffer.count) / sampleRate))s, Known speakers: \(knownSpeakers)")
            
            // Log speaker distances for adaptive threshold
            if totalUniqueSpeakers.count > 1 {
                print("📊 [DiarizationManager] Multiple speakers detected, tracking for optimization")
            }
            
            // Store all segments (not just current chunk) to maintain complete history
            allSegments = result.segments
            
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

            // POST-PROCESSING PIPELINE (Phase 1 & 3)
            // Step 1: Merge similar speakers that pyannote over-segmented
            var processedResult = mergeSimilarSpeakers(in: adjustedResult)

            // Step 2: Enforce minimum segment duration
            // TUNED: 0.6s allows quick exchanges ("Yes", "No", "Okay") to be properly attributed
            // Previously 1.0s was too aggressive and merged quick interjections into wrong speaker
            processedResult = enforceMinimumSegmentDuration(in: processedResult, minDuration: 0.6)

            // Step 3: Smooth rapid speaker switches (A-B-A pattern within 2s = likely noise)
            processedResult = smoothRapidSpeakerSwitches(in: processedResult, windowSeconds: 2.0)

            // Step 4: Accumulate speaker embeddings for profile building
            accumulateSpeakerEmbeddings(from: processedResult)

            // Step 5: Match segments against accumulated profiles for consistency
            processedResult = matchAgainstAccumulatedProfiles(in: processedResult)

            // Step 6: Calculate confidence in speaker count
            updateSpeakerConfidence(from: processedResult)

            // Update knownSpeakers to reflect processed state
            if let processedDB = processedResult.speakerDatabase {
                knownSpeakers = Set(processedDB.keys)
                totalSpeakerCount = processedDB.count
            }

            // Store speaker database for continuity
            previousSpeakerDatabase = processedResult.speakerDatabase

            // Check if any detected speakers match the current user's voice
            identifyUserSpeaker(in: processedResult)

            await MainActor.run {
                self.lastResult = processedResult
                self.updateCurrentSpeakers(from: processedResult)
            }

        } catch {
            print("❌ [DiarizationManager] Chunk processing failed: \(error)")
            await MainActor.run {
                self.lastError = error
            }
        }
    }
    
    /// Finish processing and get final diarization results
    /// Includes post-recording refinement pass for improved accuracy
    func finishProcessing() async -> DiarizationResult? {
        guard isEnabled, isInitialized else { return nil }

        // Process any remaining audio in buffer
        if !audioBuffer.isEmpty {
            await processRemainingAudio()
        }

        // PHASE 2: Post-recording refinement pass
        // Re-process the complete audio with full context for better accuracy
        if completeRecordingAudio.count > Int(sampleRate * 5.0) {
            print("🔄 [DiarizationManager] Starting post-recording refinement pass...")
            await performPostRecordingRefinement()
        }

        return lastResult
    }

    /// PHASE 2: Post-recording refinement - re-diarize with full audio context
    private func performPostRecordingRefinement() async {
        guard fluidDiarizer != nil else { return }

        let audioSeconds = Float(completeRecordingAudio.count) / sampleRate
        print("🔄 [DiarizationManager] Refinement: processing \(String(format: "%.1f", audioSeconds))s of complete audio")

        isProcessing = true

        do {
            let startTime = Date()

            // Run multi-scale diarization for better accuracy
            let refinedResult = try await performMultiScaleDiarization(on: completeRecordingAudio)

            let processingTime = Date().timeIntervalSince(startTime)
            print("✅ [DiarizationManager] Refinement complete in \(String(format: "%.2f", processingTime))s")

            // Apply full post-processing pipeline
            var processedResult = mergeSimilarSpeakers(in: refinedResult)
            processedResult = enforceMinimumSegmentDuration(in: processedResult, minDuration: 0.6)
            processedResult = smoothRapidSpeakerSwitches(in: processedResult, windowSeconds: 2.0)
            processedResult = matchAgainstAccumulatedProfiles(in: processedResult)

            // Final merge pass with accumulated profiles
            processedResult = finalProfileBasedMerge(in: processedResult)

            // Update state
            if let processedDB = processedResult.speakerDatabase {
                knownSpeakers = Set(processedDB.keys)
                totalSpeakerCount = processedDB.count
            }

            updateSpeakerConfidence(from: processedResult)

            let speakerCount = Set(processedResult.segments.map { $0.speakerId }).count
            print("✅ [DiarizationManager] Final refined result: \(speakerCount) speakers")

            await MainActor.run {
                self.lastResult = processedResult
                self.updateCurrentSpeakers(from: processedResult)
                self.isProcessing = false
                self.processingProgress = 1.0
            }

        } catch {
            print("❌ [DiarizationManager] Refinement failed: \(error)")
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    /// PHASE 2: Multi-scale diarization - process at multiple window sizes and fuse results
    private func performMultiScaleDiarization(on audioSamples: [Float]) async throws -> DiarizationResult {
        guard let diarizer = fluidDiarizer else {
            throw DiarizationError.notInitialized
        }

        print("🔄 [DiarizationManager] Multi-scale diarization: short (3s) + long (8s) windows")

        // Scale 1: Short windows (3s) - better for quick speaker turns
        let shortScaleResult = try processAtScale(audioSamples, windowSeconds: 3.0, hopSeconds: 1.5, diarizer: diarizer)

        // Scale 2: Long windows (8s) - more stable speaker embeddings
        let longScaleResult = try processAtScale(audioSamples, windowSeconds: 8.0, hopSeconds: 4.0, diarizer: diarizer)

        // Fuse results: use long-scale speaker IDs as reference, refine boundaries with short-scale
        let fusedResult = fuseMultiScaleResults(shortScale: shortScaleResult, longScale: longScaleResult)

        print("   📊 Short scale: \(Set(shortScaleResult.segments.map { $0.speakerId }).count) speakers")
        print("   📊 Long scale: \(Set(longScaleResult.segments.map { $0.speakerId }).count) speakers")
        print("   📊 Fused: \(Set(fusedResult.segments.map { $0.speakerId }).count) speakers")

        return fusedResult
    }

    /// Process audio at a specific window scale
    private func processAtScale(_ audioSamples: [Float], windowSeconds: Float, hopSeconds: Float, diarizer: DiarizerManager) throws -> DiarizationResult {
        let windowSamples = Int(windowSeconds * sampleRate)
        let hopSamples = Int(hopSeconds * sampleRate)

        var allScaleSegments: [TimedSpeakerSegment] = []
        var combinedSpeakerDB: [String: [Float]] = [:]
        var position: Float = 0

        var startIndex = 0
        while startIndex + windowSamples <= audioSamples.count {
            let windowAudio = Array(audioSamples[startIndex..<(startIndex + windowSamples)])

            do {
                let result = try diarizer.performCompleteDiarization(windowAudio)

                // Adjust timestamps to absolute position
                for segment in result.segments {
                    let adjusted = TimedSpeakerSegment(
                        speakerId: segment.speakerId,
                        embedding: segment.embedding,
                        startTimeSeconds: position + segment.startTimeSeconds,
                        endTimeSeconds: position + segment.endTimeSeconds,
                        qualityScore: segment.qualityScore
                    )
                    allScaleSegments.append(adjusted)
                }

                // Merge speaker databases
                if let db = result.speakerDatabase {
                    for (id, emb) in db {
                        if combinedSpeakerDB[id] == nil {
                            combinedSpeakerDB[id] = emb
                        }
                    }
                }
            } catch {
                print("⚠️ [DiarizationManager] Scale processing error at \(position)s: \(error)")
            }

            startIndex += hopSamples
            position += hopSeconds
        }

        return DiarizationResult(
            segments: allScaleSegments,
            speakerDatabase: combinedSpeakerDB,
            timings: nil
        )
    }

    /// Fuse multi-scale results: long-scale for speaker identity, short-scale for boundaries
    private func fuseMultiScaleResults(shortScale: DiarizationResult, longScale: DiarizationResult) -> DiarizationResult {
        // Use long-scale speaker database as the authoritative source (more stable embeddings)
        guard let longDB = longScale.speakerDatabase, !longDB.isEmpty else {
            return shortScale
        }

        // Build mapping from short-scale speaker IDs to long-scale speaker IDs
        var speakerMapping: [String: String] = [:]

        if let shortDB = shortScale.speakerDatabase {
            for (shortId, shortEmb) in shortDB {
                var bestMatch: String?
                var bestDistance: Float = Float.infinity

                for (longId, longEmb) in longDB {
                    let distance = cosineDistance(shortEmb, longEmb)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestMatch = longId
                    }
                }

                // Map if similarity is reasonable (distance < 0.5)
                if let match = bestMatch, bestDistance < 0.5 {
                    speakerMapping[shortId] = match
                } else {
                    speakerMapping[shortId] = shortId // Keep original if no good match
                }
            }
        }

        // Apply mapping to short-scale segments (better boundaries)
        var fusedSegments: [TimedSpeakerSegment] = []
        for segment in shortScale.segments {
            let mappedId = speakerMapping[segment.speakerId] ?? segment.speakerId
            let fusedSegment = TimedSpeakerSegment(
                speakerId: mappedId,
                embedding: segment.embedding,
                startTimeSeconds: segment.startTimeSeconds,
                endTimeSeconds: segment.endTimeSeconds,
                qualityScore: segment.qualityScore
            )
            fusedSegments.append(fusedSegment)
        }

        return DiarizationResult(
            segments: fusedSegments,
            speakerDatabase: longDB, // Use long-scale database
            timings: nil
        )
    }
    
    /// Process remaining audio that doesn't fill a complete chunk
    private func processRemainingAudio() async {
        guard let diarizer = fluidDiarizer, !audioBuffer.isEmpty else { return }
        
        isProcessing = true
        processingProgress = 0.0
        
        do {
            print("🔄 [DiarizationManager] Processing remaining \(audioBuffer.count) samples...")
            
            // Only process if we have at least 3 seconds of audio
            let minSamples = Int(sampleRate * 3.0)
            guard audioBuffer.count >= minSamples else {
                print("⚠️ [DiarizationManager] Not enough audio for reliable diarization")
                return
            }
            
            let result = try diarizer.performCompleteDiarization(audioBuffer)
            
            // Adjust timestamps for stream position
            var adjustedSegments: [TimedSpeakerSegment] = []
            for segment in result.segments {
                let adjusted = TimedSpeakerSegment(
                    speakerId: segment.speakerId,
                    embedding: segment.embedding,
                    startTimeSeconds: Float(streamPosition) + segment.startTimeSeconds,
                    endTimeSeconds: Float(streamPosition) + segment.endTimeSeconds,
                    qualityScore: segment.qualityScore
                )
                adjustedSegments.append(adjusted)
            }
            
            let adjustedResult = DiarizationResult(
                segments: adjustedSegments,
                speakerDatabase: result.speakerDatabase,
                timings: result.timings
            )

            // POST-PROCESSING: Merge similar speakers that pyannote over-segmented
            let mergedResult = mergeSimilarSpeakers(in: adjustedResult)

            // Update knownSpeakers to reflect merged state
            if let mergedDB = mergedResult.speakerDatabase {
                knownSpeakers = Set(mergedDB.keys)
                totalSpeakerCount = mergedDB.count
            }

            await MainActor.run {
                self.lastResult = mergedResult
                self.updateCurrentSpeakers(from: mergedResult)
                self.isProcessing = false
                self.processingProgress = 1.0
            }

            // Clear the buffer
            audioBuffer.removeAll()

            let uniqueSpeakers = Set(mergedResult.segments.map { $0.speakerId })
            print("✅ [DiarizationManager] Final diarization complete: \(uniqueSpeakers.count) speakers (after merge)")
            
        } catch {
            print("❌ [DiarizationManager] Final processing failed: \(error)")
            await MainActor.run {
                self.lastError = error
                self.isProcessing = false
            }
        }
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
    private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate
        
        var samples: [Float] = []
        
        if sourceSampleRate != Double(sampleRate) {
            // Downsample to 16kHz
            let ratio = sourceSampleRate / Double(sampleRate)
            let targetFrameCount = Int(Double(frameCount) / ratio)
            
            for frame in 0..<targetFrameCount {
                let sourceFrame = Int(Double(frame) * ratio)
                if sourceFrame < frameCount {
                    // Average all channels to mono
                    var sample: Float = 0.0
                    for channel in 0..<channelCount {
                        sample += channelData[channel][sourceFrame]
                    }
                    samples.append(sample / Float(channelCount))
                }
            }
        } else {
            // Already at 16kHz, just convert to mono
            for frame in 0..<frameCount {
                var sample: Float = 0.0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                samples.append(sample / Float(channelCount))
            }
        }
        
        return samples
    }
    
    // MARK: - Reset and Cleanup
    
    /// Reset the diarization state
    func reset() {
        audioBuffer.removeAll()
        cumulativeAudioBuffer.removeAll()  // Clear cumulative buffer
        overlapBuffer.removeAll()  // Clear overlap buffer
        allSegments.removeAll()  // Clear all segments
        previousSpeakerDatabase = nil  // Clear speaker database
        knownSpeakers.removeAll()  // Clear known speakers
        totalSpeakerCount = 0  // Reset speaker count
        lastResult = nil
        lastError = nil
        processingProgress = 0.0
        isProcessing = false
        streamPosition = 0.0
        currentSpeakers.removeAll()
        speakerDistances.removeAll()

        // Phase 3: Clear accumulated profiles
        accumulatedSpeakerEmbeddings.removeAll()
        speakerProfileEmbeddings.removeAll()
        speakerConfidence = 0.0
        speakerCountRange = (0, 0)

        // Phase 2: Clear complete recording audio
        completeRecordingAudio.removeAll()

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

            // POST-PROCESSING: Merge similar speakers that pyannote over-segmented
            let mergedResult = mergeSimilarSpeakers(in: diarizationResult)

            // Update knownSpeakers to reflect merged state
            if let mergedDB = mergedResult.speakerDatabase {
                knownSpeakers = Set(mergedDB.keys)
                totalSpeakerCount = mergedDB.count
            }

            lastResult = mergedResult
            isProcessing = false

            let speakerCount = Set(mergedResult.segments.map { $0.speakerId }).count
            print("✅ [DiarizationManager] File processing complete. Found \(speakerCount) speaker(s) (after merge)")

            return mergedResult

        } catch {
            isProcessing = false
            lastError = error
            throw DiarizationError.processingFailed(error.localizedDescription)
        }
    }

    // MARK: - Phase 1: Segment Processing

    /// PHASE 1: Enforce minimum segment duration
    /// Segments shorter than minDuration are unreliable - merge them into adjacent segments
    private func enforceMinimumSegmentDuration(in result: DiarizationResult, minDuration: Float) -> DiarizationResult {
        guard !result.segments.isEmpty else { return result }

        // Sort segments by start time
        let sortedSegments = result.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

        var processedSegments: [TimedSpeakerSegment] = []
        var shortSegmentsMerged = 0

        for segment in sortedSegments {
            let duration = segment.endTimeSeconds - segment.startTimeSeconds

            if duration < minDuration {
                // This segment is too short - merge it
                shortSegmentsMerged += 1

                if let lastSegment = processedSegments.last {
                    // Merge into previous segment by extending its end time
                    let extended = TimedSpeakerSegment(
                        speakerId: lastSegment.speakerId,
                        embedding: lastSegment.embedding,
                        startTimeSeconds: lastSegment.startTimeSeconds,
                        endTimeSeconds: segment.endTimeSeconds,
                        qualityScore: lastSegment.qualityScore
                    )
                    processedSegments[processedSegments.count - 1] = extended
                } else {
                    // No previous segment - keep it but mark as low quality
                    processedSegments.append(segment)
                }
            } else {
                // Segment is long enough - check if it should merge with previous
                if let lastSegment = processedSegments.last,
                   lastSegment.speakerId == segment.speakerId,
                   segment.startTimeSeconds - lastSegment.endTimeSeconds < 0.5 {
                    // Same speaker, small gap - merge
                    let merged = TimedSpeakerSegment(
                        speakerId: lastSegment.speakerId,
                        embedding: lastSegment.embedding,
                        startTimeSeconds: lastSegment.startTimeSeconds,
                        endTimeSeconds: segment.endTimeSeconds,
                        qualityScore: max(lastSegment.qualityScore, segment.qualityScore)
                    )
                    processedSegments[processedSegments.count - 1] = merged
                } else {
                    processedSegments.append(segment)
                }
            }
        }

        if shortSegmentsMerged > 0 {
            print("   📏 Minimum duration: merged \(shortSegmentsMerged) short segments (<\(minDuration)s)")
        }

        return DiarizationResult(
            segments: processedSegments,
            speakerDatabase: result.speakerDatabase,
            timings: result.timings
        )
    }

    /// PHASE 1: Smooth rapid speaker switches (A-B-A pattern)
    /// If speaker changes back within windowSeconds, it's likely noise - smooth it out
    private func smoothRapidSpeakerSwitches(in result: DiarizationResult, windowSeconds: Float) -> DiarizationResult {
        guard result.segments.count >= 3 else { return result }

        let sortedSegments = result.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        var processedSegments = sortedSegments
        var smoothedCount = 0

        // Look for A-B-A patterns within the window
        var i = 1
        while i < processedSegments.count - 1 {
            let prev = processedSegments[i - 1]
            let curr = processedSegments[i]
            let next = processedSegments[i + 1]

            // Check for A-B-A pattern
            if prev.speakerId == next.speakerId && prev.speakerId != curr.speakerId {
                // Check if the B segment is short and within window
                let bDuration = curr.endTimeSeconds - curr.startTimeSeconds
                let totalSpan = next.endTimeSeconds - prev.startTimeSeconds

                if bDuration < 2.0 && totalSpan < windowSeconds {
                    // Smooth: merge all three into speaker A
                    let merged = TimedSpeakerSegment(
                        speakerId: prev.speakerId,
                        embedding: prev.embedding,
                        startTimeSeconds: prev.startTimeSeconds,
                        endTimeSeconds: next.endTimeSeconds,
                        qualityScore: max(prev.qualityScore, next.qualityScore)
                    )

                    // Replace the three segments with one merged segment
                    processedSegments.remove(at: i + 1) // Remove next
                    processedSegments.remove(at: i)     // Remove curr
                    processedSegments[i - 1] = merged   // Replace prev with merged

                    smoothedCount += 1
                    // Don't increment i - check the new configuration
                    continue
                }
            }
            i += 1
        }

        if smoothedCount > 0 {
            print("   🔄 Smoothing: fixed \(smoothedCount) rapid A-B-A speaker switches")
        }

        return DiarizationResult(
            segments: processedSegments,
            speakerDatabase: result.speakerDatabase,
            timings: result.timings
        )
    }

    // MARK: - Phase 3: Speaker Profile Accumulation

    /// PHASE 3: Accumulate speaker embeddings to build better profiles over time
    private func accumulateSpeakerEmbeddings(from result: DiarizationResult) {
        for segment in result.segments {
            let speakerId = segment.speakerId

            // Initialize array if needed
            if accumulatedSpeakerEmbeddings[speakerId] == nil {
                accumulatedSpeakerEmbeddings[speakerId] = []
            }

            // Only add embeddings from segments with reasonable quality and duration
            let duration = segment.endTimeSeconds - segment.startTimeSeconds
            if duration >= 1.0 && segment.qualityScore > 0.5 {
                accumulatedSpeakerEmbeddings[speakerId]?.append(segment.embedding)

                // Keep only the most recent embeddings
                if let count = accumulatedSpeakerEmbeddings[speakerId]?.count,
                   count > maxEmbeddingsPerSpeaker {
                    accumulatedSpeakerEmbeddings[speakerId]?.removeFirst(count - maxEmbeddingsPerSpeaker)
                }
            }
        }

        // Update profile embeddings (averaged)
        for (speakerId, embeddings) in accumulatedSpeakerEmbeddings {
            if let averaged = averageEmbeddings(embeddings) {
                speakerProfileEmbeddings[speakerId] = averaged
            }
        }
    }

    /// PHASE 3: Match segments against accumulated speaker profiles for consistency
    private func matchAgainstAccumulatedProfiles(in result: DiarizationResult) -> DiarizationResult {
        guard !speakerProfileEmbeddings.isEmpty else { return result }

        var remappedSegments: [TimedSpeakerSegment] = []
        var remappings = 0

        for segment in result.segments {
            // Find best matching profile
            var bestMatch: String?
            var bestDistance: Float = Float.infinity

            for (profileId, profileEmb) in speakerProfileEmbeddings {
                let distance = cosineDistance(segment.embedding, profileEmb)
                if distance < bestDistance {
                    bestDistance = distance
                    bestMatch = profileId
                }
            }

            // Remap if we found a significantly better match than current ID
            let currentProfileDistance: Float
            if let currentProfile = speakerProfileEmbeddings[segment.speakerId] {
                currentProfileDistance = cosineDistance(segment.embedding, currentProfile)
            } else {
                currentProfileDistance = Float.infinity
            }

            // Only remap if the new match is significantly better (> 0.1 improvement)
            // and the match is good enough (< 0.4)
            if let match = bestMatch,
               bestDistance < 0.4,
               bestDistance < currentProfileDistance - 0.1,
               match != segment.speakerId {
                let remapped = TimedSpeakerSegment(
                    speakerId: match,
                    embedding: segment.embedding,
                    startTimeSeconds: segment.startTimeSeconds,
                    endTimeSeconds: segment.endTimeSeconds,
                    qualityScore: segment.qualityScore
                )
                remappedSegments.append(remapped)
                remappings += 1
            } else {
                remappedSegments.append(segment)
            }
        }

        if remappings > 0 {
            print("   👤 Profile matching: remapped \(remappings) segments to better-matching profiles")
        }

        return DiarizationResult(
            segments: remappedSegments,
            speakerDatabase: result.speakerDatabase,
            timings: result.timings
        )
    }

    /// PHASE 3: Update speaker confidence based on embedding distances
    private func updateSpeakerConfidence(from result: DiarizationResult) {
        guard let speakerDB = result.speakerDatabase, speakerDB.count > 0 else {
            speakerConfidence = 0.0
            speakerCountRange = (0, 0)
            return
        }

        let speakerIds = Array(speakerDB.keys).sorted()
        let speakerCount = speakerIds.count

        if speakerCount == 1 {
            // Single speaker - high confidence
            speakerConfidence = 0.9
            speakerCountRange = (1, 1)
            return
        }

        // Calculate average inter-speaker distance
        var distances: [Float] = []
        for i in 0..<speakerIds.count {
            for j in (i+1)..<speakerIds.count {
                if let emb1 = speakerDB[speakerIds[i]], let emb2 = speakerDB[speakerIds[j]] {
                    distances.append(cosineDistance(emb1, emb2))
                }
            }
        }

        guard !distances.isEmpty else {
            speakerConfidence = 0.5
            speakerCountRange = (1, speakerCount)
            return
        }

        let avgDistance = distances.reduce(0, +) / Float(distances.count)
        let minDistance = distances.min() ?? 0

        // Confidence based on separation:
        // - avgDistance > 0.6: very distinct speakers, high confidence
        // - avgDistance 0.4-0.6: reasonably distinct
        // - avgDistance 0.2-0.4: somewhat similar, might be over-segmented
        // - avgDistance < 0.2: very similar, likely over-segmented

        if avgDistance > 0.6 {
            speakerConfidence = 0.95
            speakerCountRange = (speakerCount, speakerCount)
        } else if avgDistance > 0.4 {
            speakerConfidence = 0.8
            speakerCountRange = (speakerCount, speakerCount)
        } else if avgDistance > 0.25 {
            speakerConfidence = 0.6
            speakerCountRange = (max(1, speakerCount - 1), speakerCount)
        } else {
            speakerConfidence = 0.4
            speakerCountRange = (1, speakerCount)
        }

        // Adjust if minimum distance suggests possible merge candidates
        if minDistance < 0.3 && speakerCount > 1 {
            speakerCountRange = (max(1, speakerCount - 1), speakerCount)
            speakerConfidence = min(speakerConfidence, 0.7)
        }

        print("   📊 Confidence: \(String(format: "%.0f%%", speakerConfidence * 100)) (\(speakerCountRange.min)-\(speakerCountRange.max) speakers, avg distance: \(String(format: "%.3f", avgDistance)))")
    }

    /// PHASE 2: Final profile-based merge after refinement
    /// Uses accumulated profiles to do a final merge pass
    private func finalProfileBasedMerge(in result: DiarizationResult) -> DiarizationResult {
        guard let speakerDB = result.speakerDatabase, speakerDB.count > 1 else { return result }

        // Compare speaker database embeddings against accumulated profiles
        // If two database speakers map to the same profile, merge them
        var mergeMap: [String: String] = [:]
        let speakerIds = Array(speakerDB.keys).sorted()

        for id in speakerIds {
            mergeMap[id] = id
        }

        // Check each pair against profiles
        for i in 0..<speakerIds.count {
            for j in (i+1)..<speakerIds.count {
                let id1 = speakerIds[i]
                let id2 = speakerIds[j]

                guard let emb1 = speakerDB[id1], let emb2 = speakerDB[id2] else { continue }

                // Find best matching profile for each
                var bestProfile1: String?
                var bestDist1: Float = Float.infinity
                var bestProfile2: String?
                var bestDist2: Float = Float.infinity

                for (profileId, profileEmb) in speakerProfileEmbeddings {
                    let dist1 = cosineDistance(emb1, profileEmb)
                    let dist2 = cosineDistance(emb2, profileEmb)

                    if dist1 < bestDist1 {
                        bestDist1 = dist1
                        bestProfile1 = profileId
                    }
                    if dist2 < bestDist2 {
                        bestDist2 = dist2
                        bestProfile2 = profileId
                    }
                }

                // If both map to the same profile with good confidence, merge them
                if let profile1 = bestProfile1, let profile2 = bestProfile2,
                   profile1 == profile2,
                   bestDist1 < 0.35, bestDist2 < 0.35 {
                    let target1 = findRoot(id1, in: mergeMap)
                    let target2 = findRoot(id2, in: mergeMap)

                    if target1 != target2 {
                        let (keep, merge) = target1 < target2 ? (target1, target2) : (target2, target1)
                        mergeMap[merge] = keep
                        print("   🔗 Profile-based merge: \(merge) → \(keep) (both match profile \(profile1))")
                    }
                }
            }
        }

        // Apply merges
        for id in speakerIds {
            mergeMap[id] = findRoot(id, in: mergeMap)
        }

        let uniqueMerged = Set(mergeMap.values)
        if uniqueMerged.count < speakerIds.count {
            var mergedSegments: [TimedSpeakerSegment] = []
            for segment in result.segments {
                let mergedId = mergeMap[segment.speakerId] ?? segment.speakerId
                let mergedSegment = TimedSpeakerSegment(
                    speakerId: mergedId,
                    embedding: segment.embedding,
                    startTimeSeconds: segment.startTimeSeconds,
                    endTimeSeconds: segment.endTimeSeconds,
                    qualityScore: segment.qualityScore
                )
                mergedSegments.append(mergedSegment)
            }

            var mergedDB: [String: [Float]] = [:]
            for mergedId in uniqueMerged {
                let originalIds = speakerIds.filter { mergeMap[$0] == mergedId }
                let embeddings = originalIds.compactMap { speakerDB[$0] }
                if let averaged = averageEmbeddings(embeddings) {
                    mergedDB[mergedId] = averaged
                }
            }

            print("   ✅ Final merge: \(speakerIds.count) → \(uniqueMerged.count) speakers")

            return DiarizationResult(
                segments: mergedSegments,
                speakerDatabase: mergedDB,
                timings: result.timings
            )
        }

        return result
    }

    // MARK: - Post-Processing Speaker Merger

    /// Merge similar speakers that pyannote over-segmented
    /// This addresses the common issue of pyannote creating too many speakers
    /// Reddit insight: https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb
    ///
    /// The approach:
    /// 1. Compare all speaker embeddings pairwise
    /// 2. Merge speakers with cosine distance below threshold
    /// 3. Update all segments to use merged speaker IDs
    private func mergeSimilarSpeakers(
        in result: DiarizationResult,
        mergeThreshold: Float = 0.35  // More aggressive than FluidAudio's 0.65
    ) -> DiarizationResult {
        guard let speakerDB = result.speakerDatabase, speakerDB.count > 1 else { return result }

        print("🔄 [DiarizationManager] Post-processing: checking \(speakerDB.count) speakers for merging (threshold: \(mergeThreshold))")

        // Build merge map: [originalId -> mergedId]
        var mergeMap: [String: String] = [:]
        let speakerIds = Array(speakerDB.keys).sorted()

        // Initialize each speaker to map to itself
        for id in speakerIds {
            mergeMap[id] = id
        }

        // Compare all pairs and build merge relationships
        for i in 0..<speakerIds.count {
            for j in (i+1)..<speakerIds.count {
                let id1 = speakerIds[i]
                let id2 = speakerIds[j]

                guard let emb1 = speakerDB[id1], let emb2 = speakerDB[id2] else { continue }

                let distance = cosineDistance(emb1, emb2)

                if distance < mergeThreshold {
                    // Merge id2 into id1 (keep lower numbered speaker)
                    let target1 = findRoot(id1, in: mergeMap)
                    let target2 = findRoot(id2, in: mergeMap)

                    if target1 != target2 {
                        // Merge the higher ID into the lower ID
                        let (keep, merge) = target1 < target2 ? (target1, target2) : (target2, target1)
                        mergeMap[merge] = keep
                        print("   🔗 Merging \(merge) → \(keep) (distance: \(String(format: "%.3f", distance)))")
                    }
                }
            }
        }

        // Flatten merge map (resolve transitive merges)
        for id in speakerIds {
            mergeMap[id] = findRoot(id, in: mergeMap)
        }

        // Count how many speakers we're reducing to
        let uniqueMergedSpeakers = Set(mergeMap.values)
        let mergeCount = speakerIds.count - uniqueMergedSpeakers.count

        if mergeCount > 0 {
            print("   ✅ Merged \(mergeCount) speakers: \(speakerIds.count) → \(uniqueMergedSpeakers.count)")
        } else {
            print("   ℹ️ No speakers merged (all sufficiently distinct)")
            return result
        }

        // Update segments with merged speaker IDs
        var mergedSegments: [TimedSpeakerSegment] = []
        for segment in result.segments {
            let mergedId = mergeMap[segment.speakerId] ?? segment.speakerId
            let mergedSegment = TimedSpeakerSegment(
                speakerId: mergedId,
                embedding: segment.embedding,
                startTimeSeconds: segment.startTimeSeconds,
                endTimeSeconds: segment.endTimeSeconds,
                qualityScore: segment.qualityScore
            )
            mergedSegments.append(mergedSegment)
        }

        // Build new speaker database with merged embeddings (average)
        var mergedSpeakerDB: [String: [Float]] = [:]
        for mergedId in uniqueMergedSpeakers {
            // Get all original IDs that map to this merged ID
            let originalIds = speakerIds.filter { mergeMap[$0] == mergedId }

            // Average their embeddings
            let embeddings = originalIds.compactMap { speakerDB[$0] }
            if let averaged = averageEmbeddings(embeddings) {
                mergedSpeakerDB[mergedId] = averaged
            } else if let first = embeddings.first {
                mergedSpeakerDB[mergedId] = first
            }
        }

        return DiarizationResult(
            segments: mergedSegments,
            speakerDatabase: mergedSpeakerDB,
            timings: result.timings
        )
    }

    /// Find root of a speaker ID in the merge map (union-find)
    private func findRoot(_ id: String, in mergeMap: [String: String]) -> String {
        var current = id
        while let parent = mergeMap[current], parent != current {
            current = parent
        }
        return current
    }

    /// Calculate cosine distance between two embeddings (0 = identical, 2 = opposite)
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.infinity }

        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        magnitudeA = sqrt(magnitudeA)
        magnitudeB = sqrt(magnitudeB)

        guard magnitudeA > 0 && magnitudeB > 0 else { return Float.infinity }

        let similarity = dotProduct / (magnitudeA * magnitudeB)
        return 1 - similarity  // Convert similarity to distance
    }

    /// Average multiple embeddings
    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float]? {
        guard !embeddings.isEmpty, let dim = embeddings.first?.count, dim > 0 else { return nil }

        var average = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            guard emb.count == dim else { continue }
            for i in 0..<dim {
                average[i] += emb[i]
            }
        }

        let count = Float(embeddings.count)
        for i in 0..<dim {
            average[i] /= count
        }

        return average
    }

    /// Clean up resources
    deinit {
        // Clean up non-MainActor properties only
        audioBuffer.removeAll()
        cumulativeAudioBuffer.removeAll()
        overlapBuffer.removeAll()
        allSegments.removeAll()
        streamPosition = 0.0
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