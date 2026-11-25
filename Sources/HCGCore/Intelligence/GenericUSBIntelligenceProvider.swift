import Foundation

/// Fallback provider for every device without a dedicated family adapter. It reports only what
/// IOKit and the host-side checks can verify, and says so.
public final class GenericUSBIntelligenceProvider: DeviceIntelligenceProvider {
    public let providerID = "com.hakmicapitalgroup.adapter.usb-core"
    public let familyName = "Generic USB / Thunderbolt"
    public let supportedProtocols = ["usb.descriptor", "thunderbolt.registry"]
    public let interfaceExtensions: [String] = []

    public init() {}

    public func recognizes(_ device: DiscoveredDevice, identification: IdentificationResult) -> Bool { true }

    public func snapshot(for device: DiscoveredDevice, identification: IdentificationResult) async -> IntelligenceSnapshot {
        let p = device.provenance
        let io: (String) -> FieldSource = { FieldSource(tool: p == .synthetic ? "SYNTHETIC fixture" : "IOKit", key: $0, provenance: p) }
        var fields: [IntelligenceField] = []
        var evidence: [IntelligenceState: String] = [:]
        if device.isPresent { evidence[.physicalDeviceDetected] = "\(device.source) reported the device." }
        if let usb = device.usb {
            if usb.vendorID != nil { evidence[.usbEnumerated] = "Descriptors read: \(usb.vendorIDHex):\(usb.productIDHex)." }
            fields += [
                IntelligenceField(key: "usb.manufacturer", label: "Manufacturer", group: .overview, value: usb.vendorName ?? USBVendorDatabase.name(for: usb.vendorID), source: io("USB Vendor Name")),
                IntelligenceField(key: "usb.productName", label: "Product", group: .overview, value: usb.productName, source: io("USB Product Name")),
                IntelligenceField(key: "usb.vendorID", label: "USB vendor ID", group: .hardware, value: usb.vendorIDHex, source: io("idVendor")),
                IntelligenceField(key: "usb.productID", label: "USB product ID", group: .hardware, value: usb.productIDHex, source: io("idProduct")),
                IntelligenceField(key: "usb.speed", label: "Connection speed", group: .connection, value: usb.speed?.displayName, source: io("Device Speed")),
                IntelligenceField(key: "usb.bcdDevice", label: "Device release", group: .software, value: usb.firmwareRevision, source: io("bcdDevice")),
                IntelligenceField(key: "usb.serialNumber", label: "USB serial number", group: .hardware, value: usb.serialNumber, source: io("USB Serial Number"), sensitive: true)
            ]
            if usb.interfaces.contains(where: \.hasDriver) || !usb.bsdNames.isEmpty || !usb.serialDevicePaths.isEmpty {
                evidence[.protocolDiscovered] = "macOS bound a driver to the device."
            }
        }
        if let tb = device.thunderbolt {
            evidence[.usbEnumerated] = "Thunderbolt switch registered."
            fields.append(IntelligenceField(key: "tb.model", label: "Model", group: .overview, value: [tb.vendorName, tb.modelName].compactMap { $0 }.joined(separator: " "), source: io("Device Model Name")))
        }
        if identification.isIdentified { evidence[.familyIdentified] = "Profile \(identification.profileName ?? "")." }
        let ladder = IntelligenceSnapshot.ladder(reaching: evidence)
        let highest = ladder.last(where: \.reached)?.state ?? .waitingForDevice
        let state: IntelligenceState = !device.isPresent ? .disconnected : (identification.isIdentified || evidence[.usbEnumerated] != nil ? highest : .unsupported)
        return IntelligenceSnapshot(
            deviceID: device.id, providerID: providerID, family: identification.family, state: state,
            stateReason: device.isPresent ? "Host-side information only. No device-family adapter communicates with this device yet." : "Disconnected.",
            nextAction: NextAction(kind: device.isPresent ? .runDiagnostics : .reconnect, title: device.isPresent ? "Run read-only host diagnostics" : "Reconnect the device"),
            ladder: ladder, fields: fields,
            limitations: ["Generic adapter: identification and host-side checks only."], provenance: p)
    }

    public func perform(_ action: NextActionKind, for device: DiscoveredDevice, identification: IdentificationResult) async -> ActionOutcome {
        .notPerformable("No device-family adapter for this device.")
    }

    public func diagnosticTests() -> [DiagnosticTest] { [] }
}
