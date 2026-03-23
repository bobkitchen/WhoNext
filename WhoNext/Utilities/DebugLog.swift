import Foundation

/// Thread-safe log buffer with periodic disk flush for crash resilience.
/// Captures all debugLog output so it can be exported from Settings without Xcode.
final class SessionLog: @unchecked Sendable {
    static let shared = SessionLog()

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let maxEntries = 5_000

    /// Flush to disk every N entries
    private let flushInterval = 200
    private var entriesSinceFlush = 0

    /// Crash-resilient log file
    private let logFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("whonext-session-live.jsonl")
    }()

    struct Entry: Codable {
        let timestamp: Date
        let message: String
    }

    init() {
        // Start fresh log file on each app launch
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let entry = Entry(timestamp: Date(), message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Periodic flush to disk for crash resilience
        entriesSinceFlush += 1
        if entriesSinceFlush >= flushInterval {
            entriesSinceFlush = 0
            flushToDiskUnsafe()
        }
    }

    func export() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Flush current entries to disk as JSONL (one JSON object per line).
    /// Called with lock already held.
    private func flushToDiskUnsafe() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var lines = ""
        for entry in entries {
            if let data = try? encoder.encode(entry),
               let line = String(data: data, encoding: .utf8) {
                lines += line + "\n"
            }
        }
        try? lines.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    /// Force flush (call before export or on significant events)
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        flushToDiskUnsafe()
    }

    /// Recover log from disk after a crash (returns entries from previous session)
    func recoverFromDisk() -> [Entry] {
        guard let data = try? String(contentsOf: logFileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var recovered: [Entry] = []
        for line in data.components(separatedBy: "\n") where !line.isEmpty {
            if let lineData = line.data(using: .utf8),
               let entry = try? decoder.decode(Entry.self, from: lineData) {
                recovered.append(entry)
            }
        }
        return recovered
    }
}

/// Logging function that:
/// - Always writes to the in-memory SessionLog (for export without Xcode)
/// - Only prints to console in DEBUG builds
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    SessionLog.shared.append(output)
    #if DEBUG
    print(output, terminator: terminator)
    #endif
}
