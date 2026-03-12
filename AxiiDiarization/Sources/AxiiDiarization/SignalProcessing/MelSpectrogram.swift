import Accelerate
import Foundation

/// Computes 128-bin log-mel spectrogram from raw 16 kHz audio using Accelerate/vDSP.
///
/// Parameters: SR=16kHz, FFT=400 (25ms), hop=160 (10ms), 128 mel bins, 0–8kHz, log scale.
enum MelSpectrogram {

    static let fftSize = 400
    static let hopSize = 160
    static let numMelBins = 128
    static let sampleRate: Double = 16000.0
    static let fMinHz: Double = 0.0
    static let fMaxHz: Double = 8000.0

    /// Compute mel spectrogram frames. Returns array of [numMelBins] vectors, one per frame.
    static func compute(_ audio: [Float], sampleRate: Double = 16000.0) -> [[Float]] {
        let n = audio.count
        guard n >= fftSize else { return [] }

        // Use power-of-2 FFT size for vDSP
        let nfft = 512  // next power of 2 >= 400
        let log2n = vDSP_Length(log2(Double(nfft)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Hanning window of length fftSize
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // Mel filterbank matrix [numMelBins x (nfft/2+1)]
        let numFreqBins = nfft / 2 + 1
        let melBank = buildMelFilterbank(
            numMelBins: numMelBins,
            numFreqBins: numFreqBins,
            sampleRate: sampleRate,
            fMin: fMinHz,
            fMax: fMaxHz
        )

        // Process frames
        let numFrames = max(0, (n - fftSize) / hopSize + 1)
        var frames: [[Float]] = []
        frames.reserveCapacity(numFrames)

        var paddedFrame = [Float](repeating: 0, count: nfft)
        var windowedFrame = [Float](repeating: 0, count: fftSize)

        for i in 0..<numFrames {
            let start = i * hopSize

            // Apply window
            vDSP_vmul(
                Array(audio[start..<(start + fftSize)]), 1,
                window, 1,
                &windowedFrame, 1,
                vDSP_Length(fftSize)
            )

            // Zero-pad to nfft
            paddedFrame = [Float](repeating: 0, count: nfft)
            for j in 0..<fftSize {
                paddedFrame[j] = windowedFrame[j]
            }

            // FFT
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

            // Power spectrum: |X[k]|^2
            var powerSpectrum = [Float](repeating: 0, count: numFreqBins)
            for k in 0..<(nfft / 2) {
                powerSpectrum[k] = realPart[k] * realPart[k] + imagPart[k] * imagPart[k]
            }
            // DC and Nyquist
            powerSpectrum[0] = realPart[0] * realPart[0]
            if numFreqBins > nfft / 2 {
                powerSpectrum[nfft / 2] = imagPart[0] * imagPart[0]
            }

            // Scale
            var scale = Float(1.0 / Float(nfft))
            vDSP_vsmul(powerSpectrum, 1, &scale, &powerSpectrum, 1, vDSP_Length(numFreqBins))

            // Apply mel filterbank: melSpec = melBank * powerSpectrum
            var melSpec = [Float](repeating: 0, count: numMelBins)
            for m in 0..<numMelBins {
                var dot: Float = 0
                vDSP_dotpr(
                    melBank[m], 1,
                    powerSpectrum, 1,
                    &dot,
                    vDSP_Length(numFreqBins)
                )
                melSpec[m] = dot
            }

            // Log scale (with floor to avoid log(0))
            let logFloor: Float = 1e-10
            for m in 0..<numMelBins {
                melSpec[m] = log(max(melSpec[m], logFloor))
            }

            frames.append(melSpec)
        }

        return frames
    }

    // MARK: - Mel Filterbank

    /// Hz to mel conversion
    private static func hzToMel(_ hz: Double) -> Double {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    /// Mel to Hz conversion
    private static func melToHz(_ mel: Double) -> Double {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    /// Build triangular mel filterbank matrix [numMelBins][numFreqBins]
    private static func buildMelFilterbank(
        numMelBins: Int,
        numFreqBins: Int,
        sampleRate: Double,
        fMin: Double,
        fMax: Double
    ) -> [[Float]] {
        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)
        let melStep = (melMax - melMin) / Double(numMelBins + 1)

        // Mel center frequencies (numMelBins + 2 points)
        var melPoints = [Double](repeating: 0, count: numMelBins + 2)
        for i in 0..<(numMelBins + 2) {
            melPoints[i] = melMin + Double(i) * melStep
        }

        // Convert to FFT bin indices
        let fftBins = melPoints.map { mel -> Double in
            let hz = melToHz(mel)
            return hz * Double(numFreqBins - 1) * 2.0 / sampleRate
        }

        var filterbank = [[Float]](repeating: [Float](repeating: 0, count: numFreqBins), count: numMelBins)

        for m in 0..<numMelBins {
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
