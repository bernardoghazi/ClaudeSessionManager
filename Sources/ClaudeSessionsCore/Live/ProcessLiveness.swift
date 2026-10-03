import Darwin

/// Whether a process id is still running, and since when.
///
/// Claude Code does not remove its registry file when a session is SIGKILLed or its terminal is
/// closed, and pids are recycled, so the start time matters as much as liveness: without it a
/// stale file whose pid was reused would look like a live session.
public struct ProcessLiveness: Sendable {
    /// Epoch millis at which the process started, `0` if it is running but the start time
    /// cannot be read, or `nil` if no process holds this pid.
    public let startedAtMillis: @Sendable (Int32) -> Int64?

    public init(startedAtMillis: @escaping @Sendable (Int32) -> Int64?) {
        self.startedAtMillis = startedAtMillis
    }

    public func isAlive(_ pid: Int32) -> Bool { startedAtMillis(pid) != nil }

    public static let system = ProcessLiveness { pid in
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        return Int64(start.tv_sec) * 1000 + Int64(start.tv_usec) / 1000
    }
}
