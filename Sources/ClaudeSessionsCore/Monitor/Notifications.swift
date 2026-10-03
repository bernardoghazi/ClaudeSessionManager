import Foundation

/// A notification ready to be handed to the OS. `focusUrl` travels with it, so each banner
/// knows which session it belongs to when clicked.
public struct SessionNotification: Equatable, Sendable {
    public let sessionId: String
    public let title: String
    public let body: String
    public let focusUrl: String?

    public init(sessionId: String, title: String, body: String, focusUrl: String? = nil) {
        self.sessionId = sessionId
        self.title = title
        self.body = body
        self.focusUrl = focusUrl
    }
}

/// Decides which events are worth interrupting the user for: a session that *needs them*, or
/// one that *finished* a turn long enough to have walked away from. Everything else is noise.
public struct NotificationPolicy: Sendable {
    public static let defaultMinRunBeforeIdle: Duration = .seconds(2)

    private let minRunBeforeIdle: Duration

    public init(minRunBeforeIdle: Duration = defaultMinRunBeforeIdle) {
        self.minRunBeforeIdle = minRunBeforeIdle
    }

    public func shouldNotify(_ event: SessionEvent) -> Bool {
        guard case let .phaseChanged(_, from, to, held) = event else { return false }
        // Defensive: the detector already refuses to emit transitions into unknown.
        if from == .unknown || to == .unknown { return false }
        switch to {
        case .waiting: return true
        case .idle: return from == .running && held >= minRunBeforeIdle
        default: return false
        }
    }
}

/// Turns a transition into the words the user sees.
public enum NotificationComposer {
    public static func compose(_ event: SessionEvent) -> SessionNotification? {
        guard case let .phaseChanged(session, _, to, held) = event else { return nil }
        let body: String
        switch to {
        case .waiting: body = waitingBody(session.waitingFor)
        case .idle: body = "Finished after \(held.humanized)"
        default: body = "Now \(to.rawValue)"
        }
        return SessionNotification(sessionId: session.sessionId, title: session.name, body: body, focusUrl: session.focusUrl)
    }

    /// Anything unrecognised is shown rather than dropped: better to surface a new value than to lie.
    public static func waitingBody(_ waitingFor: String?) -> String {
        switch waitingFor {
        case "input needed": "Needs your input"
        case "dialog open": "Waiting on a dialog"
        case "sandbox request": "Wants sandbox access"
        case "goal proposal": "Waiting on a goal proposal"
        case "worker request": "Waiting on a worker request"
        case nil: "Needs your attention"
        case let other?: "Waiting: \(other)"
        }
    }
}

extension Duration {
    /// The way a person would say it: "4m 12s", "45s", "1h 3m".
    public var humanized: String {
        let total = components.seconds
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
