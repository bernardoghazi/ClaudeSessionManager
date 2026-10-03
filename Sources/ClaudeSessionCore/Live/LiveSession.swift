import Foundation

/// What a running Claude Code session is currently doing.
///
/// `unknown` exists so an ambiguous reading can be represented without guessing.
/// Transitions into `unknown` must never raise a notification.
public enum Phase: String, Sendable {
    case running, idle, waiting, gone, unknown

    /// Maps the registry's `status` field. Claude Code validates it against
    /// `["busy","shell","idle","waiting"]`; "shell" means the user shelled out, so the agent is idle.
    public init(registryStatus status: String?) {
        switch status {
        case "busy": self = .running
        case "idle", "shell": self = .idle
        case "waiting": self = .waiting
        default: self = .unknown
        }
    }
}

/// A running Claude Code session, merged from the registry (state) and the address sources (which tab).
///
/// Identity is `sessionId`, not `pid`: a resumed session keeps its transcript while getting a new process.
public struct LiveSession: Equatable, Sendable {
    public var sessionId: String
    public var pid: Int32
    public var cwd: String
    public var name: String
    public var phase: Phase
    public var waitingFor: String?
    public var focusUrl: String?
    public var terminal: String?
    /// Epoch millis of the registry's last status change, or 0 when it recorded none.
    public var observedAt: Int64

    public init(sessionId: String, pid: Int32, cwd: String, name: String, phase: Phase,
                waitingFor: String? = nil, focusUrl: String? = nil, terminal: String? = nil, observedAt: Int64) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.name = name
        self.phase = phase
        self.waitingFor = waitingFor
        self.focusUrl = focusUrl
        self.terminal = terminal
        self.observedAt = observedAt
    }

    /// Whether clicking this session can focus its terminal tab.
    public var isFocusable: Bool { focusUrl != nil }
}

/// Epoch millis now.
public func currentMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
