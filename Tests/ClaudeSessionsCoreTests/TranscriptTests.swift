import Foundation
import Testing
@testable import ClaudeSessionsCore

struct TranscriptTests {
    private func transcript(_ lines: [String], id: String = "abc-123") -> (URL, URL) {
        let projects = tempDir("projects")
        let file = projects.appendingPathComponent("-tmp-project/\(id).jsonl")
        write(lines.joined(separator: "\n") + "\n", to: file)
        return (projects, file)
    }

    private let base = [
        #"{"type":"user","cwd":"/tmp/old","gitBranch":"main","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
        #"{"type":"user","cwd":"/tmp/project","gitBranch":"feature/x","message":{"role":"user","content":"Fix the\nlogin bug"}}"#,
    ]

    @Test func titleFallsBackToFirstRealPrompt() {
        let (projects, _) = transcript(base)
        let s = SessionIndex.load(from: projects)
        #expect(s.count == 1)
        #expect(s[0].id == "abc-123")
        #expect(s[0].title == "Fix the login bug")
        #expect(s[0].folder == "/tmp/project")
        #expect(s[0].branch == "feature/x")
        #expect(s[0].resumeCommand == "claude -r abc-123")
    }

    @Test func latestCustomTitleWinsOverAiTitle() {
        let (projects, _) = transcript(base + [
            #"{"type":"ai-title","aiTitle":"AI name"}"#,
            #"{"type":"custom-title","customTitle":"First","sessionId":"abc-123"}"#,
            #"{"type":"custom-title","customTitle":"Second \"quoted\"","sessionId":"abc-123"}"#,
        ])
        #expect(SessionIndex.load(from: projects)[0].title == #"Second "quoted""#)
    }

    @Test func transcriptWithoutCwdIsSkipped() {
        let (projects, _) = transcript([#"{"type":"summary","summary":"x"}"#])
        #expect(SessionIndex.load(from: projects).isEmpty)
    }

    @Test func unchangedFileComesFromCache() {
        let (projects, _) = transcript(base)
        let first = SessionIndex.load(from: projects)[0]
        let fake = Session(id: first.id, path: first.path, title: "cached", folder: first.folder, branch: first.branch,
                           modified: first.modified, size: first.size)
        #expect(SessionIndex.load(from: projects, cache: [first.path: fake])[0].title == "cached")
    }

    @Test func renameAppendsBothRecordsAndWins() throws {
        let (projects, file) = transcript(base)
        let session = SessionIndex.load(from: projects)[0]
        try Renamer.rename(session, to: "New / name", isRunning: false)

        let tail = read(file).split(separator: "\n").suffix(2)
        #expect(Array(tail) == [
            #"{"type":"custom-title","customTitle":"New / name","sessionId":"abc-123"}"#,
            #"{"type":"agent-name","agentName":"New / name","sessionId":"abc-123"}"#,
        ])
        #expect(SessionIndex.load(from: projects)[0].title == "New / name")
    }

    @Test func renameAddsMissingTrailingNewline() throws {
        let projects = tempDir("projects")
        let file = projects.appendingPathComponent("p/s1.jsonl")
        write(#"{"cwd":"/tmp"}"#, to: file)
        try Renamer.rename(SessionIndex.load(from: projects)[0], to: "T", isRunning: false)
        #expect(read(file).hasPrefix(#"{"cwd":"/tmp"}"# + "\n" + #"{"type":"custom-title""#))
    }

    @Test func renameRefusesRunningSession() {
        let (projects, _) = transcript(base)
        let session = SessionIndex.load(from: projects)[0]
        #expect(throws: RenameError.self) { try Renamer.rename(session, to: "x", isRunning: true) }
    }

    @Test func contentSearchIgnoresAsciiCase() async {
        let (_, file) = transcript(base)
        #expect(await ContentSearch.search([(id: "a", url: file)], for: "LOGIN") == ["a"])
        #expect(await ContentSearch.search([(id: "a", url: file)], for: "nowhere").isEmpty)
    }
}
