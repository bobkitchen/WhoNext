import Foundation
import SwiftUI
import Combine

/// Monitors recording quality and alerts users to issues
class RecordingQualityMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var status: QualityStatus = .excellent
    @Published var issues: [QualityIssue] = []
    @Published var metrics: QualityMetrics = QualityMetrics()

    // MARK: - Quality Status

    enum QualityStatus: String {
        case excellent = "Excellent"
        case good = "Good"
        case degraded = "Degraded"
        case critical = "Critical"

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .degraded: return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .excellent: return "checkmark.circle.fill"
            case .good: return "checkmark.circle"
            case .degraded: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.circle.fill"
            }
        }
    }

    // MARK: - Quality Issues

    enum QualityIssue: Identifiable, Equatable {
        case systemAudioUnavailable
        case transcriptionDelayed(seconds: Int)
        case diarizationFailed
        case lowAudioQuality(level: Float)
        case microphoneDisconnected
        case diskSpaceLow(mb: Int)
        case cpuOverload(percent: Int)

        var id: String {
            switch self {
            case .systemAudioUnavailable: return "systemAudio"
            case .transcriptionDelayed: return "transcription"
            case .diarizationFailed: return "diarization"
            case .lowAudioQuality: return "audioQuality"
            case .microphoneDisconnected: return "microphone"
            case .diskSpaceLow: return "diskSpace"
            case .cpuOverload: return "cpu"
            }
        }

        var message: String {
            switch self {
            case .systemAudioUnavailable:
                return "System audio offline - using microphone only"
            case .transcriptionDelayed(let seconds):
                return "Transcription delayed by \(seconds)s"
            case .diarizationFailed:
                return "Speaker detection unavailable"
            case .lowAudioQuality(let level):
                return "Low audio level (\(Int(level * 100))%)"
            case .microphoneDisconnected:
                return "Microphone disconnected"
            case .diskSpaceLow(let mb):
                return "Disk space low (\(mb)MB remaining)"
            case .cpuOverload(let percent):
                return "High CPU usage (\(percent)%)"
            }
        }

        var severity: IssueSeverity {
            switch self {
            case .systemAudioUnavailable: return .warning
            case .transcriptionDelayed(let seconds): return seconds > 10 ? .critical : .warning
            case .diarizationFailed: return .info
            case .lowAudioQuality(let level): return level < 0.1 ? .critical : .warning
            case .microphoneDisconnected: return .critical
            case .diskSpaceLow(let mb): return mb < 100 ? .critical : .warning
            case .cpuOverload(let percent): return percent > 90 ? .critical : .warning
            }
        }
    }

    enum IssueSeverity {
        case info
        case warning
        case critical
    }

    // MARK: - Quality Metrics

    struct QualityMetrics {
        var transcriptionLatency: TimeInterval = 0.0
        var averageAudioLevel: Float = 0.0
        var diarizationAccuracy: Float = 1.0
        var droppedFrames: Int = 0
        var cpuUsage: Float = 0.0
        var memoryUsage: Int64 = 0
        var diskSpaceRemaining: Int64 = 0

        var overallScore: Float {
            var score: Float = 100.0

            // Deduct for transcription latency
            if transcriptionLatency > 5.0 {
                score -= Float(min(transcriptionLatency - 5.0, 20.0)) * 2
            }

            // Deduct for low audio
            if averageAudioLevel < 0.3 {
                score -= (0.3 - averageAudioLevel) * 50
            }

            // Deduct for dropped frames
            score -= Float(min(droppedFrames, 10)) * 2

            // Deduct for CPU overload
            if cpuUsage > 0.8 {
                score -= (cpuUsage - 0.8) * 50
            }

            return max(0, min(100, score))
        }
    }

    // MARK: - Monitoring

    private var lastQualityCheck: Date = Date()
    private let qualityCheckInterval: TimeInterval = 5.0

    /// Update quality status based on current metrics
    func updateQualityStatus(
        hasSystemAudio: Bool,
        transcriptionLatency: TimeInterval,
        audioLevel: Float,
        hasDiarization: Bool,
        droppedFrames: Int,
        cpuUsage: Float,
        memoryUsage: Int64
    ) {
        // Update metrics
        metrics.transcriptionLatency = transcriptionLatency
        metrics.averageAudioLevel = audioLevel
        metrics.diarizationAccuracy = hasDiarization ? 1.0 : 0.0
        metrics.droppedFrames = droppedFrames
        metrics.cpuUsage = cpuUsage
        metrics.memoryUsage = memoryUsage

        // Clear old issues
        issues.removeAll()

        // Check for issues
        if !hasSystemAudio {
            issues.append(.systemAudioUnavailable)
        }

        if transcriptionLatency > 3.0 {
            issues.append(.transcriptionDelayed(seconds: Int(transcriptionLatency)))
        }

        if !hasDiarization {
            issues.append(.diarizationFailed)
        }

        if audioLevel < 0.2 {
            issues.append(.lowAudioQuality(level: audioLevel))
        }

        if droppedFrames > 5 {
            // Consider this CPU overload
            let cpuPercent = Int(cpuUsage * 100)
            if cpuPercent > 70 {
                issues.append(.cpuOverload(percent: cpuPercent))
            }
        }

        // Check disk space
        let diskSpace = getDiskSpaceRemaining()
        metrics.diskSpaceRemaining = diskSpace
        if diskSpace < 500 * 1024 * 1024 { // Less than 500MB
            issues.append(.diskSpaceLow(mb: Int(diskSpace / 1024 / 1024)))
        }

        // Update overall status
        updateStatus()
    }

    /// Update status based on issues
    private func updateStatus() {
        let criticalIssues = issues.filter { $0.severity == .critical }
        let warnings = issues.filter { $0.severity == .warning }

        if !criticalIssues.isEmpty {
            status = .critical
        } else if warnings.count >= 2 {
            status = .degraded
        } else if warnings.count == 1 {
            status = .good
        } else {
            status = .excellent
        }
    }

    /// Get remaining disk space in bytes
    private func getDiskSpaceRemaining() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
        } catch {
            print("Error getting disk space: \(error)")
        }
        return 0
    }

    /// Get a summary string for display
    func getSummary() -> String {
        if issues.isEmpty {
            return "Recording quality: \(status.rawValue)"
        } else {
            let issueCount = issues.count
            return "Recording quality: \(status.rawValue) (\(issueCount) issue\(issueCount > 1 ? "s" : ""))"
        }
    }

    /// Reset monitoring state
    func reset() {
        status = .excellent
        issues.removeAll()
        metrics = QualityMetrics()
        lastQualityCheck = Date()
    }
}
