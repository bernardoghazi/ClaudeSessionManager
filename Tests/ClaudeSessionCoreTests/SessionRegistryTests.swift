import Foundation
import Testing
@testable import ClaudeSessionCore

struct SessionRegistryTests {
    private let alive = ProcessLiveness { _ in 0 }
    private let dead = ProcessLiveness { _ in nil }

    /// A verbatim record as Claude Code 2.1.263 writes it, unknown fields included.
    private func record(pid: Int = 81464, sessionId: String = "edcdf906-40fd-409f-80e2-f3c1d23aa924",
                        kind: String = "interactive", status: String = "busy",
                        name: String? = "agents-overview-c3", cwd: String = "/Users/someone/Agents Overview",
                        extra: String = "") -> String {
        var s = #"{"pid":\#(pid),"sessionId":"\#(sessionId)","#
        s += #""cwd":"\#(cwd)","startedAt":1788899045477,"#
        s += #""procStart":"Tue Sep  8 20:24:03 2026","version":"2.1.263","#
        s += #""peerProtocol":1,"peerFeatures":["notify_idle","artifact_yield"],"#
        s += #""kind":"\#(kind)","entrypoint":"cli","pidDomain":"darwin","#
        s += #""messagingSocketPath":"/tmp/cc-socks/\#(pid).sock","#
        if let name { s += #""name":"\#(name)","nameSource":"derived","# }
        s += #""status":"\#(status)","updatedAt":1788900034310,"statusUpdatedAt":1788900034310\#(extra)}"#
        return s
    }

    private func registry(_ liveness: ProcessLiveness? = nil, files: [String: String]) -> RegistrySnapshot {
        let dir = tempDir("sessions")
        for (name, body) in files { write(body, to: dir.appendingPathComponent(name)) }
        return SessionRegistry(dir: dir, liveness: liveness ?? alive).read()
    }

    @Test func readsLiveInteractiveSessionIgnoringUnknownFields() {
        let s = registry(files: ["81464.json": record()])
        #expect(s.sessions.count == 1)
        let session = s.sessions[0]
        #expect(session.sessionId == "edcdf906-40fd-409f-80e2-f3c1d23aa924")
        #expect(session.pid == 81464)
        #expect(session.phase == .running)
        #expect(session.name == "agents-overview-c3")
        #expect(session.cwd == "/Users/someone/Agents Overview")
        #expect(session.observedAt == 1788900034310)
    }

    @Test func futureFieldDoesNotBreakRead() {
        #expect(registry(files: ["81464.json": record(extra: #","somethingNew":{"a":[1,2]}"#)]).sessions.count == 1)
    }

    @Test func carriesWaitingForThrough() {
        let s = registry(files: ["1.json": record(status: "waiting", extra: #","waitingFor":"input needed""#)]).sessions[0]
        #expect(s.phase == .waiting)
        #expect(s.waitingFor == "input needed")
    }

    @Test func skipsBackgroundAndDaemonSessions() {
        let s = registry(files: [
            "1.json": record(pid: 1, sessionId: "a", kind: "bg"),
            "2.json": record(pid: 2, sessionId: "b", kind: "daemon"),
            "3.json": record(pid: 3, sessionId: "c", kind: "daemon-worker"),
            "4.json": record(pid: 4, sessionId: "d", kind: "interactive"),
        ])
        #expect(s.sessions.map(\.sessionId) == ["d"])
        #expect(s.skipped.filter { $0.reason == .notInteractive }.count == 3)
    }

    @Test func reapsFileThatOutlivedItsProcess() {
        let s = registry(dead, files: ["81464.json": record()])
        #expect(s.sessions.isEmpty)
        #expect(s.skipped.map(\.reason) == [.deadProcess])
    }

    @Test func recycledPidIsNotMistakenForLiveSession() {
        let s = registry(ProcessLiveness { _ in 1788899045477 + 3_600_000 }, files: ["81464.json": record()])
        #expect(s.sessions.isEmpty)
        #expect(s.skipped.map(\.reason) == [.pidReused])
    }

    @Test func subSecondDriftIsFine() {
        #expect(registry(ProcessLiveness { _ in 1788899045477 - 432 }, files: ["81464.json": record()]).sessions.count == 1)
    }

    @Test func unreadableStartTimeIsStillAccepted() {
        #expect(registry(ProcessLiveness { _ in 0 }, files: ["81464.json": record()]).sessions.count == 1)
    }

    @Test func fileCaughtMidWriteIsUnreadableNotGone() {
        let truncated = String(record().prefix(120))
        let s = registry(files: ["1.json": truncated, "2.json": record(pid: 2, sessionId: "b")])
        #expect(s.sessions.map(\.sessionId) == ["b"])
        #expect(s.skipped.map(\.reason) == [.unreadable])
        #expect(s.hasUnreadable)
    }

    @Test func entryWithoutIdentityIsSkipped() {
        let s = registry(files: [
            "1.json": #"{"kind":"interactive","status":"idle","pid":1}"#,
            "2.json": #"{"kind":"interactive","status":"idle","sessionId":"b"}"#,
        ])
        #expect(s.sessions.isEmpty)
        #expect(s.skipped.filter { $0.reason == .missingIdentity }.count == 2)
    }

    @Test func fallsBackToFolderNameWhenUnnamed() {
        #expect(registry(files: ["1.json": record(name: nil, cwd: "/Users/someone/my-project")]).sessions[0].name == "my-project")
    }

    @Test func ignoresNonJsonFiles() {
        let s = registry(files: ["81464.json": record(), "81464.abc123.key": "binary-ish", "notes.txt": "hello"])
        #expect(s.sessions.count == 1)
        #expect(s.skipped.isEmpty)
    }

    @Test func missingDirectoryIsEmptyNotError() {
        let s = SessionRegistry(dir: tempDir().appendingPathComponent("nope"), liveness: alive).read()
        #expect(s.sessions.isEmpty)
        #expect(s.skipped.isEmpty)
    }

    @Test func runningSessionIdsIncludesEveryKind() {
        let dir = tempDir("sessions")
        write(record(pid: 1, sessionId: "a", kind: "bg"), to: dir.appendingPathComponent("1.json"))
        write(record(pid: 2, sessionId: "b"), to: dir.appendingPathComponent("2.json"))
        #expect(SessionRegistry(dir: dir, liveness: alive).runningSessionIds() == ["a", "b"])
        #expect(SessionRegistry(dir: dir, liveness: dead).runningSessionIds().isEmpty)
    }

    @Test func mapsStatusValues() {
        #expect(Phase(registryStatus: "busy") == .running)
        #expect(Phase(registryStatus: "idle") == .idle)
        #expect(Phase(registryStatus: "waiting") == .waiting)
        #expect(Phase(registryStatus: "shell") == .idle)
        #expect(Phase(registryStatus: nil) == .unknown)
        #expect(Phase(registryStatus: "") == .unknown)
        #expect(Phase(registryStatus: "compacting") == .unknown)
    }

    @Test func systemLivenessSeesThisProcess() {
        let me = ProcessInfo.processInfo.processIdentifier
        let started = ProcessLiveness.system.startedAtMillis(me)
        #expect(started != nil)
        #expect((started ?? 0) <= currentMillis())
        #expect((started ?? 0) > currentMillis() - 3_600_000)
    }
}
