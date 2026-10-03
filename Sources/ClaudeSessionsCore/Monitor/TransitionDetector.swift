import Foundation

/// Something that happened to a session between two registry snapshots.
public enum SessionEvent: Sendable {
    /// First time this session was seen, including every session present at app startup.
    case appeared(LiveSession)
    /// The session moved between two *known* phases. The duration is measured from the
    /// registry's own `statusUpdatedAt`, so it is the real turn length, not a polling artefact.
    case phaseChanged(LiveSession, from: Phase, to: Phase, timeInPreviousPhase: Duration)
    /// Its process died or its registry file was removed.
    case ended(LiveSession)

    public var session: LiveSession {
        switch self {
        case .appeared(let s), .ended(let s), .phaseChanged(let s, _, _, _): s
        }
    }
}

/// Turns a stream of `RegistrySnapshot`s into `SessionEvent`s. Stateful and not thread-safe.
///
/// Two rules exist purely to avoid notifying about something that did not happen:
///  1. **An unreadable file is not a dead session.** Registry files are named `<pid>.json`, so an
///     unreadable file is matched back to its pid and only that session is held over.
///  2. **`.unknown` carries no information.** The previous known phase is kept and nothing is emitted.
public final class TransitionDetector {
    private struct Tracked {
        var session: LiveSession
        var phase: Phase
        var phaseSince: Int64
    }

    private let clock: () -> Int64
    private var tracked: [String: Tracked] = [:]

    public init(clock: @escaping () -> Int64 = currentMillis) {
        self.clock = clock
    }

    /// Sessions currently being tracked.
    public var known: [LiveSession] { tracked.values.map(\.session) }

    public func update(_ snapshot: RegistrySnapshot) -> [SessionEvent] {
        var events: [SessionEvent] = []
        var seen = Set<String>()

        for session in snapshot.sessions {
            seen.insert(session.sessionId)
            guard let previous = tracked[session.sessionId] else {
                tracked[session.sessionId] = Tracked(session: session, phase: session.phase, phaseSince: timestamp(session))
                events.append(.appeared(session))
                continue
            }
            if session.phase == .unknown || session.phase == previous.phase {
                // Refresh the payload but keep the phase and the clock that goes with it.
                tracked[session.sessionId]?.session = session
                continue
            }
            let now = timestamp(session)
            events.append(.phaseChanged(session, from: previous.phase, to: session.phase,
                                        timeInPreviousPhase: .milliseconds(max(0, now - previous.phaseSince))))
            tracked[session.sessionId] = Tracked(session: session, phase: session.phase, phaseSince: now)
        }

        let heldOver = unreadablePids(snapshot)
        for id in Set(tracked.keys).subtracting(seen).sorted() {
            guard let entry = tracked[id], !heldOver.contains(entry.session.pid) else { continue }
            tracked[id] = nil
            events.append(.ended(entry.session))
        }
        return events
    }

    private func unreadablePids(_ snapshot: RegistrySnapshot) -> Set<Int32> {
        Set(snapshot.skipped
            .filter { $0.reason == .unreadable }
            .compactMap { Int32($0.file.deletingPathExtension().lastPathComponent) })
    }

    /// Prefer the registry's own timestamp; fall back to wall clock when it is absent.
    private func timestamp(_ session: LiveSession) -> Int64 {
        session.observedAt > 0 ? session.observedAt : clock()
    }
}
