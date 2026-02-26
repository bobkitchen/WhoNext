import AppKit

/// Cache for NSImage instances created from Person photo data, keyed by UUID.
/// Avoids recreating NSImage on every SwiftUI render cycle.
enum PersonAvatarCache {
    private static var cache: [UUID: NSImage] = [:]

    /// Get or create a cached NSImage for a person's photo data.
    static func image(for personID: UUID, photoData: Data?) -> NSImage? {
        guard let data = photoData else {
            cache.removeValue(forKey: personID)
            return nil
        }
        if let cached = cache[personID] {
            return cached
        }
        guard let image = NSImage(data: data) else { return nil }
        cache[personID] = image
        return image
    }

    /// Invalidate the cache entry for a person (call when photo changes).
    static func invalidate(for personID: UUID) {
        cache.removeValue(forKey: personID)
    }

    /// Clear the entire cache.
    static func clearAll() {
        cache.removeAll()
    }
}
