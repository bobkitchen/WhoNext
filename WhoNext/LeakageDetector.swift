import Foundation
import AVFoundation
import Accelerate

/// Detects audio leakage from speakers into the microphone
/// Used to distinguish genuine user speech (ME) from echo/leakage of remote participants
///
/// When users use speakers instead of headphones, the microphone picks up:
/// - User's voice (genuine ME speech)
/// - Echo of system audio played through speakers (leakage)
///
/// This detector uses cross-correlation to identify leakage:
/// - High correlation between mic and delayed system audio = leakage
/// - Low correlation = genuine local speech
@MainActor
class LeakageDetector: ObservableObject {

    // MARK: - Configuration

    /// Sample rate for audio processing
    private let sampleRate: Float = 16000

    /// Duration of system audio to store for correlation (200ms)
    private let bufferDurationSeconds: Float = 0.2

    /// Minimum lag to check (10ms - minimum speaker-to-mic delay)
    private let minLagSeconds: Float = 0.01

    /// Maximum lag to check (100ms - maximum expected room echo)
    private let maxLagSeconds: Float = 0.1

    /// Step size for lag search (10ms)
    private let lagStepSeconds: Float = 0.01

    /// Correlation threshold: above this = leakage, below = genuine speech
    /// 0.5 is conservative; may need tuning based on environment
    @Published var leakageThreshold: Float = 0.5

    /// Minimum mic energy to consider as potential speech (prevents noise triggering)
    @Published var micEnergyThreshold: Float = 0.01

    /// Energy ratio threshold: mic must be significantly louder than expected leakage
    /// If mic energy is very high relative to system, more likely genuine speech
    @Published var energyRatioThreshold: Float = 2.0

    // MARK: - State

    /// Ring buffer storing recent system audio samples
    private var systemAudioBuffer: RingBuffer<Float>

    /// Current leakage level (0 = no leakage, 1 = pure leakage)
    @Published private(set) var currentLeakageLevel: Float = 0

    /// Whether we're currently detecting leakage
    @Published private(set) var isLeakageDetected: Bool = false

    /// Statistics for debugging/tuning
    @Published private(set) var stats = LeakageStats()

    // MARK: - Computed Properties

    private var bufferCapacity: Int {
        Int(bufferDurationSeconds * sampleRate)
    }

    private var minLagSamples: Int {
        Int(minLagSeconds * sampleRate)
    }

    private var maxLagSamples: Int {
        Int(maxLagSeconds * sampleRate)
    }

    private var lagStepSamples: Int {
        Int(lagStepSeconds * sampleRate)
    }

    // MARK: - Initialization

    init() {
        self.systemAudioBuffer = RingBuffer<Float>(capacity: Int(0.3 * 16000)) // 300ms buffer
    }

    // MARK: - Public Methods

    /// Process system audio to update the reference buffer
    /// Call this for each system audio buffer received
    /// - Parameter buffer: System audio buffer (should be 16kHz mono)
    func processSystemAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength)
        ))

        systemAudioBuffer.append(contentsOf: samples)
    }

    /// Process system audio from raw float samples
    /// - Parameter samples: Array of float samples at 16kHz
    func processSystemAudio(_ samples: [Float]) {
        systemAudioBuffer.append(contentsOf: samples)
    }

    /// Detect if mic audio is genuine speech or leakage from speakers
    /// - Parameters:
    ///   - micBuffer: Microphone audio buffer
    ///   - systemLevel: Current system audio energy level (for energy ratio check)
    /// - Returns: Detection result indicating if this is genuine ME speech
    func detectGenuineSpeech(_ micBuffer: AVAudioPCMBuffer,
                              systemLevel: Float = 0) -> MEDetectionResult {
        guard let channelData = micBuffer.floatChannelData else {
            return MEDetectionResult(isGenuineME: false, confidence: 0, reason: .noAudio)
        }

        let micSamples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(micBuffer.frameLength)
        ))

        return detectGenuineSpeech(micSamples, systemLevel: systemLevel)
    }

    /// Detect if mic audio is genuine speech or leakage from speakers
    /// - Parameters:
    ///   - micSamples: Microphone audio samples at 16kHz
    ///   - systemLevel: Current system audio energy level
    /// - Returns: Detection result indicating if this is genuine ME speech
    func detectGenuineSpeech(_ micSamples: [Float],
                              systemLevel: Float = 0) -> MEDetectionResult {

        // Step 1: Check mic energy
        let micEnergy = calculateRMSEnergy(micSamples)

        guard micEnergy > micEnergyThreshold else {
            stats.silenceFrames += 1
            return MEDetectionResult(isGenuineME: false, confidence: 1.0, reason: .noSpeech)
        }

        stats.speechFrames += 1

        // Step 2: Check if we have enough system audio to correlate
        guard systemAudioBuffer.count >= micSamples.count + maxLagSamples else {
            // Not enough system audio yet, assume genuine (conservative)
            stats.assumedGenuineFrames += 1
            return MEDetectionResult(isGenuineME: true, confidence: 0.5, reason: .insufficientReference)
        }

        // Step 3: Calculate cross-correlation at multiple lags
        let correlationResult = findMaxCorrelation(micSamples)
        currentLeakageLevel = correlationResult.maxCorrelation

        // Step 4: Energy ratio check (additional heuristic)
        // If mic is much louder than system, more likely genuine
        let energyRatio = systemLevel > 0 ? micEnergy / systemLevel : Float.infinity
        let hasHighEnergyRatio = energyRatio > energyRatioThreshold

        // Step 5: Determine if genuine speech
        let isLeakage = correlationResult.maxCorrelation > leakageThreshold && !hasHighEnergyRatio
        isLeakageDetected = isLeakage

        if isLeakage {
            stats.leakageFrames += 1
            return MEDetectionResult(
                isGenuineME: false,
                confidence: correlationResult.maxCorrelation,
                reason: .leakageDetected,
                bestLag: correlationResult.bestLag,
                correlation: correlationResult.maxCorrelation
            )
        } else {
            stats.genuineFrames += 1
            return MEDetectionResult(
                isGenuineME: true,
                confidence: 1.0 - correlationResult.maxCorrelation,
                reason: hasHighEnergyRatio ? .highEnergyRatio : .lowCorrelation,
                bestLag: correlationResult.bestLag,
                correlation: correlationResult.maxCorrelation
            )
        }
    }

    /// Reset the detector state
    func reset() {
        systemAudioBuffer.clear()
        currentLeakageLevel = 0
        isLeakageDetected = false
        stats = LeakageStats()
    }

    // MARK: - Private Methods

    /// Find the maximum correlation between mic and system audio across lag range
    private func findMaxCorrelation(_ micSamples: [Float]) -> (maxCorrelation: Float, bestLag: Int) {
        var maxCorrelation: Float = 0
        var bestLag: Int = 0

        // Get system audio samples (need mic length + max lag)
        let systemSamples = systemAudioBuffer.lastN(micSamples.count + maxLagSamples)

        for lag in stride(from: minLagSamples, through: maxLagSamples, by: lagStepSamples) {
            let correlation = calculateNormalizedCorrelation(
                micSamples: micSamples,
                systemSamples: systemSamples,
                lag: lag
            )

            if abs(correlation) > abs(maxCorrelation) {
                maxCorrelation = abs(correlation)
                bestLag = lag
            }
        }

        return (maxCorrelation, bestLag)
    }

    /// Calculate normalized cross-correlation at a specific lag
    private func calculateNormalizedCorrelation(micSamples: [Float],
                                                  systemSamples: [Float],
                                                  lag: Int) -> Float {
        // Align: mic[t] correlates with system[t - lag]
        // Since system is older audio, we compare mic with earlier system samples
        let systemStartIdx = systemSamples.count - micSamples.count - lag
        guard systemStartIdx >= 0 else { return 0 }

        let alignedSystem = Array(systemSamples[systemStartIdx..<(systemStartIdx + micSamples.count)])
        guard alignedSystem.count == micSamples.count else { return 0 }

        // Normalized cross-correlation using vDSP
        var dotProduct: Float = 0
        var micEnergy: Float = 0
        var sysEnergy: Float = 0

        vDSP_dotpr(micSamples, 1, alignedSystem, 1, &dotProduct, vDSP_Length(micSamples.count))
        vDSP_svesq(micSamples, 1, &micEnergy, vDSP_Length(micSamples.count))
        vDSP_svesq(alignedSystem, 1, &sysEnergy, vDSP_Length(alignedSystem.count))

        let denominator = sqrt(micEnergy * sysEnergy)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Calculate RMS energy of audio samples
    private func calculateRMSEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))

        return sqrt(sumSquares / Float(samples.count))
    }
}

// MARK: - Supporting Types

/// Result of ME (user) speech detection
struct MEDetectionResult {
    /// Whether this is genuine user speech (not leakage)
    let isGenuineME: Bool

    /// Confidence in the detection (0-1)
    let confidence: Float

    /// Reason for the detection result
    let reason: DetectionReason

    /// Best correlation lag found (in samples)
    var bestLag: Int = 0

    /// Maximum correlation value found
    var correlation: Float = 0

    enum DetectionReason {
        case noAudio              // No mic data
        case noSpeech             // Mic energy below threshold
        case insufficientReference // Not enough system audio to compare
        case leakageDetected      // High correlation with system audio
        case lowCorrelation       // Low correlation = genuine speech
        case highEnergyRatio      // Mic much louder than system = genuine
    }

    /// Best lag in milliseconds
    var bestLagMs: Float {
        Float(bestLag) / 16.0  // 16 samples per ms at 16kHz
    }
}

/// Statistics for debugging and tuning
struct LeakageStats {
    var silenceFrames: Int = 0
    var speechFrames: Int = 0
    var leakageFrames: Int = 0
    var genuineFrames: Int = 0
    var assumedGenuineFrames: Int = 0

    var leakageRate: Float {
        guard speechFrames > 0 else { return 0 }
        return Float(leakageFrames) / Float(speechFrames)
    }

    var genuineRate: Float {
        guard speechFrames > 0 else { return 0 }
        return Float(genuineFrames) / Float(speechFrames)
    }
}
