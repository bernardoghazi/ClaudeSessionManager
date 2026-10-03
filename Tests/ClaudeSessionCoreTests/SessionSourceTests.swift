import Foundation
import Testing
@testable import ClaudeSessionCore

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
        let address = ProcessAddressResolver(environment: env.environment).resolve(pid: 55395)
        #expect(address?.focusUrl == "warp://session/tab1")
        #expect(address?.terminal == "WarpTerminal")
    }

    @Test func readsEnvironmentOnlyOnce() {
        let env = Counting([1: warp("warp://session/tab1")])
        let r = ProcessAddressResolver(environment: env.environment)
        for _ in 0..<20 { _ = r.resolve(pid: 1) }
        #expect(env.reads == 1)
    }

    @Test func negativeResultIsCachedToo() {
        let env = Counting([:])
        let r = ProcessAddressResolver(environment: env.environment)
        for _ in 0..<5 { #expect(r.resolve(pid: 1) == nil) }
        #expect(env.reads == 1)
    }

    @Test func nonWarpTerminalHasNoAddress() {
        let env = Counting([1: ["TERM_PROGRAM": "Apple_Terminal"]])
        #expect(ProcessAddressResolver(environment: env.environment).resolve(pid: 1) == nil)
    }

    @Test func forgettingExitedProcessesKeepsCacheBounded() {
        let env = Counting([1: warp("warp://session/a"), 2: warp("warp://session/b")])
        let r = ProcessAddressResolver(environment: env.environment)
        _ = r.resolve(pid: 1); _ = r.resolve(pid: 2)
        #expect(env.reads == 2)
        r.forget(livePids: [2])
        _ = r.resolve(pid: 2)
        #expect(env.reads == 2)
        _ = r.resolve(pid: 1)
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

    private func source(_ dir: URL, env: [Int32: [String: String]] = [:]) -> SessionSource {
        SessionSource(registry: SessionRegistry(dir: dir, liveness: ProcessLiveness { _ in 0 }),
                      processes: ProcessAddressResolver(environment: ProcessEnvironment { env[$0] ?? [:] }))
    }

    @Test func sessionGetsAddressFromItsEnvironment() {
        let dir = tempDir()
        write(session(55395, "abc"), to: dir.appendingPathComponent("55395.json"))
        let result = source(dir, env: [55395: ["WARP_FOCUS_URL": "warp://session/tab7", "TERM_PROGRAM": "WarpTerminal"]])
            .read().sessions[0]
        #expect(result.focusUrl == "warp://session/tab7")
        #expect(result.terminal == "WarpTerminal")
        #expect(result.isFocusable)
    }

    @Test func sessionWithoutAddressIsReportedNotFocusable() {
        let dir = tempDir()
        write(session(1, "abc"), to: dir.appendingPathComponent("1.json"))
        let result = source(dir).read().sessions[0]
        #expect(result.focusUrl == nil)
        #expect(!result.isFocusable)
    }

    @Test func forkedSessionsInOneTabShareItsAddress() {
        let dir = tempDir()
        write(session(1, "parent"), to: dir.appendingPathComponent("1.json"))
        write(session(2, "child"), to: dir.appendingPathComponent("2.json"))
        let tab = ["WARP_FOCUS_URL": "warp://session/tab1"]
        let sessions = source(dir, env: [1: tab, 2: tab]).read().sessions
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.focusUrl == "warp://session/tab1" })
    }
}
