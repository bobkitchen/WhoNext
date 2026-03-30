import Foundation
import Accelerate

/// Energy-based local speaker detector for 1:1 and group diarization.
///
/// Uses mic-to-system energy ratio to distinguish local speech from system audio bleed.
/// Produces `TimedSpeakerSegment` values with speakerId "local_1" — drop-in compatible
/// with the SegmentAligner pipeline.
final class EnergyGateDetector {

    // MARK: - Configuration

    /// Minimum mic-to-system energy ratio (in dB) to classify a frame as local speech.
    /// 6dB (~2x amplitude) — lowered from 10dB which was too aggressive and missed local speech.
    let ratioThresholdDB: Float

    /// Number of samples per frame (30ms at 16kHz = 480 samples)
    private let frameSamples = 480

    /// Number of frames for sliding window smoothing (240ms = 8 frames at 30ms)
    /// Longer window bridges natural pauses within words/sentences
    private let smoothingWindowSize = 8

    /// Number of hangover frames (300ms = 10 frames at 30ms)
    /// Prevents speech from fragmenting into micro-segments at natural pauses
    private let hangoverFrames = 10

    /// Noise floor calibration duration in seconds
    private let calibrationDuration: TimeInterval = 2.0

    /// System RMS below this is considered silence
    private let systemSilenceThreshold: Float = 0.001

    /// Multiplier above noise floor for speech detection
    private let noiseFloorMultiplier: Float = 2.0

    /// Absolute minimum noise floor to prevent hair-trigger detection
    /// when calibrating in silence (-60 dBFS)
    private let absoluteMinimumNoiseFloor: Float = 0.001

    /// Minimum segment duration in seconds — segments shorter than this are dropped.
    /// 0.3s filters noise bursts while keeping short interjections ("yeah", "mm-hmm").
    private let minimumSegmentDuration: Float = 0.3

    // MARK: - State

    /// Adaptive noise floor (initially calibrated from first 2s, then continuously adapted)
    private var noiseFloor: Float = 0
    private var isCalibrated = false
    private var calibrationSamples: [Float] = []
    private var calibrationFrameCount = 0
    private let calibrationFramesNeeded: Int

    /// Adaptive noise floor decay rate — when mic is quiet and system is silent,
    /// slowly lower the noise floor toward current ambient level.
    /// This handles the case where initial calibration was done during loud system audio
    /// (e.g., YouTube playing) and the noise floor is stuck too high.
    private let adaptationRate: Float = 0.02
    private var adaptationFrameCounter = 0
    private let adaptationInterval = 10  // Adapt every 10 quiet frames (~300ms)

    /// Sliding window of speech/silence decisions for smoothing
    private var smoothingWindow: [Bool] = []

    /// Hangover counter — frames remaining before allowing transition to silence
    private var hangoverCounter = 0

    /// Current speech state after smoothing + hangover
    private(set) var isSpeaking = false

    /// Tracking for segment generation
    private var speechStartTime: TimeInterval?

    /// Frame counter for periodic ratio logging (~1s interval)
    private var logCounter = 0
    private let logInterval: Int

    /// 30-second diagnostic summary
    private var summaryCounter = 0
    private let summaryInterval: Int
    private var summaryOnsetCount = 0
    private var summaryTotalSpeechFrames = 0
    private var summaryTotalFrames = 0
    private var summaryMaxRatioDB: Float = -100
    private var summaryMinRatioDB: Float = 100

    // MARK: - Init

    /// - Parameter ratioThresholdDB: Mic-to-system energy ratio threshold in dB (default 6dB).
    init(ratioThresholdDB: Float = 6.0) {
        self.ratioThresholdDB = ratioThresholdDB
        self.calibrationFramesNeeded = Int(calibrationDuration * 16000.0 / Double(frameSamples))
        self.logInterval = Int(1.0 * 16000.0 / Double(frameSamples))
        self.summaryInterval = Int(30.0 * 16000.0 / Double(frameSamples))
    }

    // MARK: - Public API

    /// Process a chunk of mic audio samples and return any completed local speaker segments.
    ///
    /// - Parameters:
    ///   - micSamples: Float array of mic audio at 16kHz mono
    ///   - systemRMS: Current RMS of the system audio stream (for cross-stream comparison)
    ///   - chunkStartTime: Absolute start time of this chunk in the recording
    /// - Returns: Array of `TimedSpeakerSegment` for detected local speech, or empty array
    func processChunk(micSamples: [Float], systemRMS: Float, chunkStartTime: TimeInterval) -> [TimedSpeakerSegment] {
        var segments: [TimedSpeakerSegment] = []
        let frameCount = micSamples.count / frameSamples

        for frameIndex in 0..<frameCount {
            let offset = frameIndex * frameSamples
            let end = min(offset + frameSamples, micSamples.count)
            let frameSlice = Array(micSamples[offset..<end])

            let frameTime = chunkStartTime + Double(offset) / 16000.0
            let frameDuration = Double(end - offset) / 16000.0

            let micRMS = calculateRMSvDSP(frameSlice)

            // Calibration phase: collect mic RMS values to establish noise floor
            if !isCalibrated {
                calibrationSamples.append(micRMS)
                calibrationFrameCount += 1
                if calibrationFrameCount >= calibrationFramesNeeded {
                    calibrateNoiseFloor()
                }
                continue
            }

            // Speech detection: mic above adaptive threshold AND energy ratio check
            let isSpeechFrame = detectSpeech(micRMS: micRMS, systemRMS: systemRMS)

            // Adaptive noise floor: when mic is quiet (not speech) and system is silent,
            // gradually lower the noise floor toward current ambient level.
            // This fixes the case where initial calibration happened during loud system audio
            // (e.g., YouTube playing → mic picks up speaker bleed → noise floor set too high).
            if !isSpeechFrame && systemRMS < systemSilenceThreshold && micRMS > 0 {
                adaptationFrameCounter += 1
                if adaptationFrameCounter >= adaptationInterval {
                    let oldFloor = noiseFloor
                    // Exponential moving average toward current quiet mic level
                    noiseFloor = noiseFloor * (1.0 - adaptationRate) + micRMS * adaptationRate
                    noiseFloor = max(noiseFloor, absoluteMinimumNoiseFloor)
                    if abs(oldFloor - noiseFloor) > 0.001 {
                        debugLog("[EnergyGate] 🔄 Noise floor adapted: \(String(format: "%.5f", oldFloor)) → \(String(format: "%.5f", noiseFloor)) (speechThreshold: \(String(format: "%.5f", noiseFloor * noiseFloorMultiplier)))")
                    }
                    adaptationFrameCounter = 0
                }
            } else {
                adaptationFrameCounter = 0
            }

            // Track stats for 30s summary
            let ratioDB = energyRatioDB(micRMS: micRMS, systemRMS: systemRMS)
            summaryTotalFrames += 1
            if isSpeechFrame { summaryTotalSpeechFrames += 1 }
            summaryMaxRatioDB = max(summaryMaxRatioDB, ratioDB)
            summaryMinRatioDB = min(summaryMinRatioDB, ratioDB)

            // 30-second diagnostic summary
            summaryCounter += 1
            if summaryCounter >= summaryInterval {
                let speechPct = summaryTotalFrames > 0 ? Float(summaryTotalSpeechFrames) / Float(summaryTotalFrames) * 100 : 0
                debugLog("[EnergyGate] 📊 30s summary: local speech \(String(format: "%.0f", speechPct))% of frames, \(summaryOnsetCount) onsets, ratio range \(String(format: "%.1f", summaryMinRatioDB))–\(String(format: "%.1f", summaryMaxRatioDB))dB, threshold: \(String(format: "%.1f", ratioThresholdDB))dB")
                summaryCounter = 0
                summaryOnsetCount = 0
                summaryTotalSpeechFrames = 0
                summaryTotalFrames = 0
                summaryMaxRatioDB = -100
                summaryMinRatioDB = 100
            }

            // Sliding window smoothing (majority vote)
            smoothingWindow.append(isSpeechFrame)
            if smoothingWindow.count > smoothingWindowSize {
                smoothingWindow.removeFirst()
            }
            let speechVotes = smoothingWindow.filter { $0 }.count
            let smoothedSpeech = speechVotes > smoothingWindowSize / 2

            // Hangover logic
            let previouslySpeaking = isSpeaking
            if smoothedSpeech {
                hangoverCounter = hangoverFrames
                isSpeaking = true
            } else if hangoverCounter > 0 {
                hangoverCounter -= 1
                isSpeaking = true
            } else {
                isSpeaking = false
            }

            // Segment boundary detection
            if isSpeaking && !previouslySpeaking {
                // Speech onset
                speechStartTime = frameTime
                summaryOnsetCount += 1
                debugLog("[EnergyGate] ONSET at \(String(format: "%.2f", frameTime))s  mic: \(String(format: "%.5f", micRMS))  sys: \(String(format: "%.5f", systemRMS))  ratio: \(String(format: "%.1f", ratioDB))dB")
                Task { @MainActor in
                    DiarizationDiagnostics.shared.logEnergyGateOnset(
                        at: frameTime, micRMS: micRMS, systemRMS: systemRMS, ratioDB: ratioDB
                    )
                }
            } else if !isSpeaking && previouslySpeaking {
                // Speech offset — emit segment if long enough
                if let start = speechStartTime {
                    let segEnd = frameTime + frameDuration
                    let segDuration = Float(segEnd - start)
                    debugLog("[EnergyGate] OFFSET at \(String(format: "%.2f", segEnd))s  duration: \(String(format: "%.2f", segDuration))s")
                    Task { @MainActor in
                        DiarizationDiagnostics.shared.logEnergyGateOffset(
                            at: segEnd, duration: TimeInterval(segDuration)
                        )
                    }

                    // Only emit segments longer than minimum duration
                    if segDuration >= minimumSegmentDuration {
                        let segment = TimedSpeakerSegment(
                            speakerId: "local_1",
                            startTimeSeconds: Float(start),
                            endTimeSeconds: Float(segEnd),
                            qualityScore: 0.8
                        )
                        segments.append(segment)
                    }
                    speechStartTime = nil
                }
            }
        }

        return segments
    }

    /// Flush any in-progress speech segment (call at end of recording).
    func flush(at endTime: TimeInterval) -> TimedSpeakerSegment? {
        guard let start = speechStartTime, isSpeaking else { return nil }
        let segDuration = Float(endTime - start)
        speechStartTime = nil
        isSpeaking = false
        hangoverCounter = 0

        guard segDuration >= minimumSegmentDuration else { return nil }

        return TimedSpeakerSegment(
            speakerId: "local_1",
            startTimeSeconds: Float(start),
            endTimeSeconds: Float(endTime),
            qualityScore: 0.8
        )
    }

    /// Reset all state for a new recording.
    func reset() {
        noiseFloor = 0
        isCalibrated = false
        calibrationSamples.removeAll()
        calibrationFrameCount = 0
        smoothingWindow.removeAll()
        hangoverCounter = 0
        isSpeaking = false
        speechStartTime = nil
        logCounter = 0
        adaptationFrameCounter = 0
    }

    // MARK: - Private

    /// Calculate RMS using vDSP for acceleration.
    private func calculateRMSvDSP(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    /// Establish noise floor from calibration samples using median,
    /// with an absolute minimum to prevent hair-trigger detection.
    private func calibrateNoiseFloor() {
        let sorted = calibrationSamples.sorted()
        let mid = sorted.count / 2
        let medianNoiseFloor = sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2.0
            : sorted[mid]

        // Apply absolute minimum — prevents calibrating in silence from setting
        // a noise floor of ~0.000001 which triggers on any signal
        noiseFloor = max(medianNoiseFloor, absoluteMinimumNoiseFloor)
        isCalibrated = true
        let speechThreshold = noiseFloor * noiseFloorMultiplier
        calibrationSamples.removeAll()
        debugLog("[EnergyGateDetector] Calibrated: noiseFloor=\(String(format: "%.5f", noiseFloor)) (raw median=\(String(format: "%.8f", medianNoiseFloor))), speechThreshold=\(String(format: "%.5f", speechThreshold)), ratioThresholdDB=\(String(format: "%.1f", ratioThresholdDB))dB, frames=\(calibrationFrameCount)")

        Task { @MainActor in
            DiarizationDiagnostics.shared.logEnergyGateCalibration(
                noiseFloor: noiseFloor,
                speechThreshold: speechThreshold
            )
        }
    }

    /// Determine if a frame contains local speech based on mic energy and ratio.
    private func detectSpeech(micRMS: Float, systemRMS: Float) -> Bool {
        let speechThreshold = noiseFloor * noiseFloorMultiplier
        guard micRMS > speechThreshold else { return false }

        if systemRMS < systemSilenceThreshold {
            return true
        }

        let ratioDB = energyRatioDB(micRMS: micRMS, systemRMS: systemRMS)
        return ratioDB > ratioThresholdDB
    }

    /// Calculate mic-to-system energy ratio in dB.
    private func energyRatioDB(micRMS: Float, systemRMS: Float) -> Float {
        guard systemRMS > 0 else { return 100.0 }
        return 20.0 * log10(micRMS / systemRMS)
    }
}
