import Foundation
import Accelerate

/// A thread-safe ring buffer for storing audio samples
/// Used for leakage detection: stores recent system audio to compare against mic input
final class RingBuffer<T> {
    private var buffer: [T]
    private var writeIndex: Int = 0
    private var isFull: Bool = false
    private let capacity: Int
    private let lock = NSLock()

    /// Initialize with a fixed capacity
    /// - Parameter capacity: Maximum number of elements to store
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }

    /// Current number of elements in the buffer
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return isFull ? capacity : writeIndex
    }

    /// Whether the buffer is empty
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return writeIndex == 0 && !isFull
    }

    /// Append a single element to the buffer
    /// - Parameter element: Element to append
    func append(_ element: T) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(element)
        } else {
            buffer[writeIndex] = element
        }

        writeIndex = (writeIndex + 1) % capacity
        if writeIndex == 0 && buffer.count == capacity {
            isFull = true
        }
    }

    /// Append multiple elements to the buffer
    /// - Parameter elements: Array of elements to append
    func append(contentsOf elements: [T]) {
        lock.lock()
        defer { lock.unlock() }

        for element in elements {
            if buffer.count < capacity {
                buffer.append(element)
            } else {
                buffer[writeIndex] = element
            }
            writeIndex = (writeIndex + 1) % capacity
        }

        if buffer.count == capacity {
            isFull = true
        }
    }

    /// Get the last N elements in chronological order
    /// - Parameter n: Number of elements to retrieve
    /// - Returns: Array of the last N elements, or fewer if buffer doesn't have N elements
    func lastN(_ n: Int) -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let currentCount = isFull ? capacity : writeIndex
        let actualN = min(n, currentCount)

        guard actualN > 0 else { return [] }

        var result: [T] = []
        result.reserveCapacity(actualN)

        // Calculate start index for reading
        let startIndex: Int
        if isFull {
            // Buffer is full, writeIndex points to oldest element
            // We want the last N elements, so start from (writeIndex - actualN + capacity) % capacity
            startIndex = (writeIndex - actualN + capacity) % capacity
        } else {
            // Buffer not full, elements are from 0 to writeIndex-1
            startIndex = max(0, writeIndex - actualN)
        }

        // Read in chronological order
        for i in 0..<actualN {
            let index = (startIndex + i) % capacity
            result.append(buffer[index])
        }

        return result
    }

    /// Get all elements in chronological order
    /// - Returns: Array of all elements in order
    func allElements() -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let currentCount = isFull ? capacity : writeIndex
        guard currentCount > 0 else { return [] }

        if !isFull {
            // Elements are in order from 0 to writeIndex-1
            return Array(buffer[0..<writeIndex])
        } else {
            // Buffer is full, need to reorder
            var result: [T] = []
            result.reserveCapacity(capacity)

            // Oldest is at writeIndex, go around
            for i in 0..<capacity {
                let index = (writeIndex + i) % capacity
                result.append(buffer[index])
            }
            return result
        }
    }

    /// Clear all elements from the buffer
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        isFull = false
    }
}

// MARK: - Float-specific extensions for audio processing

extension RingBuffer where T == Float {

    /// Get the RMS (root mean square) level of recent samples
    /// - Parameter sampleCount: Number of samples to analyze
    /// - Returns: RMS level (0.0 to ~1.0 for normalized audio)
    func rmsLevel(sampleCount: Int) -> Float {
        let samples = lastN(sampleCount)
        guard !samples.isEmpty else { return 0 }

        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return sqrt(sumSquares / Float(samples.count))
    }

    /// Cross-correlate with another signal at a given lag
    /// - Parameters:
    ///   - other: Signal to correlate with
    ///   - lag: Number of samples to delay `other` (positive = other is delayed)
    /// - Returns: Normalized correlation coefficient (-1 to 1)
    func crossCorrelation(with other: [Float], lag: Int) -> Float {
        let ourSamples = lastN(other.count + abs(lag))
        guard ourSamples.count >= other.count else { return 0 }

        // Align samples based on lag
        let ourSlice: [Float]
        let otherSlice: [Float]

        if lag >= 0 {
            // Our signal leads, compare our[lag:] with other[:]
            let startIdx = min(lag, ourSamples.count - 1)
            let endIdx = min(startIdx + other.count, ourSamples.count)
            ourSlice = Array(ourSamples[startIdx..<endIdx])
            otherSlice = Array(other.prefix(ourSlice.count))
        } else {
            // Other signal leads
            let absLag = abs(lag)
            let startIdx = min(absLag, other.count - 1)
            let endIdx = min(startIdx + ourSamples.count, other.count)
            otherSlice = Array(other[startIdx..<endIdx])
            ourSlice = Array(ourSamples.prefix(otherSlice.count))
        }

        guard ourSlice.count > 0 && ourSlice.count == otherSlice.count else { return 0 }

        // Calculate normalized cross-correlation using vDSP
        var dotProduct: Float = 0
        var ourEnergy: Float = 0
        var otherEnergy: Float = 0

        vDSP_dotpr(ourSlice, 1, otherSlice, 1, &dotProduct, vDSP_Length(ourSlice.count))
        vDSP_svesq(ourSlice, 1, &ourEnergy, vDSP_Length(ourSlice.count))
        vDSP_svesq(otherSlice, 1, &otherEnergy, vDSP_Length(otherSlice.count))

        let denominator = sqrt(ourEnergy * otherEnergy)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
