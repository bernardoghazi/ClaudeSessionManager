import Foundation
@testable import ClaudeSessionCore

func tempDir(_ name: String = "test") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("csm-\(name)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(text.utf8).write(to: url)
}

func read(_ url: URL) -> String {
    String(decoding: try! Data(contentsOf: url), as: UTF8.self)
}

func live(id: String = "a", pid: Int32 = 100, phase: Phase = .running, at: Int64 = 1_000,
          name: String = "project", waitingFor: String? = nil, focusUrl: String? = nil) -> LiveSession {
    LiveSession(sessionId: id, pid: pid, cwd: "/tmp/project", name: name, phase: phase,
                waitingFor: waitingFor, focusUrl: focusUrl, observedAt: at)
}

/// Thread-safe recorder for injected command runners.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [[String]] = []
    var commands: [[String]] { lock.lock(); defer { lock.unlock() }; return _commands }
    func add(_ c: [String]) { lock.lock(); _commands.append(c); lock.unlock() }
}
