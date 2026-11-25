import Foundation

/// The complete, fixed set of external commands the Apple adapter may run. Every invocation is an
/// argument vector built here — identifiers are validated, nothing goes through a shell, and nothing
/// from a device, manifest or URL can add commands.
public enum AppleToolCommand: Hashable {
    case xcodeSelectPrintPath
    case findDevicectl
    case devicectlVersion
    case devicectlHelp(group: [String])
    case listDevices(timeoutSeconds: Int, outputPath: String)
    case deviceDetails(identifier: String, outputPath: String)
    case lockState(identifier: String, outputPath: String)
    case listApps(identifier: String, outputPath: String)
    /// Starts Apple's supported pairing flow. The user must unlock the device and tap Trust.
    case pair(identifier: String, outputPath: String)
    case ideviceinfo(executable: String, udid: String, domain: String?)
    case idevicepairValidate(executable: String, udid: String)

    public static let xcrun = "/usr/bin/xcrun"
    public static let xcodeSelect = "/usr/bin/xcode-select"

    /// Returns nil when an identifier fails validation.
    public var invocation: (executable: String, arguments: [String])? {
        func safe(_ id: String) -> Bool { CommandArgumentPolicy.isSafeIdentifier(id) }
        switch self {
        case .xcodeSelectPrintPath: return (Self.xcodeSelect, ["-p"])
        case .findDevicectl: return (Self.xcrun, ["--find", "devicectl"])
        case .devicectlVersion: return (Self.xcrun, ["devicectl", "--version"])
        case .devicectlHelp(let group):
            let allowed: Set<String> = ["device", "info", "manage", "list"]
            guard group.allSatisfy(allowed.contains) else { return nil }
            return (Self.xcrun, ["devicectl"] + group + ["--help"])
        case .listDevices(let t, let path):
            return (Self.xcrun, ["devicectl", "list", "devices", "--timeout", String(max(5, t)), "--json-output", path])
        case .deviceDetails(let id, let path):
            guard safe(id) else { return nil }
            return (Self.xcrun, ["devicectl", "device", "info", "details", "--device", id, "--json-output", path])
        case .lockState(let id, let path):
            guard safe(id) else { return nil }
            return (Self.xcrun, ["devicectl", "device", "info", "lockState", "--device", id, "--json-output", path])
        case .listApps(let id, let path):
            guard safe(id) else { return nil }
            return (Self.xcrun, ["devicectl", "device", "info", "apps", "--device", id, "--json-output", path])
        case .pair(let id, let path):
            guard safe(id) else { return nil }
            return (Self.xcrun, ["devicectl", "manage", "pair", "--device", id, "--json-output", path])
        case .ideviceinfo(let exe, let udid, let domain):
            guard safe(udid), LibimobiledeviceTools.isAllowedExecutable(exe) else { return nil }
            var args = ["-u", udid, "-x"]
            if let d = domain {
                guard LibimobiledeviceTools.allowedDomains.contains(d) else { return nil }
                args += ["-q", d]
            }
            return (exe, args)
        case .idevicepairValidate(let exe, let udid):
            guard safe(udid), LibimobiledeviceTools.isAllowedExecutable(exe) else { return nil }
            return (exe, ["-u", udid, "validate"])
        }
    }

    /// Human-readable form for evidence and logs (paths shortened).
    public var displayString: String {
        guard let inv = invocation else { return "rejected command" }
        let exe = (inv.executable as NSString).lastPathComponent
        let args = inv.arguments.map { $0.hasPrefix("/") && $0.hasSuffix(".json") ? "<file>" : $0 }
        return ([exe] + args).joined(separator: " ")
    }
}

public enum LibimobiledeviceTools {
    public static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    public static let allowedDomains: Set<String> = ["com.apple.mobile.battery", "com.apple.disk_usage"]

    public static func isAllowedExecutable(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let dir = (path as NSString).deletingLastPathComponent
        return ["ideviceinfo", "idevicepair"].contains(name) && searchDirectories.contains(dir)
    }
}

/// What the installed Xcode / tools can actually do, discovered at runtime.
public struct AppleToolchainStatus: Codable, Hashable {
    public var developerDirectory: String?
    public var xcodeVersion: String?
    public var xcodeBuild: String?
    public var isCommandLineToolsOnly: Bool
    public var devicectlPath: String?
    public var devicectlVersion: String?
    /// Subcommands detected from `devicectl … --help` (capability probe only).
    public var devicectlSubcommands: [String]
    public var ideviceinfoPath: String?
    public var idevicepairPath: String?
    public var problems: [String]
    public var inspectedAt: Date

    public var hasDevicectl: Bool { devicectlPath != nil }
    public func supports(_ subcommand: String) -> Bool { devicectlSubcommands.contains(subcommand) }

    public static let unavailable = AppleToolchainStatus(developerDirectory: nil, xcodeVersion: nil, xcodeBuild: nil, isCommandLineToolsOnly: false,
                                                         devicectlPath: nil, devicectlVersion: nil, devicectlSubcommands: [],
                                                         ideviceinfoPath: nil, idevicepairPath: nil,
                                                         problems: ["Toolchain not inspected."], inspectedAt: Date())

    public var summary: String {
        if let v = xcodeVersion { return "Xcode \(v)\(xcodeBuild.map { " (\($0))" } ?? "")" + (hasDevicectl ? " · devicectl \(devicectlVersion ?? "available")" : " · devicectl unavailable") }
        if isCommandLineToolsOnly { return "Command Line Tools only (no devicectl)" }
        return "Xcode not found"
    }
}

/// Inspects the installed Xcode before any Apple device method is chosen.
public enum AppleToolchainInspector {
    static let knownSubcommands = ["details", "lockState", "apps", "processes", "files", "displays", "pair", "unpair"]

    public static func inspect(runner: CommandRunner, readFile: (String) -> Data? = { FileManager.default.contents(atPath: $0) }) async -> AppleToolchainStatus {
        var status = AppleToolchainStatus.unavailable
        status.problems = []
        status.inspectedAt = Date()

        let select = await run(.xcodeSelectPrintPath, runner, timeout: 10)
        if select?.succeeded == true {
            let dir = select!.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            status.developerDirectory = dir
            status.isCommandLineToolsOnly = dir.contains("CommandLineTools")
            if dir.hasSuffix("/Contents/Developer") {
                let plist = (dir as NSString).deletingLastPathComponent + "/version.plist"
                if let data = readFile(plist),
                   let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
                    status.xcodeVersion = dict["CFBundleShortVersionString"] as? String
                    status.xcodeBuild = dict["ProductBuildVersion"] as? String
                }
            }
        } else {
            status.problems.append("xcode-select did not report a developer directory.")
        }
        if status.isCommandLineToolsOnly {
            status.problems.append("Only the Command Line Tools are selected. devicectl ships with Xcode: install Xcode and run `sudo xcode-select -s /Applications/Xcode.app`.")
        }

        let find = await run(.findDevicectl, runner, timeout: 15)
        if find?.succeeded == true {
            status.devicectlPath = find!.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = await run(.devicectlVersion, runner, timeout: 20)
            if version?.succeeded == true {
                status.devicectlVersion = version!.stdoutText.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            var found: Set<String> = []
            for group in [["device", "info"], ["manage"]] {
                if let help = await run(.devicectlHelp(group: group), runner, timeout: 20) {
                    let text = help.stdoutText + "\n" + help.stderrText
                    for word in knownSubcommands where containsWord(text, word) { found.insert(word) }
                }
            }
            status.devicectlSubcommands = found.sorted()
        } else if !status.isCommandLineToolsOnly {
            status.problems.append("`xcrun devicectl` was not found. It requires Xcode 15 or later.")
        }

        for dir in LibimobiledeviceTools.searchDirectories {
            if status.ideviceinfoPath == nil, runner.isExecutable(atPath: dir + "/ideviceinfo") { status.ideviceinfoPath = dir + "/ideviceinfo" }
            if status.idevicepairPath == nil, runner.isExecutable(atPath: dir + "/idevicepair") { status.idevicepairPath = dir + "/idevicepair" }
        }
        return status
    }

    static func run(_ command: AppleToolCommand, _ runner: CommandRunner, timeout: TimeInterval) async -> CommandResult? {
        guard let inv = command.invocation else { return nil }
        return await runner.run(inv.executable, inv.arguments, timeout: timeout)
    }

    static func containsWord(_ text: String, _ word: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == Substring(word) }
    }
}
