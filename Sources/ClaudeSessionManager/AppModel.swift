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
    /// Folder, status and search filters; a session must pass all of them to be listed.
    @Published var filter = SessionFilter() {
        didSet {
            // Folder and status apply instantly; only a new query (or a scope that now needs
            // transcripts) is worth a rescan.
            if filter.trimmedQuery != oldValue.trimmedQuery || filter.needsContentSearch != oldValue.needsContentSearch {
                scheduleContentSearch()
            }
        }
    }

    let log = ActivityLog.file()
    let notifier = Notifier()
    private lazy var focuser = SessionFocuser(log: log)

    private var cache: [URL: Session] = [:]
    private var searchTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    private init() {
        notifier.onClick = { [weak self] url in
            guard let self else { return }
            self.log.record("notification click -> focused=\(self.focuser.focus(url: url))")
        }
    }

    /// Starts polling. Called once from the app delegate.
    func start() {
        log.record("launch")
        notifier.start()
        startMonitor()
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

    // MARK: - Transcripts

    var filtered: [Session] {
        sessions.filter { filter.matches($0, phase: live[$0.id]?.phase, contentMatches: contentMatches) }
    }

    /// Every folder that has sessions, for the Folder filter, with how many each has.
    var folderOptions: [(folder: String, display: String, count: Int)] {
        Dictionary(grouping: sessions, by: \.folder)
            .map { (folder: $0.key, display: $0.value[0].displayFolder, count: $0.value.count) }
            .sorted { $0.display.localizedStandardCompare($1.display) == .orderedAscending }
    }

    /// Clears folder, status and search text; the search scope is a preference, so it stays.
    func clearFilters() {
        filter = SessionFilter(scope: filter.scope)
    }

    /// How many sessions each status choice would show, ignoring the other filters.
    func count(of status: StatusFilter) -> Int {
        sessions.filter { status.matches(live[$0.id]?.phase) }.count
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
        let q = filter.trimmedQuery
        guard filter.needsContentSearch else {
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
