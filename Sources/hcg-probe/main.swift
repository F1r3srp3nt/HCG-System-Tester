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
    """)
    exit(0)
}

let showSerials = args.contains("--show-serials")
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

printRecords()

if args.contains("--diagnose") {
    let engine = DiagnosticEngine()
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
