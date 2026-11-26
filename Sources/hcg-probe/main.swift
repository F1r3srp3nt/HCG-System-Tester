import Foundation
import HCGCore
import HCGHardware

// hcg-probe — command-line companion to HCG System Tester.
//
//   hcg-probe                 one-shot list of real USB devices
//   hcg-probe --watch         live attach/detach events (Ctrl-C to stop)
//   hcg-probe --json          one-shot JSON (redacted)
//   hcg-probe --diagnose      list devices and run the read-only default suite on each
//   hcg-probe --synthetic     use labelled synthetic fixtures instead of hardware
//   hcg-probe --show-serials  do not mask serial numbers in terminal output
//   hcg-probe --toolchain     inspect Xcode / devicectl / libimobiledevice capabilities
//   hcg-probe --apple         Apple Device Intelligence for every connected iPhone / iPad

let args = Set(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    print("""
    hcg-probe \(HCGSystemTesterInfo.version) — \(HCGSystemTesterInfo.productName) discovery probe

      hcg-probe                 list real USB / Thunderbolt devices once
      hcg-probe --watch         stream live attach / detach events (Ctrl-C to stop)
      hcg-probe --json          print a redacted JSON snapshot
      hcg-probe --diagnose      run the read-only default diagnostic suite on every device
      hcg-probe --synthetic     use labelled SYNTHETIC fixtures instead of hardware
      hcg-probe --show-serials  show serial numbers unmasked in terminal output
      hcg-probe --toolchain     inspect Xcode / devicectl / libimobiledevice capabilities
      hcg-probe --apple         Apple Device Intelligence for every connected iPhone / iPad
      hcg-probe --apple --pair  also start Apple's pairing flow for unpaired devices (tap Trust on the device)
      hcg-probe --connectivity  match devices to encyclopedia profiles and check required equipment (read-only)
      hcg-probe --connectivity --ssdp   also send one SSDP M-SEARCH on the local network and list responders
    """)
    exit(0)
}

let showSerials = args.contains("--show-serials")

/// Runs an async block to completion from top-level code while keeping the main run loop alive.
func runAsync(_ body: @escaping () async -> Void) {
    let group = DispatchGroup()
    group.enter()
    Task { await body(); group.leave() }
    while group.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

if args.contains("--toolchain") {
    runAsync {
        let t = await AppleToolchainInspector.inspect(runner: ProcessCommandRunner())
        print("Developer directory : \(t.developerDirectory ?? "not set")")
        print("Xcode               : \(t.xcodeVersion.map { "\($0) (\(t.xcodeBuild ?? "?"))" } ?? "not found")")
        print("devicectl           : \(t.devicectlPath ?? "not available") \(t.devicectlVersion ?? "")")
        print("devicectl commands  : \(t.devicectlSubcommands.isEmpty ? "none detected" : t.devicectlSubcommands.joined(separator: ", "))")
        print("libimobiledevice    : \(t.ideviceinfoPath ?? "not installed (optional)")")
        for p in t.problems { print("! \(p)") }
    }
    exit(0)
}
let useSynthetic = args.contains("--synthetic")
let inventory = DeviceInventory(keySalt: "hcg-probe")
/// Serialises inventory access: IOKit delivers events on its own queue.
let inventoryQueue = DispatchQueue(label: "hcg-probe.inventory")

func line(_ r: DeviceRecord) -> String {
    let d = r.device
    var parts: [String] = []
    if let usb = d.usb {
        parts.append("\(usb.vendorIDHex):\(usb.productIDHex)")
        if let s = usb.speed { parts.append(s.shortName) }
        if let loc = usb.locationID { parts.append("loc \(Hex.format32(loc))") }
        if let serial = usb.serialNumber { parts.append("SN " + (showSerials ? serial : Redactor.maskSerial(serial))) }
        if !usb.bsdNames.isEmpty { parts.append("disk " + usb.bsdNames.joined(separator: ",")) }
        if !usb.serialDevicePaths.isEmpty { parts.append(usb.serialDevicePaths.joined(separator: ",")) }
    }
    if let tb = d.thunderbolt, let depth = tb.depth { parts.append("depth \(depth)") }
    let ident = r.identification.profileName.map { "\($0) [\(r.identification.confidence.displayName)]" } ?? "unidentified"
    return "\(d.displayName)\n    \(parts.joined(separator: " · "))\n    \(ident) → \(r.status.displayName): \(r.statusReason)"
}

func printRecords() {
    let records = inventoryQueue.sync { inventory.presentRecords }
    if records.isEmpty {
        print(useSynthetic ? "No synthetic fixtures." : "No USB or Thunderbolt devices are enumerated by macOS right now.")
        print("Tip: charge-only cables and host-to-host links (e.g. Mac ↔ console) never enumerate.")
        return
    }
    for (i, r) in records.enumerated() {
        print(String(format: "%2ld. ", i + 1) + line(r))
        for l in r.assessment.layers {
            print("      · \(l.layer.displayName): \(l.state.displayName)")
        }
    }
}

let backends: [DeviceDiscoveryBackend] = useSynthetic ? [SyntheticDiscoveryBackend()] : HostDiscovery.makeHardwareBackends()
if backends.isEmpty {
    print("Real hardware discovery requires macOS (IOKit). Use --synthetic to exercise the engine with labelled fixtures.")
    exit(2)
}

let watching = args.contains("--watch")
for backend in backends {
    backend.start { event in
        let handle = {
            inventory.apply(event)
            guard watching else { return }
            let stamp = ISO8601DateFormatter().string(from: Date())
            switch event {
            case .attached(let d):
                if let r = inventory.record(d.id) { print("[\(stamp)] ATTACHED  " + line(r)) }
            case .detached(let id, _):
                print("[\(stamp)] DETACHED  \(inventory.record(id)?.device.displayName ?? id.rawValue)")
            case .backendStatus(let s):
                print("[\(stamp)] BACKEND   \(s.displayName): \(s.state.rawValue) — \(s.detail)")
            }
        }
        inventoryQueue.sync(execute: handle)
    }
}

if watching {
    print("Watching for USB / Thunderbolt changes. Connect or disconnect a device… (Ctrl-C to stop)")
    signal(SIGINT) { _ in
        print("\nStopped.")
        exit(0)
    }
    dispatchMain()
}

if args.contains("--json") {
    let records = inventoryQueue.sync { inventory.presentRecords }
    let report = ReportGenerator.make(title: "hcg-probe snapshot", runs: [], records: records, redactor: Redactor())
    let data = (try? ReportGenerator.json(report)) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

if args.contains("--connectivity") {
    let records = inventoryQueue.sync { inventory.presentRecords }
    let profiles = EncyclopediaData.all
    print("Universal Connectivity — \(profiles.count) profiles · \(UniversalProtocolRegistry.all.count) protocols · discovery only, nothing is connected")
    for r in records {
        let e = ObservedEndpoint.fromUSB(r.device)
        let m = EndpointMatcher.match(e, profiles: profiles)
        let matched = m.isEmpty ? "no profile match (discovered only)" : m.map { "\($0.profileID) [\($0.evidence.joined(separator: ", "))]" }.joined(separator: "; ")
        print("  \(r.device.displayName) (\(r.device.provenance.displayName)) → \(matched)")
    }
    runAsync {
        let ifs = await HostNetwork.interfaces()
        let active = ifs.filter { $0.hasAddress && ($0.type == "Wi-Fi" || $0.type == "Ethernet") }.map { "\($0.name) (\($0.type))" }
        let paths = Set(HostFacts.probedPaths.filter { FileManager.default.fileExists(atPath: $0) })
        let eq = EquipmentDetector.detect(HostFacts(activeNetworkInterfaces: active, usbDevices: records.map(\.device), existingPaths: paths))
        print("Equipment detected on this Mac:")
        for (id, s) in eq.sorted(by: { $0.key < $1.key }) { print("  \(id): \(s.availability.displayName) — \(s.evidence)") }
        if args.contains("--ssdp") {
            let found = await SSDPDiscovery.search(timeout: 3)
            print("SSDP: \(found.count) responder(s)")
            for e in found {
                let m = EndpointMatcher.match(e, profiles: profiles).map(\.profileID)
                print("  \(e.name) · \(e.attributes["serviceType"] ?? "") → \(m.isEmpty ? "no profile match" : m.joined(separator: ", "))")
            }
        }
    }
    exit(0)
}

printRecords()

if args.contains("--apple") {
    let records = inventoryQueue.sync { inventory.presentRecords }
    let provider = AppleDeviceIntelligenceProvider(runner: useSynthetic ? SyntheticAppleRunner(paired: false) : ProcessCommandRunner(),
                                                   provenance: useSynthetic ? .synthetic : .hardware)
    let apple = records.filter { provider.recognizes($0.device, identification: $0.identification) }
    if apple.isEmpty { print("\nNo iPhone or iPad is enumerated on USB. Connect one with a data-capable cable and unlock it.") }
    runAsync {
        for r in apple {
            var snap = await provider.snapshot(for: r.device, identification: r.identification)
            if args.contains("--pair"), snap.nextAction.kind == .pairDevice {
                print("\nStarting Apple's pairing flow for \(r.device.displayName). Unlock the device and tap Trust…")
                let outcome = await provider.perform(.pairDevice, for: r.device, identification: r.identification)
                print("  \(outcome.message)")
                provider.invalidateCaches()
                snap = await provider.snapshot(for: r.device, identification: r.identification)
            }
            print("\n== Apple Device Intelligence: \(r.device.displayName) ==")
            print("State \(snap.state.number)/13: \(snap.state.displayName) — \(snap.stateReason)")
            print("Next action: \(snap.nextAction.title)")
            for i in snap.nextAction.instructions { print("  • \(i)") }
            for step in snap.ladder { print("  [\(step.reached ? "x" : " ")] \(step.state.displayName)\(step.evidence.map { " — \($0)" } ?? "")") }
            for group in IntelligenceGroup.allCases {
                let fields = snap.fields(in: group)
                guard !fields.isEmpty else { continue }
                print("  \(group.displayName):")
                for f in fields {
                    let v = f.value.map { f.sensitive && !showSerials ? Redactor.maskSerial($0) : $0 } ?? "unavailable — \(f.unavailableReason ?? "")"
                    print("    \(f.label): \(v)   [\(f.source.description)]")
                }
            }
            if !snap.services.isEmpty { print("  Services: " + snap.services.map(\.name).joined(separator: ", ")) }
            for l in snap.limitations { print("  ! \(l)") }
            for e in snap.errors { print("  ✗ \(e)") }
        }
    }
}

if args.contains("--diagnose") {
    let appleProvider = AppleDeviceIntelligenceProvider(runner: useSynthetic ? SyntheticAppleRunner() : ProcessCommandRunner(),
                                                        provenance: useSynthetic ? .synthetic : .hardware)
    let engine = DiagnosticEngine(tests: HostOperationCatalog.standardTests() + appleProvider.diagnosticTests())
    let records = inventoryQueue.sync { inventory.presentRecords }
    let group = DispatchGroup()
    group.enter()
    Task {
        for r in records {
            guard let probe = backends.first(where: { $0.provenance == r.device.provenance && $0.connectionTypes.contains(r.device.connectionType) }) ?? backends.first else { continue }
            let ctx = DiagnosticContext(device: r.device, identification: r.identification, probe: probe, deviceKey: r.stableKey)
            let run = await engine.run(testIDs: engine.defaultSuite(for: r.device, identification: r.identification), context: ctx)
            print("\n== \(r.device.displayName) ==")
            for res in run.results {
                let m = res.measurements.map { "\($0.name)=\($0.formatted)" }.joined(separator: ", ")
                print("  [\(res.outcome.displayName.uppercased())] \(res.testName): \(res.summary)\(m.isEmpty ? "" : " (\(m))")")
            }
        }
        group.leave()
    }
    while group.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
