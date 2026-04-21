import AppKit
import Foundation
import Observation
import ParakeetStreamingASR
import SpeechVAD

let logPath = "/tmp/dictate.log"
let logLock = NSLock()
func dlog(_ msg: String) {
    logLock.lock()
    defer { logLock.unlock() }
    if let data = "\(msg)\n".data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

/// Off-main-thread audio processing.
final class ASRProcessor: Sendable {
    let session: StreamingSession
    private let vad: SileroVADModel
    private let lock = NSLock()
    private let _buffer = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
    private let _vadLeftover = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
    nonisolated(unsafe) var speechActive = false
    nonisolated(unsafe) var silenceCount = 0
    nonisolated(unsafe) var hasPendingUtterance = false
    nonisolated(unsafe) var smoothGain: Float = 1.0
    nonisolated(unsafe) var lastRms: Float = 0
    nonisolated(unsafe) var lastNormRms: Float = 0

    // VAD silence chunks (512 samples @ 16kHz = 32ms) before we force-finalize.
    // 30 chunks ≈ 960ms — long enough to avoid mid-sentence cutoff, short
    // enough that the UI commits promptly after speech ends.
    private let forceFinalizeSilentChunks = 30

    init(session: StreamingSession, vad: SileroVADModel) {
        self.session = session
        self.vad = vad
        _buffer.initialize(to: [])
        _vadLeftover.initialize(to: [])
        _allAudio.initialize(to: [])
        vad.resetState()
    }
    deinit {
        _buffer.deinitialize(count: 1); _buffer.deallocate()
        _vadLeftover.deinitialize(count: 1); _vadLeftover.deallocate()
        _allAudio.deinitialize(count: 1); _allAudio.deallocate()
    }

    // Debug: save all audio to file
    private let _allAudio = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)

    func appendAudio(_ samples: [Float]) {
        lock.lock()
        _buffer.pointee.append(contentsOf: samples)
        lock.unlock()
    }

    func appendDebugAudio(_ samples: [Float]) {
        lock.lock()
        _allAudio.pointee.append(contentsOf: samples)
        lock.unlock()
    }

    /// Save captured audio to WAV for debugging.
    func saveDebugAudio() {
        lock.lock()
        let audio = _allAudio.pointee
        lock.unlock()
        guard !audio.isEmpty else { return }

        let path = "/tmp/dictate-debug.wav"
        // Write raw WAV (16kHz, mono, float32)
        var header = Data()
        let dataSize = UInt32(audio.count * 4)
        let fileSize = UInt32(36 + dataSize)
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })  // float
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(64000).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(32).littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        var fileData = header
        audio.withUnsafeBufferPointer { buf in
            fileData.append(UnsafeBufferPointer(start: UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), count: buf.count * 4))
        }
        try? fileData.write(to: URL(fileURLWithPath: path))
        dlog("Saved \(audio.count) samples (\(String(format: "%.1f", Float(audio.count)/16000))s) to \(path)")
    }

    var bufferedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _buffer.pointee.count
    }

    func processBuffered() -> (partials: [ParakeetStreamingASRModel.PartialTranscript], speaking: Bool) {
        lock.lock()
        let chunk = _buffer.pointee
        _buffer.pointee.removeAll(keepingCapacity: true)
        lock.unlock()
        guard !chunk.isEmpty else { return ([], speechActive) }

        // Normalize with smoothed gain to avoid amplitude swings between chunks.
        // Compute target gain, then blend with previous gain for smooth transition.
        var normalized = chunk
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // No normalization — FluidAudio feeds raw mic audio directly.
        // The model should handle normal mic levels.

        // VAD: carry leftover samples across calls so the stateful LSTM
        // sees a continuous stream. Chunks are exactly 512 samples.
        lock.lock()
        var vadInput = _vadLeftover.pointee
        vadInput.append(contentsOf: normalized)
        lock.unlock()
        var offset = 0
        while offset + 512 <= vadInput.count {
            let prob = vad.processChunk(Array(vadInput[offset..<offset+512]))
            if prob >= 0.5 {
                speechActive = true
                silenceCount = 0
                hasPendingUtterance = true
            } else {
                silenceCount += 1
                if silenceCount >= 15 { speechActive = false }
            }
            offset += 512
        }
        let leftover = Array(vadInput[offset...])
        lock.lock()
        _vadLeftover.pointee = leftover
        lock.unlock()

        // ASR on normalized audio
        lastRms = rms
        lastNormRms = rms  // Same as raw — no normalization
        do {
            self.appendDebugAudio(normalized)
            var partials = try session.pushAudio(normalized)

            // If the joint already finalized the utterance on its own (via
            // its EOU head), mark the utterance as handled so we don't then
            // also force-finalize and duplicate the sentence.
            if partials.contains(where: { $0.isFinal }) {
                hasPendingUtterance = false
            }

            // VAD-driven force finalize: if speech has ended and we have
            // an utterance pending, emit a final before the joint's EOU
            // debounce eventually fires. Noise during "silence" keeps the
            // joint's EOU timer resetting, so VAD is more reliable here.
            if hasPendingUtterance
                && !speechActive
                && silenceCount >= forceFinalizeSilentChunks
            {
                if let forced = session.forceEndOfUtterance() {
                    dlog("FORCE-FINAL via VAD: '\(forced.text)'")
                    partials.append(forced)
                }
                hasPendingUtterance = false
            }

            dlog("asr: rms=\(String(format:"%.4f",rms)) vad=\(speechActive) partials=\(partials.count)")
            if !partials.isEmpty {
                dlog("ASR: \(partials.count) partials — '\(partials.map { $0.text }.joined(separator: ", "))'")
            }
            return (partials, speechActive)
        } catch {
            dlog("ASR error: \(error)")
            return ([], speechActive)
        }
    }

    func finalize() -> [ParakeetStreamingASRModel.PartialTranscript] {
        let (r, _) = processBuffered()
        do { return r + (try session.finalize()) }
        catch { return r }
    }
}

@MainActor
final class DictateViewModel: ObservableObject {
    // Using ObservableObject + @Published (Combine) rather than @Observable
    // because @Observable's ObservationRegistrar does not reliably trigger
    // SwiftUI re-renders inside a MenuBarExtra popover (NSHostingView inside
    // NSPopover). @Published + @StateObject pumps through Combine and works.
    @Published var sentences: [String] = []
    @Published var partialText = ""
    @Published var lastCommittedText = ""  // Track what's been committed to extract deltas
    @Published var isRecording = false
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var errorMessage: String?
    @Published var isSpeechActive = false
    @Published var debugAudioRms: Float = 0
    @Published var debugNormRms: Float = 0
    @Published var debugChunksProcessed: Int = 0
    @Published var debugPartialsReceived: Int = 0

    private var model: ParakeetStreamingASRModel?
    private var vad: SileroVADModel?
    private var processor: ASRProcessor?
    private let recorder = StreamingRecorder()
    private let processQueue = DispatchQueue(label: "dictate.asr", qos: .userInteractive)
    private var processTimer: DispatchSourceTimer?

    var modelLoaded: Bool { model != nil && vad != nil }
    var audioLevel: Float { recorder.audioLevel }

    var wordCount: Int {
        let all = sentences.joined(separator: " ") + (partialText.isEmpty ? "" : " " + partialText)
        return all.split(separator: " ").count
    }

    var fullText: String {
        let committed = sentences.joined(separator: "\n")
        if committed.isEmpty { return partialText }
        if partialText.isEmpty { return committed }
        return committed + "\n" + partialText
    }

    init() {
        Task { await loadModels() }
    }

    func loadModels() async {
        guard model == nil else { return }
        isLoading = true
        loadingStatus = "Downloading ASR model..."

        do {
            let loaded = try await Task.detached {
                try await ParakeetStreamingASRModel.fromPretrained { [weak self] p, s in
                    DispatchQueue.main.async {
                        self?.loadingStatus = s.isEmpty ? "Downloading... \(Int(p * 100))%" : "\(s) (\(Int(p * 100))%)"
                    }
                }
            }.value
            loadingStatus = "Warming up..."
            try loaded.warmUp()
            model = loaded

            loadingStatus = "Loading VAD..."
            vad = try await Task.detached {
                try await SileroVADModel.fromPretrained(engine: .coreml)
            }.value
            loadingStatus = ""
            dlog("Models loaded (ASR + VAD)")
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            loadingStatus = ""
        }
        isLoading = false
    }

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        dlog("startRecording called, model=\(model != nil), vad=\(vad != nil)")
        guard let model, let vad else { dlog("GUARD FAILED"); return }
        errorMessage = nil; partialText = ""; sentences.removeAll(); lastCommittedText = ""

        do {
            let session = try model.createSession()
            let proc = ASRProcessor(session: session, vad: vad)
            processor = proc

            recorder.start { [proc] chunk in proc.appendAudio(chunk) }

            let timer = DispatchSource.makeTimerSource(queue: processQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(300))
            timer.setEventHandler { [weak self, proc] in
                let count = proc.bufferedCount
                if count > 0 { dlog("timer: \(count) buffered") }
                let (partials, speaking) = proc.processBuffered()
                let rms = proc.lastRms
                let normRms = proc.lastNormRms
                // Schedule the UI update via RunLoop.main.perform in every
                // relevant mode so it pumps through regardless of which mode
                // a MenuBarExtra popover has the main loop in. Both
                // DispatchQueue.main and Task{@MainActor} target only the
                // default mode and get starved while the popover is open.
                let weakSelf = self
                RunLoop.main.perform(inModes: [.common, .default, .eventTracking, .modalPanel]) {
                    MainActor.assumeIsolated {
                        guard let self = weakSelf else { return }
                        self.isSpeechActive = speaking
                        self.debugAudioRms = rms
                        self.debugNormRms = normRms
                        self.debugChunksProcessed += 1
                        self.debugPartialsReceived += partials.count
                        for partial in partials {
                            if partial.isFinal && !partial.text.isEmpty {
                                self.sentences.append(partial.text)
                                self.partialText = ""
                            } else if !partial.text.isEmpty {
                                self.partialText = partial.text
                            }
                        }
                    }
                }
            }
            timer.resume()
            processTimer = timer
            isRecording = true
            dlog("Recording started")
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        processTimer?.cancel(); processTimer = nil
        recorder.stop(); isRecording = false; isSpeechActive = false
        if let processor {
            processor.saveDebugAudio()
            for p in processor.finalize() where !p.text.isEmpty { sentences.append(p.text) }
        }
        processor = nil; partialText = ""
    }

    func pasteToFrontApp() {
        guard !fullText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true); kd?.flags = .maskCommand
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false); ku?.flags = .maskCommand
            kd?.post(tap: .cghidEventTap); ku?.post(tap: .cghidEventTap)
        }
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
    }

    func clearText() { sentences.removeAll(); partialText = ""; lastCommittedText = "" }
}
