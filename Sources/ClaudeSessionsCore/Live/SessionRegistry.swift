import Foundation

/// The on-disk shape of `~/.claude/sessions/<pid>.json`.
///
/// Every field is optional: the format is internal to Claude Code and undocumented, so a schema
/// change should degrade one field rather than fail the whole read.
struct RegistryEntry: Decodable {
    var pid: Int64?
    var sessionId: String?
    var cwd: String?
    var name: String?
    var kind: String?
    var status: String?
    var waitingFor: String?
    var version: String?
    var startedAt: Int64?
    var updatedAt: Int64?
    var statusUpdatedAt: Int64?
}

/// Why a registry file did not become a `LiveSession`.
public enum SkipReason: Sendable {
    /// File could not be parsed. Usually a partial read of a file mid-write.
    case unreadable
    /// A background or daemon session, not a terminal the user can return to.
    case notInteractive
    /// The registry file outlived its process.
    case deadProcess
    /// The pid is running, but it is a different process that inherited the number.
    case pidReused
    /// No `sessionId` or no `pid`, so the entry cannot be identified.
    case missingIdentity
}

public struct SkippedEntry: Sendable {
    public let file: URL
    public let reason: SkipReason

    public init(file: URL, reason: SkipReason) {
        self.file = file
        self.reason = reason
    }
}

/// One reading of the whole registry directory.
///
/// `skipped` matters as much as `sessions`: an entry skipped as `.unreadable` is *not* evidence
/// that the session ended, so a consumer diffing snapshots must not mark it gone.
public struct RegistrySnapshot: Sendable {
    public var sessions: [LiveSession]
    public var skipped: [SkippedEntry]

    public init(sessions: [LiveSession], skipped: [SkippedEntry] = []) {
        self.sessions = sessions
        self.skipped = skipped
    }

    public var hasUnreadable: Bool { skipped.contains { $0.reason == .unreadable } }
}

/// Anything that can produce a snapshot of current sessions.
public protocol SnapshotSource {
    func read() -> RegistrySnapshot
}

/// Reads Claude Code's live session registry.
public struct SessionRegistry: SnapshotSource {
    /// How far a process's start time may sit from the session's recorded start before we stop
    /// believing they are the same process. Observed drift is well under a second.
    static let pidReuseToleranceMillis: Int64 = 30_000

    private let dir: URL
    private let liveness: ProcessLiveness

    public init(dir: URL = Paths.registryDir, liveness: ProcessLiveness = .system) {
        self.dir = dir
        self.liveness = liveness
    }

    public func read() -> RegistrySnapshot {
        var sessions: [LiveSession] = []
        var skipped: [SkippedEntry] = []
        for file in files() {
            switch readEntry(file) {
            case .success(let session): sessions.append(session)
            case .failure(let skip): skipped.append(SkippedEntry(file: file, reason: skip.reason))
            }
        }
        return RegistrySnapshot(sessions: sessions, skipped: skipped)
    }

    /// Ids of every session with a live process, of any kind. Used to refuse renaming a session
    /// that is open anywhere, including in background workers the menu does not show.
    public func runningSessionIds() -> Set<String> {
        var ids = Set<String>()
        for file in files() {
            guard let entry = decode(file), let pid = entry.pid, let id = entry.sessionId,
                  liveness.isAlive(Int32(truncatingIfNeeded: pid)) else { continue }
            ids.insert(id)
        }
        return ids
    }

    private func files() -> [URL] {
        // A missing directory means Claude Code has never run, not an error.
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func decode(_ file: URL) -> RegistryEntry? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(RegistryEntry.self, from: data)
    }

    private struct Skip: Error { let reason: SkipReason }

    private func readEntry(_ file: URL) -> Result<LiveSession, Skip> {
        // Covers both a truncated file caught mid-write and a schema we cannot read.
        guard let entry = decode(file) else { return .failure(Skip(reason: .unreadable)) }
        guard let rawPid = entry.pid, let sessionId = entry.sessionId,
              !sessionId.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(Skip(reason: .missingIdentity))
        }
        // Background workers and daemons are real sessions but not places a user can go.
        guard entry.kind == "interactive" else { return .failure(Skip(reason: .notInteractive)) }

        let pid = Int32(truncatingIfNeeded: rawPid)
        guard let processStart = liveness.startedAtMillis(pid) else {
            return .failure(Skip(reason: .deadProcess))
        }
        // If the process holding this pid started well away from the session, something else
        // inherited its number.
        if let sessionStart = entry.startedAt, processStart > 0,
           abs(processStart - sessionStart) > Self.pidReuseToleranceMillis {
            return .failure(Skip(reason: .pidReused))
        }

        let cwd = entry.cwd ?? ""
        let folderName = (cwd as NSString).lastPathComponent
        let name = [entry.name, folderName, sessionId]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? sessionId
        return .success(LiveSession(
            sessionId: sessionId,
            pid: pid,
            cwd: cwd,
            name: name,
            phase: Phase(registryStatus: entry.status),
            waitingFor: entry.waitingFor,
            observedAt: entry.statusUpdatedAt ?? entry.updatedAt ?? 0
        ))
    }
}
