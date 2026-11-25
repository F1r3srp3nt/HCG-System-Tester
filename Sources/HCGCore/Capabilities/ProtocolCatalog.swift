import Foundation

/// A protocol that HCG System Tester knows about, with an honest support status.
public struct ProtocolDescriptor: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var connectionTypes: [ConnectionType]
    public var support: SupportLevel
    public var summary: String

    public init(id: String, name: String, connectionTypes: [ConnectionType], support: SupportLevel, summary: String) {
        self.id = id
        self.name = name
        self.connectionTypes = connectionTypes
        self.support = support
        self.summary = summary
    }
}

public enum SupportLevel: String, Codable, CaseIterable, Hashable, Comparable {
    /// Implemented and exercised against real hardware discovery.
    case live
    /// Partially implemented (e.g. presence detection without communication).
    case partial
    /// Designed in the SDK; no implementation yet.
    case planned
    /// Requires a hardware or software adapter that is not part of System Tester.
    case requiresAdapter
    /// Not possible on this platform or not offered by the device.
    case unavailable

    public var displayName: String {
        switch self {
        case .live: return "Live"
        case .partial: return "Partial"
        case .planned: return "Planned"
        case .requiresAdapter: return "Adapter required"
        case .unavailable: return "Unavailable"
        }
    }

    private var rank: Int {
        switch self { case .live: return 4; case .partial: return 3; case .planned: return 2; case .requiresAdapter: return 1; case .unavailable: return 0 }
    }

    public static func < (lhs: SupportLevel, rhs: SupportLevel) -> Bool { lhs.rank < rhs.rank }
}

public enum ProtocolCatalog {
    public static let all: [ProtocolDescriptor] = [
        ProtocolDescriptor(id: "usb.descriptor", name: "USB descriptors (IORegistry)", connectionTypes: [.usb], support: .live,
                           summary: "Read-only device, configuration and interface descriptors as published by macOS."),
        ProtocolDescriptor(id: "usb.hub", name: "USB hub topology", connectionTypes: [.usb], support: .live,
                           summary: "Hub/port topology derived from locationID."),
        ProtocolDescriptor(id: "usb.msc", name: "USB Mass Storage", connectionTypes: [.usb], support: .partial,
                           summary: "Detects the BSD disk the storage stack publishes and its size. No reads or writes to the medium."),
        ProtocolDescriptor(id: "usb.cdc-acm", name: "USB CDC ACM serial", connectionTypes: [.usb, .usbSerial], support: .partial,
                           summary: "Detects the serial callout device (/dev/cu.*). Opening the port is a planned, user-authorised operation."),
        ProtocolDescriptor(id: "usb.vendor-serial", name: "Vendor USB-serial bridge", connectionTypes: [.usb, .usbSerial], support: .partial,
                           summary: "Detects the serial callout device when the macOS (or vendor) driver is loaded."),
        ProtocolDescriptor(id: "usb.hid", name: "USB HID", connectionTypes: [.usb, .hid], support: .partial,
                           summary: "Interface presence and driver attachment. Input reports are never captured."),
        ProtocolDescriptor(id: "usb.audio", name: "USB Audio Class", connectionTypes: [.usb], support: .partial,
                           summary: "Interface presence only."),
        ProtocolDescriptor(id: "usb.uvc", name: "USB Video Class", connectionTypes: [.usb], support: .partial,
                           summary: "Interface presence only. Camera streams are never opened."),
        ProtocolDescriptor(id: "usb.ptp", name: "PTP / MTP", connectionTypes: [.usb], support: .requiresAdapter,
                           summary: "Still-image / media transfer. macOS has no built-in MTP client."),
        ProtocolDescriptor(id: "usb.cdc-ncm", name: "USB networking (ECM/NCM)", connectionTypes: [.usb, .ethernet], support: .partial,
                           summary: "Interface presence only. Network diagnostics are a planned module."),
        ProtocolDescriptor(id: "usb.vendor-gip", name: "Xbox Game Input Protocol", connectionTypes: [.usb], support: .unavailable,
                           summary: "Vendor-specific controller protocol. Descriptor-level identification only."),
        ProtocolDescriptor(id: "apple.usbmux", name: "Apple usbmux", connectionTypes: [.usb], support: .partial,
                           summary: "Device-services multiplexer. Used through Xcode CoreDevice (devicectl) and optional libimobiledevice after the device trusts this Mac."),
        ProtocolDescriptor(id: "apple.coredevice", name: "Apple CoreDevice (xcrun devicectl)", connectionTypes: [.usb, .localNetwork], support: .live,
                           summary: "Structured device, OS, pairing and service information via Xcode's devicectl (JSON). Requires Xcode 15+ and pairing for live data."),
        ProtocolDescriptor(id: "apple.lockdown", name: "Apple lockdown (libimobiledevice, optional)", connectionTypes: [.usb], support: .partial,
                           summary: "Battery and disk-usage domains via user-installed libimobiledevice after pairing. Never bundled or installed by System Tester."),
        ProtocolDescriptor(id: "android.adb", name: "Android Debug Bridge", connectionTypes: [.usb, .localNetwork], support: .requiresAdapter,
                           summary: "Requires adb and per-device RSA key approval on the phone."),
        ProtocolDescriptor(id: "thunderbolt.registry", name: "Thunderbolt switch registry", connectionTypes: [.thunderbolt], support: .live,
                           summary: "Read-only Thunderbolt / USB4 switch properties published by macOS."),
        ProtocolDescriptor(id: "network.mdns", name: "DNS-SD / Bonjour", connectionTypes: [.localNetwork, .ethernet], support: .planned,
                           summary: "Local-network service discovery (requires Local Network permission)."),
        ProtocolDescriptor(id: "network.reachability", name: "Network reachability", connectionTypes: [.localNetwork, .ethernet], support: .planned,
                           summary: "Path and latency checks to user-specified hosts."),
        ProtocolDescriptor(id: "bluetooth.le", name: "Bluetooth Low Energy", connectionTypes: [.bluetooth], support: .planned,
                           summary: "Advertisement discovery via Core Bluetooth (requires Bluetooth permission)."),
        ProtocolDescriptor(id: "matter", name: "Matter", connectionTypes: [.localNetwork], support: .planned,
                           summary: "Smart-home devices through the platform's Matter support."),
        ProtocolDescriptor(id: "homekit", name: "HomeKit", connectionTypes: [.localNetwork], support: .unavailable,
                           summary: "The HomeKit framework is not available to macOS apps outside Mac Catalyst."),
        ProtocolDescriptor(id: "mqtt", name: "MQTT", connectionTypes: [.localNetwork, .remoteAuthenticated], support: .planned,
                           summary: "Read-only subscription to an authorised broker."),
        ProtocolDescriptor(id: "manufacturer.api", name: "Documented manufacturer APIs", connectionTypes: [.manufacturerAPI], support: .requiresAdapter,
                           summary: "Per-manufacturer adapters using documented, authorised APIs only."),
        ProtocolDescriptor(id: "hcg.devicelink", name: "HCG Device Link (hcg.devicelink/1)", connectionTypes: [.remoteAuthenticated], support: .planned,
                           summary: "Paired, signed HCG Server link for sharing hcg.diagnostic-report/1 results."),
        ProtocolDescriptor(id: "synthetic.fixture", name: "Synthetic fixture protocol", connectionTypes: [.synthetic], support: .live,
                           summary: "Simulated device behaviour for testing. Never represents real hardware.")
    ]

    public static func descriptor(_ id: String) -> ProtocolDescriptor? { all.first { $0.id == id } }

    public static var knownIDs: Set<String> { Set(all.map(\.id)) }

    /// Protocols directly evidenced by interface descriptors.
    public static func protocols(evidencedBy device: DiscoveredDevice) -> [String] {
        if device.provenance == .synthetic { return ["synthetic.fixture"] }
        guard let usb = device.usb else {
            return device.connectionType == .thunderbolt ? ["thunderbolt.registry"] : []
        }
        var out: [String] = ["usb.descriptor"]
        func add(_ p: String) { if !out.contains(p) { out.append(p) } }
        if usb.isHub { add("usb.hub") }
        for i in usb.interfaces {
            switch (i.classCode, i.subclassCode, i.protocolCode) {
            case (0x08, _, _): add("usb.msc")
            case (0x02, 0x02, _): add("usb.cdc-acm")
            case (0x02, 0x06, _), (0x02, 0x0D, _): add("usb.cdc-ncm")
            case (0x03, _, _): add("usb.hid")
            case (0x01, _, _): add("usb.audio")
            case (0x0E, _, _): add("usb.uvc")
            case (0x06, _, _): add("usb.ptp")
            case (0xFF, 0x42, 0x01): add("android.adb")
            case (0xFF, 0x47, 0xD0), (0xFF, 0x5D, 0x01): add("usb.vendor-gip")
            case (0xFF, 0xFE, 0x02): add("apple.usbmux"); add("apple.coredevice")
            default: break
            }
        }
        if !usb.serialDevicePaths.isEmpty && !out.contains("usb.cdc-acm") { add("usb.vendor-serial") }
        return out
    }
}
