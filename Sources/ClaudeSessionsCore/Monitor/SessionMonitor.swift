import Foundation

/// Runs the chain once per poll: snapshot -> transitions -> policy -> notifications.
///
/// Not thread-safe; drive it from a single task.
public final class SessionMonitor: @unchecked Sendable {
    /// The registry is a handful of small files, so re-reading it outright is cheap; measured at ~0.1% CPU.
    public static let pollInterval: Duration = .milliseconds(500)

    public struct Tick: Sendable {
        public let sessions: [LiveSession]
        public let events: [SessionEvent]
        public let notifications: [SessionNotification]
    }

    private let source: SnapshotSource
    private let detector: TransitionDetector
    private let policy: NotificationPolicy

    public init(source: SnapshotSource = SessionSource(),
                detector: TransitionDetector = TransitionDetector(),
                policy: NotificationPolicy = NotificationPolicy()) {
        self.source = source
        self.detector = detector
        self.policy = policy
    }

    public func tick() -> Tick {
        let events = detector.update(source.read())
        let notifications = events.filter(policy.shouldNotify).compactMap(NotificationComposer.compose)
        return Tick(sessions: detector.known, events: events, notifications: notifications)
    }
}
