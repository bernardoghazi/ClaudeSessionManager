import Foundation

/// Brings the terminal running a session to the front by opening its deep link (`warp://session/…`).
public struct SessionFocuser: Sendable {
    private let log: ActivityLog
    private let run: @Sendable ([String]) -> CommandResult

    public init(log: ActivityLog = .none, run: @escaping @Sendable ([String]) -> CommandResult = { Shell.run($0) }) {
        self.log = log
        self.run = run
    }

    /// Returns false when there is no address or opening it failed.
    @discardableResult
    public func focus(url: String?) -> Bool {
        guard let url else { return false }
        let result = run(["/usr/bin/open", url])
        if !result.succeeded { log.record("focus failed: \(url) -> \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return result.succeeded
    }
}
