import XCTest
@testable import HCGCore

/// Fake runner that behaves like `xcrun devicectl … --json-output <file>`.
final class ScriptedRunner: CommandRunner {
    var responses: [(prefix: [String], json: String?, stdout: String, exit: Int32)] = []
    var executables: Set<String> = []
    private(set) var calls: [[String]] = []

    func on(_ prefix: [String], json: String? = nil, stdout: String = "", exit: Int32 = 0) {
        responses.append((prefix, json, stdout, exit))
    }

    func isExecutable(atPath path: String) -> Bool { executables.contains(path) }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        let full = [(executable as NSString).lastPathComponent] + arguments
        calls.append(full)
        guard let r = responses.first(where: { full.starts(with: $0.prefix) }) else {
            return CommandResult(exitCode: 1, stderr: Data("no scripted response".utf8))
        }
        if let json = r.json, let i = arguments.firstIndex(of: "--json-output") {
            FileManager.default.createFile(atPath: arguments[i + 1], contents: Data(json.utf8))
        }
        return CommandResult(exitCode: r.exit, stdout: Data(r.stdout.utf8), durationSeconds: 0.12)
    }

    static func xcode(paired: Bool, detailsJSON: String? = AppleSyntheticFixtures.detailsJSON()) -> ScriptedRunner {
        let r = ScriptedRunner()
        r.on(["xcode-select", "-p"], stdout: "/Applications/Xcode.app/Contents/Developer\n")
        r.on(["xcrun", "--find", "devicectl"], stdout: "/Applications/Xcode.app/Contents/Developer/usr/bin/devicectl\n")
        r.on(["xcrun", "devicectl", "--version"], stdout: "397.21\n")
        r.on(["xcrun", "devicectl", "device", "info", "--help"], stdout: "SUBCOMMANDS:\n  apps\n  details\n  lockState\n")
        r.on(["xcrun", "devicectl", "manage", "--help"], stdout: "SUBCOMMANDS:\n  pair\n  unpair\n")
        r.on(["xcrun", "devicectl", "list", "devices"], json: AppleSyntheticFixtures.listJSON(paired: paired))
        if let d = detailsJSON { r.on(["xcrun", "devicectl", "device", "info", "details"], json: d) }
        r.on(["xcrun", "devicectl", "device", "info", "lockState"], json: #"{"info":{"outcome":"success"},"result":{"passcodeRequired":true}}"#)
        return r
    }
}

/// A USB device that looks like a real iPhone to the provider (hardware provenance).
func usbIPhone(serial: String? = CoreDeviceRecord.normalize(AppleSyntheticFixtures.udid), speed: USBSpeed = .high, present: Bool = true) -> DiscoveredDevice {
    var d = AppleSyntheticFixtures.iPhone
    d.id = DeviceIdentifier("usb:test-iphone")
    d.provenance = .hardware
    d.connectionType = .usb
    d.name = "iPhone"
    d.usb?.serialNumber = serial
    d.usb?.speed = speed
    d.isPresent = present
    return d
}

final class AppleIntelligenceTests: XCTestCase {
    let engine = IdentificationEngine()

    func testParsesDevicectlListAndDetails() {
        let devices = DevicectlOutput.devices(Data(AppleSyntheticFixtures.listJSON(paired: true).utf8))
        XCTAssertEqual(devices.count, 1)
        let d = devices[0]
        XCTAssertEqual(d.productType, "iPhone17,2")
        XCTAssertEqual(d.osVersion, "99.0")
        XCTAssertEqual(d.osBuild, "SYN0001")
        XCTAssertEqual(d.internalStorageCapacity, 256_000_000_000)
        XCTAssertEqual(d.ecid, "1234")
        XCTAssertEqual(d.cpuType, "arm64e")
        XCTAssertTrue(d.isPaired)
        XCTAssertTrue(d.isWired)
        XCTAssertEqual(d.capabilities.count, 3)
        XCTAssertEqual(DevicectlOutput.deviceDetails(Data(AppleSyntheticFixtures.detailsJSON().utf8))?.udid, AppleSyntheticFixtures.udid)

        let err = DevicectlOutput.parse(Data(#"{"error":{"code":3,"userInfo":{"NSLocalizedDescription":{"string":"Device is locked"}}}}"#.utf8))
        XCTAssertEqual(err?.errorDescription, "Device is locked")
        XCTAssertFalse(err?.isSuccess ?? true)
        XCTAssertTrue(DevicectlOutput.devices(Data("not json".utf8)).isEmpty)
        XCTAssertEqual(DevicectlOutput.devices(Data(#"{"result":{"devices":[{"identifier":"X"}]}}"#.utf8)).first?.identifier, "X", "Sparse records parse")
    }

    func testCommandAllowList() {
        XCTAssertNil(AppleToolCommand.deviceDetails(identifier: "--help", outputPath: "/tmp/x.json").invocation)
        XCTAssertNil(AppleToolCommand.deviceDetails(identifier: "abc; rm -rf /", outputPath: "/tmp/x.json").invocation)
        XCTAssertNil(AppleToolCommand.ideviceinfo(executable: "/tmp/evil/ideviceinfo", udid: "00008140-0001", domain: nil).invocation)
        XCTAssertNil(AppleToolCommand.ideviceinfo(executable: "/opt/homebrew/bin/ideviceinfo", udid: "00008140-0001", domain: "com.apple.mobile.wireless_lockdown").invocation)
        XCTAssertNil(AppleToolCommand.devicectlHelp(group: ["device", "install"]).invocation)
        let inv = AppleToolCommand.deviceDetails(identifier: "SYNTHETIC-COREDEVICE-0001", outputPath: "/tmp/x.json").invocation
        XCTAssertEqual(inv?.executable, "/usr/bin/xcrun")
        XCTAssertEqual(inv?.arguments, ["devicectl", "device", "info", "details", "--device", "SYNTHETIC-COREDEVICE-0001", "--json-output", "/tmp/x.json"])
    }

    func testToolchainInspection() async {
        let t = await AppleToolchainInspector.inspect(runner: ScriptedRunner.xcode(paired: true), readFile: { path in
            path.hasSuffix("Xcode.app/Contents/version.plist")
                ? try? PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "27.2", "ProductBuildVersion": "27C1"], format: .xml, options: 0)
                : nil
        })
        XCTAssertEqual(t.xcodeVersion, "27.2")
        XCTAssertEqual(t.xcodeBuild, "27C1")
        XCTAssertTrue(t.hasDevicectl)
        XCTAssertEqual(t.devicectlVersion, "397.21")
        XCTAssertTrue(t.supports("details") && t.supports("lockState") && t.supports("pair"))
        XCTAssertFalse(t.supports("processes"))

        let clt = ScriptedRunner()
        clt.on(["xcode-select", "-p"], stdout: "/Library/Developer/CommandLineTools\n")
        clt.on(["xcrun", "--find", "devicectl"], exit: 72)
        let t2 = await AppleToolchainInspector.inspect(runner: clt)
        XCTAssertTrue(t2.isCommandLineToolsOnly)
        XCTAssertFalse(t2.hasDevicectl)
        XCTAssertTrue(t2.problems.contains { $0.contains("xcode-select -s") })
    }

    func testPairedDeviceReachesDiagnosticsWithSourcedFields() async throws {
        let provider = AppleDeviceIntelligenceProvider(runner: ScriptedRunner.xcode(paired: true))
        let device = usbIPhone()
        let ident = engine.identify(device)
        XCTAssertTrue(provider.recognizes(device, identification: ident))
        let snap = await provider.snapshot(for: device, identification: ident)
        XCTAssertEqual(snap.state, .diagnosticsAvailable, snap.stateReason)
        XCTAssertTrue(snap.ladder.allSatisfy(\.reached), "Every progression step has evidence")
        XCTAssertEqual(snap.value("apple.marketingName"), "[SYNTHETIC] iPhone 16 Pro Max")
        XCTAssertEqual(snap.value("apple.osVersion"), "99.0")
        XCTAssertEqual(snap.value("apple.pairingState"), "paired")
        XCTAssertTrue(snap.value("apple.storageCapacity")?.hasPrefix("256") ?? false)
        XCTAssertTrue(snap.correlation?.hasPrefix("Matched by UDID") ?? false)
        XCTAssertFalse(snap.communicationEvidence.isEmpty)
        XCTAssertFalse(snap.authorizationEvidence.isEmpty)
        // Every field names its source, every unavailable field explains why.
        for f in snap.fields {
            XCTAssertFalse(f.source.tool.isEmpty, f.key)
            if f.value == nil { XCTAssertNotNil(f.unavailableReason, f.key) }
        }
        XCTAssertEqual(snap.field("apple.osVersion")?.source.key, "deviceProperties.osVersionNumber")
        XCTAssertTrue(snap.field("apple.udid")?.sensitive ?? false)
        XCTAssertTrue(snap.field("battery.level")?.unavailableReason?.contains("libimobiledevice") ?? false)
        XCTAssertTrue(snap.limitations.contains { $0.contains("Connected at USB 2.0") }, "USB 2 link on a USB 3 capable model is flagged")
        XCTAssertTrue(snap.services.contains { $0.identifier == "apple.usbmux" })
        XCTAssertTrue(snap.services.contains { $0.identifier == "com.apple.coredevice.feature.getdeviceinfo" })
    }

    func testUnpairedDeviceOffersPairingAndPairs() async {
        let runner = ScriptedRunner.xcode(paired: false, detailsJSON: nil)
        let provider = AppleDeviceIntelligenceProvider(runner: runner)
        let device = usbIPhone()
        let ident = engine.identify(device)
        let snap = await provider.snapshot(for: device, identification: ident)
        XCTAssertEqual(snap.state, .pairingAvailable)
        XCTAssertEqual(snap.nextAction.kind, .pairDevice)
        XCTAssertTrue(snap.nextAction.performable)
        XCTAssertTrue(snap.nextAction.instructions.contains { $0.contains("Trust") })
        XCTAssertTrue(snap.communicationEvidence.isEmpty, "No communication is claimed before pairing")
        XCTAssertFalse(runner.calls.contains { $0.contains("details") }, "Unpaired devices are not queried")

        runner.on(["xcrun", "devicectl", "manage", "pair"], json: #"{"info":{"outcome":"success"},"result":{}}"#)
        let outcome = await provider.perform(.pairDevice, for: device, identification: ident)
        XCTAssertTrue(outcome.succeeded, outcome.message)
        XCTAssertTrue(runner.calls.contains { $0.starts(with: ["xcrun", "devicectl", "manage", "pair", "--device", AppleSyntheticFixtures.coreDeviceID]) })
    }

    func testLockedDeviceAsksToUnlock() async {
        let runner = ScriptedRunner.xcode(paired: true, detailsJSON: #"{"error":{"userInfo":{"NSLocalizedDescription":"The device is locked. Unlock it and try again."}}}"#)
        let provider = AppleDeviceIntelligenceProvider(runner: runner)
        let device = usbIPhone()
        let snap = await provider.snapshot(for: device, identification: engine.identify(device))
        XCTAssertEqual(snap.state, .authorizationRequired)
        XCTAssertEqual(snap.nextAction.kind, .unlockDevice)
        XCTAssertTrue(snap.errors.contains { $0.contains("locked") })
        XCTAssertTrue(snap.ladder.first { $0.state == .pairingEstablished }?.reached ?? false)
        XCTAssertFalse(snap.ladder.first { $0.state == .communicationEstablished }?.reached ?? true)
    }

    func testNoXcodeLimitsConnectionButKeepsUSBInformation() async {
        let runner = ScriptedRunner()
        runner.on(["xcode-select", "-p"], stdout: "/Library/Developer/CommandLineTools\n")
        runner.on(["xcrun", "--find", "devicectl"], exit: 72)
        let provider = AppleDeviceIntelligenceProvider(runner: runner)
        let device = usbIPhone()
        let snap = await provider.snapshot(for: device, identification: engine.identify(device))
        XCTAssertEqual(snap.state, .connectionLimited)
        XCTAssertEqual(snap.nextAction.kind, .selectXcode)
        XCTAssertEqual(snap.value("usb.vendorID"), "0x05AC")
        XCTAssertNil(snap.value("apple.osVersion"))
        XCTAssertTrue(snap.field("apple.osVersion")?.unavailableReason?.contains("xcode-select") ?? false)
        XCTAssertTrue(snap.ladder.first { $0.state == .protocolDiscovered }?.reached ?? false)
    }

    func testDeviceNotListedAsksToUnlock() async {
        let runner = ScriptedRunner.xcode(paired: true)
        runner.responses.removeAll { $0.prefix == ["xcrun", "devicectl", "list", "devices"] }
        runner.on(["xcrun", "devicectl", "list", "devices"], json: #"{"info":{"outcome":"success"},"result":{"devices":[]}}"#)
        let provider = AppleDeviceIntelligenceProvider(runner: runner)
        let device = usbIPhone(serial: "0000OTHERDEVICE0000")
        let snap = await provider.snapshot(for: device, identification: engine.identify(device))
        XCTAssertEqual(snap.state, .protocolDiscovered)
        XCTAssertEqual(snap.nextAction.kind, .unlockDevice)
        XCTAssertNil(snap.correlation)
    }

    func testCorrelation() {
        let records = DevicectlOutput.devices(Data(AppleSyntheticFixtures.listJSON(paired: true).utf8))
        XCTAssertTrue(AppleDeviceIntelligenceProvider.correlate(usbIPhone(), with: records)?.method.hasPrefix("Matched by UDID") ?? false)
        XCTAssertTrue(AppleDeviceIntelligenceProvider.correlate(usbIPhone(serial: nil), with: records)?.method.hasPrefix("Matched by elimination") ?? false)
        var two = records
        var other = records[0]
        other.udid = "00008000-AAAA"
        two.append(other)
        XCTAssertNil(AppleDeviceIntelligenceProvider.correlate(usbIPhone(serial: nil), with: two), "Ambiguous matches are refused")
    }

    func testDisconnectedSnapshotAndTimeline() async {
        let provider = AppleDeviceIntelligenceProvider(runner: ScriptedRunner.xcode(paired: true))
        let engineI = DeviceIntelligenceEngine(providers: [provider, GenericUSBIntelligenceProvider()])
        let device = usbIPhone()
        let ident = engine.identify(device)
        _ = await engineI.refresh(device, identification: ident, key: "k")
        engineI.markDisconnected(device.id, key: "k")
        XCTAssertEqual(engineI.snapshots[device.id]?.state, .disconnected)
        XCTAssertEqual(engineI.snapshots[device.id]?.nextAction.kind, .reconnect)
        XCTAssertTrue(engineI.timeline(key: "k").contains { $0.kind == .disconnect })
        let gone = await provider.snapshot(for: usbIPhone(present: false), identification: ident)
        XCTAssertEqual(gone.state, .disconnected)
    }

    func testRedactedExportHidesIdentifiers() async throws {
        let provider = AppleDeviceIntelligenceProvider(runner: ScriptedRunner.xcode(paired: true))
        let device = usbIPhone()
        let snap = await provider.snapshot(for: device, identification: engine.identify(device)).redacted()
        let json = String(decoding: try JSONEncoder().encode(snap), as: UTF8.self)
        XCTAssertFalse(json.contains(AppleSyntheticFixtures.udid))
        XCTAssertFalse(json.contains(CoreDeviceRecord.normalize(AppleSyntheticFixtures.udid)))
        XCTAssertFalse(json.contains("SYNTHETICSN"))
        XCTAssertTrue(json.contains("iPhone17,2"), "Non-sensitive facts remain")
    }

    func testAppleDiagnosticsRunWithSourcesAndAreScopedToApple() async {
        let backend = SyntheticDiscoveryBackend(fixtures: [AppleSyntheticFixtures.iPhone])
        let provider = AppleDeviceIntelligenceProvider(runner: SyntheticAppleRunner(), provenance: .synthetic)
        provider.timelineProvider = { _ in [] }
        let diag = DiagnosticEngine(tests: HostOperationCatalog.standardTests() + provider.diagnosticTests())
        let device = AppleSyntheticFixtures.iPhone
        let ident = engine.identify(device)
        XCTAssertEqual(ident.profileID, "apple.iphone")
        let ctx = DiagnosticContext(device: device, identification: ident, probe: backend, sleep: { _ in })
        let ids = AppleDiagnostics.descriptors.map(\.id)
        let run = await diag.run(testIDs: ids, context: ctx)
        let byID = Dictionary(uniqueKeysWithValues: run.results.map { ($0.testID, $0) })
        XCTAssertEqual(byID["apple.usb-enumeration"]?.outcome, .passed)
        XCTAssertEqual(byID["apple.pairing-status"]?.outcome, .passed)
        XCTAssertEqual(byID["apple.service-availability"]?.outcome, .passed)
        XCTAssertEqual(byID["apple.query-latency"]?.outcome, .passed)
        XCTAssertTrue(byID["apple.query-latency"]?.evidence.first?.contains("SYNTHETIC devicectl fixture") ?? false)
        XCTAssertEqual(byID["apple.query-latency"]?.measurements.first?.provenance, .synthetic)
        XCTAssertEqual(byID["apple.reconnect-handling"]?.outcome, .notSupported, "Never simulated on hardware; not yet exercised")
        XCTAssertEqual(byID["apple.battery-storage"]?.outcome, .passed, "Capacity from devicectl")
        XCTAssertEqual(byID["apple.compatibility"]?.outcome, .warning, "USB 2 link on a USB 3 model")
        for r in run.results {
            XCTAssertNotEqual(r.outcome, .error, "\(r.testID): \(r.errors)")
            XCTAssertFalse(r.limitations.isEmpty && r.evidence.isEmpty, r.testID)
        }
        // Scoped to Apple: never applicable to a non-Apple phone.
        let pixelTests = diag.applicableTests(for: Fixtures.pixelADB, identification: engine.identify(Fixtures.pixelADB)).map(\.id)
        XCTAssertFalse(pixelTests.contains { $0.hasPrefix("apple.") })
    }

    func testGenericProviderIsHonest() async {
        let p = GenericUSBIntelligenceProvider()
        let snap = await p.snapshot(for: Fixtures.sandisk, identification: engine.identify(Fixtures.sandisk))
        XCTAssertEqual(snap.state, .protocolDiscovered)
        XCTAssertTrue(snap.communicationEvidence.isEmpty)
        XCTAssertFalse(snap.ladder.first { $0.state == .communicationEstablished }?.reached ?? true)
        let mystery = await p.snapshot(for: Fixtures.mystery, identification: engine.identify(Fixtures.mystery))
        XCTAssertEqual(mystery.state, .usbEnumerated)
    }

    func testInventoryAppliesIntelligence() {
        let inv = DeviceInventory(keySalt: "t")
        let device = usbIPhone()
        inv.apply(.attached(device))
        XCTAssertEqual(inv.record(device.id)?.status, .diagnosticsAvailable, "iPhone no longer 'Adapter required' now that an adapter exists")
        inv.applyIntelligence(device.id, communication: ["live details"], authorization: ["paired"])
        XCTAssertEqual(inv.record(device.id)?.status, .authenticated)
        XCTAssertEqual(inv.record(device.id)?.assessment.state(of: .authorization), .verified)
        inv.applyIntelligence(device.id, communication: [], authorization: ["paired"])
        XCTAssertEqual(inv.record(device.id)?.status, .diagnosticsAvailable, "Status falls back when the device stops answering")
    }

    func testLiveMonitorStats() {
        let m = LiveMonitor()
        let t0 = Date(timeIntervalSince1970: 1000)
        m.connected(key: "k", at: t0)
        m.record(MonitorSample(at: t0, present: true, latencyMs: 0.5, source: "IOKit", provenance: .hardware), key: "k")
        m.record(MonitorSample(at: t0.addingTimeInterval(5), present: true, latencyMs: 1.5, source: "IOKit", provenance: .hardware), key: "k")
        m.record(MonitorSample(at: t0.addingTimeInterval(10), present: false, latencyMs: nil, source: "IOKit", provenance: .hardware), key: "k")
        let s = m.stats(key: "k", now: t0.addingTimeInterval(60))
        XCTAssertEqual(s.uptimeSeconds, 60, accuracy: 0.01)
        XCTAssertEqual(s.availabilityPercent ?? 0, 66.67, accuracy: 0.1)
        XCTAssertEqual(s.latencyBySource["IOKit"]?.mean ?? 0, 1.0, accuracy: 0.001)
        m.disconnected(key: "k")
        XCTAssertEqual(m.stats(key: "k").dropouts, 1)
        XCTAssertNil(m.stats(key: "k").connectedSince)
    }

    func testAppleAdapterManifestIsValid() {
        let issues = ManifestValidator.validate(BuiltInAdapters.appleDeviceIntelligence, origin: .builtIn).filter { $0.severity == .error }
        XCTAssertTrue(issues.isEmpty, "\(issues)")
        XCTAssertTrue(HostOperationCatalog.ids.contains("apple.query-latency"))
    }
}
