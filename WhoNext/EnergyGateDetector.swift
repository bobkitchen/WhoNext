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
    /// 10dB (~3.2x amplitude) reduces false positives from VoIP bleed vs the old 5dB.
    let ratioThresholdDB: Float

    /// Number of samples per frame (30ms at 16kHz = 480 samples)
    private let frameSamples = 480

    /// Number of frames for sliding window smoothing (120ms = 4 frames at 30ms)
    private let smoothingWindowSize = 4

    /// Number of hangover frames (90ms = 3 frames at 30ms)
    private let hangoverFrames = 3

    /// Noise floor calibration duration in seconds
    private let calibrationDuration: TimeInterval = 2.0

    /// System RMS below this is considered silence
    private let systemSilenceThreshold: Float = 0.001

    /// Multiplier above noise floor for speech detection
    private let noiseFloorMultiplier: Float = 2.0

    /// Absolute minimum noise floor to prevent hair-trigger detection
    /// when calibrating in silence (-60 dBFS)
    private let absoluteMinimumNoiseFloor: Float = 0.001

    /// Minimum segment duration in seconds — segments shorter than this are dropped
    private let minimumSegmentDuration: Float = 0.2

    // MARK: - State

    /// Adaptive noise floor (calibrated from first 2s)
    private var noiseFloor: Float = 0
    private var isCalibrated = false
    private var calibrationSamples: [Float] = []
    private var calibrationFrameCount = 0
    private let calibrationFramesNeeded: Int

    /// Sliding window of speech/silence decisions for smoothing
    private var smoothingWindow: [Bool] = []

    /// Hangover counter — frames remaining before allowing transition to silence
    private var hangoverCounter = 0

    /// Current speech state after smoothing + hangover
    private var isSpeaking = false

    /// Tracking for segment generation
    private var speechStartTime: TimeInterval?

    /// Frame counter for periodic ratio logging (~1s interval)
    private var logCounter = 0
    private let logInterval: Int

    // MARK: - Init

    /// - Parameter ratioThresholdDB: Mic-to-system energy ratio threshold in dB (default 10dB).
    init(ratioThresholdDB: Float = 10.0) {
        self.ratioThresholdDB = ratioThresholdDB
        self.calibrationFramesNeeded = Int(calibrationDuration * 16000.0 / Double(frameSamples))
        self.logInterval = Int(1.0 * 16000.0 / Double(frameSamples))
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

            // Periodic ratio logging for calibration data
            logCounter += 1
            if logCounter >= logInterval {
                logCounter = 0
                let ratioDB = energyRatioDB(micRMS: micRMS, systemRMS: systemRMS)
                debugLog("[EnergyGate] ratio: \(String(format: "%.1f", ratioDB))dB  mic: \(String(format: "%.5f", micRMS))  sys: \(String(format: "%.5f", systemRMS))  speaking: \(isSpeaking)")
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
                let ratioDB = energyRatioDB(micRMS: micRMS, systemRMS: systemRMS)
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
