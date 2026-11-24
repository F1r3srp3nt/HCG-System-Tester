import Foundation

/// Per-connection-type implementation status, shown in the Command Center and
/// used to explain *why* a connection is unavailable or limited.
public struct ConnectionCapability: Codable, Hashable, Identifiable {
    public var connectionType: ConnectionType
    public var support: SupportLevel
    public var discoveryMethod: String
    public var verifiableLayers: [ConnectivityLayer]
    public var requiredPermissions: [String]
    public var limitations: [String]

    public var id: ConnectionType { connectionType }
}

public enum ConnectionCapabilityRegistry {
    public static let macOS: [ConnectionCapability] = [
        ConnectionCapability(
            connectionType: .usb, support: .live,
            discoveryMethod: "IOKit matching notifications on IOUSBHostDevice (first-match + terminated)",
            verifiableLayers: [.physical, .enumeration, .protocolCompatibility],
            requiredPermissions: [],
            limitations: [
                "Devices that only negotiate USB Power Delivery (charge-only cables or host-to-host links) never enumerate and cannot be seen.",
                "A USB-C cable without data lines produces no discovery event at all."
            ]),
        ConnectionCapability(
            connectionType: .usbSerial, support: .partial,
            discoveryMethod: "IOSerialBSDClient callout paths beneath the USB device",
            verifiableLayers: [.physical, .enumeration, .protocolCompatibility],
            requiredPermissions: [],
            limitations: ["Opening a serial port (functional communication) is planned and will require per-device authorisation."]),
        ConnectionCapability(
            connectionType: .hid, support: .partial,
            discoveryMethod: "HID interfaces of enumerated USB devices",
            verifiableLayers: [.physical, .enumeration, .protocolCompatibility],
            requiredPermissions: [],
            limitations: ["Input reports are never captured; Input Monitoring permission is not requested."]),
        ConnectionCapability(
            connectionType: .thunderbolt, support: .partial,
            discoveryMethod: "IOKit IOThunderboltSwitch registry entries (depth > 0)",
            verifiableLayers: [.physical, .enumeration],
            requiredPermissions: [],
            limitations: ["Switch-level information only; tunnelled PCIe/DisplayPort devices are not inspected."]),
        ConnectionCapability(
            connectionType: .ethernet, support: .planned,
            discoveryMethod: "Network framework path monitoring",
            verifiableLayers: [],
            requiredPermissions: ["Local Network"],
            limitations: ["Not implemented in 0.1.0."]),
        ConnectionCapability(
            connectionType: .bluetooth, support: .planned,
            discoveryMethod: "Core Bluetooth scanning",
            verifiableLayers: [],
            requiredPermissions: ["Bluetooth"],
            limitations: ["Not implemented in 0.1.0."]),
        ConnectionCapability(
            connectionType: .localNetwork, support: .planned,
            discoveryMethod: "DNS-SD / Bonjour browsing for documented service types",
            verifiableLayers: [],
            requiredPermissions: ["Local Network"],
            limitations: ["Not implemented in 0.1.0."]),
        ConnectionCapability(
            connectionType: .remoteAuthenticated, support: .planned,
            discoveryMethod: "HCG Device Link (hcg.devicelink/1) after pairing with an authorised HCG Server",
            verifiableLayers: [],
            requiredPermissions: ["HCG Connect sign-in", "Device Link pairing"],
            limitations: ["No HCG Connect client is registered for System Tester yet; remote features are disabled."]),
        ConnectionCapability(
            connectionType: .manufacturerAPI, support: .requiresAdapter,
            discoveryMethod: "Per-manufacturer adapters",
            verifiableLayers: [],
            requiredPermissions: ["Per-adapter, explicit"],
            limitations: ["No manufacturer adapters ship in 0.1.0."]),
        ConnectionCapability(
            connectionType: .synthetic, support: .live,
            discoveryMethod: "Synthetic fixture backend (opt-in, always labelled)",
            verifiableLayers: ConnectivityLayer.allCases,
            requiredPermissions: [],
            limitations: ["Synthetic data never represents real hardware."])
    ]

    public static func capability(for type: ConnectionType) -> ConnectionCapability? {
        macOS.first { $0.connectionType == type }
    }
}

/// Fine-grained capabilities a device offers to diagnostics (derived from evidence).
public enum DeviceCapability: String, Codable, CaseIterable, Hashable {
    case presence
    case descriptors
    case interfaceList
    case linkSpeed
    case firmwareRevision
    case storageVolume
    case serialPort
    case hidInterface
    case topology
    case thunderboltSwitch
    case syntheticChannel

    public var displayName: String {
        switch self {
        case .presence: return "Presence"
        case .descriptors: return "Descriptors"
        case .interfaceList: return "Interface list"
        case .linkSpeed: return "Link speed"
        case .firmwareRevision: return "Firmware revision"
        case .storageVolume: return "Storage volume"
        case .serialPort: return "Serial port"
        case .hidInterface: return "HID interface"
        case .topology: return "Topology"
        case .thunderboltSwitch: return "Thunderbolt switch"
        case .syntheticChannel: return "Synthetic channel"
        }
    }

    public static func derive(for device: DiscoveredDevice) -> Set<DeviceCapability> {
        var caps: Set<DeviceCapability> = [.presence]
        if device.provenance == .synthetic { caps.insert(.syntheticChannel) }
        if let usb = device.usb {
            if usb.vendorID != nil || usb.productID != nil { caps.insert(.descriptors) }
            if !usb.interfaces.isEmpty { caps.insert(.interfaceList) }
            if usb.speed != nil { caps.insert(.linkSpeed) }
            if usb.bcdDevice != nil { caps.insert(.firmwareRevision) }
            if !usb.bsdNames.isEmpty { caps.insert(.storageVolume) }
            if !usb.serialDevicePaths.isEmpty { caps.insert(.serialPort) }
            if usb.interfaces.contains(where: { $0.classCode == 0x03 }) { caps.insert(.hidInterface) }
            if usb.locationID != nil { caps.insert(.topology) }
        }
        if device.thunderbolt != nil { caps.insert(.thunderboltSwitch) }
        return caps
    }
}
