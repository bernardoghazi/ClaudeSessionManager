import Foundation

/// Every location the app reads or writes.
public enum Paths {
    public static var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Claude Code's own directory. Read only, except for the rename records appended to transcripts.
    public static var claudeDir: URL { userHome.appendingPathComponent(".claude", isDirectory: true) }
    public static var projectsDir: URL { claudeDir.appendingPathComponent("projects", isDirectory: true) }
    /// The live session registry, `~/.claude/sessions/<pid>.json`.
    public static var registryDir: URL { claudeDir.appendingPathComponent("sessions", isDirectory: true) }

    /// This app's own directory. `CLAUDE_SESSIONS_MANAGER_HOME` overrides it here and in the plugin hook.
    public static var appHome: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_SESSIONS_MANAGER_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return userHome.appendingPathComponent(".claude-sessions-manager", isDirectory: true)
    }
    public static var addressesDir: URL { appHome.appendingPathComponent("addresses", isDirectory: true) }
    public static var pluginMirrorDir: URL { appHome.appendingPathComponent("plugin", isDirectory: true) }
    public static var activityLog: URL { appHome.appendingPathComponent("activity.log") }
}
