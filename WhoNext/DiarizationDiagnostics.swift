import Foundation
#if canImport(AxiiDiarization)
import AxiiDiarization
#endif

// MARK: - Diagnostic Event Types

/// Structured diagnostic events for diarization pipeline analysis.
/// Collected during recording and exported as JSON for post-hoc analysis.
@MainActor
final class DiarizationDiagnostics {

    static let shared = DiarizationDiagnostics()

    // MARK: - Event Storage

    private var events: [DiagnosticEvent] = []
    private var isCollecting = false
    private var sessionStartTime: Date?

    // MARK: - Pipeline Counters

    struct PipelineCounters {
        var systemBuffersReceived: Int = 0
        var systemChunksEmitted: Int = 0
        var systemTotalFrames: Int = 0
        var micBuffersReceived: Int = 0
        var micEnergyGateSegments: Int = 0
        var wavFramesWritten: Int = 0
        var diarizationChunksProcessed: Int = 0
    }

    var counters = PipelineCounters()

    // MARK: - Control

    func startSession() {
        events.removeAll()
        counters = PipelineCounters()
        sessionStartTime = Date()
        isCollecting = true
        print("[DiarizationDiagnostics] Session started")
    }

    func stopSession() {
        isCollecting = false
        print("[DiarizationDiagnostics] Session stopped — \(events.count) events collected")
    }

    // MARK: - Event Recording

    private let maxEventCount = 50_000

    func record(_ event: DiagnosticEvent) {
        guard isCollecting else { return }
        if events.count >= maxEventCount {
            // Batch eviction: drop oldest 1000 events to avoid repeated trimming
            events.removeFirst(1000)
            print("[DiarizationDiagnostics] Event buffer full — evicted 1000 oldest events")
        }
        events.append(event)
    }

    /// Convenience: log a raw diarization result before SpeakerCache remapping
    func logRawDiarizationOutput(
        chunkPosition: TimeInterval,
        rawSpeakerCount: Int,
        rawSpeakerIds: [String],
        segmentCount: Int,
        speakerDatabase: [String: [Float]]?
    ) {
        // Log inter-speaker cosine similarities from the speaker database
        var similarities: [String: Float] = [:]
        if let db = speakerDatabase, db.count > 1 {
            let ids = Array(db.keys).sorted()
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let sim = VectorMath.cosineSimilarity(db[ids[i]]!, db[ids[j]]!)
                    similarities["\(ids[i])↔\(ids[j])"] = sim
                }
            }
        }

        record(.rawDiarizationOutput(
            timestamp: elapsedSeconds(),
            chunkPosition: chunkPosition,
            rawSpeakerCount: rawSpeakerCount,
            rawSpeakerIds: rawSpeakerIds,
            segmentCount: segmentCount,
            interSpeakerSimilarities: similarities
        ))

        // Also print for real-time console monitoring
        let simStr = similarities.map { "\($0.key):\(String(format: "%.3f", $0.value))" }.joined(separator: ", ")
        print("[DIAG:Diarization] chunk@\(String(format: "%.1f", chunkPosition))s: \(rawSpeakerCount) raw speakers [\(rawSpeakerIds.joined(separator: ","))], \(segmentCount) segments")
        if !simStr.isEmpty {
            print("[DIAG:Diarization] inter-speaker similarities: [\(simStr)]")
        }
    }

    /// Log SpeakerCache remap decisions
    func logSpeakerCacheRemap(
        rawDiarizationId: String,
        stableCacheId: String?,
        similarity: Float?,
        isNewSpeaker: Bool
    ) {
        record(.speakerCacheRemap(
            timestamp: elapsedSeconds(),
            rawDiarizationId: rawDiarizationId,
            stableCacheId: stableCacheId,
            similarity: similarity,
            isNewSpeaker: isNewSpeaker
        ))

        if isNewSpeaker {
            print("[DIAG:Cache] NEW speaker: raw '\(rawDiarizationId)' → cache '\(stableCacheId ?? "nil")'")
        } else if let stableId = stableCacheId, stableId != rawDiarizationId {
            print("[DIAG:Cache] REMAP: raw '\(rawDiarizationId)' → cache '\(stableId)' (sim: \(String(format: "%.3f", similarity ?? 0)))")
        }
    }

    /// Log phantom speaker merge decisions
    func logPhantomMerge(
        sourceId: String,
        destId: String,
        similarity: Float,
        sourceSpeakingTime: Float,
        destSpeakingTime: Float
    ) {
        record(.phantomMerge(
            timestamp: elapsedSeconds(),
            sourceId: sourceId,
            destId: destId,
            similarity: similarity,
            sourceSpeakingTime: sourceSpeakingTime,
            destSpeakingTime: destSpeakingTime
        ))

        print("[DIAG:Merge] MERGE '\(sourceId)' (\(String(format: "%.1f", sourceSpeakingTime))s) → '\(destId)' (\(String(format: "%.1f", destSpeakingTime))s) sim: \(String(format: "%.3f", similarity))")
    }

    /// Log energy gate decisions
    func logEnergyGateCalibration(noiseFloor: Float, speechThreshold: Float) {
        record(.energyGateCalibration(
            timestamp: elapsedSeconds(),
            noiseFloor: noiseFloor,
            speechThreshold: speechThreshold
        ))
    }

    func logEnergyGateOnset(at time: TimeInterval, micRMS: Float, systemRMS: Float, ratioDB: Float) {
        record(.energyGateSpeechOnset(
            timestamp: elapsedSeconds(),
            speechTime: time,
            micRMS: micRMS,
            systemRMS: systemRMS,
            ratioDB: ratioDB
        ))
    }

    func logEnergyGateOffset(at time: TimeInterval, duration: TimeInterval) {
        record(.energyGateSpeechOffset(
            timestamp: elapsedSeconds(),
            speechTime: time,
            duration: duration
        ))
    }

    /// Log system audio pipeline stats
    func logPipelineSnapshot() {
        record(.pipelineSnapshot(
            timestamp: elapsedSeconds(),
            counters: counters
        ))
    }

    // MARK: - Export

    /// Export all diagnostic events as JSON to a file, returning the URL.
    func exportToJSON() throws -> URL {
        let export = DiagnosticExport(
            sessionStart: sessionStartTime ?? Date(),
            sessionEnd: Date(),
            eventCount: events.count,
            counters: counters,
            events: events
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let dateStr = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "diarization-diagnostics-\(dateStr).json"

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)

        print("[DiarizationDiagnostics] Exported \(events.count) events to \(fileURL.lastPathComponent)")
        return fileURL
    }

    /// Get a summary string for display in settings UI
    func summaryString() -> String {
        guard !events.isEmpty else { return "No diagnostic data collected" }

        let rawOutputEvents = events.filter {
            if case .rawDiarizationOutput = $0 { return true }
            return false
        }
        let mergeEvents = events.filter {
            if case .phantomMerge = $0 { return true }
            return false
        }
        let remapEvents = events.filter {
            if case .speakerCacheRemap = $0 { return true }
            return false
        }

        var lines: [String] = []
        lines.append("Events: \(events.count)")
        lines.append("Diarization chunks: \(rawOutputEvents.count)")
        lines.append("Cache remaps: \(remapEvents.count)")
        lines.append("Phantom merges: \(mergeEvents.count)")
        lines.append("System buffers: \(counters.systemBuffersReceived)")
        lines.append("System chunks emitted: \(counters.systemChunksEmitted)")
        lines.append("WAV frames written: \(counters.wavFramesWritten)")
        lines.append("Diarization chunks: \(counters.diarizationChunksProcessed)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func elapsedSeconds() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}

// MARK: - Event Types

enum DiagnosticEvent: Codable {
    case rawDiarizationOutput(
        timestamp: TimeInterval,
        chunkPosition: TimeInterval,
        rawSpeakerCount: Int,
        rawSpeakerIds: [String],
        segmentCount: Int,
        interSpeakerSimilarities: [String: Float]
    )
    case speakerCacheRemap(
        timestamp: TimeInterval,
        rawDiarizationId: String,
        stableCacheId: String?,
        similarity: Float?,
        isNewSpeaker: Bool
    )
    case phantomMerge(
        timestamp: TimeInterval,
        sourceId: String,
        destId: String,
        similarity: Float,
        sourceSpeakingTime: Float,
        destSpeakingTime: Float
    )
    case energyGateCalibration(
        timestamp: TimeInterval,
        noiseFloor: Float,
        speechThreshold: Float
    )
    case energyGateSpeechOnset(
        timestamp: TimeInterval,
        speechTime: TimeInterval,
        micRMS: Float,
        systemRMS: Float,
        ratioDB: Float
    )
    case energyGateSpeechOffset(
        timestamp: TimeInterval,
        speechTime: TimeInterval,
        duration: TimeInterval
    )
    case pipelineSnapshot(
        timestamp: TimeInterval,
        counters: DiarizationDiagnostics.PipelineCounters
    )
}

// MARK: - Export Envelope

struct DiagnosticExport: Codable {
    let sessionStart: Date
    let sessionEnd: Date
    let eventCount: Int
    let counters: DiarizationDiagnostics.PipelineCounters
    let events: [DiagnosticEvent]
}

// Make PipelineCounters codable
extension DiarizationDiagnostics.PipelineCounters: Codable {}
