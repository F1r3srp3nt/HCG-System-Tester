import Foundation

// Host-implemented diagnostic operations. All are read-only unless stated.
// Declarative adapters may only reference these by ID (see HostOperationCatalog).

public struct PresenceTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.presence", name: "Connection presence", category: .connectionHealth,
        summary: "Re-reads the device from its discovery backend to confirm it is still enumerated.")
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        var evidence = ["Backend: \(d.source)", "Identifier: \(d.id)"]
        if let loc = d.usb?.locationID { evidence.append("locationID \(Hex.format32(loc)) (port path \(USBTopology.portPath(locationID: loc).map(String.init).joined(separator: "→")))") }
        return DiagnosticTestOutput(
            outcome: .passed, summary: "The device is enumerated by the host.",
            evidence: evidence,
            limitations: ["Proves enumeration only. It does not prove that the device's functions work."])
    }
}

public struct IdentificationTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.identification", name: "Device identification", category: .deviceIdentification,
        summary: "Reports which profile matched, with the descriptor evidence and confidence.")
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        _ = try ctx.requirePresent()
        let id = ctx.identification
        var evidence = id.evidence
        if let usb = ctx.device.usb {
            evidence.append("VID \(usb.vendorIDHex) / PID \(usb.productIDHex)")
            evidence.append("Device class \(usb.usbClass.name)")
        }
        if id.isIdentified {
            return DiagnosticTestOutput(
                outcome: id.confidence >= .medium ? .passed : .warning,
                summary: "Identified as \(id.profileName ?? "?") (\(id.category.displayName)), confidence \(id.confidence.displayName).",
                measurements: [ctx.measurement("Identification score", id.score * 100, "%")],
                evidence: evidence,
                limitations: id.knownLimitations,
                recommendedNextAction: id.confidence >= .medium ? "No action needed." : "Confirm the product manually; only partial evidence matched.")
        }
        return DiagnosticTestOutput(
            outcome: .warning, summary: "No device profile matched. The device is shown with raw descriptors only.",
            evidence: evidence,
            limitations: ["Unknown devices are never assumed to support any function."],
            recommendedNextAction: "Create a device profile in Adapter Developer Studio, or record this device as compatibility evidence.")
    }
}

public struct InterfaceInventoryTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.interfaces", name: "Interface inventory", category: .interfaceAvailability,
        summary: "Lists every USB interface and whether macOS attached a driver to it.",
        requiredCapabilities: [.descriptors])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "Not a USB device.")
        }
        if usb.interfaces.isEmpty {
            return DiagnosticTestOutput(
                outcome: .warning, summary: "The device reported no interfaces.",
                limitations: ["Some devices publish interfaces only after a configuration is selected by a driver."],
                recommendedNextAction: "Re-plug the device; if it persists, the device may be in a low-power or bootloader state.")
        }
        let without = usb.interfaces.filter { !$0.hasDriver }
        let evidence = usb.interfaces.map { i in
            "Interface \(i.number): \(i.functionDescription) [\(DeviceMatchRules.triple(i))] — " +
                (i.hasDriver ? "driver: \(i.attachedServices.joined(separator: ", "))" : "no driver attached")
        }
        return DiagnosticTestOutput(
            outcome: without.isEmpty ? .passed : .warning,
            summary: "\(usb.interfaces.count) interface(s); \(usb.interfaces.count - without.count) with a driver attached.",
            measurements: [ctx.measurement("Interfaces", Double(usb.interfaces.count), "count"),
                           ctx.measurement("Interfaces without driver", Double(without.count), "count")],
            evidence: evidence,
            limitations: ["A missing driver is normal for vendor-specific interfaces that are used by an app rather than a kernel driver."],
            recommendedNextAction: without.isEmpty ? "No action needed." : "Interfaces without a driver can only be used by an adapter that speaks their protocol.")
    }
}

public struct RegistryLatencyTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.registry-latency", name: "Host query latency", category: .communicationLatency,
        summary: "Times 20 consecutive re-reads of the device's registry entry on the host.",
        estimatedDurationSeconds: 0.5)
    public var samples: Int
    public init(samples: Int = 20) { self.samples = samples }

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        var timings: [Double] = []
        for _ in 0..<samples {
            let start = ctx.monotonicSeconds()
            _ = try ctx.requirePresent()
            timings.append((ctx.monotonicSeconds() - start) * 1000)
        }
        let sorted = timings.sorted()
        let mean = timings.reduce(0, +) / Double(max(1, timings.count))
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return DiagnosticTestOutput(
            outcome: .passed,
            summary: String(format: "Mean %.3f ms over %ld host queries.", mean, timings.count),
            measurements: [ctx.measurement("Mean query latency", mean, "ms"),
                           ctx.measurement("Min query latency", sorted.first ?? 0, "ms"),
                           ctx.measurement("p95 query latency", p95, "ms"),
                           ctx.measurement("Max query latency", sorted.last ?? 0, "ms")],
            evidence: ["\(timings.count) samples"],
            limitations: ["Measures host-side registry access, NOT a round trip to the device. Device round-trip latency requires a protocol adapter."])
    }
}

public struct ProtocolValidationTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.protocol-validation", name: "Protocol validation", category: .protocolValidation,
        summary: "Checks that each interface class has the OS service it implies (disk for storage, callout device for serial, driver for HID).",
        requiredCapabilities: [.descriptors])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb else { return DiagnosticTestOutput(outcome: .notSupported, summary: "Not a USB device.") }
        var evidence: [String] = []
        var problems: [String] = []
        let classes = usb.allClassCodes
        if classes.contains(0x08) {
            if usb.bsdNames.isEmpty { problems.append("Mass-storage interface present but no BSD disk was published.") }
            else { evidence.append("Mass storage → BSD disk(s) \(usb.bsdNames.joined(separator: ", "))") }
        }
        let hasSerialInterface = usb.interfaces.contains { $0.classCode == 0x02 && $0.subclassCode == 0x02 }
        if hasSerialInterface {
            if usb.serialDevicePaths.isEmpty { problems.append("CDC ACM interface present but no serial callout device was published.") }
            else { evidence.append("CDC ACM → \(usb.serialDevicePaths.joined(separator: ", "))") }
        } else if !usb.serialDevicePaths.isEmpty {
            evidence.append("Serial callout device(s): \(usb.serialDevicePaths.joined(separator: ", "))")
        }
        for i in usb.interfaces where i.classCode == 0x03 {
            if i.hasDriver { evidence.append("HID interface \(i.number) → \(i.attachedServices.joined(separator: ", "))") }
            else { problems.append("HID interface \(i.number) has no driver attached.") }
        }
        if usb.isHub { evidence.append("Hub class device") }
        if evidence.isEmpty && problems.isEmpty {
            return DiagnosticTestOutput(
                outcome: .notSupported,
                summary: "No interface class with a host-verifiable OS service.",
                evidence: usb.interfaces.map { "Interface \($0.number): \($0.functionDescription)" },
                limitations: ["Vendor-specific protocols can only be validated by a matching adapter."])
        }
        return DiagnosticTestOutput(
            outcome: problems.isEmpty ? .passed : .warning,
            summary: problems.isEmpty ? "Every checked interface has its expected OS service." : "\(problems.count) interface(s) lack their expected OS service.",
            evidence: evidence,
            limitations: ["Validates that the OS bound the protocol; does not exchange data with the device."],
            errors: problems,
            recommendedNextAction: problems.isEmpty ? "No action needed." : "A vendor driver may be required, or the device firmware may be in a non-standard mode. System Tester never installs drivers.")
    }
}

public struct PresenceStabilityTest: DiagnosticTest {
    public let descriptor: DiagnosticTestDescriptor
    public var durationSeconds: Double
    public var intervalSeconds: Double

    public init(extended: Bool = false) {
        durationSeconds = extended ? 60 : 5
        intervalSeconds = extended ? 0.5 : 0.25
        descriptor = DiagnosticTestDescriptor(
            id: extended ? "host.presence-stability-extended" : "host.presence-stability",
            name: extended ? "Connection stability (60 s)" : "Connection stability (5 s)",
            category: .connectionStability, impact: extended ? .extended : .readOnly,
            summary: "Polls the device's presence every \(extended ? "500" : "250") ms for \(extended ? 60 : 5) s and records drop-outs.",
            effects: extended ? "Runs for one minute. Read-only; the device is not touched." : nil,
            estimatedDurationSeconds: extended ? 60 : 5)
    }

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let polls = max(1, Int(durationSeconds / intervalSeconds))
        var missing = 0
        var firstMissIndex: Int?
        for index in 0..<polls {
            if ctx.probe.refresh(ctx.device.id) == nil {
                missing += 1
                if firstMissIndex == nil { firstMissIndex = index }
            }
            try await ctx.sleep(intervalSeconds)
        }
        let availability = Double(polls - missing) / Double(polls) * 100
        if missing == polls { throw DiagnosticError.deviceDisconnected(ctx.device.id) }
        let evidence = ["\(polls) polls at \(Int(intervalSeconds * 1000)) ms"] +
            (firstMissIndex.map { ["First drop-out at poll \($0 + 1) (≈\(String(format: "%.2f", Double($0) * intervalSeconds)) s)"] } ?? [])
        return DiagnosticTestOutput(
            outcome: missing == 0 ? .passed : .failed,
            summary: missing == 0 ? "No drop-outs in \(Int(durationSeconds)) s." : "\(missing) of \(polls) polls found the device missing.",
            measurements: [ctx.measurement("Availability", availability, "%"),
                           ctx.measurement("Drop-outs", Double(missing), "count")],
            evidence: evidence,
            limitations: ["Detects re-enumeration and disconnects visible to the host; very short glitches between polls are not observed."],
            recommendedNextAction: missing == 0 ? "No action needed." : "Try another cable or port, avoid unpowered hubs, and re-run. Record the result as compatibility evidence.")
    }
}

public struct LinkSpeedTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.link-speed", name: "Negotiated link speed", category: .dataTransferPerformance,
        summary: "Compares the negotiated USB link speed with the maximum the device declares (bcdUSB).",
        requiredCapabilities: [.linkSpeed])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb, let speed = usb.speed else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "The host did not report a link speed.")
        }
        var measurements = [ctx.measurement("Negotiated link rate", speed.megabitsPerSecond, "Mbit/s")]
        var evidence = ["Negotiated: \(speed.displayName)"]
        var outcome = DiagnosticOutcome.passed
        var summary = "Running at \(speed.displayName)."
        var next = "No action needed."
        if let max = usb.maximumSupportedSpeed, let bcd = usb.usbSpecification {
            measurements.append(ctx.measurement("Declared maximum link rate", max.megabitsPerSecond, "Mbit/s"))
            evidence.append("Device declares USB \(bcd) (up to \(max.displayName))")
            if speed.rawValue < max.rawValue && max.rawValue >= USBSpeed.superSpeed.rawValue {
                outcome = .warning
                summary = "Running at \(speed.shortName), below the \(max.shortName) the device declares."
                next = "Use a USB 3 / USB-C data cable rated for the speed, connect directly to the Mac (not through a USB 2 hub), and re-test."
            }
        }
        return DiagnosticTestOutput(
            outcome: outcome, summary: summary, measurements: measurements, evidence: evidence,
            limitations: ["This is the negotiated signalling rate, not measured throughput. Throughput testing needs a protocol adapter."],
            recommendedNextAction: next)
    }
}

public struct StorageInfoTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.storage-info", name: "Storage information", category: .storageInformation,
        summary: "Reports the BSD disk(s) and medium size published by macOS. Never reads or writes the medium.",
        requiredCapabilities: [.storageVolume])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb, !usb.bsdNames.isEmpty else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "No storage medium published.")
        }
        var measurements: [DiagnosticMeasurement] = []
        if let size = usb.mediaSizeBytes {
            measurements.append(ctx.measurement("Medium size", Double(size) / 1_000_000_000, "GB"))
        }
        return DiagnosticTestOutput(
            outcome: .passed,
            summary: "Disk(s) \(usb.bsdNames.joined(separator: ", "))" + (usb.mediaSizeBytes.map { String(format: ", %.1f GB", Double($0) / 1e9) } ?? "") + ".",
            measurements: measurements,
            evidence: usb.bsdNames.map { "/dev/\($0)" },
            limitations: ["SMART health data is generally not exposed through USB bridges on macOS.", "File-system contents are never accessed."])
    }
}

public struct FirmwareInfoTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.firmware-info", name: "Firmware information", category: .firmwareInformation,
        summary: "Reports the device release number (bcdDevice) and USB specification (bcdUSB).",
        requiredCapabilities: [.firmwareRevision])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb, let fw = usb.firmwareRevision else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "No device release number reported.")
        }
        var evidence = ["bcdDevice \(fw)"]
        if let spec = usb.usbSpecification { evidence.append("bcdUSB \(spec)") }
        return DiagnosticTestOutput(
            outcome: .passed, summary: "Device release \(fw)" + (usb.usbSpecification.map { ", USB \($0)" } ?? "") + ".",
            evidence: evidence,
            limitations: ["bcdDevice is the vendor's release number; it may not equal the marketing firmware version."])
    }
}

public struct EnumerationErrorReport: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.enumeration-errors", name: "Enumeration error report", category: .errorReporting,
        summary: "Flags missing descriptor strings, unknown classes and other enumeration anomalies.")
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let usb = d.usb else { return DiagnosticTestOutput(outcome: .notSupported, summary: "Not a USB device.") }
        var findings: [String] = []
        if usb.vendorID == nil || usb.productID == nil { findings.append("Vendor or product ID missing.") }
        if usb.productName == nil { findings.append("No product string descriptor.") }
        if usb.vendorName == nil { findings.append("No manufacturer string descriptor.") }
        if usb.speed == nil { findings.append("Link speed not reported.") }
        if usb.vendorID == 0 && usb.productID == 0 { findings.append("VID/PID 0000:0000 — typical of a failed enumeration.") }
        if case .other = usb.usbClass { findings.append("Device class \(Hex.format8(usb.deviceClass ?? 0)) is not a USB-IF assigned class.") }
        let serious = findings.contains { $0.contains("missing") || $0.contains("failed") }
        return DiagnosticTestOutput(
            outcome: findings.isEmpty ? .passed : (serious ? .failed : .warning),
            summary: findings.isEmpty ? "No enumeration anomalies found." : "\(findings.count) anomaly(ies) found.",
            measurements: [ctx.measurement("Anomalies", Double(findings.count), "count")],
            evidence: findings.isEmpty ? ["All standard descriptor fields present"] : findings,
            limitations: ["Missing optional strings are common on inexpensive devices and are not faults by themselves."],
            recommendedNextAction: serious ? "Re-plug the device, try another cable, and check whether it is in a bootloader mode." : "No action needed.")
    }
}

public struct ThunderboltSwitchTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "host.thunderbolt-switch", name: "Thunderbolt switch information", category: .interfaceAvailability,
        summary: "Reports the Thunderbolt / USB4 switch vendor, model and route.",
        requiredCapabilities: [.thunderboltSwitch])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        guard let tb = d.thunderbolt else { return DiagnosticTestOutput(outcome: .notSupported, summary: "Not a Thunderbolt device.") }
        var evidence: [String] = []
        if let v = tb.vendorName { evidence.append("Vendor: \(v)") }
        if let m = tb.modelName { evidence.append("Model: \(m)") }
        if let r = tb.routeString { evidence.append("Route string: 0x" + String(r, radix: 16)) }
        if let depth = tb.depth { evidence.append("Depth: \(depth)") }
        if let c = tb.ioClassName { evidence.append("IOKit class: \(c)") }
        return DiagnosticTestOutput(outcome: .passed, summary: "Thunderbolt switch enumerated.", evidence: evidence,
                                    limitations: ["Tunnelled PCIe / DisplayPort / USB devices behind the switch are not inspected."])
    }
}

public struct ConsoleInterfaceResearchTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "research.console-interfaces", name: "Console interface research", category: .deviceSpecific,
        summary: "Explains which interfaces a console-family device actually exposes on this connection, and what is not reachable.",
        categories: [.playStation, .xbox, .nintendo])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        let d = try ctx.requirePresent()
        let exposed = d.usb?.interfaces.map { "Interface \($0.number): \($0.functionDescription)" } ?? []
        return DiagnosticTestOutput(
            outcome: .passed,
            summary: "Observed \(exposed.count) USB interface(s) on this \(ctx.identification.category.displayName) device.",
            evidence: exposed + ["Profile: \(ctx.identification.profileName ?? "none")"],
            limitations: [
                "Consumer consoles act as USB hosts and expose no USB diagnostic device interface to a computer.",
                "Console network services require the console owner's authorisation and documented APIs; none are accessed here.",
                "System Tester does not bypass console authentication, DRM or firmware protections."
            ],
            recommendedNextAction: "Record this as compatibility evidence. For console network diagnostics, a documented, authorised network adapter is required.")
    }
}

/// A state-changing operation that exists only for synthetic fixtures. It demonstrates and
/// tests the authorisation gate without ever touching real hardware.
public struct SyntheticFaultInjectionTest: DiagnosticTest {
    public let descriptor = DiagnosticTestDescriptor(
        id: "synthetic.fault-injection", name: "Synthetic disconnect injection", category: .connectionStability,
        impact: .stateChanging,
        summary: "Asks a synthetic fixture to simulate a disconnect and reconnect, then verifies detection.",
        effects: "Changes the synthetic fixture's simulated state. Never applies to real hardware.",
        requiredCapabilities: [.syntheticChannel])
    public init() {}

    public func run(_ ctx: DiagnosticContext) async throws -> DiagnosticTestOutput {
        guard ctx.device.provenance == .synthetic, let fixture = ctx.probe as? SyntheticFaultInjectable else {
            return DiagnosticTestOutput(outcome: .notSupported, summary: "Only synthetic fixtures support fault injection.")
        }
        fixture.injectDisconnect(ctx.device.id)
        let detected = ctx.probe.refresh(ctx.device.id) == nil
        fixture.restore(ctx.device.id)
        let recovered = ctx.probe.refresh(ctx.device.id) != nil
        return DiagnosticTestOutput(
            outcome: detected && recovered ? .passed : .failed,
            summary: detected && recovered ? "Disconnect detected and recovery confirmed." : "Fault injection was not observed correctly.",
            measurements: [ctx.measurement("Disconnect detected", detected ? 1 : 0, "bool"),
                           ctx.measurement("Recovered", recovered ? 1 : 0, "bool")],
            evidence: ["SYNTHETIC fixture"],
            limitations: ["Synthetic data — not a property of any real device."])
    }
}

/// Implemented by synthetic probes that can simulate faults.
public protocol SyntheticFaultInjectable: AnyObject {
    func injectDisconnect(_ id: DeviceIdentifier)
    func restore(_ id: DeviceIdentifier)
}
