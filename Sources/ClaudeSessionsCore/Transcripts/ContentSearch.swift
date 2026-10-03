import Foundation

/// Full-text search over transcript files. There is no index; every search scans the files.
public enum ContentSearch {

    /// Returns the ids whose transcript contains `query`, ignoring ASCII case.
    public static func search(_ targets: [(id: String, url: URL)], for query: String) async -> Set<String> {
        let needle = Array(query.lowercased().utf8)
        return await withTaskGroup(of: String?.self) { group in
            for (id, url) in targets {
                group.addTask {
                    if Task.isCancelled { return nil }
                    guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
                    return containsCaseInsensitive(data, needle) ? id : nil
                }
            }
            var found = Set<String>()
            for await id in group { if let id { found.insert(id) } }
            return found
        }
    }

    static func containsCaseInsensitive(_ data: Data, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, data.count >= needle.count else { return false }
        @inline(__always) func lower(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Bool in
            let p = buf.bindMemory(to: UInt8.self)
            let n = p.count, m = needle.count
            let first = needle[0]
            var i = 0
            while i <= n - m {
                if lower(p[i]) == first {
                    var j = 1
                    while j < m && lower(p[i + j]) == needle[j] { j += 1 }
                    if j == m { return true }
                }
                i += 1
            }
            return false
        }
    }
}
