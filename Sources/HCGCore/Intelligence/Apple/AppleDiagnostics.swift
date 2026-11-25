import Foundation

/// Real, read-only Apple device diagnostics. Each result names its measurement source.
public enum AppleDiagnostics {
    static let families: [DeviceCategory] = [.smartphone, .tablet]
    static let apple: [UInt16] = [0x05AC]

    static func d(_ id: String, _ name: String, _ cat: DiagnosticCategory, _ summary: String, duration: Double = 2) -> DiagnosticTestDescriptor {
        DiagnosticTestDescriptor(id: id, name: name, category: cat, summary: summary, categories: families, vendorIDs: apple, estimatedDurationSeconds: duration)
    }

    public static let usbEnumeration = d("apple.usb-enumeration", "Apple USB enumeration", .connectionHealth,
                                         "Verifies the Apple USB descriptors and the usbmux/PTP interfaces macOS enumerated.", duration: 0.2)
    public static let identification = d("apple.identification", "Apple device identification", .deviceIdentification,
                                         "Cross-checks IOKit's USB identity against CoreDevice's model, product type and UDID.")
    public static let pairing = d("apple.pairing-status", "Pairing verification", .protocolValidation,
                                  "Reports whether the device trusts this Mac (CoreDevice, plus libimobiledevice when installed).")
    public static let services = d("apple.service-availability", "Authorized service availability", .interfaceAvailability,
                                   "Lists the device services CoreDevice offers, developer-disk-image services and tunnel state.")
    public static let latency = d("apple.query-latency", "Device response latency", .communicationLatency,
                                  "Times three live CoreDevice queries answered by the device.", duration: 8)
    public static let stability = d("apple.connection-stability", "Apple connection stability (10 s)", .connectionStability,
                                    "Watches USB presence for 10 s and confirms CoreDevice still sees the device afterwards.", duration: 11)
    public static let information = d("apple.device-information", "Device information retrieval", .deviceSpecific,
                                      "Retrieves every supported field and reports what is unavailable and why.")
    public static let reconnect = d("apple.reconnect-handling", "Disconnect & reconnect handling", .connectionStability,
                                    "Checks that a disconnect was detected and the device was re-identified after reconnecting.", duration: 0.1)
    public static let authorization = d("apple.authorization-requirements", "Authorization requirements", .deviceSpecific,
                                        "Explains which authorization each capability needs and what is already satisfied.")
    public static let compatibility = d("apple.compatibility", "Compatibility evaluation", .deviceSpecific,
                                        "Evaluates Xcode/devicectl support, cable speed against the model's USB capability and transport.")
    public static let batteryStorage = d("apple.battery-storage", "Battery & storage", .hardwareHealth,
                                         "Reports battery level and free space where a supported source exposes them.")

    public static let descriptors: [DiagnosticTestDescriptor] = [usbEnumeration, identification, pairing, services, latency, stability,
                                                                  information, reconnect, authorization, compatibility, batteryStorage]

    /// One test instance per operation, routed to whichever provider recognises the device
    /// (e.g. the hardware provider for a real iPhone, the synthetic provider for the fixture).
    public static func tests(providers: [AppleDeviceIntelligenceProvider]) -> [DiagnosticTest] {
        descriptors.map { AppleTest(descriptor: $0, providers: providers) }
    }
}

struct AppleTest: DiagnosticTest {
    let descriptor: DiagnosticTestDescriptor
    let providers: [AppleDeviceIntelligenceProvider]

    func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let device = try ctx.requirePresent()
        guard let provider = providers.first(where: { $0.recognizes(device, identification: ctx.identification) }) else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "Not an Apple iPhone/iPad handled by this adapter.")
        }
        return try await RoutedAppleTest(descriptor: descriptor, provider: provider).run(ctx, device)
    }
}

struct RoutedAppleTest {
    let descriptor: DiagnosticTestDescriptor
    let provider: AppleDeviceIntelligenceProvider

    var sourceLabel: String { provider.toolSource }

    func run(_ ctx: DiagnosticContext, _ device: DiscoveredDevice) async throws -> DiagnosticTestOutput {
        switch descriptor.id {
        case AppleDiagnostics.usbEnumeration.id: return usbEnumeration(device)
        case AppleDiagnostics.latency.id: return await latency(ctx, device)
        case AppleDiagnostics.stability.id: return try await stability(ctx, device)
        case AppleDiagnostics.reconnect.id: return reconnect(ctx)
        default: break
        }
        let snap = await provider.snapshot(for: device, identification: ctx.identification)
        switch descriptor.id {
        case AppleDiagnostics.identification.id: return identification(snap, device)
        case AppleDiagnostics.pairing.id: return await pairing(snap)
        case AppleDiagnostics.services.id: return services(snap)
        case AppleDiagnostics.information.id: return information(snap)
        case AppleDiagnostics.authorization.id: return authorization(snap)
        case AppleDiagnostics.compatibility.id: return await compatibility(snap, device)
        case AppleDiagnostics.batteryStorage.id: return batteryStorage(snap)
        default: return DiagnosticTestOutput(outcome: .error, summary: "Unknown Apple test.")
        }
    }

    func fieldEvidence(_ snap: IntelligenceSnapshot, _ keys: [String]) -> [String] {
        keys.compactMap { snap.field($0) }.map { f in
            "\(f.label): \(f.sensitive ? (f.value.map { Redactor.maskSerial($0) } ?? "—") : (f.value ?? "unavailable — \(f.unavailableReason ?? "")")) [source: \(f.source.description)]"
        }
    }

    func usbEnumeration(_ d: DiscoveredDevice) -> DiagnosticTestOutput {
        guard let usb = d.usb else { return DiagnosticTestOutput(outcome: .failed, summary: "No USB descriptors.") }
        let mux = usb.interfaces.contains(where: AppleDeviceIntelligenceProvider.isUsbmuxInterface)
        let ptp = usb.interfaces.contains { $0.classCode == 0x06 }
        var evidence = ["VID \(usb.vendorIDHex) PID \(usb.productIDHex) “\(usb.productName ?? d.name)” [source: IOKit]",
                        "Interfaces: " + usb.interfaces.map { "#\($0.number) \(DeviceMatchRules.triple($0)) \($0.functionDescription)" }.joined(separator: "; ")]
        if let s = usb.speed { evidence.append("Negotiated link: \(s.displayName) [source: IOKit Device Speed]") }
        return DiagnosticTestOutput(
            outcome: mux ? .passed : .warning,
            summary: mux ? "Apple device enumerated with its usbmux service interface\(ptp ? " and PTP" : "")." : "Enumerated, but the usbmux interface is missing.",
            measurements: [ctx0("Interfaces", Double(usb.interfaces.count), "count", d.provenance)],
            evidence: evidence,
            limitations: ["Enumeration alone does not mean the device will answer; see pairing and service tests."],
            recommendedNextAction: mux ? "No action needed." : "Unlock the device. A locked device in USB Restricted Mode, or a charge-only cable, exposes fewer interfaces.")
    }

    func ctx0(_ name: String, _ v: Double, _ unit: String, _ p: DataProvenance) -> DiagnosticMeasurement {
        DiagnosticMeasurement(name: name, value: v, unit: unit, provenance: p)
    }

    func identification(_ snap: IntelligenceSnapshot, _ d: DiscoveredDevice) -> DiagnosticTestOutput {
        var evidence = fieldEvidence(snap, ["usb.productName", "apple.deviceType", "apple.marketingName", "apple.productType", "apple.hardwareModel"])
        if let c = snap.correlation { evidence.append("Correlation: \(c)") }
        guard snap.value("apple.productType") != nil else {
            return DiagnosticTestOutput(outcome: .warning, summary: "Identified from USB only (Apple “\(d.usb?.productName ?? d.name)”); CoreDevice identity not available.",
                                        evidence: evidence, limitations: ["The commercial model needs CoreDevice (Xcode) or a lockdown session."],
                                        recommendedNextAction: snap.nextAction.title)
        }
        let usbName = (d.usb?.productName ?? d.name).lowercased()
        let family = snap.value("apple.deviceType")?.lowercased() ?? ""
        let consistent = family.isEmpty || usbName.contains(family)
        let byUDID = snap.correlation?.hasPrefix("Matched by UDID") ?? false
        return DiagnosticTestOutput(
            outcome: consistent && byUDID ? .passed : .warning,
            summary: "\(snap.value("apple.marketingName") ?? "Apple device") (\(snap.value("apple.productType") ?? "?")) — \(byUDID ? "UDID-verified" : "matched by elimination").",
            evidence: evidence,
            limitations: consistent ? [] : ["USB product name and CoreDevice family disagree."],
            recommendedNextAction: byUDID ? "No action needed." : "Disconnect other Apple devices so the match can be verified.")
    }

    func pairing(_ snap: IntelligenceSnapshot) async -> DiagnosticTestOutput {
        var evidence = fieldEvidence(snap, ["apple.pairingState", "apple.authenticationType"])
        let tools = await provider.toolchain()
        if let exe = tools.idevicepairPath, let udid = snap.value("apple.udid") ?? snap.value("usb.serialNumber"),
           let inv = AppleToolCommand.idevicepairValidate(executable: exe, udid: udid).invocation {
            let r = await provider.runner.run(inv.executable, inv.arguments, timeout: 20)
            evidence.append("idevicepair validate: \(r.succeeded ? "valid pairing record" : r.failureSummary) [source: libimobiledevice]")
        }
        let state = snap.value("apple.pairingState")
        if state == nil {
            return DiagnosticTestOutput(outcome: .warning, summary: "Pairing status unavailable.", evidence: evidence,
                                        limitations: [snap.field("apple.pairingState")?.unavailableReason ?? ""], recommendedNextAction: snap.nextAction.title)
        }
        let paired = state?.lowercased() == "paired"
        return DiagnosticTestOutput(
            outcome: paired ? .passed : .warning,
            summary: paired ? "The device trusts this Mac (paired)." : "Not paired (\(state!)).",
            evidence: evidence,
            limitations: ["Pairing status is reported by Apple's services; System Tester does not read pairing records directly."],
            recommendedNextAction: paired ? "No action needed." : "Unlock the device and use Pair, then tap Trust on the device.")
    }

    func services(_ snap: IntelligenceSnapshot) -> DiagnosticTestOutput {
        let list = snap.services.map { "\($0.name) [\($0.identifier)] — \($0.available ? "available" : "unavailable") [source: \($0.source.description)]" }
        let coreDevice = snap.services.filter { $0.identifier.hasPrefix("com.apple.coredevice") }.count
        return DiagnosticTestOutput(
            outcome: coreDevice > 0 ? .passed : .warning,
            summary: coreDevice > 0 ? "\(coreDevice) CoreDevice service(s) available; \(snap.services.count) service(s) in total." : "No CoreDevice services reported (USB-level services only).",
            measurements: [ctx0("CoreDevice services", Double(coreDevice), "count", snap.provenance)],
            evidence: list + fieldEvidence(snap, ["apple.ddiServices", "apple.developerMode", "apple.tunnelState"]),
            limitations: ["Service availability is what CoreDevice advertises; individual services may still require Developer Mode."],
            recommendedNextAction: coreDevice > 0 ? "No action needed." : snap.nextAction.title)
    }

    func latency(_ ctx: DiagnosticContext, _ d: DiscoveredDevice) async -> DiagnosticTestOutput {
        let listing = await provider.listDevices(force: true)
        guard let match = AppleDeviceIntelligenceProvider.correlate(d, with: listing.devices), match.record.isPaired, let id = match.record.identifier else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "Needs a paired device visible to CoreDevice.",
                                        limitations: ["Unpaired devices do not answer live queries."], recommendedNextAction: "Pair the device first.")
        }
        var samples: [Double] = []
        var errors: [String] = []
        for _ in 0..<3 {
            let r = await provider.measureQueryLatency(identifier: id)
            if let ms = r.ms { samples.append(ms) } else if let e = r.error { errors.append(e) }
        }
        guard !samples.isEmpty else {
            return DiagnosticTestOutput(outcome: .failed, summary: "The device did not answer.", errors: errors,
                                        recommendedNextAction: "Unlock the device and keep it awake, then re-run.")
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        return DiagnosticTestOutput(
            outcome: errors.isEmpty ? .passed : .warning,
            summary: String(format: "Median %.0f ms over %ld live queries.", median, samples.count),
            measurements: [ctx.measurement("Median response latency", median, "ms"), ctx.measurement("Min response latency", sorted.first!, "ms"),
                           ctx.measurement("Max response latency", sorted.last!, "ms")],
            evidence: ["Source: \(sourceLabel) device info details (uncached), \(samples.count) sample(s)"] + samples.map { String(format: "%.1f ms", $0) },
            limitations: ["Measured end to end: includes devicectl start-up and CoreDevice service overhead, so it is an upper bound on device response time."],
            errors: errors)
    }

    func stability(_ ctx: DiagnosticContext, _ d: DiscoveredDevice) async throws -> DiagnosticTestOutput {
        let polls = 20
        var missing = 0
        for _ in 0..<polls {
            if ctx.probe.refresh(d.id) == nil { missing += 1 }
            try await ctx.sleep(0.5)
        }
        if missing == polls { throw DiagnosticError.deviceDisconnected(d.id) }
        let listing = await provider.listDevices(force: true)
        let stillSeen = AppleDeviceIntelligenceProvider.correlate(d, with: listing.devices) != nil
        return DiagnosticTestOutput(
            outcome: missing == 0 && stillSeen ? .passed : (missing == 0 ? .warning : .failed),
            summary: missing == 0 ? "No USB drop-outs in 10 s; CoreDevice \(stillSeen ? "still sees" : "no longer sees") the device." : "\(missing) of \(polls) USB polls missed the device.",
            measurements: [ctx.measurement("USB availability", Double(polls - missing) / Double(polls) * 100, "%"), ctx.measurement("Drop-outs", Double(missing), "count")],
            evidence: ["Source: IOKit registry re-read every 500 ms", "Source: \(sourceLabel) list devices after the window"],
            limitations: ["Glitches shorter than the polling interval are not observed."],
            recommendedNextAction: missing == 0 ? "No action needed." : "Try another USB-C cable or port.")
    }

    func reconnect(_ ctx: DiagnosticContext) -> DiagnosticTestOutput {
        let timeline = provider.timelineProvider?(ctx.deviceKey) ?? []
        let disconnects = timeline.filter { $0.kind == .disconnect }
        let reconnects = timeline.filter { $0.kind == .reconnect }
        guard let lastDisconnect = disconnects.last else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "Not exercised yet: no disconnect has been observed for this device.",
                                        limitations: ["This test evaluates real events; it never simulates a disconnect on hardware."],
                                        recommendedNextAction: "Unplug the device, wait for “Disconnected”, plug it back in, then run this test again.")
        }
        let recovered = reconnects.contains { $0.at > lastDisconnect.at }
        return DiagnosticTestOutput(
            outcome: recovered ? .passed : .warning,
            summary: recovered ? "Disconnect detected and the device was re-identified after reconnecting." : "Disconnect detected; no reconnect yet.",
            measurements: [ctx.measurement("Disconnects observed", Double(disconnects.count), "count"), ctx.measurement("Reconnects observed", Double(reconnects.count), "count")],
            evidence: timeline.suffix(6).map { "\($0.kind.rawValue) @ \(ISO8601DateFormatter().string(from: $0.at)): \($0.message)" },
            limitations: ["Based on the events recorded during this app session."])
    }

    func information(_ snap: IntelligenceSnapshot) -> DiagnosticTestOutput {
        let available = snap.fields.filter(\.isAvailable)
        let missing = snap.fields.filter { !$0.isAvailable }
        return DiagnosticTestOutput(
            outcome: snap.value("apple.osVersion") != nil ? .passed : .warning,
            summary: "\(available.count) field(s) retrieved, \(missing.count) unavailable.",
            measurements: [DiagnosticMeasurement(name: "Fields retrieved", value: Double(available.count), unit: "count", provenance: snap.provenance),
                           DiagnosticMeasurement(name: "Fields unavailable", value: Double(missing.count), unit: "count", provenance: snap.provenance)],
            evidence: available.map { "\($0.label) [source: \($0.source.description)]" },
            limitations: missing.map { "\($0.label): \($0.unavailableReason ?? "unavailable")" },
            recommendedNextAction: snap.nextAction.kind == .none || snap.nextAction.kind == .runDiagnostics ? "No action needed." : snap.nextAction.title)
    }

    func authorization(_ snap: IntelligenceSnapshot) -> DiagnosticTestOutput {
        let paired = snap.value("apple.pairingState")?.lowercased() == "paired"
        let dev = snap.value("apple.developerMode")?.lowercased()
        let rows = [
            "USB descriptors & interfaces — no authorization needed (satisfied)",
            "Model, OS version, build — needs Trust/pairing (\(paired ? "satisfied" : "NOT satisfied"))",
            "Live response latency — needs pairing (\(paired ? "satisfied" : "NOT satisfied"))",
            "Installed apps list — needs pairing, requested by you (\(paired ? "available on request" : "NOT satisfied"))",
            "Battery & free space — needs pairing + optional libimobiledevice (\(snap.value("battery.level") != nil ? "satisfied" : "not available"))",
            "Developer services (install/debug) — need Developer Mode (\(dev ?? "unknown")); System Tester does not use them"
        ]
        return DiagnosticTestOutput(
            outcome: .passed,
            summary: paired ? "Read-only device information is authorized (paired)." : "Device trust is required before device information can be read.",
            evidence: rows + snap.authorizationEvidence,
            limitations: ["System Tester never bypasses passcodes, pairing, device locks or Activation Lock and never enables Developer Mode."],
            recommendedNextAction: paired ? "No action needed." : snap.nextAction.title)
    }

    func compatibility(_ snap: IntelligenceSnapshot, _ d: DiscoveredDevice) async -> DiagnosticTestOutput {
        let tools = await provider.toolchain()
        var evidence = ["Toolchain: \(tools.summary)"]
        var warnings: [String] = []
        if !tools.hasDevicectl { warnings.append("devicectl unavailable — install/select Xcode 15+.") }
        if let cap = snap.field("apple.usbCapability"), let v = cap.value { evidence.append("Model USB capability: \(v) [source: \(cap.source.tool)]") }
        if let s = d.usb?.speed { evidence.append("Negotiated: \(s.displayName) [source: IOKit]") }
        warnings += snap.limitations.filter { $0.hasPrefix("Connected at") || $0.contains("local network") }
        if snap.value("apple.ddiServices") == "Not mounted" && snap.value("apple.developerMode")?.lowercased() == "enabled" {
            evidence.append("Developer disk image not mounted (normal until a developer service needs it).")
        }
        return DiagnosticTestOutput(
            outcome: warnings.isEmpty ? .passed : .warning,
            summary: warnings.isEmpty ? "Compatible: supported toolchain, link and transport." : "\(warnings.count) compatibility limitation(s).",
            evidence: evidence,
            limitations: warnings,
            recommendedNextAction: warnings.first.map { _ in "Address the listed limitations, then re-run." } ?? "No action needed.")
    }

    func batteryStorage(_ snap: IntelligenceSnapshot) -> DiagnosticTestOutput {
        let keys = ["battery.level", "battery.charging", "apple.storageCapacity", "storage.total", "storage.available"]
        let fields = keys.compactMap { snap.field($0) }
        let available = fields.filter(\.isAvailable)
        var measurements: [DiagnosticMeasurement] = []
        if let v = snap.value("battery.level"), let n = Double(v.replacingOccurrences(of: " %", with: "")) {
            measurements.append(DiagnosticMeasurement(name: "Battery level", value: n, unit: "%", provenance: snap.provenance))
        }
        return DiagnosticTestOutput(
            outcome: available.isEmpty ? .notSupported : .passed,
            summary: available.isEmpty ? "No supported source exposes battery or free-space data for this device." : available.map { "\($0.label): \($0.value!)" }.joined(separator: " · "),
            measurements: measurements,
            evidence: fieldEvidence(snap, keys),
            limitations: fields.filter { !$0.isAvailable }.map { "\($0.label): \($0.unavailableReason ?? "")" } + ["Battery health/cycle count are not exposed by supported interfaces."])
    }
}
