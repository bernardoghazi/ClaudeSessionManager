import Foundation

/// Where a session's terminal lives.
public struct SessionAddress: Equatable, Sendable {
    public let sessionId: String
    public let focusUrl: String?
    public let terminal: String?
    public let recordedAt: Int64

    public init(sessionId: String, focusUrl: String?, terminal: String?, recordedAt: Int64) {
        self.sessionId = sessionId
        self.focusUrl = focusUrl
        self.terminal = terminal
        self.recordedAt = recordedAt
    }
}

private struct AddressRecord: Decodable {
    var sessionId: String?
    var focusUrl: String?
    var terminal: String?
    var recordedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case focusUrl = "focus_url"
        case terminal
        case recordedAt = "recorded_at"
    }
}

/// Reads the addresses written by the plugin's hook into `<app home>/addresses/<session_id>.json`.
///
/// A spool directory rather than a socket: sessions almost always start before this app does,
/// and files persist until claimed. The hook writes via a temporary file and rename, so a
/// record is never observed half-written.
public struct AddressStore {
    /// Guards the startup race: the hook can land before the session's registry file exists.
    public static let defaultGraceMillis: Int64 = 5 * 60 * 1000

    private let dir: URL

    public init(dir: URL = Paths.addressesDir) {
        self.dir = dir
    }

    public func read() -> [String: SessionAddress] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var result: [String: SessionAddress] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(AddressRecord.self, from: data),
                  let id = record.sessionId, !id.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            result[id] = SessionAddress(sessionId: id, focusUrl: record.focusUrl, terminal: record.terminal,
                                        recordedAt: record.recordedAt ?? 0)
        }
        return result
    }

    /// Deletes addresses for sessions that are no longer live and are older than `grace`.
    public func reap(liveSessionIds: Set<String>, now: Int64, graceMillis: Int64 = defaultGraceMillis) {
        for (id, address) in read() {
            if liveSessionIds.contains(id) { continue }
            if now - address.recordedAt < graceMillis { continue }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        }
    }
}
