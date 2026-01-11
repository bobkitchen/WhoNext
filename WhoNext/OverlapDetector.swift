import Foundation
import AVFoundation

/// Detects overlapping speech (when multiple people speak simultaneously)
/// Used to:
/// 1. Protect centroids from being poisoned by mixed-speaker audio
/// 2. Mark segments with overlap metadata for downstream processing
/// 3. Track overlap statistics for meeting analysis
class OverlapDetector {

    // MARK: - Configuration

    /// Threshold for considering audio as active speech
    private let speechThreshold: Float

    /// Minimum overlap duration (seconds) to count as overlap
    private let minOverlapDuration: Float

    /// Sample rate for audio processing
    private let sampleRate: Float = 16000

    // MARK: - State

    /// Current overlap state
    private(set) var isOverlapDetected: Bool = false

    /// Duration of current overlap (seconds)
    private(set) var currentOverlapDuration: Float = 0

    /// Statistics
    private(set) var stats = OverlapStats()

    // MARK: - Initialization

    init(speechThreshold: Float = 0.02, minOverlapDuration: Float = 0.3) {
        self.speechThreshold = speechThreshold
        self.minOverlapDuration = minOverlapDuration
    }

    // MARK: - Public Methods

    /// Detect overlap between mic and system audio
    /// - Parameters:
    ///   - micLevel: RMS level of microphone audio
    ///   - systemLevel: RMS level of system audio
    /// - Returns: True if overlap is detected
    func detectOverlap(micLevel: Float, systemLevel: Float) -> Bool {
        let micActive = micLevel > speechThreshold
        let systemActive = systemLevel > speechThreshold

        let wasOverlapping = isOverlapDetected
        isOverlapDetected = micActive && systemActive

        if isOverlapDetected {
            stats.overlapFrames += 1
            if !wasOverlapping {
                stats.overlapEvents += 1
            }
        }

        stats.totalFrames += 1

        return isOverlapDetected
    }

    /// Detect overlap from audio buffers
    /// - Parameters:
    ///   - micBuffer: Microphone audio buffer
    ///   - systemBuffer: System audio buffer
    /// - Returns: Overlap detection result with details
    func detectOverlap(micBuffer: AVAudioPCMBuffer?, systemBuffer: AVAudioPCMBuffer?) -> OverlapResult {
        let micLevel = calculateRMSLevel(micBuffer)
        let systemLevel = calculateRMSLevel(systemBuffer)

        let hasOverlap = detectOverlap(micLevel: micLevel, systemLevel: systemLevel)

        // Estimate overlap ratio based on energy
        let overlapRatio: Float
        if micLevel > 0 && systemLevel > 0 {
            let minLevel = min(micLevel, systemLevel)
            let maxLevel = max(micLevel, systemLevel)
            overlapRatio = minLevel / maxLevel
        } else {
            overlapRatio = 0
        }

        return OverlapResult(
            isOverlapping: hasOverlap,
            micLevel: micLevel,
            systemLevel: systemLevel,
            overlapRatio: overlapRatio
        )
    }

    /// Check if a time range has overlap based on tracked segments
    /// - Parameters:
    ///   - segments: All speaker segments
    ///   - startTime: Start of range to check
    ///   - endTime: End of range to check
    /// - Returns: True if any overlap exists in the range
    func hasOverlapInRange(segments: [(speakerId: String, startTime: Float, endTime: Float)],
                           startTime: Float, endTime: Float) -> Bool {
        // Find all segments that overlap with our range
        let overlapping = segments.filter { segment in
            segment.startTime < endTime && segment.endTime > startTime
        }

        // Check if any two segments from different speakers overlap
        for i in 0..<overlapping.count {
            for j in (i+1)..<overlapping.count {
                if overlapping[i].speakerId != overlapping[j].speakerId {
                    // Check if these two segments overlap in time
                    let overlap = min(overlapping[i].endTime, overlapping[j].endTime) -
                                  max(overlapping[i].startTime, overlapping[j].startTime)
                    if overlap > minOverlapDuration {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Reset detector state
    func reset() {
        isOverlapDetected = false
        currentOverlapDuration = 0
        stats = OverlapStats()
    }

    // MARK: - Private Methods

    private func calculateRMSLevel(_ buffer: AVAudioPCMBuffer?) -> Float {
        guard let buffer = buffer,
              let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        let samples = channelData[0]

        for i in 0..<frameLength {
            let sample = samples[i]
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameLength))
    }
}

// MARK: - Supporting Types

struct OverlapResult {
    let isOverlapping: Bool
    let micLevel: Float
    let systemLevel: Float
    let overlapRatio: Float  // 0-1, how balanced the overlap is

    var description: String {
        if isOverlapping {
            return "Overlap detected (mic: \(String(format: "%.3f", micLevel)), sys: \(String(format: "%.3f", systemLevel)), ratio: \(String(format: "%.2f", overlapRatio)))"
        } else {
            return "No overlap"
        }
    }
}

struct OverlapStats {
    var totalFrames: Int = 0
    var overlapFrames: Int = 0
    var overlapEvents: Int = 0  // Number of distinct overlap periods

    var overlapRate: Float {
        totalFrames > 0 ? Float(overlapFrames) / Float(totalFrames) : 0
    }

    var description: String {
        """
        Overlap Stats:
        - Total frames: \(totalFrames)
        - Overlap frames: \(overlapFrames) (\(Int(overlapRate * 100))%)
        - Overlap events: \(overlapEvents)
        """
    }
}
