import Foundation

public enum RenameError: LocalizedError {
    case sessionRunning

    public var errorDescription: String? {
        "This session is open in Claude Code. Use /rename there instead."
    }
}

public enum Renamer {

    /// Appends the `custom-title` and `agent-name` records `/rename` writes; the last ones in the file win.
    /// Running sessions are refused because Claude Code periodically re-appends its in-memory title.
    public static func rename(_ session: Session, to title: String, isRunning: Bool) throws {
        guard !isRunning else { throw RenameError.sessionRunning }

        // Built by hand to match Claude Code's key order exactly; JSONSerialization can't order keys.
        func json(_ s: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        }
        // Claude Code shows the name from `agent-name`, so `custom-title` alone isn't enough.
        let title = try json(title), id = try json(session.id)
        var line = Data((#"{"type":"custom-title","customTitle":\#(title),"sessionId":\#(id)}"# + "\n"
            + #"{"type":"agent-name","agentName":\#(title),"sessionId":\#(id)}"# + "\n").utf8)

        let handle = try FileHandle(forUpdating: session.path)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: 0) }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
    }
}
