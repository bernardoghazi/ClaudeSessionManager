import Foundation

/// Append-only record of what the app did.
///
/// Once a notification is handed to the OS the app is blind to it, so this is the only way to
/// answer "did it post, and what happened when it was clicked" after the fact.
public struct ActivityLog: Sendable {
    public let record: @Sendable (String) -> Void

    public init(record: @escaping @Sendable (String) -> Void) {
        self.record = record
    }

    public static let none = ActivityLog { _ in }

    public static func file(_ url: URL = Paths.activityLog) -> ActivityLog {
        let lock = NSLock()
        return ActivityLog { line in
            lock.lock(); defer { lock.unlock() }
            // Diagnostics must never take the app down, so every failure is ignored.
            let text = "\(ISO8601DateFormatter().string(from: Date()))  \(line)\n"
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(text.utf8))
            } else {
                try? Data(text.utf8).write(to: url)
            }
        }
    }
}
