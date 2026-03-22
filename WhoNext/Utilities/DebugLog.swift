import Foundation

/// Thread-safe in-memory log buffer for session diagnostics.
/// Captures all debugLog output so it can be exported from Settings without Xcode.
final class SessionLog: @unchecked Sendable {
    static let shared = SessionLog()

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let maxEntries = 5_000

    struct Entry: Codable {
        let timestamp: Date
        let message: String
    }

    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(timestamp: Date(), message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
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
