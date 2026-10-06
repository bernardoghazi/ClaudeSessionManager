import Foundation

/// Which sessions to show by live status.
public enum StatusFilter: String, CaseIterable, Sendable {
    case all, running, waiting, working, idle, notRunning

    /// `phase` is nil for a session that isn't running. "Idle" includes an unrecognised status,
    /// which the window also shows as Idle.
    public func matches(_ phase: Phase?) -> Bool {
        switch self {
        case .all: true
        case .running: phase != nil
        case .waiting: phase == .waiting
        case .working: phase == .running
        case .idle: phase != nil && phase != .waiting && phase != .running
        case .notRunning: phase == nil
        }
    }
}

/// What the search text is matched against.
public enum SearchScope: String, CaseIterable, Sendable {
    /// Title, folder, branch, ID or transcript content.
    case all
    /// Title only; never scans transcripts.
    case title
    /// Transcript content only.
    case content
}

/// Every filter the Sessions window applies. A session must pass all of them.
public struct SessionFilter: Equatable, Sendable {
    /// Exact `Session.folder` values to show; empty shows every folder.
    public var folders: Set<String> = []
    public var status: StatusFilter = .all
    public var query = ""
    public var scope: SearchScope = .all

    public init(folders: Set<String> = [], status: StatusFilter = .all, query: String = "", scope: SearchScope = .all) {
        self.folders = folders
        self.status = status
        self.query = query
        self.scope = scope
    }

    public var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Whether anything narrows the list, so there is something to clear.
    public var isActive: Bool { !folders.isEmpty || status != .all || !trimmedQuery.isEmpty }

    /// Whether the transcripts have to be scanned to answer the query.
    public var needsContentSearch: Bool { !trimmedQuery.isEmpty && scope != .title }

    /// The folder and status filters alone, which need no transcript scan.
    public func matchesFolderAndStatus(_ session: Session, phase: Phase?) -> Bool {
        (folders.isEmpty || folders.contains(session.folder)) && status.matches(phase)
    }

    /// `contentMatches` holds the ids whose transcript contains the query, or nil while that scan
    /// hasn't finished; content then simply doesn't count as a match yet.
    public func matches(_ session: Session, phase: Phase?, contentMatches: Set<String>?) -> Bool {
        guard matchesFolderAndStatus(session, phase: phase) else { return false }
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        let inContent = contentMatches?.contains(session.id) ?? false
        switch scope {
        case .title:
            return session.title.localizedCaseInsensitiveContains(q)
        case .content:
            return inContent
        case .all:
            return session.title.localizedCaseInsensitiveContains(q)
                || session.folder.localizedCaseInsensitiveContains(q)
                || session.branch.localizedCaseInsensitiveContains(q)
                || session.id.localizedCaseInsensitiveContains(q)
                || inContent
        }
    }
}
