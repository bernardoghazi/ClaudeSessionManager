import Foundation
import AppKit
import ClaudeSessionCore

/// Everything the menu and the window render: every session on disk, joined by id with the live
/// state of the ones that are running.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var contentMatches: Set<String>? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var live: [String: LiveSession] = [:]
    @Published private(set) var pluginStatus: PluginStatus = .unknown
    @Published private(set) var isInstallingPlugin = false
    @Published var query = "" {
        didSet { scheduleContentSearch() }
    }

    let log = ActivityLog.file()
    let notifier = Notifier()
    private lazy var focuser = SessionFocuser(log: log)
    private let installer: PluginInstaller

    private var cache: [URL: Session] = [:]
    private var searchTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    private init() {
        installer = PluginInstaller(source: Self.bundledPlugin(), log: log)
        notifier.onClick = { [weak self] url in
            guard let self else { return }
            self.log.record("notification click -> focused=\(self.focuser.focus(url: url))")
        }
    }

    /// Starts polling and plugin housekeeping. Called once from the app delegate.
    func start() {
        log.record("launch")
        notifier.start()
        startMonitor()
        setUpPlugin()
        reload()
    }

    // MARK: - Live sessions

    /// Running sessions, ordered by name so rows never move under the pointer while a menu is open.
    var liveSorted: [LiveSession] {
        live.values.sorted { ($0.name.lowercased(), $0.sessionId) < ($1.name.lowercased(), $1.sessionId) }
    }

    var waitingCount: Int { live.values.filter { $0.phase == .waiting }.count }

    func focus(_ session: LiveSession) {
        log.record("focus -> \(session.name) focused=\(focuser.focus(url: session.focusUrl))")
    }

    private func startMonitor() {
        let monitor = SessionMonitor()
        monitorTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let tick = monitor.tick()
                await self?.apply(tick)
                try? await Task.sleep(for: SessionMonitor.pollInterval)
            }
        }
    }

    private func apply(_ tick: SessionMonitor.Tick) {
        let latest = Dictionary(tick.sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        if latest != live { live = latest }

        for notification in tick.notifications {
            log.record("post: \(notification.title) | \(notification.body)")
            notifier.post(notification)
        }

        // A session that started since the last load has a transcript the window doesn't know yet.
        let known = Set(sessions.map(\.id))
        if tick.events.contains(where: { if case .appeared(let s) = $0 { !known.contains(s.sessionId) } else { false } }) {
            reload()
        }
    }

    // MARK: - Plugin

    private func setUpPlugin() {
        let installer = self.installer
        Task.detached(priority: .utility) { [weak self] in
            // Keeps the mirrored hook current, so a new build's hook takes effect on next launch.
            installer.sync()
            if installer.removeLegacyPlugin() {
                // The user had opted into the Agents Overview plugin; carry that choice over.
                installer.install()
            }
            let status = installer.status()
            await self?.pluginStatusChanged(status, announce: true)
        }
    }

    func installPlugin() {
        guard !isInstallingPlugin else { return }
        isInstallingPlugin = true
        let installer = self.installer, log = self.log
        Task.detached(priority: .userInitiated) { [weak self] in
            let ok = installer.install()
            log.record("plugin install requested: success=\(ok)")
            let status = installer.status()
            await self?.pluginStatusChanged(status, announce: false)
        }
    }

    private func pluginStatusChanged(_ status: PluginStatus, announce: Bool) {
        log.record("plugin status: \(status)")
        pluginStatus = status
        isInstallingPlugin = false
        if announce && status == .notInstalled {
            notifier.post(SessionNotification(
                sessionId: "plugin",
                title: "Claude Session Manager",
                body: "Helper plugin not installed — install it from the menu bar icon."
            ))
        }
    }

    /// The plugin shipped inside the app bundle; in a `swift run` there is no bundle, so use the repo's copy.
    private static func bundledPlugin() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("plugin", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("plugin", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Transcripts

    var filtered: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            s.title.localizedCaseInsensitiveContains(q)
                || s.folder.localizedCaseInsensitiveContains(q)
                || s.branch.localizedCaseInsensitiveContains(q)
                || s.id.localizedCaseInsensitiveContains(q)
                || (contentMatches?.contains(s.id) ?? false)
        }
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let cache = self.cache
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                SessionIndex.load(cache: cache)
            }.value
            self.cache = Dictionary(uniqueKeysWithValues: loaded.map { ($0.path, $0) })
            self.sessions = loaded
            self.isLoading = false
            self.scheduleContentSearch(debounce: false)
        }
    }

    func rename(_ session: Session, to title: String) throws {
        // Checks every kind of running session, not just the interactive ones the menu shows.
        let running = SessionRegistry().runningSessionIds().contains(session.id)
        try Renamer.rename(session, to: title, isRunning: running)
        reload()
    }

    private func scheduleContentSearch(debounce: Bool = true) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            contentMatches = nil
            isSearching = false
            return
        }
        let targets = sessions.map { (id: $0.id, url: $0.path) }
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            isSearching = true
            let matches = await Task.detached(priority: .userInitiated) {
                await ContentSearch.search(targets, for: q)
            }.value
            if Task.isCancelled { return }
            contentMatches = matches
            isSearching = false
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
