import Foundation

extension PluginInstaller {
    /// Plugins this app replaces, with the marketplace each was registered from: the standalone
    /// Agents Overview app's, and this app's own from before it was renamed from "Claude Sessions Manager".
    public static let legacyPlugins: [(id: String, marketplace: String)] = [
        ("agents-overview@agents-overview", "agents-overview"),
        ("claude-sessions-manager@claude-sessions-manager", "claude-sessions-manager"),
    ]

    /// Unregisters any legacy plugin that is still installed, so its hook stops writing to the old
    /// directory. Returns true when one was found and removed, meaning the user had opted into the
    /// plugin and the replacement should be installed in its place.
    ///
    /// The old directories (`~/.agents-overview`, `~/.claude-sessions-manager`) are left on disk.
    @discardableResult
    public func removeLegacyPlugin() -> Bool {
        guard let claude = cli(), let listed = listPlugins() else { return false }
        let installed = Set(listed.compactMap(\.id))
        var removed = false
        for legacy in Self.legacyPlugins where installed.contains(legacy.id) {
            let uninstall = run([claude.path, "plugin", "uninstall", legacy.id])
            log.record("legacy plugin uninstall \(legacy.id): exit=\(uninstall.exitCode) \(uninstall.output.trimmed)")
            let remove = run([claude.path, "plugin", "marketplace", "remove", legacy.marketplace])
            log.record("legacy marketplace remove \(legacy.marketplace): exit=\(remove.exitCode) \(remove.output.trimmed)")
            removed = removed || uninstall.succeeded
        }
        return removed
    }
}
