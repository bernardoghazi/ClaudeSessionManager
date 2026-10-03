import Foundation

/// Reads the environment of a running process owned by this user.
///
/// This is what makes pre-existing sessions work: a hook never runs in a session that started
/// before the plugin was installed, but Warp exports `WARP_FOCUS_URL` into every shell it spawns
/// and a process keeps its environment for life.
public struct ProcessEnvironment: Sendable {
    public let read: @Sendable (Int32) -> [String: String]

    public init(read: @escaping @Sendable (Int32) -> [String: String]) {
        self.read = read
    }

    /// `ps eww` prints the environment space-separated, so a value containing a space is
    /// ambiguous. The variables we want are a URL and a program name, so splitting on whitespace is enough.
    public static let system = ProcessEnvironment { pid in
        let result = Shell.run(["/bin/ps", "eww", "-p", String(pid)])
        guard result.succeeded else { return [:] }
        var env: [String: String] = [:]
        for token in result.output.split(whereSeparator: \.isWhitespace) {
            guard let eq = token.firstIndex(of: "="), eq > token.startIndex else { continue }
            let key = token[..<eq]
            guard key.first.map({ $0 == "_" || $0.isLetter }) == true,
                  key.allSatisfy({ $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) else { continue }
            env[String(key)] = String(token[token.index(after: eq)...])
        }
        return env
    }
}

/// Recovers a session's address from its own process environment.
///
/// Results are cached per pid, including misses: a process's environment is fixed for its
/// lifetime, so this costs one `ps` per session ever rather than one per poll.
public final class ProcessAddressResolver {
    private let environment: ProcessEnvironment
    private var cache: [Int32: SessionAddress?] = [:]

    public init(environment: ProcessEnvironment = .system) {
        self.environment = environment
    }

    public func resolve(pid: Int32, sessionId: String) -> SessionAddress? {
        if let cached = cache[pid] { return cached }
        let env = environment.read(pid)
        var address: SessionAddress?
        if let url = env["WARP_FOCUS_URL"], !url.trimmingCharacters(in: .whitespaces).isEmpty {
            address = SessionAddress(sessionId: sessionId, focusUrl: url, terminal: env["TERM_PROGRAM"], recordedAt: 0)
        }
        cache[pid] = .some(address)
        return address
    }

    /// Drops entries for processes that have exited, so the cache cannot grow unbounded.
    public func forget(livePids: Set<Int32>) {
        cache = cache.filter { livePids.contains($0.key) }
    }
}
