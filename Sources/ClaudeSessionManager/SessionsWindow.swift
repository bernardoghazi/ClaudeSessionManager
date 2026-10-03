import SwiftUI
import AppKit
import ClaudeSessionCore

struct SessionsWindow: View {
    static let id = "sessions"

    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<Session.ID>()
    @State private var sortOrder = [KeyPathComparator(\Row.modified, order: .reverse)]
    @State private var toast: String?
    @State private var renaming: Session?

    private var rows: [Row] {
        // Most recent first breaks ties, e.g. among sessions with the same status.
        model.filtered
            .map { Row(session: $0, live: model.live[$0.id]) }
            .sorted(using: sortOrder + [KeyPathComparator(\Row.modified, order: .reverse)])
    }

    private var selected: [Session] {
        model.sessions.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Status", value: \.statusRank) { s in
                    StatusBadge(live: s.live)
                }
                .width(min: 70, ideal: 85)
                TableColumn("Session", value: \.title) { s in
                    Text(s.title).help(s.title)
                }
                .width(min: 200, ideal: 340)
                TableColumn("Folder", value: \.folder) { s in
                    Text(s.displayFolder)
                        .foregroundStyle(s.folderExists ? .primary : .secondary)
                        .strikethrough(!s.folderExists)
                        .help(s.folderExists ? s.folder : "\(s.folder) (folder no longer exists)")
                }
                .width(min: 150, ideal: 280)
                TableColumn("Branch", value: \.branch) { s in
                    Text(s.branch).foregroundStyle(.secondary).help(s.branch)
                }
                .width(min: 80, ideal: 180)
                TableColumn("Last Edited", value: \.modified) { s in
                    Text(s.modified, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .monospacedDigit()
                }
                .width(min: 120, ideal: 150)
                TableColumn("Size", value: \.size) { s in
                    Text(ByteCountFormatter.string(fromByteCount: s.size, countStyle: .file))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 60, ideal: 70)
            }
            .contextMenu(forSelectionType: Session.ID.self) { ids in
                if let s = model.sessions.first(where: { ids.contains($0.id) }) {
                    if let live = model.live[s.id], live.isFocusable {
                        Button("Focus Terminal") { model.focus(live) }
                        Divider()
                    }
                    Button("Copy Session ID") { copy(s.id, "Session ID") }
                    Button("Copy Resume Command") { copy(s.resumeCommand, "Resume command") }
                    Button("Copy Branch Name") { copy(s.branch, "Branch name") }
                        .disabled(!s.hasBranch)
                    Divider()
                    if model.live[s.id] == nil {
                        Button("Rename…") { renaming = s }
                    } else {
                        Button("Rename… (use /rename in the running session)") {}
                            .disabled(true)
                    }
                    Button("Reveal Folder in Finder") { reveal(s) }
                        .disabled(!s.folderExists)
                }
            } primaryAction: { ids in
                guard let s = model.sessions.first(where: { ids.contains($0.id) }) else { return }
                // A running session is already somewhere; go there instead of resuming it twice.
                if let live = model.live[s.id], live.isFocusable {
                    model.focus(live)
                } else {
                    copy(s.resumeCommand, "Resume command")
                }
            }
            .onCopyCommand {
                guard let s = selected.first else { return [] }
                showToast("Copied session ID")
                return [NSItemProvider(object: s.id as NSString)]
            }

            Divider()
            statusBar
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search titles, folders, branches and content")
        .toolbar {
            ToolbarItemGroup {
                Button { selected.first.map { copy($0.id, "Session ID") } } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                }
                .help("Copy session ID (⌘C)")
                .disabled(selection.isEmpty)
                Button { selected.first.map { copy($0.resumeCommand, "Resume command") } } label: {
                    Label("Copy Resume Command", systemImage: "terminal")
                }
                .help("Copy `claude -r <id>` (double-click a row that isn't running)")
                .disabled(selection.isEmpty)
                Button { selected.first.map { copy($0.branch, "Branch name") } } label: {
                    Label("Copy Branch Name", systemImage: "arrow.triangle.branch")
                }
                .help("Copy git branch name (⇧⌘C)")
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(selected.first?.hasBranch != true)
                Button { renaming = selected.first } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .help("Rename session (⌘⏎)")
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selected.first.map { model.live[$0.id] != nil } ?? true)
                Button { model.reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh (⌘R)")
            }
        }
        .sheet(item: $renaming) { s in
            RenameSheet(session: s) { newTitle in
                try model.rename(s, to: newTitle)
                showToast("Renamed session")
            }
        }
        .onAppear {
            // A Dock icon and app switcher entry only while the window is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            model.reload()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isLoading || model.isSearching {
                ProgressView().controlSize(.small)
                Text(model.isLoading ? "Loading sessions…" : "Searching content…")
            } else {
                Text("\(rows.count) of \(model.sessions.count) sessions")
            }
            Spacer()
            if let toast {
                Text(toast).foregroundStyle(.green).transition(.opacity)
            } else if let s = selected.first {
                if let live = model.live[s.id] {
                    Text(verbatim: "pid \(live.pid)").font(.caption.monospaced())
                }
                Text(s.id).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func copy(_ text: String, _ what: String) {
        Clipboard.copy(text)
        showToast("Copied \(what.lowercased())")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private func reveal(_ s: Session) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.folder)])
    }
}

struct StatusBadge: View {
    let live: LiveSession?

    var body: some View {
        if let live {
            Label {
                Text(live.phase.label)
            } icon: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(live.phase.color)
            }
            .help(live.waitingReason ?? live.phase.label)
        }
    }
}

/// A table row: a session plus its live status, so the status column can be sorted.
@dynamicMemberLookup
struct Row: Identifiable {
    let session: Session
    let live: LiveSession?

    var id: Session.ID { session.id }

    /// Descending puts Waiting first, then Working, then Idle, then sessions that aren't running.
    var statusRank: Int {
        switch live?.phase {
        case nil: 0
        case .waiting?: 3
        case .running?: 2
        default: 1
        }
    }

    subscript<T>(dynamicMember keyPath: KeyPath<Session, T>) -> T { session[keyPath: keyPath] }
}

struct RenameSheet: View {
    let session: Session
    let onRename: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var error: String?

    init(session: Session, onRename: @escaping (String) throws -> Void) {
        self.session = session
        self.onRename = onRename
        _title = State(initialValue: session.title)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Session").font(.headline)
            TextField("Session name", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .onSubmit(submit)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || trimmed == session.title)
            }
        }
        .padding(20)
    }

    private func submit() {
        guard !trimmed.isEmpty, trimmed != session.title else { return }
        do {
            try onRename(trimmed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
