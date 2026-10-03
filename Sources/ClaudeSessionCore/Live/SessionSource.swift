import Foundation

/// The registry (what a session is doing) joined with its address (which terminal tab), read
/// from the session's own process environment.
public final class SessionSource: SnapshotSource {
    private let registry: SessionRegistry
    private let processes: ProcessAddressResolver

    public init(registry: SessionRegistry = SessionRegistry(),
                processes: ProcessAddressResolver = ProcessAddressResolver()) {
        self.registry = registry
        self.processes = processes
    }

    public func read() -> RegistrySnapshot {
        var snapshot = registry.read()
        snapshot.sessions = snapshot.sessions.map { session in
            guard let address = processes.resolve(pid: session.pid) else { return session }
            var merged = session
            merged.focusUrl = address.focusUrl
            merged.terminal = address.terminal
            return merged
        }
        processes.forget(livePids: Set(snapshot.sessions.map(\.pid)))
        return snapshot
    }
}
