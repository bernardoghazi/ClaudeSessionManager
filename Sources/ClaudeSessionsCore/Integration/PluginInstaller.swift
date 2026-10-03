import Foundation

/// What the companion plugin's registration looks like from here.
public enum PluginStatus: Sendable {
    /// Registered with Claude Code and enabled.
    case installed
    /// Claude Code is present but does not know about the plugin.
    case notInstalled
    /// The `claude` executable could not be found, so nothing can be said.
    case noCli
    /// The CLI was there but did not answer in a shape we understand.
    case unknown
}

/// Registers the companion plugin with Claude Code.
///
/// - **Register through the CLI, never by editing `settings.json`.** Claude Code owns that file
///   and rewrites it; a read-modify-write from here could drop somebody's other plugins.
/// - **Point the marketplace at a stable directory, not the app bundle.** Reinstalling replaces
///   the whole `.app`, so the bundled copy is synced to `target`, which survives that. A
///   `directory` marketplace runs the plugin from that path, so the sync is also what makes an
///   upgrade take effect.
public struct PluginInstaller: Sendable {
    public static let id = "claude-sessions-manager@claude-sessions-manager"

    let source: URL?
    let target: URL
    let log: ActivityLog
    let cli: @Sendable () -> URL?
    let run: @Sendable ([String]) -> CommandResult

    public init(source: URL?,
                target: URL = Paths.pluginMirrorDir,
                log: ActivityLog = .none,
                cli: @escaping @Sendable () -> URL? = { PluginInstaller.findCli() },
                run: @escaping @Sendable ([String]) -> CommandResult = { Shell.run($0) }) {
        self.source = source
        self.target = target
        self.log = log
        self.cli = cli
        self.run = run
    }

    /// Asks the CLI what it knows. Spawns a process, so call it sparingly.
    public func status() -> PluginStatus {
        guard let listed = listPlugins() else { return cli() == nil ? .noCli : .unknown }
        guard let ours = listed.first(where: { $0.id == Self.id }), ours.enabled != false else { return .notInstalled }
        return .installed
    }

    /// Copies the bundled plugin to `target` and registers it. Safe to repeat, so it doubles as repair.
    @discardableResult
    public func install() -> Bool {
        guard let claude = cli() else {
            log.record("plugin install skipped: no claude executable found")
            return false
        }
        guard sync() else { return false }

        let add = run([claude.path, "plugin", "marketplace", "add", target.path])
        log.record("plugin marketplace add: exit=\(add.exitCode) \(add.output.trimmed)")
        // -y because there is no terminal to answer a confirmation prompt.
        let install = run([claude.path, "plugin", "install", Self.id, "-y"])
        log.record("plugin install: exit=\(install.exitCode) \(install.output.trimmed)")
        return install.succeeded
    }

    /// Mirrors the bundled plugin into `target`. Each file is replaced atomically, so a session
    /// reading a hook script at the same moment never sees it missing.
    @discardableResult
    public func sync() -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard let source, fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else {
            log.record("plugin sync skipped: no bundled plugin at \(source?.path ?? "nil")")
            return false
        }
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let root = source.resolvingSymlinksInPath().path
            guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
            for case let url as URL in walker {
                let relative = String(url.resolvingSymlinksInPath().path.dropFirst(root.count + 1))
                let destination = target.appendingPathComponent(relative)
                if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(contentsOf: url).write(to: destination, options: .atomic)
                }
            }
            log.record("plugin synced to \(target.path)")
            return true
        } catch {
            log.record("plugin sync failed: \(error)")
            return false
        }
    }

    struct ListedPlugin: Decodable {
        var id: String?
        var enabled: Bool?
    }

    /// `claude plugin list --json`, or nil when the CLI is missing or the answer is unreadable.
    func listPlugins() -> [ListedPlugin]? {
        guard let claude = cli() else { return nil }
        let result = run([claude.path, "plugin", "list", "--json"])
        guard result.succeeded else {
            log.record("plugin list failed: exit=\(result.exitCode) \(result.output.trimmed)")
            return nil
        }
        // The CLI prints JSON, but tolerate anything printed around it.
        let output = result.output
        guard let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"), start < end,
              let listed = try? JSONDecoder().decode([ListedPlugin].self, from: Data(output[start...end].utf8)) else {
            log.record("plugin list unparseable")
            return nil
        }
        return listed
    }

    /// Finds `claude`. An app launched from Finder inherits a minimal PATH, so the usual install
    /// locations are probed by hand; `~/.local/bin` is the default and never on that PATH.
    public static func findCli(home: URL = Paths.userHome) -> URL? {
        [home.appendingPathComponent(".local/bin/claude"),
         URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
         URL(fileURLWithPath: "/usr/local/bin/claude"),
         URL(fileURLWithPath: "/usr/bin/claude")]
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
