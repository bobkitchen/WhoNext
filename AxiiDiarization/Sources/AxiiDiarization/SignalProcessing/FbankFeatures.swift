import Accelerate
import Foundation

/// Computes 80-bin filterbank features for WeSpeaker embedding extraction.
///
/// Parameters: SR=16kHz, FFT=400, hop=160, 80 bins, cepstral mean normalization.
enum FbankFeatures {

    static let fftSize = 400
    static let hopSize = 160
    static let numBins = 80
    static let fMinHz: Double = 20.0
    static let fMaxHz: Double = 7600.0

    /// Compute fbank feature frames with cepstral mean normalization.
    /// Returns array of [numBins] vectors, one per frame.
    static func compute(_ audio: [Float], sampleRate: Double = 16000.0) -> [[Float]] {
        let n = audio.count
        guard n >= fftSize else { return [] }

        let nfft = 512
        let log2n = vDSP_Length(log2(Double(nfft)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Hanning window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let numFreqBins = nfft / 2 + 1
        let melBank = buildMelFilterbank(
            numBins: numBins,
            numFreqBins: numFreqBins,
            sampleRate: sampleRate,
            fMin: fMinHz,
            fMax: fMaxHz
        )

        let numFrames = max(0, (n - fftSize) / hopSize + 1)
        var frames: [[Float]] = []
        frames.reserveCapacity(numFrames)

        var paddedFrame = [Float](repeating: 0, count: nfft)
        var windowedFrame = [Float](repeating: 0, count: fftSize)

        for i in 0..<numFrames {
            let start = i * hopSize

            vDSP_vmul(
                Array(audio[start..<(start + fftSize)]), 1,
                window, 1,
                &windowedFrame, 1,
                vDSP_Length(fftSize)
            )

            paddedFrame = [Float](repeating: 0, count: nfft)
            for j in 0..<fftSize {
                paddedFrame[j] = windowedFrame[j]
            }

            var realPart = [Float](repeating: 0, count: nfft / 2)
            var imagPart = [Float](repeating: 0, count: nfft / 2)

            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    paddedFrame.withUnsafeBufferPointer { buf in
                        buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: nfft / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(nfft / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }

            var powerSpectrum = [Float](repeating: 0, count: numFreqBins)
            for k in 0..<(nfft / 2) {
                powerSpectrum[k] = realPart[k] * realPart[k] + imagPart[k] * imagPart[k]
            }
            powerSpectrum[0] = realPart[0] * realPart[0]
            if numFreqBins > nfft / 2 {
                powerSpectrum[nfft / 2] = imagPart[0] * imagPart[0]
            }

            var scale = Float(1.0 / Float(nfft))
            vDSP_vsmul(powerSpectrum, 1, &scale, &powerSpectrum, 1, vDSP_Length(numFreqBins))

            // Apply mel filterbank
            var fbankFrame = [Float](repeating: 0, count: numBins)
            for m in 0..<numBins {
                var dot: Float = 0
                vDSP_dotpr(
                    melBank[m], 1,
                    powerSpectrum, 1,
                    &dot,
                    vDSP_Length(numFreqBins)
                )
                fbankFrame[m] = log(max(dot, 1e-10))
            }

            frames.append(fbankFrame)
        }

        // Cepstral mean normalization
        guard !frames.isEmpty else { return [] }
        var mean = [Float](repeating: 0, count: numBins)
        for frame in frames {
            for i in 0..<numBins {
                mean[i] += frame[i]
            }
        }
        let count = Float(frames.count)
        for i in 0..<numBins {
            mean[i] /= count
        }
        for f in 0..<frames.count {
            for i in 0..<numBins {
                frames[f][i] -= mean[i]
            }
        }

        return frames
    }

    // MARK: - Mel Filterbank

    private static func hzToMel(_ hz: Double) -> Double {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    private static func melToHz(_ mel: Double) -> Double {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    private static func buildMelFilterbank(
        numBins: Int,
        numFreqBins: Int,
        sampleRate: Double,
        fMin: Double,
        fMax: Double
    ) -> [[Float]] {
        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)
        let melStep = (melMax - melMin) / Double(numBins + 1)

        var melPoints = [Double](repeating: 0, count: numBins + 2)
        for i in 0..<(numBins + 2) {
            melPoints[i] = melMin + Double(i) * melStep
        }

        let fftBins = melPoints.map { mel -> Double in
            let hz = melToHz(mel)
            return hz * Double(numFreqBins - 1) * 2.0 / sampleRate
        }

        var filterbank = [[Float]](repeating: [Float](repeating: 0, count: numFreqBins), count: numBins)

        for m in 0..<numBins {
            let left = fftBins[m]
            let center = fftBins[m + 1]
            let right = fftBins[m + 2]

            for k in 0..<numFreqBins {
                let freq = Double(k)
                if freq >= left && freq <= center && center > left {
                    filterbank[m][k] = Float((freq - left) / (center - left))
                } else if freq > center && freq <= right && right > center {
                    filterbank[m][k] = Float((right - freq) / (right - center))
                }
            }
        }

        return filterbank
    }
}
