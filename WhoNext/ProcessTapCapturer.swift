import Foundation
import AVFoundation
import AudioToolbox
import AppKit
import CoreAudio

// MARK: - Error Type

enum ProcessTapError: LocalizedError {
    case noMeetingProcessDetected
    case coreAudio(String, OSStatus)
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case formatCreationFailed
    case converterCreationFailed
    case tapFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .noMeetingProcessDetected:
            return "No running meeting application detected (Zoom, Teams, FaceTime, etc.)."
        case .coreAudio(let op, let status):
            return "Core Audio error in \(op): \(status)"
        case .tapCreationFailed(let status):
            return "AudioHardwareCreateProcessTap failed with status \(status). Audio Recording permission may be denied."
        case .aggregateCreationFailed(let status):
            return "AudioHardwareCreateAggregateDevice failed with status \(status)."
        case .ioProcCreationFailed(let status):
            return "AudioDeviceCreateIOProcIDWithBlock failed with status \(status)."
        case .deviceStartFailed(let status):
            return "AudioDeviceStart failed with status \(status)."
        case .formatCreationFailed:
            return "Failed to create AVAudioFormat from tap stream description."
        case .converterCreationFailed:
            return "Failed to create AVAudioConverter for tap audio."
        case .tapFormatUnavailable:
            return "Tap stream format is not available."
        }
    }
}

// MARK: - AudioObjectID Helpers

extension AudioObjectID {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let unknownObject = AudioObjectID(kAudioObjectUnknown)
    var isValidAudioObject: Bool { self != AudioObjectID(kAudioObjectUnknown) }

    /// Read a scalar property (global scope, main element).
    fileprivate func readValue<T>(_ selector: AudioObjectPropertySelector, defaultValue: T) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw ProcessTapError.coreAudio("property \(selector) size", err)
        }
        var value = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, ptr)
        }
        guard err == noErr else {
            throw ProcessTapError.coreAudio("property \(selector) data", err)
        }
        return value
    }

    /// Read a CFString property.
    fileprivate func readStringProperty(_ selector: AudioObjectPropertySelector) throws -> String {
        try readValue(selector, defaultValue: "" as CFString) as String
    }

    /// Read `kAudioHardwarePropertyProcessObjectList` from the system object.
    static func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(.systemObject, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw ProcessTapError.coreAudio("readProcessList size", err)
        }
        var ids = [AudioObjectID](
            repeating: .unknownObject,
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        err = AudioObjectGetPropertyData(.systemObject, &address, 0, nil, &dataSize, &ids)
        guard err == noErr else {
            throw ProcessTapError.coreAudio("readProcessList data", err)
        }
        return ids
    }

    /// Read the PID associated with a process AudioObjectID.
    func readProcessPID() -> pid_t? {
        let pid: pid_t = (try? readValue(kAudioProcessPropertyPID, defaultValue: pid_t(-1))) ?? -1
        return pid > 0 ? pid : nil
    }

    /// Read the bundle ID for a process AudioObjectID.
    func readProcessBundleID() -> String? {
        let s = (try? readStringProperty(kAudioProcessPropertyBundleID)) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Whether the process is currently doing audio I/O.
    func readProcessIsRunning() -> Bool {
        let v: Int = (try? readValue(kAudioProcessPropertyIsRunning, defaultValue: 0)) ?? 0
        return v == 1
    }

    /// Read `kAudioHardwarePropertyDefaultSystemOutputDevice`.
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.systemObject.readValue(
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            defaultValue: AudioDeviceID(kAudioObjectUnknown)
        )
    }

    /// Read `kAudioDevicePropertyDeviceUID`.
    func readDeviceUID() throws -> String {
        try readStringProperty(kAudioDevicePropertyDeviceUID)
    }

    /// Read `kAudioTapPropertyFormat`.
    func readTapStreamFormat() throws -> AudioStreamBasicDescription {
        try readValue(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }
}

// MARK: - Meeting Process Detection

struct MeetingProcess: Equatable {
    enum App: String, CaseIterable {
        case zoom = "us.zoom.xos"
        case teamsNew = "com.microsoft.teams2"
        case teamsLegacy = "com.microsoft.teams"
        case facetime = "com.apple.FaceTime"
        case webex = "Cisco-Systems.Spark"
        case slack = "com.tinyspeck.slackmacgap"
        case chrome = "com.google.Chrome"
        case safari = "com.apple.Safari"
        case edge = "com.microsoft.edgemac"
        case arc = "company.thebrowser.Browser"
        case firefox = "org.mozilla.firefox"

        var displayName: String {
            switch self {
            case .zoom: return "Zoom"
            case .teamsNew, .teamsLegacy: return "Microsoft Teams"
            case .facetime: return "FaceTime"
            case .webex: return "Webex"
            case .slack: return "Slack"
            case .chrome: return "Chrome"
            case .safari: return "Safari"
            case .edge: return "Edge"
            case .arc: return "Arc"
            case .firefox: return "Firefox"
            }
        }
    }

    let pid: pid_t
    let bundleID: String
    let displayName: String
    let audioObjectID: AudioObjectID
    let isAudioActive: Bool
}

enum MeetingProcessDetector {

    /// Detect the best candidate meeting app to tap.
    /// Prioritises dedicated meeting apps with active audio, then any running meeting app.
    static func detect() -> MeetingProcess? {
        let processIDs: [AudioObjectID]
        do {
            processIDs = try AudioObjectID.readProcessList()
        } catch {
            debugLog("[ProcessTap] Failed to read Core Audio process list: \(error.localizedDescription)")
            return nil
        }

        let knownBundleIDs = Set(MeetingProcess.App.allCases.map(\.rawValue))

        struct Candidate {
            let pid: pid_t
            let bundleID: String
            let app: MeetingProcess.App
            let objectID: AudioObjectID
            let isAudioActive: Bool
        }

        var candidates: [Candidate] = []
        for objectID in processIDs {
            guard let bundleID = objectID.readProcessBundleID(),
                  knownBundleIDs.contains(bundleID),
                  let app = MeetingProcess.App(rawValue: bundleID),
                  let pid = objectID.readProcessPID() else { continue }
            let isRunning = objectID.readProcessIsRunning()
            candidates.append(
                Candidate(pid: pid, bundleID: bundleID, app: app,
                          objectID: objectID, isAudioActive: isRunning)
            )
        }

        guard !candidates.isEmpty else {
            debugLog("[ProcessTap] No known meeting apps running")
            return nil
        }

        // Reject idle candidates. Core Audio's kAudioProcessPropertyIsRunning reflects
        // active audio I/O — when false the app is launched but not producing sound
        // (e.g. Teams open with no call). Tapping an idle process yields a silent
        // system stream, so instead we return nil and let the caller fall back to
        // SCStream, which captures whatever IS making noise (YouTube in a browser,
        // music apps, etc.). This avoids the "everything attributed to Me" failure
        // mode where mic-only audio masquerades as a full conversation.
        let audioActive = candidates.filter(\.isAudioActive)
        guard !audioActive.isEmpty else {
            let names = candidates.map { "\($0.app.displayName) (idle)" }.joined(separator: ", ")
            debugLog("[ProcessTap] No audio-active meeting apps — candidates: \(names). Falling back to SCStream.")
            return nil
        }

        // Priority order: dedicated meeting apps first, then browsers.
        let priority: [MeetingProcess.App] = [
            .zoom, .teamsNew, .teamsLegacy, .facetime, .webex,
            .chrome, .edge, .arc, .safari, .firefox, .slack
        ]
        let rank: [MeetingProcess.App: Int] = Dictionary(
            uniqueKeysWithValues: priority.enumerated().map { ($1, $0) }
        )

        let best = audioActive
            .sorted { (rank[$0.app] ?? Int.max) < (rank[$1.app] ?? Int.max) }
            .first!

        return MeetingProcess(
            pid: best.pid,
            bundleID: best.bundleID,
            displayName: best.app.displayName,
            audioObjectID: best.objectID,
            isAudioActive: best.isAudioActive
        )
    }
}

// MARK: - Process Tap

/// Low-level wrapper over `AudioHardwareCreateProcessTap` plus an aggregate device for I/O.
final class ProcessTap {

    let process: MeetingProcess

    private var processTapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private(set) var tapStreamDescription: AudioStreamBasicDescription?

    init(process: MeetingProcess) {
        self.process = process
    }

    func prepare() throws {
        // 1. Create the process tap (stereo mixdown of the meeting app's audio).
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [process.audioObjectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .unmuted

        var tapID: AUAudioObjectID = AUAudioObjectID(kAudioObjectUnknown)
        let createErr = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard createErr == noErr else {
            throw ProcessTapError.tapCreationFailed(createErr)
        }
        self.processTapID = tapID

        // 2. Read the tap's stream format (typically 48kHz stereo Float32).
        self.tapStreamDescription = try tapID.readTapStreamFormat()

        // 3. Create an aggregate device wrapping the tap so we can run I/O on it.
        let systemOutputID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "WhoNext-Tap-\(process.pid)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDesc.uuid.uuidString
                ]
            ]
        ]

        var aggDevID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        let aggErr = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggDevID)
        guard aggErr == noErr else {
            // Clean up tap before throwing.
            _ = AudioHardwareDestroyProcessTap(processTapID)
            self.processTapID = AudioObjectID(kAudioObjectUnknown)
            throw ProcessTapError.aggregateCreationFailed(aggErr)
        }
        self.aggregateDeviceID = aggDevID
    }

    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock) throws {
        var procID: AudioDeviceIOProcID?
        let createErr = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue, ioBlock)
        guard createErr == noErr, let procID else {
            throw ProcessTapError.ioProcCreationFailed(createErr)
        }
        self.deviceProcID = procID

        let startErr = AudioDeviceStart(aggregateDeviceID, procID)
        guard startErr == noErr else {
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.deviceProcID = nil
            throw ProcessTapError.deviceStartFailed(startErr)
        }
    }

    func invalidate() {
        if aggregateDeviceID.isValidAudioObject {
            if let procID = deviceProcID {
                _ = AudioDeviceStop(aggregateDeviceID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                deviceProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if processTapID.isValidAudioObject {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            processTapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        // Mirror invalidate() without touching actor state — safe from any thread.
        if aggregateDeviceID.isValidAudioObject {
            if let procID = deviceProcID {
                _ = AudioDeviceStop(aggregateDeviceID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if processTapID.isValidAudioObject {
            _ = AudioHardwareDestroyProcessTap(processTapID)
        }
    }
}

// MARK: - Process Tap Capturer

/// Captures clean audio directly from a meeting application via Core Audio process tap.
/// Delivers 16 kHz mono Float32 PCM buffers suitable for the WhoNext pipeline.
///
/// Why this exists: `ScreenCaptureKit` captures the entire system mix — music, browser
/// tabs, notifications — all mingled together. A process tap captures exactly one app,
/// giving clean audio for transcription and diarization.
@MainActor
final class ProcessTapCapturer {

    private(set) var isActive = false
    private(set) var activeProcess: MeetingProcess?

    private var tap: ProcessTap?
    private let ioQueue = DispatchQueue(label: "com.whonext.processtap.io", qos: .userInteractive)

    private let targetFormat: AVAudioFormat

    init() {
        self.targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000.0,
            channels: 1
        )!
    }

    /// Attempt to start tapping a detected meeting process.
    /// - Parameter onAudio: Called on the I/O queue with 16 kHz mono Float32 buffers.
    ///   The caller is responsible for deep-copying the buffer before async handling.
    /// - Returns: The meeting process that is being tapped.
    func start(onAudio: @escaping (AVAudioPCMBuffer) -> Void) throws -> MeetingProcess {
        precondition(!isActive, "ProcessTapCapturer already active")

        guard let process = MeetingProcessDetector.detect() else {
            throw ProcessTapError.noMeetingProcessDetected
        }

        debugLog("[ProcessTap] Detected \(process.displayName) (pid=\(process.pid), bundle=\(process.bundleID), audioActive=\(process.isAudioActive))")

        let tap = ProcessTap(process: process)
        try tap.prepare()

        guard var asbd = tap.tapStreamDescription else {
            throw ProcessTapError.tapFormatUnavailable
        }

        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw ProcessTapError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ProcessTapError.converterCreationFailed
        }

        debugLog("[ProcessTap] Tap format: \(sourceFormat.sampleRate)Hz, \(sourceFormat.channelCount)ch → 16kHz mono")

        let target = targetFormat

        try tap.run(on: ioQueue) { _, inInputData, _, _, _ in
            Self.handleIOBlock(
                inputData: inInputData,
                sourceFormat: sourceFormat,
                targetFormat: target,
                converter: converter,
                onAudio: onAudio
            )
        }

        self.tap = tap
        self.activeProcess = process
        self.isActive = true
        return process
    }

    func stop() {
        guard isActive else { return }
        debugLog("[ProcessTap] Stopping tap for \(activeProcess?.displayName ?? "unknown")")
        tap?.invalidate()
        tap = nil
        activeProcess = nil
        isActive = false
    }

    private static func handleIOBlock(
        inputData: UnsafePointer<AudioBufferList>,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter,
        onAudio: (AVAudioPCMBuffer) -> Void
    ) {
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: inputData,
            deallocator: nil
        ), sourceBuffer.frameLength > 0 else {
            return
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        var err: NSError?
        let status = converter.convert(to: outBuffer, error: &err) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error || err != nil {
            debugLog("[ProcessTap] Conversion error: \(err?.localizedDescription ?? "unknown")")
            return
        }

        guard outBuffer.frameLength > 0 else { return }
        onAudio(outBuffer)
    }
}
