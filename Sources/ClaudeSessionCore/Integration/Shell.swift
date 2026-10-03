import Foundation

/// The outcome of running one command, enough to log what went wrong.
public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum Shell {
    /// Runs `command[0]` (an absolute path) with the remaining arguments, capturing stdout and stderr together.
    public static func run(_ command: [String]) -> CommandResult {
        guard let executable = command.first else { return CommandResult(exitCode: -1, output: "empty command") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, output: "\(error)")
        }
        // Drain before waiting, or a chatty command fills the pipe and never exits.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
