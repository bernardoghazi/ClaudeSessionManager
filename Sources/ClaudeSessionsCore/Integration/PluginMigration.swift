import Foundation

extension PluginInstaller {
    /// The plugin the standalone Agents Overview app registered, which this app replaces.
    public static let legacyId = "agents-overview@agents-overview"
    static let legacyMarketplace = "agents-overview"

    /// Unregisters the Agents Overview plugin if it is still installed, so its hook stops writing
    /// to `~/.agents-overview`. Returns true when it was found and removed, meaning the user had
    /// opted into the plugin and the replacement should be installed in its place.
    ///
    /// `~/.agents-overview` itself is left on disk: the old app may still be installed.
    @discardableResult
    public func removeLegacyPlugin() -> Bool {
        guard let claude = cli(), let listed = listPlugins(),
              listed.contains(where: { $0.id == Self.legacyId }) else { return false }

        let uninstall = run([claude.path, "plugin", "uninstall", Self.legacyId])
        log.record("legacy plugin uninstall: exit=\(uninstall.exitCode) \(uninstall.output.trimmed)")
        let remove = run([claude.path, "plugin", "marketplace", "remove", Self.legacyMarketplace])
        log.record("legacy marketplace remove: exit=\(remove.exitCode) \(remove.output.trimmed)")
        return uninstall.succeeded
    }
}
