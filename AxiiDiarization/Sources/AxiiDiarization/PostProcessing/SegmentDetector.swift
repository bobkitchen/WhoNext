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
    ///   - offsetThreshold: Probability below which speech offset is detected
    static func detect(
        probabilities: [[Float]],
        frameStep: Double,
        onsetThreshold: Float = 0.4,
        offsetThreshold: Float = 0.6
    ) -> [RawSegment] {
        let numFrames = probabilities.count
        guard numFrames > 0, let numSpeakers = probabilities.first?.count else { return [] }

        var segments: [RawSegment] = []

        for speaker in 0..<numSpeakers {
            var isActive = false
            var segmentStart = 0

            for frame in 0..<numFrames {
                let prob = probabilities[frame][speaker]

                if !isActive && prob >= onsetThreshold {
                    // Speech onset
                    isActive = true
                    segmentStart = frame
                } else if isActive && prob < (1.0 - offsetThreshold) {
                    // Speech offset (note: offset threshold is inverted for hysteresis)
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
