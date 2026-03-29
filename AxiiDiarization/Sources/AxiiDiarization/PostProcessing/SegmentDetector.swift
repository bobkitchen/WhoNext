import Foundation

/// Converts Sortformer sigmoid output to discrete speaker activity segments
/// using hysteresis thresholding.
enum SegmentDetector {

    struct RawSegment {
        let speakerChannel: Int
        let startFrame: Int
        let endFrame: Int
        let startTime: Double
        let endTime: Double
    }

    /// Detect speaker segments from per-frame probabilities.
    /// - Parameters:
    ///   - probabilities: Array of [4] probability vectors per frame
    ///   - frameStep: Time duration of each frame in seconds
    ///   - onsetThreshold: Probability above which speech onset is detected
    ///   - offsetThreshold: Probability below which speech offset is detected (should be > onset for hysteresis)
    static func detect(
        probabilities: [[Float]],
        frameStep: Double,
        onsetThreshold: Float = 0.25,
        offsetThreshold: Float = 0.65
    ) -> [RawSegment] {
        let numFrames = probabilities.count
        guard numFrames > 0, let numSpeakers = probabilities.first?.count else { return [] }

        var segments: [RawSegment] = []

        // Proper hysteresis: onset at low threshold, offset at higher threshold.
        // Once active, stays active until prob drops below (1.0 - offsetThreshold).
        // onset=0.25: start detecting when prob >= 0.25
        // offset=0.65: stop detecting when prob < (1.0 - 0.65) = 0.35
        // This creates a hysteresis band: [0.25, 0.35] where state doesn't change.
        let offsetLevel = 1.0 - offsetThreshold  // = 0.35

        for speaker in 0..<numSpeakers {
            var isActive = false
            var segmentStart = 0

            for frame in 0..<numFrames {
                let prob = probabilities[frame][speaker]

                if !isActive && prob >= onsetThreshold {
                    // Speech onset
                    isActive = true
                    segmentStart = frame
                } else if isActive && prob < offsetLevel {
                    // Speech offset — requires prob to drop below offsetLevel (0.35)
                    // This is HIGHER than onset (0.25), creating true hysteresis
                    isActive = false
                    segments.append(RawSegment(
                        speakerChannel: speaker,
                        startFrame: segmentStart,
                        endFrame: frame,
                        startTime: Double(segmentStart) * frameStep,
                        endTime: Double(frame) * frameStep
                    ))
                }
            }

            // Close any open segment at end
            if isActive {
                segments.append(RawSegment(
                    speakerChannel: speaker,
                    startFrame: segmentStart,
                    endFrame: numFrames,
                    startTime: Double(segmentStart) * frameStep,
                    endTime: Double(numFrames) * frameStep
                ))
            }
        }

        // Sort by start time
        return segments.sorted { $0.startTime < $1.startTime }
    }
}
