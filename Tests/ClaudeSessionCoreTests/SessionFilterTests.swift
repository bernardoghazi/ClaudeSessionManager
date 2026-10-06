import Foundation
import Testing
@testable import ClaudeSessionCore

struct SessionFilterTests {
    private func session(_ id: String = "s1", title: String = "Fix login bug", folder: String = "/work/app",
                         branch: String = "main") -> Session {
        Session(id: id, path: URL(fileURLWithPath: "/tmp/\(id).jsonl"), title: title, folder: folder, branch: branch,
                modified: Date(), size: 1)
    }

    @Test func statusChoicesMatchTheRightPhases() {
        let phases: [Phase?] = [nil, .running, .waiting, .idle, .unknown]
        func matched(_ s: StatusFilter) -> [Phase?] { phases.filter { s.matches($0) } }
        #expect(matched(.all) == phases)
        #expect(matched(.running) == [.running, .waiting, .idle, .unknown])
        #expect(matched(.waiting) == [.waiting])
        #expect(matched(.working) == [.running])
        #expect(matched(.idle) == [.idle, .unknown])
        #expect(matched(.notRunning) == [nil])
    }

    @Test func folderMatchesExactly() {
        let f = SessionFilter(folders: ["/work/app"])
        #expect(f.matches(session(folder: "/work/app"), phase: nil, contentMatches: nil))
        #expect(!f.matches(session(folder: "/work/app-old"), phase: nil, contentMatches: nil))
        #expect(!f.matches(session(folder: "/work"), phase: nil, contentMatches: nil))
    }

    @Test func anyOfSeveralFoldersMatches() {
        let f = SessionFilter(folders: ["/work/app", "/work/site"])
        #expect(f.matches(session(folder: "/work/app"), phase: nil, contentMatches: nil))
        #expect(f.matches(session(folder: "/work/site"), phase: nil, contentMatches: nil))
        #expect(!f.matches(session(folder: "/work/other"), phase: nil, contentMatches: nil))
        #expect(SessionFilter(folders: []).matches(session(folder: "/anywhere"), phase: nil, contentMatches: nil))
    }

    @Test func titleScopeIgnoresEverythingButTheTitle() {
        let f = SessionFilter(query: "login", scope: .title)
        #expect(f.matches(session(), phase: nil, contentMatches: nil))
        #expect(!f.matches(session(title: "Other", folder: "/login"), phase: nil, contentMatches: ["s1"]))
    }

    @Test func contentScopeUsesOnlyTheTranscriptMatches() {
        let f = SessionFilter(query: "login", scope: .content)
        #expect(!f.matches(session(), phase: nil, contentMatches: []))
        #expect(!f.matches(session(), phase: nil, contentMatches: nil))
        #expect(f.matches(session(title: "Other"), phase: nil, contentMatches: ["s1"]))
    }

    @Test func allScopeMatchesAnyField() {
        let f = SessionFilter(query: "needle")
        #expect(f.matches(session(title: "a needle"), phase: nil, contentMatches: nil))
        #expect(f.matches(session(title: "x", folder: "/needle"), phase: nil, contentMatches: nil))
        #expect(f.matches(session(title: "x", branch: "needle-fix"), phase: nil, contentMatches: nil))
        #expect(f.matches(session("needle-id", title: "x"), phase: nil, contentMatches: nil))
        #expect(f.matches(session(title: "x"), phase: nil, contentMatches: ["s1"]))
        #expect(!f.matches(session(title: "x"), phase: nil, contentMatches: []))
    }

    @Test func everyFilterMustPass() {
        let f = SessionFilter(folders: ["/work/app"], status: .running, query: "login", scope: .title)
        #expect(f.matches(session(), phase: .idle, contentMatches: nil))
        #expect(!f.matches(session(), phase: nil, contentMatches: nil))                       // not running
        #expect(!f.matches(session(folder: "/elsewhere"), phase: .idle, contentMatches: nil))  // wrong folder
        #expect(!f.matches(session(title: "Other"), phase: .idle, contentMatches: nil))        // title misses
    }

    @Test func blankQueryMatchesEverythingElsePassing() {
        #expect(SessionFilter(query: "   ", scope: .content).matches(session(), phase: nil, contentMatches: nil))
    }

    @Test func activeAndContentSearchFlags() {
        #expect(!SessionFilter().isActive)
        #expect(!SessionFilter(query: "  ", scope: .content).isActive)
        #expect(SessionFilter(folders: ["/a"]).isActive)
        #expect(SessionFilter(status: .waiting).isActive)
        #expect(SessionFilter(query: "x").isActive)

        #expect(!SessionFilter().needsContentSearch)
        #expect(!SessionFilter(query: "x", scope: .title).needsContentSearch)
        #expect(SessionFilter(query: "x", scope: .all).needsContentSearch)
        #expect(SessionFilter(query: "x", scope: .content).needsContentSearch)
    }
}
