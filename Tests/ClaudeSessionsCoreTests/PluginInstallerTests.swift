import Foundation
import Testing
@testable import ClaudeSessionsCore

struct PluginInstallerTests {
    private let claude = URL(fileURLWithPath: "/usr/local/bin/claude")

    /// Exactly the shape `claude plugin list --json` prints.
    private func listing(_ ids: String...) -> String {
        "[" + ids.map { #"{"id":"\#($0)","version":"0.1.0","scope":"user","enabled":true}"# }.joined(separator: ",") + "]"
    }

    private func installer(source: URL? = nil, target: URL = tempDir("target"), cli: URL?? = nil,
                           respond: @escaping @Sendable ([String]) -> CommandResult) -> PluginInstaller {
        let resolved: URL? = cli ?? claude
        return PluginInstaller(source: source, target: target, cli: { resolved }, run: respond)
    }

    @Sendable private static func fail(_: [String]) -> CommandResult {
        Issue.record("must not run a command")
        return CommandResult(exitCode: 1, output: "")
    }

    @Test func installedWhenListed() {
        let out = listing("other@x", PluginInstaller.id)
        #expect(installer { _ in CommandResult(exitCode: 0, output: out) }.status() == .installed)
    }

    @Test func notInstalledWhenOnlyOthersListed() {
        let out = listing("other@x")
        #expect(installer { _ in CommandResult(exitCode: 0, output: out) }.status() == .notInstalled)
    }

    @Test func disabledCountsAsNotInstalled() {
        let out = #"[{"id":"\#(PluginInstaller.id)","enabled":false}]"#
        #expect(installer { _ in CommandResult(exitCode: 0, output: out) }.status() == .notInstalled)
    }

    @Test func noCliMeansNoAnswer() {
        #expect(installer(cli: .some(nil), respond: Self.fail).status() == .noCli)
    }

    @Test func unreadableAnswerIsNotAbsentPlugin() {
        #expect(installer { _ in CommandResult(exitCode: 0, output: "not json") }.status() == .unknown)
        #expect(installer { _ in CommandResult(exitCode: 1, output: "boom") }.status() == .unknown)
    }

    @Test func toleratesNoiseAroundJson() {
        let out = "warning: something\n\(listing(PluginInstaller.id))\n"
        #expect(installer { _ in CommandResult(exitCode: 0, output: out) }.status() == .installed)
    }

    @Test func syncCopiesBundledPlugin() {
        let source = tempDir("bundled"), target = tempDir("target")
        write(#"{"hooks":{}}"#, to: source.appendingPathComponent("hooks/hooks.json"))
        #expect(installer(source: source, target: target, respond: Self.fail).sync())
        #expect(read(target.appendingPathComponent("hooks/hooks.json")) == #"{"hooks":{}}"#)
    }

    @Test func syncOverwritesOlderCopy() {
        let source = tempDir("bundled"), target = tempDir("target")
        write("new", to: source.appendingPathComponent("marker"))
        write("old", to: target.appendingPathComponent("marker"))
        installer(source: source, target: target, respond: Self.fail).sync()
        #expect(read(target.appendingPathComponent("marker")) == "new")
    }

    @Test func installRegistersTargetNotBundle() {
        let source = tempDir("bundled"), target = tempDir("target")
        write("x", to: source.appendingPathComponent("marker"))
        let recorder = Recorder()
        let ok = installer(source: source, target: target) { recorder.add($0); return CommandResult(exitCode: 0, output: "ok") }.install()
        #expect(ok)
        #expect(recorder.commands.first == [claude.path, "plugin", "marketplace", "add", target.path])
        #expect(recorder.commands.last == [claude.path, "plugin", "install", PluginInstaller.id, "-y"])
    }

    @Test func installRunsNothingWithoutPluginToSync() {
        #expect(!installer(source: nil, respond: Self.fail).install())
    }

    @Test func removesLegacyPluginWhenPresent() {
        let recorder = Recorder()
        let out = listing(PluginInstaller.legacyId)
        let removed = installer { recorder.add($0); return CommandResult(exitCode: 0, output: out) }.removeLegacyPlugin()
        #expect(removed)
        #expect(recorder.commands.dropFirst().map { Array($0.dropFirst()) } == [
            ["plugin", "uninstall", PluginInstaller.legacyId],
            ["plugin", "marketplace", "remove", "agents-overview"],
        ])
    }

    @Test func leavesThingsAloneWithoutLegacyPlugin() {
        let recorder = Recorder()
        let out = listing(PluginInstaller.id)
        #expect(!installer { recorder.add($0); return CommandResult(exitCode: 0, output: out) }.removeLegacyPlugin())
        #expect(recorder.commands.count == 1)  // only the listing
    }
}
