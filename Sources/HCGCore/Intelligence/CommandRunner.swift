import Foundation

/// Result of running an external, allow-listed tool.
public struct CommandResult: Hashable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var durationSeconds: Double
    public var timedOut: Bool
    public var launchError: String?

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data(), durationSeconds: Double = 0,
                timedOut: Bool = false, launchError: String? = nil) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationSeconds = durationSeconds
        self.timedOut = timedOut
        self.launchError = launchError
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut && launchError == nil }
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }

    /// One-line explanation of a failure, suitable for the UI (never includes the full output).
    public var failureSummary: String {
        if let e = launchError { return "Could not start the tool: \(e)" }
        if timedOut { return "Timed out after \(String(format: "%.0f", durationSeconds)) s." }
        let line = (stderrText + "\n" + stdoutText)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "no output"
        return "Exit code \(exitCode): \(line.prefix(240))"
    }
}

/// Executes a fixed executable with an argument vector (never through a shell).
public protocol CommandRunner: AnyObject {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult
    func isExecutable(atPath path: String) -> Bool
}

/// `Foundation.Process` implementation. Arguments are passed as a vector, stdin is closed,
/// and the process is terminated when the timeout expires.
public final class ProcessCommandRunner: CommandRunner {
    public init() {}

    public func isExecutable(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, timeout: timeout))
            }
        }
    }

    final class Flag {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, launchError: String(describing: error))
        }
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let timedOut = Flag()
        let killer = DispatchWorkItem {
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(1, timeout), execute: killer)
        process.waitUntilExit()
        killer.cancel()
        group.wait()
        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        return CommandResult(exitCode: process.terminationStatus, stdout: outData, stderr: errData,
                             durationSeconds: duration, timedOut: timedOut.isSet)
    }
}

/// Identifiers passed to external tools must look like CoreDevice identifiers / UDIDs.
public enum CommandArgumentPolicy {
    /// UUIDs, UDIDs (with or without hyphen), ECID-like hex. No spaces, no option-like prefixes.
    public static func isSafeIdentifier(_ s: String) -> Bool {
        guard (8...64).contains(s.count), !s.hasPrefix("-") else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" } && s.allSatisfy(\.isASCII)
    }
}
