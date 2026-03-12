import CoreML
import Accelerate
import Foundation

/// CoreML wrapper for WeSpeaker ResNet34 speaker embedding model.
///
/// Actual model I/O (inspected from .mlpackage):
///   Input:  `fbank_features` shape `[1, 80, 300]` — 80 fbank bins, 300 frames
///   Input:  `mel_length` shape `[1]` — actual frame count
///   Output: `embedding` shape `[1, 256]` — 256-dim speaker embedding
///
/// The model expects a fixed 300-frame window. Shorter inputs are zero-padded.
final class WeSpeakerModel {

    private let model: MLModel

    /// Fixed input size expected by the model
    static let maxInputFrames = 300

    init(modelURL: URL, configuration: MLModelConfiguration) throws {
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    /// Run inference on fbank feature frames.
    /// - Parameter fbankFrames: Array of [80] vectors, one per time frame
    /// - Returns: L2-normalized 256-dim embedding vector
    func predict(fbankFrames: [[Float]]) throws -> [Float] {
        let numBins = FbankFeatures.numBins  // 80
        let maxFrames = Self.maxInputFrames

        let actualFrames = min(fbankFrames.count, maxFrames)
        guard actualFrames > 0 else { throw AxiiModelError.invalidInput("Empty fbank frames") }

        // Build input: fbank_features [1, 80, 300]
        let fbankShape: [NSNumber] = [1, NSNumber(value: numBins), NSNumber(value: maxFrames)]
        let fbankInput = try MLMultiArray(shape: fbankShape, dataType: .float32)

        let ptr = fbankInput.dataPointer.assumingMemoryBound(to: Float.self)
        let totalElements = numBins * maxFrames
        memset(ptr, 0, totalElements * MemoryLayout<Float>.size)

        // Fill: layout [1][bin][frame]
        for t in 0..<actualFrames {
            for b in 0..<numBins {
                ptr[b * maxFrames + t] = fbankFrames[t][b]
            }
        }

        // Build input: mel_length [1]
        let lengthInput = try MLMultiArray(shape: [1], dataType: .int32)
        lengthInput.dataPointer.assumingMemoryBound(to: Int32.self)[0] = Int32(actualFrames)

        // Run inference
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "fbank_features": MLFeatureValue(multiArray: fbankInput),
            "mel_length": MLFeatureValue(multiArray: lengthInput)
        ])

        let prediction = try model.prediction(from: provider)

        guard let outputValue = prediction.featureValue(for: "embedding"),
              let outputArray = outputValue.multiArrayValue else {
            throw AxiiModelError.invalidOutput("No output array for key 'embedding'")
        }

        return parseEmbedding(outputArray)
    }

    /// Parse output to a flat Float vector, then L2-normalize.
    private func parseEmbedding(_ array: MLMultiArray) -> [Float] {
        let shape = array.shape.map { $0.intValue }
        let totalCount = shape.reduce(1, *)
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)

        let embDim: Int
        if shape.count == 2 {
            embDim = shape[1]  // [1, 256]
        } else if shape.count == 1 {
            embDim = shape[0]  // [256]
        } else {
            embDim = totalCount
        }

        var embedding = [Float](repeating: 0, count: embDim)
        for i in 0..<embDim {
            embedding[i] = ptr[i]
        }

        // L2 normalize
        var norm: Float = 0
        vDSP_dotpr(embedding, 1, embedding, 1, &norm, vDSP_Length(embDim))
        norm = sqrt(norm)
        if norm > 0 {
            vDSP_vsdiv(embedding, 1, &norm, &embedding, 1, vDSP_Length(embDim))
        }

        return embedding
    }
}
