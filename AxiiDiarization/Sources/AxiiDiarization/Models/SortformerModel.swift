import CoreML
import Foundation

/// CoreML wrapper for Sortformer v2.1 speaker segmentation model.
///
/// Actual model I/O (inspected from .mlpackage):
///   Input:  `mel_features` shape `[4, 128, 1024]` — batch=4, 128 mel bins, 1024 frames
///   Input:  `mel_length` shape `[4]` — actual frame count per batch item
///   Output: `speaker_probs` shape `[4, 128, 4]` — 128 output frames, 4 speaker channels
///
/// The model expects a fixed window of 1024 mel frames (~10.24s at hop=160/SR=16k).
/// We pad shorter inputs and use mel_length to indicate actual length.
final class SortformerModel {

    private let model: MLModel

    /// Fixed input size expected by the model
    static let maxInputFrames = 1024
    /// Output frames per window
    static let outputFrames = 128
    /// Downsampling factor: 1024 input → 128 output
    static let downsampleFactor = 8
    /// Batch size the model was compiled with
    static let batchSize = 4

    init(modelURL: URL, configuration: MLModelConfiguration) throws {
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    /// Run inference on mel spectrogram frames.
    /// - Parameter melFrames: Array of [128] vectors, one per time frame
    /// - Returns: Array of [4] probability vectors (sigmoid-activated), one per output frame
    func predict(melFrames: [[Float]]) throws -> [[Float]] {
        let numMelBins = MelSpectrogram.numMelBins  // 128
        let numSpeakers = 4
        let maxFrames = Self.maxInputFrames
        let batchSize = Self.batchSize

        let actualFrames = min(melFrames.count, maxFrames)
        guard actualFrames > 0 else { return [] }

        // Build input: mel_features [4, 128, 1024]
        // We use batch slot 0 only; rest are zero-padded
        let melShape: [NSNumber] = [NSNumber(value: batchSize), NSNumber(value: numMelBins), NSNumber(value: maxFrames)]
        let melInput = try MLMultiArray(shape: melShape, dataType: .float32)

        let melPtr = melInput.dataPointer.assumingMemoryBound(to: Float.self)
        // Zero-fill (already zero from MLMultiArray init, but be safe)
        let totalMelElements = batchSize * numMelBins * maxFrames
        memset(melPtr, 0, totalMelElements * MemoryLayout<Float>.size)

        // Fill batch slot 0: layout [batch][bin][frame]
        let frameStride = maxFrames
        for t in 0..<actualFrames {
            for b in 0..<numMelBins {
                melPtr[b * frameStride + t] = melFrames[t][b]
            }
        }

        // Build input: mel_length [4]
        let lengthInput = try MLMultiArray(shape: [NSNumber(value: batchSize)], dataType: .int32)
        let lengthPtr = lengthInput.dataPointer.assumingMemoryBound(to: Int32.self)
        lengthPtr[0] = Int32(actualFrames)
        for i in 1..<batchSize {
            lengthPtr[i] = 0
        }

        // Run inference
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "mel_features": MLFeatureValue(multiArray: melInput),
            "mel_length": MLFeatureValue(multiArray: lengthInput)
        ])

        let prediction = try model.prediction(from: provider)

        guard let outputValue = prediction.featureValue(for: "speaker_probs"),
              let outputArray = outputValue.multiArrayValue else {
            throw AxiiModelError.invalidOutput("No output array for key 'speaker_probs'")
        }

        // Parse output [4, 128, 4] — take batch slot 0 only
        return parseOutput(outputArray, actualFrames: actualFrames, numSpeakers: numSpeakers)
    }

    /// Parse output: extract batch 0, apply sigmoid, return [outputFrames][4]
    private func parseOutput(_ array: MLMultiArray, actualFrames: Int, numSpeakers: Int) -> [[Float]] {
        let shape = array.shape.map { $0.intValue }
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)

        // Output shape: [batchSize, 128, 4]
        let outFrames = shape.count >= 2 ? shape[1] : Self.outputFrames
        let outSpeakers = shape.count >= 3 ? shape[2] : numSpeakers

        // Calculate how many output frames correspond to actual input
        let validOutputFrames = min(outFrames, (actualFrames + Self.downsampleFactor - 1) / Self.downsampleFactor)

        var frames: [[Float]] = []
        frames.reserveCapacity(validOutputFrames)

        let batchStride = outFrames * outSpeakers  // stride between batch items
        for t in 0..<validOutputFrames {
            var frame = [Float](repeating: 0, count: numSpeakers)
            for s in 0..<min(outSpeakers, numSpeakers) {
                let raw = ptr[0 * batchStride + t * outSpeakers + s]  // batch 0
                frame[s] = sigmoid(raw)
            }
            frames.append(frame)
        }

        return frames
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}

enum AxiiModelError: LocalizedError {
    case invalidOutput(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput(let msg): return "Model output error: \(msg)"
        case .invalidInput(let msg): return "Model input error: \(msg)"
        }
    }
}
