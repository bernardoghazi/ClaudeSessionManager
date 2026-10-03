import Foundation
import Testing
@testable import ClaudeSessionsCore

struct AddressStoreTests {
    /// Exactly what the plugin's record-address.sh hook writes.
    private func record(id: String = "a", url: String = "warp://session/abc", at: Int64 = 1_000) -> String {
        #"{"session_id":"\#(id)","cwd":"/Users/me/My Project","source":"startup","focus_url":"\#(url)","terminal":"WarpTerminal","terminal_session_uuid":"abc","recorded_at":\#(at)}"#
    }

    private func store(_ files: [String: String]) -> (AddressStore, URL) {
        let dir = tempDir("addresses")
        for (name, body) in files { write(body, to: dir.appendingPathComponent(name)) }
        return (AddressStore(dir: dir), dir)
    }

    @Test func readsWhatTheHookWrote() {
        let address = store(["a.json": record()]).0.read()["a"]
        #expect(address?.focusUrl == "warp://session/abc")
        #expect(address?.terminal == "WarpTerminal")
        #expect(address?.recordedAt == 1_000)
    }

    @Test func malformedRecordIsSkipped() {
        #expect(Set(store(["a.json": "{oops", "b.json": record(id: "b")]).0.read().keys) == ["b"])
    }

    @Test func missingDirectoryIsEmpty() {
        #expect(AddressStore(dir: tempDir().appendingPathComponent("nope")).read().isEmpty)
    }

    @Test func reapsAddressesWhoseSessionIsGone() {
        let (s, dir) = store(["a.json": record(at: 0)])
        s.reap(liveSessionIds: [], now: 10 * 60 * 1000)
        #expect(s.read().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.json").path))
    }

    @Test func keepsAddressesForLiveSessions() {
        let (s, _) = store(["a.json": record(at: 0)])
        s.reap(liveSessionIds: ["a"], now: 10 * 60 * 1000)
        #expect(Set(s.read().keys) == ["a"])
    }

    @Test func brandNewAddressSurvivesStartupRace() {
        let (s, _) = store(["a.json": record(at: 1_000)])
        s.reap(liveSessionIds: [], now: 1_000 + 30_000)
        #expect(Set(s.read().keys) == ["a"])
    }

    @Test func recordWithoutSessionIdIsIgnored() {
        #expect(store(["a.json": #"{"focus_url":"warp://session/x"}"#]).0.read().isEmpty)
    }
}

struct ProcessAddressResolverTests {
    private final class Counting: @unchecked Sendable {
        var reads = 0
        let envs: [Int32: [String: String]]
        init(_ envs: [Int32: [String: String]]) { self.envs = envs }
        var environment: ProcessEnvironment { ProcessEnvironment { pid in self.reads += 1; return self.envs[pid] ?? [:] } }
    }

    private func warp(_ url: String) -> [String: String] {
        ["WARP_FOCUS_URL": url, "TERM_PROGRAM": "WarpTerminal", "PATH": "/usr/bin"]
    }

    @Test func recoversAddressOfRunningSession() {
        let env = Counting([55395: warp("warp://session/tab1")])
        let address = ProcessAddressResolver(environment: env.environment).resolve(pid: 55395, sessionId: "abc")
        #expect(address?.focusUrl == "warp://session/tab1")
        #expect(address?.terminal == "WarpTerminal")
    }

    @Test func readsEnvironmentOnlyOnce() {
        let env = Counting([1: warp("warp://session/tab1")])
        let r = ProcessAddressResolver(environment: env.environment)
        for _ in 0..<20 { _ = r.resolve(pid: 1, sessionId: "abc") }
        #expect(env.reads == 1)
    }

    @Test func negativeResultIsCachedToo() {
        let env = Counting([:])
        let r = ProcessAddressResolver(environment: env.environment)
        for _ in 0..<5 { #expect(r.resolve(pid: 1, sessionId: "abc") == nil) }
        #expect(env.reads == 1)
    }

    @Test func nonWarpTerminalHasNoAddress() {
        let env = Counting([1: ["TERM_PROGRAM": "Apple_Terminal"]])
        #expect(ProcessAddressResolver(environment: env.environment).resolve(pid: 1, sessionId: "abc") == nil)
    }

    @Test func forgettingExitedProcessesKeepsCacheBounded() {
        let env = Counting([1: warp("warp://session/a"), 2: warp("warp://session/b")])
        let r = ProcessAddressResolver(environment: env.environment)
        _ = r.resolve(pid: 1, sessionId: "a"); _ = r.resolve(pid: 2, sessionId: "b")
        #expect(env.reads == 2)
        r.forget(livePids: [2])
        _ = r.resolve(pid: 2, sessionId: "b")
        #expect(env.reads == 2)
        _ = r.resolve(pid: 1, sessionId: "a")
        #expect(env.reads == 3)
    }

    @Test func systemEnvironmentReadsThisProcess() {
        let env = ProcessEnvironment.system.read(ProcessInfo.processInfo.processIdentifier)
        #expect(env["HOME"] != nil || env["PATH"] != nil)
    }
}

struct SessionSourceTests {
    private func session(_ pid: Int32, _ id: String) -> String {
        #"{"pid":\#(pid),"sessionId":"\#(id)","cwd":"/tmp/p","kind":"interactive","status":"idle"}"#
    }

    private func address(_ id: String, _ url: String, at: Int64 = Int64.max / 2) -> String {
        #"{"session_id":"\#(id)","focus_url":"\#(url)","terminal":"WarpTerminal","recorded_at":\#(at)}"#
    }

    private func source(_ s: URL, _ a: URL, now: Int64 = 0, env: [Int32: [String: String]] = [:]) -> SessionSource {
        SessionSource(registry: SessionRegistry(dir: s, liveness: ProcessLiveness { _ in 0 }),
                      addresses: AddressStore(dir: a),
                      processes: ProcessAddressResolver(environment: ProcessEnvironment { env[$0] ?? [:] }),
                      clock: { now })
    }

    @Test func preExistingSessionGetsAddressFromEnvironment() {
        let (s, a) = (tempDir(), tempDir())
        write(session(55395, "abc"), to: s.appendingPathComponent("1.json"))
        let result = source(s, a, env: [55395: ["WARP_FOCUS_URL": "warp://session/tab7"]]).read().sessions[0]
        #expect(result.focusUrl == "warp://session/tab7")
        #expect(result.isFocusable)
    }

    @Test func recordedAddressWinsOverEnvironment() {
        let (s, a) = (tempDir(), tempDir())
        write(session(1, "abc"), to: s.appendingPathComponent("1.json"))
        write(address("abc", "warp://session/recorded"), to: a.appendingPathComponent("abc.json"))
        let result = source(s, a, env: [1: ["WARP_FOCUS_URL": "warp://session/from-env"]]).read().sessions[0]
        #expect(result.focusUrl == "warp://session/recorded")
        #expect(result.terminal == "WarpTerminal")
    }

    @Test func sessionWithoutAddressIsReportedNotFocusable() {
        let (s, a) = (tempDir(), tempDir())
        write(session(1, "abc"), to: s.appendingPathComponent("1.json"))
        let result = source(s, a).read().sessions[0]
        #expect(result.focusUrl == nil)
        #expect(!result.isFocusable)
    }

    @Test func forkedSessionsShareOneAddress() {
        let (s, a) = (tempDir(), tempDir())
        write(session(1, "parent"), to: s.appendingPathComponent("1.json"))
        write(session(2, "child"), to: s.appendingPathComponent("2.json"))
        write(address("parent", "warp://session/tab1"), to: a.appendingPathComponent("parent.json"))
        write(address("child", "warp://session/tab1"), to: a.appendingPathComponent("child.json"))
        let sessions = source(s, a).read().sessions
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.focusUrl == "warp://session/tab1" })
    }

    @Test func unreadableRegistryFileSuspendsReaping() {
        let (s, a) = (tempDir(), tempDir())
        write("{truncated", to: s.appendingPathComponent("1.json"))
        write(address("abc", "warp://session/tab1", at: 0), to: a.appendingPathComponent("abc.json"))
        _ = source(s, a, now: Int64.max / 4).read()
        #expect(Set(AddressStore(dir: a).read().keys) == ["abc"])
    }

    @Test func addressOutlastingItsSessionIsCleanedUp() {
        let (s, a) = (tempDir(), tempDir())
        write(address("gone", "warp://session/tab9", at: 0), to: a.appendingPathComponent("gone.json"))
        _ = source(s, a, now: Int64.max / 4).read()
        #expect(AddressStore(dir: a).read().isEmpty)
    }
}
