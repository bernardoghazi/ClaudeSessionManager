import Foundation

/// A session on disk, from its transcript at `~/.claude/projects/<project>/<id>.jsonl`.
public struct Session: Identifiable, Hashable, Sendable {
    public let id: String          // session id (file name without .jsonl)
    public let path: URL
    public let title: String
    public let folder: String
    public let branch: String
    public let modified: Date
    public let size: Int64

    public init(id: String, path: URL, title: String, folder: String, branch: String, modified: Date, size: Int64) {
        self.id = id
        self.path = path
        self.title = title
        self.folder = folder
        self.branch = branch
        self.modified = modified
        self.size = size
    }

    public var resumeCommand: String {
        "claude -r \(id)"
    }

    /// False when the session wasn't on a named branch (no repo, or detached HEAD).
    public var hasBranch: Bool { !branch.isEmpty && branch != "HEAD" }

    public var displayFolder: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    public var folderExists: Bool { FileManager.default.fileExists(atPath: folder) }
}

/// Reads every transcript into a `Session`, without decoding the full JSONL.
public enum SessionIndex {

    /// Loads all sessions, reusing `cache` entries whose modification date and size are unchanged.
    public static func load(from projectsDir: URL = Paths.projectsDir, cache: [URL: Session] = [:]) -> [Session] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for dir in dirs {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            files += items.filter { $0.pathExtension == "jsonl" }
        }

        var results = [Session?](repeating: nil, count: files.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: files.count) { i in
            let url = files[i]
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate else { return }
            let size = Int64(values.fileSize ?? 0)
            let session: Session?
            if let cached = cache[url], cached.modified == modified, cached.size == size {
                session = cached
            } else {
                session = parse(url: url, modified: modified, size: size)
            }
            lock.lock(); results[i] = session; lock.unlock()
        }
        return results.compactMap { $0 }.sorted { $0.modified > $1.modified }
    }

    static func parse(url: URL, modified: Date, size: Int64) -> Session? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let cwd = lastStringValue(in: data, key: "cwd") else { return nil }
        let title = lastStringValue(in: data, key: "customTitle")
            ?? lastStringValue(in: data, key: "aiTitle")
            ?? firstUserPrompt(in: data)
            ?? "(untitled)"
        return Session(
            id: url.deletingPathExtension().lastPathComponent,
            path: url,
            title: title.replacingOccurrences(of: "\n", with: " "),
            folder: cwd,
            branch: lastStringValue(in: data, key: "gitBranch") ?? "",
            modified: modified,
            size: size
        )
    }

    /// Finds the last top-level `"key":"value"` in the raw JSONL and decodes the value.
    static func lastStringValue(in data: Data, key: String) -> String? {
        let pattern = Data("\"\(key)\":\"".utf8)
        guard let r = data.range(of: pattern, options: .backwards) else { return nil }
        var end = r.upperBound
        var escaped = false
        while end < data.endIndex {
            let b = data[end]
            if escaped { escaped = false }
            else if b == UInt8(ascii: "\\") { escaped = true }
            else if b == UInt8(ascii: "\"") { break }
            end += 1
        }
        let raw = data[(r.upperBound - 1)...min(end, data.endIndex - 1)]
        let value = (try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed)) as? String
        return value?.isEmpty == false ? value : nil
    }

    static func firstUserPrompt(in data: Data) -> String? {
        var start = data.startIndex
        var linesChecked = 0
        while start < data.endIndex, linesChecked < 500 {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            linesChecked += 1
            start = end + 1
            guard line.range(of: Data("\"type\":\"user\"".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.hasPrefix("<") else { continue }
            return String(content.prefix(200))
        }
        return nil
    }
}
