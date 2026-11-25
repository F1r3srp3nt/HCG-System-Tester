import Foundation

/// Apple Device Intelligence Adapter — the reference device-family adapter.
///
/// Sources, in order of preference:
/// 1. **IOKit** — USB descriptors, interfaces and link speed (always, read-only).
/// 2. **Xcode CoreDevice** via `xcrun devicectl … --json-output` — structured device, OS, pairing,
///    developer-mode and service information. Supported Apple tooling; requires Xcode 15+.
/// 3. **libimobiledevice** (`ideviceinfo -x`, optional, user-installed, LGPL) — battery and free-space
///    domains from the device's lockdown service after pairing. Never installed or bundled by System Tester.
///
/// The adapter never bypasses pairing, passcodes, device locks or Activation Lock, never enables
/// Developer Mode and never changes device settings. Pairing is started only when the user clicks
/// "Pair", and then follows Apple's own Trust flow on the device.
public final class AppleDeviceIntelligenceProvider: DeviceIntelligenceProvider {
    public static let adapterID = "com.hakmicapitalgroup.adapter.apple-device-intelligence"

    public let providerID = AppleDeviceIntelligenceProvider.adapterID
    public let familyName = "Apple iPhone / iPad"
    public let supportedProtocols = ["usb.descriptor", "apple.usbmux", "apple.coredevice", "apple.lockdown", "usb.ptp"]
    public let interfaceExtensions = ["apple.device-illustration", "apple.pairing-guide"]

    public let runner: CommandRunner
    public let provenance: DataProvenance
    /// Supplies the inventory timeline to the reconnect-handling diagnostic.
    public var timelineProvider: ((String) -> [IntelligenceTimelineEntry])?

    private let lock = NSLock()
    private var cachedToolchain: AppleToolchainStatus?
    private var listCache: (at: Date, devices: [CoreDeviceRecord], error: String?, durationMs: Double)?
    private var detailCache: [String: (at: Date, record: CoreDeviceRecord, durationMs: Double)] = [:]
    public var listCacheTTL: TimeInterval = 4
    public var detailCacheTTL: TimeInterval = 15

    var toolSource: String { provenance == .synthetic ? "SYNTHETIC devicectl fixture" : "xcrun devicectl" }

    public init(runner: CommandRunner, provenance: DataProvenance = .hardware) {
        self.runner = runner
        self.provenance = provenance
    }

    // MARK: Recognition

    public func recognizes(_ device: DiscoveredDevice, identification: IdentificationResult) -> Bool {
        device.provenance == provenance && Self.isAppleMobileDevice(device)
    }

    public static func isAppleMobileDevice(_ d: DiscoveredDevice) -> Bool {
        guard let usb = d.usb, usb.vendorID == 0x05AC else { return false }
        let name = (usb.productName ?? d.name).lowercased()
        if ["iphone", "ipad", "ipod"].contains(where: { name.contains($0) }) { return true }
        if usb.interfaces.contains(where: Self.isUsbmuxInterface) { return true }
        if let pid = usb.productID, (0x1290...0x12AF).contains(pid) { return true }
        return false
    }

    static func isUsbmuxInterface(_ i: USBInterfaceInfo) -> Bool { i.classCode == 0xFF && i.subclassCode == 0xFE && i.protocolCode == 0x02 }

    // MARK: Toolchain & CoreDevice access

    public func toolchain(forceRefresh: Bool = false) async -> AppleToolchainStatus {
        if !forceRefresh, let t = withLock({ cachedToolchain }) { return t }
        let t = await AppleToolchainInspector.inspect(runner: runner)
        withLock { cachedToolchain = t }
        return t
    }

    public func invalidateCaches() {
        withLock {
            listCache = nil
            detailCache = [:]
        }
    }

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    struct JSONRun {
        var result: CommandResult
        var data: Data?
        var display: String
        var durationMs: Double { result.durationSeconds * 1000 }
        var document: DevicectlOutput.Document? { data.flatMap(DevicectlOutput.parse) }
        var errorText: String? {
            if let e = document?.errorDescription { return e }
            if !result.succeeded { return result.failureSummary }
            if data == nil { return "devicectl produced no JSON output." }
            return nil
        }
    }

    func runJSON(_ make: (String) -> AppleToolCommand, timeout: TimeInterval) async -> JSONRun? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hcg-systemtester-\(UUID().uuidString).json").path
        let command = make(path)
        guard let inv = command.invocation else { return nil }
        let result = await runner.run(inv.executable, inv.arguments, timeout: timeout)
        let data = FileManager.default.contents(atPath: path)
        try? FileManager.default.removeItem(atPath: path)
        return JSONRun(result: result, data: data, display: command.displayString)
    }

    /// `devicectl list devices`, cached briefly so one refresh never spawns it twice.
    public func listDevices(force: Bool = false) async -> (devices: [CoreDeviceRecord], error: String?, durationMs: Double) {
        if !force, let c = withLock({ listCache }), Date().timeIntervalSince(c.at) < listCacheTTL {
            return (c.devices, c.error, c.durationMs)
        }
        guard let run = await runJSON({ .listDevices(timeoutSeconds: 5, outputPath: $0) }, timeout: 30) else {
            return ([], "Command rejected by policy.", 0)
        }
        let devices = run.data.map(DevicectlOutput.devices) ?? []
        let error = devices.isEmpty ? run.errorText : nil
        withLock { listCache = (Date(), devices, error, run.durationMs) }
        return (devices, error, run.durationMs)
    }

    /// `devicectl device info details` — a live query answered by the device through CoreDevice.
    public func details(identifier: String, force: Bool = false) async -> (record: CoreDeviceRecord?, error: String?, durationMs: Double) {
        if !force, let c = withLock({ detailCache[identifier] }), Date().timeIntervalSince(c.at) < detailCacheTTL {
            return (c.record, nil, c.durationMs)
        }
        guard let run = await runJSON({ .deviceDetails(identifier: identifier, outputPath: $0) }, timeout: 45) else {
            return (nil, "Command rejected by policy.", 0)
        }
        if let error = run.errorText, run.document?.isSuccess != true { return (nil, error, run.durationMs) }
        guard let record = run.data.flatMap(DevicectlOutput.deviceDetails) else {
            return (nil, run.errorText ?? "devicectl returned no device details.", run.durationMs)
        }
        withLock { detailCache[identifier] = (Date(), record, run.durationMs) }
        return (record, nil, run.durationMs)
    }

    /// Measures one uncached round trip (used by the latency diagnostic and the Live Monitor).
    public func measureQueryLatency(identifier: String) async -> (ms: Double?, error: String?) {
        let r = await details(identifier: identifier, force: true)
        return r.record == nil ? (nil, r.error) : (r.durationMs, nil)
    }

    public func lockState(identifier: String) async -> (pairs: [(String, String)], error: String?) {
        guard let run = await runJSON({ .lockState(identifier: identifier, outputPath: $0) }, timeout: 30) else { return ([], "Command rejected by policy.") }
        if let e = run.errorText, run.document?.isSuccess != true { return ([], e) }
        return (run.data.map(DevicectlOutput.flatResult) ?? [], nil)
    }

    /// Installed applications. User-triggered only (more sensitive than device facts).
    public func installedApps(identifier: String) async -> (apps: [(name: String, bundleID: String, version: String?)], error: String?) {
        guard let run = await runJSON({ .listApps(identifier: identifier, outputPath: $0) }, timeout: 60) else { return ([], "Command rejected by policy.") }
        if let e = run.errorText, run.document?.isSuccess != true { return ([], e) }
        return (run.data.map(DevicectlOutput.apps) ?? [], nil)
    }

    func lockdown(_ exe: String, udid: String, domain: String?) async -> (dict: [String: Any]?, error: String?, durationMs: Double) {
        guard let inv = AppleToolCommand.ideviceinfo(executable: exe, udid: udid, domain: domain).invocation else { return (nil, "Command rejected by policy.", 0) }
        let r = await runner.run(inv.executable, inv.arguments, timeout: 20)
        guard r.succeeded, let d = LockdownOutput.plist(r.stdout) else { return (nil, r.failureSummary, r.durationSeconds * 1000) }
        return (d, nil, r.durationSeconds * 1000)
    }

    /// Finds the CoreDevice record for a USB device: by UDID ↔ USB serial number, else by elimination.
    public static func correlate(_ device: DiscoveredDevice, with records: [CoreDeviceRecord]) -> (record: CoreDeviceRecord, method: String)? {
        let candidates = records.filter { $0.reality?.lowercased() != "virtual" }
        if let serial = device.usb?.serialNumber.map(CoreDeviceRecord.normalize) {
            if let r = candidates.first(where: { $0.normalizedUDID == serial }) {
                return (r, "Matched by UDID: CoreDevice hardwareProperties.udid equals the USB serial number reported by IOKit.")
            }
        }
        let wired = candidates.filter(\.isWired)
        if wired.count == 1 {
            return (wired[0], "Matched by elimination: the only wired device CoreDevice reports (the USB serial number was not available to compare).")
        }
        return nil
    }

    // MARK: Snapshot

    public func snapshot(for device: DiscoveredDevice, identification: IdentificationResult) async -> IntelligenceSnapshot {
        var b = SnapshotBuilder(device: device, provider: self)
        b.addUSBEvidence()
        guard device.isPresent else { return b.finish(override: .disconnected, reason: "The device left the bus.", action: NextAction(kind: .reconnect, title: "Reconnect the device")) }

        let tools = await toolchain()
        b.addToolchainFields(tools)

        var record: CoreDeviceRecord?
        var communicated = false
        var blocking: (IntelligenceState, String, NextAction)?

        if tools.hasDevicectl {
            let listing = await listDevices()
            if let e = listing.error { b.errors.append("devicectl list devices: \(e)") }
            if let match = Self.correlate(device, with: listing.devices) {
                record = match.record
                b.correlation = match.method
                b.evidence[.protocolDiscovered] = b.evidence[.protocolDiscovered] ?? "CoreDevice lists the device (\(match.record.transportType ?? "transport unknown"))."
                if match.record.isPaired {
                    b.evidence[.authorizationRequired] = "Satisfied — this device already trusts this Mac."
                    b.evidence[.pairingAvailable] = "Satisfied — pairing completed earlier."
                    b.evidence[.pairingEstablished] = "CoreDevice connectionProperties.pairingState = paired."
                    b.authorizationEvidence.append("Paired with this Mac (CoreDevice pairingState = paired).")
                    if let id = match.record.identifier {
                        let det = await details(identifier: id)
                        if let r = det.record {
                            record = match.record.merged(with: r)
                            communicated = true
                            b.communicationEvidence.append("`devicectl device info details` returned live properties (iOS \(r.osVersion ?? "?")) in \(String(format: "%.0f", det.durationMs)) ms.")
                            b.evidence[.communicationEstablished] = "Live device properties retrieved through CoreDevice."
                            b.latencyMs = det.durationMs
                        } else if let e = det.error {
                            b.errors.append("devicectl device info details: \(e)")
                            blocking = Self.classify(error: e)
                        }
                        if tools.supports("lockState") {
                            let ls = await lockState(identifier: id)
                            if ls.pairs.isEmpty {
                                b.fields.append(.unavailable("apple.lockState", "Lock state", .authorization,
                                                             reason: ls.error ?? "Not reported.", source: FieldSource(tool: "\(toolSource) device info lockState", provenance: provenance)))
                            }
                            for (k, v) in ls.pairs {
                                b.fields.append(IntelligenceField(key: "apple.lockState.\(k)", label: "Lock state · \(k)", group: .authorization, value: v,
                                                                  source: FieldSource(tool: "\(toolSource) device info lockState", key: "result.\(k)", provenance: provenance)))
                            }
                        } else {
                            b.fields.append(.unavailable("apple.lockState", "Lock state", .authorization,
                                                         reason: "This Xcode's devicectl does not offer `device info lockState`.", source: FieldSource(tool: toolSource, provenance: provenance)))
                        }
                    }
                } else {
                    let canPair = tools.supports("pair")
                    blocking = canPair
                        ? (.pairingAvailable, "The device is visible to CoreDevice but has not paired with this Mac.", NextAction(
                            kind: .pairDevice, title: "Pair this iPhone with your Mac",
                            instructions: ["Unlock the iPhone with your passcode.", "Click Pair. When “Trust This Computer?” appears on the iPhone, tap Trust and enter your passcode.",
                                           "Pairing uses Apple's own Trust flow. System Tester never bypasses it."],
                            performable: true))
                        : (.authorizationRequired, "The device is visible but not paired, and this Xcode cannot start pairing from devicectl.", NextAction(
                            kind: .trustComputer, title: "Trust this Mac on the device",
                            instructions: ["Unlock the iPhone.", "Open Finder and select the iPhone in the sidebar.", "Tap Trust on the iPhone and enter your passcode, then click Refresh."]))
                }
            } else if listing.error == nil {
                blocking = (.protocolDiscovered, "CoreDevice does not list this device yet.", NextAction(
                    kind: .unlockDevice, title: "Unlock the iPhone",
                    instructions: ["Unlock the iPhone. A locked device can hide its services (USB Restricted Mode).",
                                   "If “Trust This Computer?” appears, tap Trust.", "Then click Refresh."]))
            }
        }

        if let r = record { b.addCoreDeviceFields(r) } else { b.addCoreDeviceUnavailable(tools) }
        b.addModelFacts(record)

        // Optional libimobiledevice for battery and free space (only after pairing; never for unpaired devices).
        let udid = record?.udid ?? device.usb?.serialNumber
        if let exe = tools.ideviceinfoPath, let u = udid, (record?.isPaired ?? !tools.hasDevicectl) {
            let base = await lockdown(exe, udid: u, domain: nil)
            if let d = base.dict {
                communicated = true
                b.communicationEvidence.append("ideviceinfo (lockdown) answered in \(String(format: "%.0f", base.durationMs)) ms.")
                b.evidence[.communicationEstablished] = b.evidence[.communicationEstablished] ?? "Lockdown service answered (libimobiledevice)."
                b.addLockdownBase(d)
                if record == nil { b.authorizationEvidence.append("Lockdown session accepted, so a pairing record exists.") }
            } else if let e = base.error {
                b.errors.append("ideviceinfo: \(e)")
            }
            if base.dict != nil {
                let battery = await lockdown(exe, udid: u, domain: "com.apple.mobile.battery")
                b.addBattery(battery.dict, error: battery.error)
                let disk = await lockdown(exe, udid: u, domain: "com.apple.disk_usage")
                b.addDisk(disk.dict, error: disk.error)
            } else {
                b.addBattery(nil, error: base.error)
                b.addDisk(nil, error: base.error)
            }
        } else {
            let reason: String
            if tools.ideviceinfoPath == nil {
                reason = "Not exposed by Xcode devicectl. Optional: install libimobiledevice (`brew install libimobiledevice`) to read the device's battery and disk-usage domains after pairing."
            } else {
                reason = "Available after the device is paired."
            }
            b.addBattery(nil, error: reason)
            b.addDisk(nil, error: reason)
        }

        if communicated {
            b.evidence[.diagnosticsAvailable] = "Apple read-only diagnostics can run against live data."
        }

        if !tools.hasDevicectl && !communicated {
            return b.finish(override: .connectionLimited,
                            reason: tools.problems.first ?? "Xcode's devicectl is not available, so only USB-level information can be shown.",
                            action: NextAction(kind: tools.isCommandLineToolsOnly ? .selectXcode : .installXcode,
                                               title: tools.isCommandLineToolsOnly ? "Select Xcode" : "Install Xcode",
                                               instructions: ["devicectl ships with Xcode 15 or later.",
                                                              "Run: sudo xcode-select -s /Applications/Xcode.app", "Then click Refresh."]))
        }
        if let block = blocking, !communicated {
            return b.finish(override: block.0, reason: block.1, action: block.2)
        }
        if communicated {
            if record?.isNetwork == true {
                b.limitations.append("CoreDevice reports this device over the local network, not over the USB cable.")
            }
            return b.finish(override: nil, reason: "Live information retrieved from the device through \(b.communicationEvidence.count > 1 ? "CoreDevice and lockdown" : "a supported Apple service").",
                            action: NextAction(kind: .runDiagnostics, title: "Run Apple read-only diagnostics"))
        }
        return b.finish(override: nil, reason: "USB-level identification only.", action: NextAction(kind: .refresh, title: "Refresh"))
    }

    static func classify(error: String) -> (IntelligenceState, String, NextAction) {
        let e = error.lowercased()
        if e.contains("lock") || e.contains("passcode") || e.contains("unlock") {
            return (.authorizationRequired, "The device is locked or needs to be unlocked to answer.", NextAction(
                kind: .unlockDevice, title: "Unlock the device", instructions: ["Unlock the iPhone with your passcode, keep it awake, then click Refresh."]))
        }
        if e.contains("developer mode") || e.contains("ddi") || e.contains("developer disk") {
            return (.connectionLimited, "The requested service needs Developer Mode or a developer disk image.", NextAction(
                kind: .enableDeveloperMode, title: "Developer Mode (only if you need developer services)",
                instructions: ["Developer Mode is only required for developer capabilities (installing development builds, debugging).",
                               "On the device: Settings › Privacy & Security › Developer Mode. System Tester never enables it for you."]))
        }
        return (.connectionLimited, "CoreDevice could not query the device: \(error.prefix(160))", NextAction(
            kind: .refresh, title: "Retry", instructions: ["Keep the device unlocked and connected, then click Refresh.", "If it persists, reconnect the cable."]))
    }

    // MARK: Actions

    public func perform(_ action: NextActionKind, for device: DiscoveredDevice, identification: IdentificationResult) async -> ActionOutcome {
        switch action {
        case .refresh, .runDiagnostics:
            invalidateCaches()
            if action == .refresh { _ = await toolchain(forceRefresh: true) }
            return .completed("Refreshed.")
        case .pairDevice:
            let tools = await toolchain()
            guard tools.supports("pair") else { return .notPerformable("This Xcode's devicectl cannot start pairing. Use Finder to trust this Mac.") }
            let listing = await listDevices(force: true)
            guard let match = Self.correlate(device, with: listing.devices), let id = match.record.identifier else {
                return .notPerformable("CoreDevice does not list this device. Unlock it and click Refresh first.")
            }
            if match.record.isPaired { return .completed("Already paired.") }
            guard let run = await runJSON({ .pair(identifier: id, outputPath: $0) }, timeout: 150) else { return .failed("Command rejected by policy.") }
            invalidateCaches()
            if run.document?.isSuccess == true && run.result.succeeded {
                return .completed("Pairing completed. The device now trusts this Mac.")
            }
            return .failed("Pairing did not complete: \(run.errorText ?? "unknown error"). Make sure the iPhone is unlocked and you tapped Trust.")
        default:
            return .notPerformable("This step is performed on the device by you. Follow the instructions shown.")
        }
    }

    public func diagnosticTests() -> [DiagnosticTest] { AppleDiagnostics.tests(providers: [self]) }
}

/// Assembles a snapshot; keeps the provider logic readable.
struct SnapshotBuilder {
    let device: DiscoveredDevice
    let provider: AppleDeviceIntelligenceProvider
    var fields: [IntelligenceField] = []
    var services: [ServiceInfo] = []
    var evidence: [IntelligenceState: String] = [:]
    var limitations: [String] = []
    var errors: [String] = []
    var correlation: String?
    var communicationEvidence: [String] = []
    var authorizationEvidence: [String] = []
    var latencyMs: Double?

    init(device: DiscoveredDevice, provider: AppleDeviceIntelligenceProvider) {
        self.device = device
        self.provider = provider
    }

    var prov: DataProvenance { provider.provenance }
    var tool: String { provider.toolSource }

    func io(_ key: String) -> FieldSource { FieldSource(tool: prov == .synthetic ? "SYNTHETIC IOKit fixture" : "IOKit (IOUSBHostDevice)", key: key, provenance: prov) }
    func dc(_ key: String) -> FieldSource { FieldSource(tool: "\(tool) list devices / device info details", key: key, provenance: prov) }

    mutating func add(_ key: String, _ label: String, _ group: IntelligenceGroup, _ value: String?, _ source: FieldSource, sensitive: Bool = false, reason: String? = nil) {
        fields.append(IntelligenceField(key: key, label: label, group: group, value: value, unavailableReason: reason, source: source, sensitive: sensitive))
    }

    mutating func addUSBEvidence() {
        guard let usb = device.usb else { return }
        if device.isPresent { evidence[.physicalDeviceDetected] = "\(device.source) reported the device." }
        if usb.vendorID != nil && usb.productID != nil {
            evidence[.usbEnumerated] = "Descriptors read: \(usb.vendorIDHex):\(usb.productIDHex), \(usb.interfaces.count) interface(s)\(usb.speed.map { ", \($0.shortName)" } ?? "")."
        }
        let name = usb.productName ?? device.name
        evidence[.familyIdentified] = "Apple vendor ID 0x05AC with product “\(name)”."
        if let mux = usb.interfaces.first(where: AppleDeviceIntelligenceProvider.isUsbmuxInterface) {
            evidence[.protocolDiscovered] = "Apple usbmux interface #\(mux.number) (FF.FE.02) present."
        }

        add("usb.manufacturer", "Manufacturer", .overview, usb.vendorName ?? "Apple", io(usb.vendorName == nil ? "idVendor → vendor table" : "USB Vendor Name"))
        add("usb.productName", "USB product name", .hardware, usb.productName, io("USB Product Name"))
        add("usb.vendorID", "USB vendor ID", .hardware, usb.vendorIDHex, io("idVendor"))
        add("usb.productID", "USB product ID", .hardware, usb.productIDHex, io("idProduct"))
        add("usb.speed", "Connection speed", .connection, usb.speed?.displayName, io("Device Speed"))
        add("usb.connectionType", "Connection type", .connection, "USB (wired)\(usb.speed.map { " · \($0.shortName)" } ?? "")", io("IOUSBHostDevice"))
        add("usb.bcdUSB", "USB specification", .hardware, usb.usbSpecification, io("bcdUSB"))
        add("usb.bcdDevice", "USB device release", .hardware, usb.firmwareRevision, io("bcdDevice"))
        add("usb.interfaces", "USB interfaces", .hardware,
            usb.interfaces.isEmpty ? nil : usb.interfaces.map { "#\($0.number) \($0.functionDescription)" }.joined(separator: "; "),
            io("IOUSBHostInterface"), reason: "No interfaces published yet (drivers may still be attaching).")
        add("usb.topology", "USB topology", .connection,
            usb.locationID.map { "Bus \(USBTopology.busNumber(locationID: $0)) · port path \(USBTopology.portPath(locationID: $0).map(String.init).joined(separator: "→")) · \(Hex.format32($0))" },
            io("locationID"))
        add("usb.serialNumber", "USB serial number", .hardware, usb.serialNumber, io("USB Serial Number"), sensitive: true,
            reason: "Not published by the device.")

        for i in usb.interfaces {
            let info: (id: String, name: String, note: String)
            switch (i.classCode, i.subclassCode, i.protocolCode) {
            case (0xFF, 0xFE, 0x02): info = ("apple.usbmux", "Apple usbmux (device services multiplexer)", "Carries lockdown and CoreDevice traffic")
            case (0x06, 0x01, 0x01): info = ("usb.ptp", "PTP (photo transfer)", "Used by Image Capture / Photos")
            case (0x02, 0x0D, _): info = ("usb.cdc-ncm", "USB networking (NCM)", "Network interface used by CoreDevice tunnels")
            default: continue
            }
            if !services.contains(where: { $0.identifier == info.id }) {
                services.append(ServiceInfo(identifier: info.id, name: info.name, available: true, note: info.note,
                                            source: io("interface #\(i.number) \(DeviceMatchRules.triple(i))")))
            }
        }
    }

    mutating func addToolchainFields(_ t: AppleToolchainStatus) {
        let src = FieldSource(tool: "xcode-select / Xcode version.plist / xcrun", provenance: .hardware)
        add("toolchain.xcode", "Xcode", .developer, t.xcodeVersion.map { "\($0)\(t.xcodeBuild.map { " (\($0))" } ?? "")" }, src,
            reason: t.problems.first ?? "Xcode not found.")
        add("toolchain.devicectl", "devicectl", .developer, t.devicectlPath.map { _ in t.devicectlVersion ?? "available" }, src,
            reason: "devicectl requires Xcode 15 or later.")
        add("toolchain.subcommands", "devicectl capabilities detected", .developer,
            t.devicectlSubcommands.isEmpty ? nil : t.devicectlSubcommands.joined(separator: ", "), src, reason: "No subcommands detected.")
        add("toolchain.libimobiledevice", "libimobiledevice (optional)", .developer, t.ideviceinfoPath, src,
            reason: "Not installed. Optional: enables battery and free-space information after pairing.")
    }

    mutating func addCoreDeviceFields(_ r: CoreDeviceRecord) {
        add("apple.name", "Device name", .overview, r.name, dc("deviceProperties.name"))
        add("apple.marketingName", "Model", .overview, r.marketingName, dc("hardwareProperties.marketingName"))
        add("apple.deviceType", "Device family", .overview, r.deviceType, dc("hardwareProperties.deviceType"))
        add("apple.productType", "Product type", .hardware, r.productType, dc("hardwareProperties.productType"))
        add("apple.hardwareModel", "Hardware model identifier", .hardware, r.hardwareModel, dc("hardwareProperties.hardwareModel"))
        add("apple.cpuType", "CPU architecture", .hardware, r.cpuType, dc("hardwareProperties.cpuType.name"))
        add("apple.platform", "Operating system", .software, r.platform.map { $0 == "iOS" && r.deviceType == "iPad" ? "iPadOS" : $0 }, dc("hardwareProperties.platform"))
        add("apple.osVersion", "OS version", .software, r.osVersion, dc("deviceProperties.osVersionNumber"))
        add("apple.osBuild", "Build number", .software, r.osBuild, dc("deviceProperties.osBuildUpdate"))
        add("apple.bootState", "Boot state", .software, r.bootState, dc("deviceProperties.bootState"))
        add("apple.storageCapacity", "Storage capacity", .storage, r.internalStorageCapacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) },
            dc("hardwareProperties.internalStorageCapacity"), reason: "Not reported by this devicectl version.")
        add("apple.pairingState", "Pairing status", .authorization, r.pairingState, dc("connectionProperties.pairingState"))
        add("apple.authenticationType", "Authentication type", .authorization, r.authenticationType, dc("connectionProperties.authenticationType"))
        add("apple.developerMode", "Developer Mode", .authorization, r.developerModeStatus, dc("deviceProperties.developerModeStatus"),
            reason: "Reported after pairing.")
        add("apple.ddiServices", "Developer disk image services", .developer, r.ddiServicesAvailable.map { $0 ? "Available" : "Not mounted" },
            dc("deviceProperties.ddiServicesAvailable"), reason: "Reported after pairing.")
        add("apple.transport", "CoreDevice transport", .connection, r.transportType, dc("connectionProperties.transportType"))
        add("apple.tunnelState", "CoreDevice tunnel", .connection, r.tunnelState, dc("connectionProperties.tunnelState"))
        add("apple.lastConnection", "Last CoreDevice connection", .connection, r.lastConnectionDate, dc("connectionProperties.lastConnectionDate"))
        add("apple.coreDeviceIdentifier", "CoreDevice identifier", .developer, r.identifier, dc("identifier"), sensitive: true)
        add("apple.udid", "UDID", .hardware, r.udid, dc("hardwareProperties.udid"), sensitive: true)
        add("apple.serialNumber", "Serial number", .hardware, r.serialNumber, dc("hardwareProperties.serialNumber"), sensitive: true)
        add("apple.ecid", "ECID", .hardware, r.ecid, dc("hardwareProperties.ecid"), sensitive: true)
        for c in r.capabilities where !services.contains(where: { $0.identifier == c.featureIdentifier }) {
            services.append(ServiceInfo(identifier: c.featureIdentifier, name: c.name, available: true,
                                        source: dc("capabilities[].featureIdentifier")))
        }
        if r.developerModeStatus?.lowercased() == "disabled" {
            limitations.append("Developer Mode is off. That is fine for System Tester's read-only information; it is only needed for developer capabilities. System Tester never enables it.")
        }
    }

    mutating func addCoreDeviceUnavailable(_ t: AppleToolchainStatus) {
        let reason = t.hasDevicectl ? "CoreDevice has not reported this device (unlock it and trust this Mac, then refresh)." : (t.problems.first ?? "Xcode devicectl is not available.")
        let src = FieldSource(tool: tool, provenance: prov)
        for (key, label, group) in [("apple.name", "Device name", IntelligenceGroup.overview), ("apple.marketingName", "Model", .overview),
                                    ("apple.productType", "Product type", .hardware), ("apple.hardwareModel", "Hardware model identifier", .hardware),
                                    ("apple.osVersion", "OS version", .software), ("apple.osBuild", "Build number", .software),
                                    ("apple.pairingState", "Pairing status", .authorization), ("apple.developerMode", "Developer Mode", .authorization),
                                    ("apple.storageCapacity", "Storage capacity", .storage)] {
            fields.append(.unavailable(key, label, group, reason: reason, source: src))
        }
    }

    mutating func addModelFacts(_ r: CoreDeviceRecord?) {
        guard let pt = r?.productType, let facts = AppleModelFacts.table[pt] else { return }
        add("apple.usbCapability", "USB capability (model)", .connection, facts.usbCapability,
            FieldSource(tool: "HCG model table (Apple published specifications)", key: pt, provenance: .hardware))
        if let max = facts.usbMaxSpeed, max.rawValue >= USBSpeed.superSpeed.rawValue,
           let negotiated = device.usb?.speed, negotiated.rawValue < USBSpeed.superSpeed.rawValue {
            limitations.append("Connected at \(negotiated.shortName). \(facts.name) supports \(facts.usbCapability) — the cable or port is limiting the link (many USB-C cables are USB 2 only).")
        }
    }

    mutating func addLockdownBase(_ d: [String: Any]) {
        let p = prov
        let src: (String) -> FieldSource = { FieldSource(tool: "ideviceinfo (libimobiledevice)", key: $0, provenance: p) }
        add("lockdown.modelNumber", "Model number", .hardware, LockdownOutput.string(d, "ModelNumber"), src("ModelNumber"))
        add("lockdown.regionInfo", "Region", .hardware, LockdownOutput.string(d, "RegionInfo"), src("RegionInfo"))
        if fields.first(where: { $0.key == "apple.osVersion" })?.value == nil {
            add("lockdown.productVersion", "OS version (lockdown)", .software, LockdownOutput.string(d, "ProductVersion"), src("ProductVersion"))
            add("lockdown.buildVersion", "Build number (lockdown)", .software, LockdownOutput.string(d, "BuildVersion"), src("BuildVersion"))
            add("lockdown.productType", "Product type (lockdown)", .hardware, LockdownOutput.string(d, "ProductType"), src("ProductType"))
        }
    }

    mutating func addBattery(_ d: [String: Any]?, error: String?) {
        let src = FieldSource(tool: "ideviceinfo -q com.apple.mobile.battery", provenance: prov)
        guard let d = d else {
            fields.append(.unavailable("battery.level", "Battery level", .battery, reason: error ?? "Unavailable.", source: src))
            fields.append(.unavailable("battery.charging", "Charging", .battery, reason: error ?? "Unavailable.", source: src))
            return
        }
        add("battery.level", "Battery level", .battery, LockdownOutput.string(d, "BatteryCurrentCapacity").map { "\($0) %" }, FieldSource(tool: src.tool, key: "BatteryCurrentCapacity", provenance: prov))
        add("battery.charging", "Charging", .battery, (d["BatteryIsCharging"] as? Bool).map { $0 ? "Yes" : "No" }, FieldSource(tool: src.tool, key: "BatteryIsCharging", provenance: prov))
        add("battery.external", "External power", .battery, (d["ExternalConnected"] as? Bool).map { $0 ? "Connected" : "Not connected" }, FieldSource(tool: src.tool, key: "ExternalConnected", provenance: prov))
    }

    mutating func addDisk(_ d: [String: Any]?, error: String?) {
        let src = FieldSource(tool: "ideviceinfo -q com.apple.disk_usage", provenance: prov)
        guard let d = d else {
            fields.append(.unavailable("storage.available", "Available storage", .storage, reason: error ?? "Unavailable.", source: src))
            return
        }
        func bytes(_ k: String) -> String? { LockdownOutput.int64(d, k).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } }
        add("storage.total", "Total disk capacity", .storage, bytes("TotalDiskCapacity"), FieldSource(tool: src.tool, key: "TotalDiskCapacity", provenance: prov))
        add("storage.dataCapacity", "Data partition capacity", .storage, bytes("TotalDataCapacity"), FieldSource(tool: src.tool, key: "TotalDataCapacity", provenance: prov))
        add("storage.available", "Available storage", .storage, bytes("TotalDataAvailable") ?? bytes("AmountDataAvailable"),
            FieldSource(tool: src.tool, key: "TotalDataAvailable", provenance: prov))
    }

    func finish(override: IntelligenceState?, reason: String, action: NextAction) -> IntelligenceSnapshot {
        let ladder = IntelligenceSnapshot.ladder(reaching: evidence)
        let highest = ladder.last(where: \.reached)?.state ?? .waitingForDevice
        let state = override ?? highest
        let family = fields.first(where: { $0.key == "apple.deviceType" })?.value
            ?? (device.usb?.productName ?? device.name)
        return IntelligenceSnapshot(
            deviceID: device.id, providerID: provider.providerID, family: "Apple \(family)", state: state, stateReason: reason,
            nextAction: action, ladder: ladder, fields: fields, services: services.sorted { $0.name < $1.name },
            limitations: limitations, errors: errors, correlation: correlation,
            communicationEvidence: communicationEvidence, authorizationEvidence: authorizationEvidence,
            retrievedAt: Date(), provenance: provider.provenance)
    }
}
