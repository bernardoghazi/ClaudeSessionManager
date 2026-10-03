import Foundation

/// The registry (what a session is doing) joined with its address (which terminal tab).
public final class SessionSource: SnapshotSource {
    private let registry: SessionRegistry
    private let addresses: AddressStore
    private let processes: ProcessAddressResolver
    private let clock: () -> Int64

    public init(registry: SessionRegistry = SessionRegistry(),
                addresses: AddressStore = AddressStore(),
                processes: ProcessAddressResolver = ProcessAddressResolver(),
                clock: @escaping () -> Int64 = currentMillis) {
        self.registry = registry
        self.addresses = addresses
        self.processes = processes
        self.clock = clock
    }

    public func read() -> RegistrySnapshot {
        var snapshot = registry.read()
        let byId = addresses.read()

        snapshot.sessions = snapshot.sessions.map { session in
            // The hook's record wins; the process environment covers everything else, including
            // sessions that were already running before the plugin existed.
            guard let address = byId[session.sessionId]
                ?? processes.resolve(pid: session.pid, sessionId: session.sessionId) else { return session }
            var merged = session
            merged.focusUrl = address.focusUrl
            merged.terminal = address.terminal
            return merged
        }

        processes.forget(livePids: Set(snapshot.sessions.map(\.pid)))

        // Only tidy up when the registry was fully readable: a file caught mid-write makes its
        // session look absent, and reaping on that would throw away a good address.
        if !snapshot.hasUnreadable {
            addresses.reap(liveSessionIds: Set(snapshot.sessions.map(\.sessionId)), now: clock())
        }
        return snapshot
    }
}
