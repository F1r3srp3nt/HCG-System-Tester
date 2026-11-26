import Foundation

/// How far HCG has validated a protocol adapter.
public enum ValidationStatus: String, Codable, CaseIterable, Hashable {
    case researchOnly
    case planned
    case implementedUnverified
    case verifiedOnHardware
    case delegated
    case prohibited

    public var displayName: String {
        switch self {
        case .researchOnly: return "Research only"
        case .planned: return "Planned"
        case .implementedUnverified: return "Implemented — awaiting physical verification"
        case .verifiedOnHardware: return "Verified on hardware"
        case .delegated: return "Delegated to another HCG product"
        case .prohibited: return "Prohibited"
        }
    }
}

/// A communication protocol / transport with its adapter declaration.
/// Discovery and active communication are declared and validated separately.
public struct ConnectivityProtocol: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var layer: String
    public var summary: String
    /// Passive or user-started discovery support.
    public var discovery: SupportLevel
    /// Active (read-only) communication support.
    public var communication: SupportLevel
    public var adapterID: String?
    public var capabilities: [String]
    public var dependencies: [String]
    public var permissions: [String]
    public var supportedCategories: [ConnectivityCategory]
    public var validation: ValidationStatus
    public var safetyNotes: [String]
    /// Another HCG product that owns this capability (no duplication).
    public var owner: String?
    public var references: [DocumentationReference]

    public init(id: String, name: String, layer: String, summary: String, discovery: SupportLevel, communication: SupportLevel,
                adapterID: String? = nil, capabilities: [String] = [], dependencies: [String] = [], permissions: [String] = [],
                supportedCategories: [ConnectivityCategory] = [], validation: ValidationStatus, safetyNotes: [String] = [],
                owner: String? = nil, references: [DocumentationReference] = []) {
        self.id = id
        self.name = name
        self.layer = layer
        self.summary = summary
        self.discovery = discovery
        self.communication = communication
        self.adapterID = adapterID
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.permissions = permissions
        self.supportedCategories = supportedCategories
        self.validation = validation
        self.safetyNotes = safetyNotes
        self.owner = owner
        self.references = references
    }

    public var isImplemented: Bool { validation == .implementedUnverified || validation == .verifiedOnHardware }
}

public enum UniversalProtocolRegistry {
    static func ref(_ id: String, _ title: String, _ publisher: String, _ url: String) -> DocumentationReference {
        DocumentationReference(id: id, title: title, publisher: publisher, url: url)
    }

    public static let all: [ConnectivityProtocol] = [
        ConnectivityProtocol(id: "usb", name: "USB", layer: "Physical / link", summary: "IOKit enumeration of USB devices, interfaces, drivers and link speed.",
                             discovery: .live, communication: .partial, adapterID: "com.hakmicapitalgroup.adapter.usb-core",
                             capabilities: ["enumerate", "descriptors", "interfaces", "link speed", "host diagnostics"], dependencies: ["cable.usbc-data"],
                             supportedCategories: ConnectivityCategory.allCases, validation: .verifiedOnHardware,
                             safetyNotes: ["No USB control requests are sent to devices."]),
        ConnectivityProtocol(id: "thunderbolt", name: "Thunderbolt / USB4", layer: "Physical / link", summary: "IOThunderboltSwitch registry discovery.",
                             discovery: .live, communication: .unavailable, adapterID: "com.hakmicapitalgroup.adapter.thunderbolt",
                             capabilities: ["enumerate switches"], dependencies: ["cable.thunderbolt"], supportedCategories: [.storageDevice, .desktopComputer, .laptop],
                             validation: .implementedUnverified),
        ConnectivityProtocol(id: "apple.coredevice", name: "Apple CoreDevice (devicectl)", layer: "Application", summary: "Structured iPhone/iPad information through Xcode.",
                             discovery: .live, communication: .live, adapterID: AppleDeviceIntelligenceProvider.adapterID,
                             capabilities: ["identify", "OS & build", "pairing state", "services", "latency"], dependencies: ["software.xcode", "cable.usbc-data"],
                             permissions: ["Device Trust (pairing)"], supportedCategories: [.smartphone, .tablet], validation: .implementedUnverified),
        ConnectivityProtocol(id: "bluetooth.le", name: "Bluetooth Low Energy (GATT)", layer: "Wireless", summary: "Advertisement scanning; on approval, connect and read Device Information and Battery characteristics.",
                             discovery: .live, communication: .partial, adapterID: "com.hakmicapitalgroup.adapter.ble-gatt",
                             capabilities: ["scan advertisements", "read Device Information (0x180A)", "read Battery Level (0x180F)"],
                             dependencies: ["interface.bluetooth"], permissions: ["macOS Bluetooth permission"],
                             supportedCategories: [.sensor, .wearable, .iot, .smartHome, .microcontroller, .vehicle],
                             validation: .implementedUnverified, safetyNotes: ["Characteristics are never written."]),
        ConnectivityProtocol(id: "bluetooth.classic", name: "Bluetooth Classic", layer: "Wireless", summary: "Lists devices already paired with this Mac (read-only). Pairing stays in System Settings.",
                             discovery: .partial, communication: .unavailable, capabilities: ["list paired devices"], dependencies: ["interface.bluetooth"],
                             permissions: ["macOS Bluetooth permission"], supportedCategories: [.gamingConsole, .wearable, .smartphone],
                             validation: .implementedUnverified),
        ConnectivityProtocol(id: "network.mdns", name: "Wi-Fi / LAN — DNS-SD (Bonjour)", layer: "Network", summary: "Browses documented service types on the local network.",
                             discovery: .live, communication: .partial, adapterID: "com.hakmicapitalgroup.adapter.bonjour",
                             capabilities: ["browse services", "resolve TXT records"], dependencies: ["interface.wifi-or-ethernet"],
                             permissions: ["macOS Local Network permission"], supportedCategories: ConnectivityCategory.allCases,
                             validation: .implementedUnverified, safetyNotes: ["Browsing and TXT resolution only; no connection is opened to the service."]),
        ConnectivityProtocol(id: "network.ssdp", name: "Wi-Fi / LAN — SSDP / UPnP / DIAL", layer: "Network", summary: "On request, sends one standard M-SEARCH and reads UPnP device descriptions.",
                             discovery: .live, communication: .partial, adapterID: "com.hakmicapitalgroup.adapter.ssdp",
                             capabilities: ["M-SEARCH", "device description (manufacturer, model)"], dependencies: ["interface.wifi-or-ethernet"],
                             permissions: ["macOS Local Network permission"], supportedCategories: [.smartTelevision, .networkEquipment, .gamingConsole, .smartHome],
                             validation: .implementedUnverified),
        ConnectivityProtocol(id: "wifi", name: "Wi-Fi", layer: "Wireless", summary: "Host Wi-Fi interface status; devices are reached through Bonjour/SSDP/manufacturer APIs.",
                             discovery: .partial, communication: .unavailable, dependencies: ["interface.wifi-or-ethernet"],
                             supportedCategories: ConnectivityCategory.allCases, validation: .implementedUnverified,
                             safetyNotes: ["Host interface status only; System Tester never joins or scans other networks."]),
        ConnectivityProtocol(id: "ethernet", name: "Ethernet", layer: "Physical / link", summary: "Host interface link status; LAN discovery through Bonjour/SSDP.",
                             discovery: .partial, communication: .unavailable, dependencies: ["interface.wifi-or-ethernet"],
                             supportedCategories: [.server, .desktopComputer, .industrialMachinery, .robot, .roboticArm, .networkEquipment],
                             validation: .implementedUnverified, safetyNotes: ["Host interface status only; no traffic is sent to machines."]),
        ConnectivityProtocol(id: "nfc", name: "NFC", layer: "Wireless", summary: "Macs have no NFC radio. Needs a USB PC/SC reader.",
                             discovery: .requiresAdapter, communication: .requiresAdapter, dependencies: ["reader.nfc"], supportedCategories: [.wearable, .iot],
                             validation: .planned, safetyNotes: ["Payment and identity cards are never read."]),
        ConnectivityProtocol(id: "serial", name: "Serial (USB CDC / bridges)", layer: "Link", summary: "Callout devices are discovered; opening ports is planned behind per-device authorisation.",
                             discovery: .live, communication: .planned, adapterID: "com.hakmicapitalgroup.adapter.usb-serial",
                             dependencies: ["cable.usbc-data"], supportedCategories: [.microcontroller, .singleBoardComputer, .laboratoryInstrument, .robot],
                             validation: .implementedUnverified, safetyNotes: ["Nothing is sent to a port without explicit authorisation."]),
        ConnectivityProtocol(id: "uart", name: "UART (logic level)", layer: "Link", summary: "Board-level serial at 3.3 V or 5 V through a USB-to-UART adapter.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["adapter.usb-ttl-3v3"],
                             supportedCategories: [.microcontroller, .singleBoardComputer, .robot], validation: .planned,
                             safetyNotes: ["Voltage mismatch damages hardware: confirm 3.3 V vs 5 V before wiring."]),
        ConnectivityProtocol(id: "can", name: "CAN bus", layer: "Fieldbus", summary: "Needs a USB-CAN interface with a macOS driver; listen-only first.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["interface.usb-can"],
                             supportedCategories: [.vehicle, .motorcycle, .agriculturalMachinery, .constructionEquipment, .industrialMachinery, .robot],
                             validation: .planned, safetyNotes: ["Listen-only mode. Transmitting on a vehicle or machine bus is prohibited."]),
        ConnectivityProtocol(id: "obd2", name: "OBD-II (SAE J1979 / ISO 15765-4)", layer: "Vehicle diagnostics", summary: "Read-only PIDs, stored DTCs and VIN through an OBD-II interface.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["interface.obd2"],
                             supportedCategories: [.vehicle, .motorcycle], validation: .planned,
                             safetyNotes: ["Read-only modes 01/03/09 only.", "Clearing codes (mode 04), actuator tests, coding and flashing are prohibited."]),
        ConnectivityProtocol(id: "j1939", name: "SAE J1939", layer: "Fieldbus", summary: "Heavy-equipment CAN protocol (250/500 kbit/s); listen-only PGN decoding.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["interface.usb-can", "cable.j1939-deutsch9"],
                             supportedCategories: [.agriculturalMachinery, .constructionEquipment, .vehicle], validation: .planned,
                             safetyNotes: ["Listen-only. No requests, no commands."]),
        ConnectivityProtocol(id: "isobus", name: "ISOBUS (ISO 11783)", layer: "Fieldbus", summary: "Tractor–implement network; listen-only observation.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["interface.usb-can", "cable.isobus"],
                             supportedCategories: [.agriculturalMachinery], validation: .researchOnly,
                             safetyNotes: ["Never participate in address claim or control implements."]),
        ConnectivityProtocol(id: "modbus", name: "Modbus TCP / RTU", layer: "Industrial", summary: "Read-only register reads from authorised devices.",
                             discovery: .unavailable, communication: .planned, dependencies: ["interface.wifi-or-ethernet"],
                             supportedCategories: [.industrialMachinery, .roboticArm, .laboratoryInstrument], validation: .planned,
                             safetyNotes: ["Function codes 01–04 only; writes (05/06/15/16) are prohibited."]),
        ConnectivityProtocol(id: "opcua", name: "OPC UA", layer: "Industrial", summary: "Browse and read nodes on authorised servers.",
                             discovery: .planned, communication: .planned, dependencies: ["interface.wifi-or-ethernet"],
                             permissions: ["Server credentials / certificates"], supportedCategories: [.industrialMachinery, .roboticArm, .laboratoryInstrument],
                             validation: .planned, safetyNotes: ["Read and subscribe only; method calls and writes are prohibited."]),
        ConnectivityProtocol(id: "mqtt", name: "MQTT", layer: "Messaging", summary: "Subscribe-only to an authorised broker.",
                             discovery: .partial, communication: .planned, dependencies: ["interface.wifi-or-ethernet"],
                             permissions: ["Broker credentials"], supportedCategories: [.iot, .smartHome, .industrialMachinery, .sensor], validation: .planned,
                             safetyNotes: ["Never publish."]),
        ConnectivityProtocol(id: "ros2", name: "ROS 2 (DDS)", layer: "Robotics middleware", summary: "Observe nodes and topics on an authorised ROS 2 domain.",
                             discovery: .planned, communication: .planned, dependencies: ["software.ros2", "interface.wifi-or-ethernet"],
                             supportedCategories: [.robot, .roboticArm, .drone], validation: .planned,
                             safetyNotes: ["Never publish to command topics (e.g. /cmd_vel) or call action servers."]),
        ConnectivityProtocol(id: "hdmi.cec", name: "HDMI-CEC", layer: "AV control", summary: "Mac HDMI ports do not expose CEC; needs a USB-CEC adapter.",
                             discovery: .requiresAdapter, communication: .planned, dependencies: ["adapter.hdmi-cec"],
                             supportedCategories: [.smartTelevision, .gamingConsole], validation: .planned,
                             safetyNotes: ["Observe only; no power/input commands."]),
        ConnectivityProtocol(id: "matter", name: "Matter", layer: "Smart home", summary: "Commissionable and operational nodes are discovered via DNS-SD; control needs commissioning by an approved controller.",
                             discovery: .live, communication: .unavailable, dependencies: ["interface.wifi-or-ethernet"],
                             permissions: ["Setup code / existing fabric controller"], supportedCategories: [.smartHome, .iot, .sensor, .smartTelevision],
                             validation: .implementedUnverified, safetyNotes: ["Discovery only. System Tester does not commission or control accessories."]),
        ConnectivityProtocol(id: "thread", name: "Thread", layer: "Smart home", summary: "Macs have no Thread radio; border routers are discovered via DNS-SD (_meshcop._udp).",
                             discovery: .partial, communication: .unavailable, dependencies: ["interface.wifi-or-ethernet"],
                             supportedCategories: [.smartHome, .iot, .sensor], validation: .implementedUnverified),
        ConnectivityProtocol(id: "sdr.receive", name: "Receive-only SDR", layer: "Radio", summary: "Receive-only signal observation is owned by HCG Signal Contractor.",
                             discovery: .requiresAdapter, communication: .unavailable, dependencies: ["sdr.receiver"],
                             supportedCategories: [.radioReceiver], validation: .delegated,
                             safetyNotes: ["Receive only. Transmission and jamming are prohibited."], owner: "HCG Signal Contractor"),
        ConnectivityProtocol(id: "manufacturer.api", name: "Authorised manufacturer APIs", layer: "Application", summary: "Documented vendor APIs used with the owner's authorisation (e.g. SmartThings, John Deere Operations Center, DJI Cloud API).",
                             discovery: .unavailable, communication: .partial, dependencies: [],
                             permissions: ["Owner account / API credentials (HCG Connect governance)"],
                             supportedCategories: [.smartTelevision, .agriculturalMachinery, .drone, .roboticArm, .smartHome],
                             validation: .researchOnly, safetyNotes: ["Read-only scopes only."]),
        ConnectivityProtocol(id: "samsung.tv-local", name: "Samsung TV local info (port 8001)", layer: "Application", summary: "Read-only device information JSON published by Tizen TVs on the LAN.",
                             discovery: .unavailable, communication: .partial, adapterID: "com.hakmicapitalgroup.adapter.samsung-tv-info",
                             dependencies: ["interface.wifi-or-ethernet"], supportedCategories: [.smartTelevision], validation: .implementedUnverified,
                             safetyNotes: ["GET only. Remote-control channels (which require on-TV approval) are not used."]),
        ConnectivityProtocol(id: "vehicle.control", name: "Vehicle / machine / robot / drone control", layer: "Control", summary: "ECU modification, actuation, motion, flight and firmware flashing.",
                             discovery: .unavailable, communication: .unavailable, supportedCategories: [.vehicle, .motorcycle, .agriculturalMachinery, .constructionEquipment, .industrialMachinery, .robot, .roboticArm, .drone],
                             validation: .prohibited, safetyNotes: ["Requires separate engineering, authorisation and safety validation. Not part of System Tester."])
    ]

    public static func protocolInfo(_ id: String) -> ConnectivityProtocol? { all.first { $0.id == id } }
}

// MARK: - Equipment (Hardware Requirements Center)

public enum EquipmentKind: String, Codable, CaseIterable, Hashable {
    case cable, adapter, diagnosticInterface, software, driver, hostInterface
    public var displayName: String {
        switch self {
        case .cable: return "Cable"
        case .adapter: return "Adapter"
        case .diagnosticInterface: return "Diagnostic interface"
        case .software: return "Software"
        case .driver: return "Driver"
        case .hostInterface: return "Host interface"
        }
    }
}

public struct EquipmentSpec: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var kind: EquipmentKind
    /// Specifications required for compatibility — never a specific product endorsement.
    public var requiredSpecifications: [String]
    public var examples: [String]
    public var supportsProtocols: [String]
    /// How System Tester can detect it, if at all.
    public var detection: String
    public var safetyNotes: [String]

    public init(id: String, name: String, kind: EquipmentKind, requiredSpecifications: [String], examples: [String] = [],
                supportsProtocols: [String] = [], detection: String, safetyNotes: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.requiredSpecifications = requiredSpecifications
        self.examples = examples
        self.supportsProtocols = supportsProtocols
        self.detection = detection
        self.safetyNotes = safetyNotes
    }
}

public enum EquipmentAvailability: String, Codable, Hashable {
    case detected
    case declaredOwned
    case missing
    case unknown

    public var displayName: String {
        switch self {
        case .detected: return "Detected"
        case .declaredOwned: return "Owned (declared by you)"
        case .missing: return "Missing"
        case .unknown: return "Unknown"
        }
    }
    public var satisfied: Bool { self == .detected || self == .declaredOwned }
}

public struct EquipmentStatus: Codable, Hashable {
    public var availability: EquipmentAvailability
    public var evidence: String
    public var at: Date

    public init(_ availability: EquipmentAvailability, _ evidence: String, at: Date = Date()) {
        self.availability = availability
        self.evidence = evidence
        self.at = at
    }
}

public enum EquipmentCatalog {
    public static let all: [EquipmentSpec] = [
        EquipmentSpec(id: "cable.usbc-data", name: "USB-C data cable", kind: .cable,
                      requiredSpecifications: ["Carries USB data (not charge-only)", "USB 3.x 10 Gbit/s rating for full speed on USB 3 devices"],
                      supportsProtocols: ["usb", "apple.coredevice", "serial"],
                      detection: "Inferred when any device enumerates over USB-C; speed class inferred from negotiated link speed."),
        EquipmentSpec(id: "cable.thunderbolt", name: "Thunderbolt 4/5 or USB4 cable", kind: .cable,
                      requiredSpecifications: ["Thunderbolt or USB4 certified (lightning-bolt / USB4 logo)"], supportsProtocols: ["thunderbolt"],
                      detection: "Inferred when a Thunderbolt switch is discovered."),
        EquipmentSpec(id: "adapter.usbc-usba", name: "USB-C to USB-A adapter", kind: .adapter,
                      requiredSpecifications: ["USB data pass-through (USB 3 if the device is USB 3)"], supportsProtocols: ["usb", "serial"],
                      detection: "Not detectable (passive). Declare if owned."),
        EquipmentSpec(id: "interface.bluetooth", name: "Bluetooth controller", kind: .hostInterface,
                      requiredSpecifications: ["Bluetooth 4.0+ (LE) — built into every supported Mac"], supportsProtocols: ["bluetooth.le", "bluetooth.classic"],
                      detection: "Core Bluetooth power state (after you allow Bluetooth access)."),
        EquipmentSpec(id: "interface.wifi-or-ethernet", name: "Wi-Fi or Ethernet connection", kind: .hostInterface,
                      requiredSpecifications: ["Same local network/VLAN as the target device", "Multicast (mDNS/SSDP) not blocked"],
                      supportsProtocols: ["network.mdns", "network.ssdp", "wifi", "ethernet", "matter", "mqtt", "ros2", "modbus", "opcua"],
                      detection: "Host network interfaces (getifaddrs) with an active IPv4/IPv6 address."),
        EquipmentSpec(id: "software.xcode", name: "Xcode 15+ (devicectl)", kind: .software,
                      requiredSpecifications: ["Xcode selected with xcode-select", "Version that supports the device's iOS"],
                      supportsProtocols: ["apple.coredevice"], detection: "xcode-select + xcrun --find devicectl."),
        EquipmentSpec(id: "software.libimobiledevice", name: "libimobiledevice (optional)", kind: .software,
                      requiredSpecifications: ["ideviceinfo in /opt/homebrew/bin or /usr/local/bin"], supportsProtocols: ["apple.coredevice"],
                      detection: "Executable present."),
        EquipmentSpec(id: "software.ps-remote-play", name: "PS Remote Play for Mac (Sony)", kind: .software,
                      requiredSpecifications: ["Official Sony app", "PlayStation Network account linked to the console"],
                      supportsProtocols: ["manufacturer.api"], detection: "/Applications/PS Remote Play.app present."),
        EquipmentSpec(id: "software.arduino-cli", name: "Arduino IDE or arduino-cli", kind: .software,
                      requiredSpecifications: ["Official Arduino tooling"], supportsProtocols: ["serial"],
                      detection: "/Applications/Arduino IDE.app or arduino-cli in /opt/homebrew/bin."),
        EquipmentSpec(id: "software.ros2", name: "ROS 2 distribution", kind: .software,
                      requiredSpecifications: ["Same ROS 2 distribution and ROS_DOMAIN_ID as the robot", "macOS is a community-supported (Tier 3) platform — a Linux VM or container may be required"],
                      supportsProtocols: ["ros2"], detection: "ros2 executable on a known path (declare if installed elsewhere)."),
        EquipmentSpec(id: "software.mqtt-client", name: "MQTT client tooling (mosquitto)", kind: .software,
                      requiredSpecifications: ["MQTT 3.1.1/5 client", "Broker address and read-only credentials"], supportsProtocols: ["mqtt"],
                      detection: "mosquitto_sub in /opt/homebrew/bin."),
        EquipmentSpec(id: "interface.obd2", name: "OBD-II diagnostic interface", kind: .diagnosticInterface,
                      requiredSpecifications: ["SAE J1962 16-pin connector", "ISO 15765-4 CAN (all 2008+ US cars; EU petrol 2001+ / diesel 2004+)",
                                               "ELM327 v1.4b+ or STN11xx/STN21xx command set (avoid clones with incomplete command sets)",
                                               "USB (serial) or Bluetooth LE transport supported by macOS"],
                      supportsProtocols: ["obd2", "can"], detection: "USB serial bridge present (vendor chip only — model not verifiable); declare if owned.",
                      safetyNotes: ["Use read-only modes only. Never clear codes or run actuator tests while driving or without workshop safety."]),
        EquipmentSpec(id: "interface.usb-can", name: "USB-CAN interface", kind: .diagnosticInterface,
                      requiredSpecifications: ["CAN 2.0B, 250 and 500 kbit/s", "Listen-only (silent) mode", "macOS driver or SLCAN/gs_usb firmware"],
                      supportsProtocols: ["can", "j1939", "isobus"], detection: "Declare if owned (driver-specific detection planned).",
                      safetyNotes: ["Must be configured listen-only before connecting to a live bus."]),
        EquipmentSpec(id: "cable.j1939-deutsch9", name: "J1939 9-pin Deutsch diagnostic cable", kind: .cable,
                      requiredSpecifications: ["Deutsch HD10 9-pin (type I or II to match the machine)", "Breakout to the CAN interface (DB9 or OBD)"],
                      supportsProtocols: ["j1939"], detection: "Not detectable. Declare if owned."),
        EquipmentSpec(id: "cable.isobus", name: "ISOBUS in-cab breakout", kind: .cable,
                      requiredSpecifications: ["ISO 11783-2 in-cab connector", "Passive tap; must not terminate or load the bus"],
                      supportsProtocols: ["isobus"], detection: "Not detectable. Declare if owned."),
        EquipmentSpec(id: "adapter.usb-ttl-3v3", name: "USB to UART adapter (3.3 V)", kind: .adapter,
                      requiredSpecifications: ["3.3 V logic (selectable 5 V only if the target is 5 V)", "TX/RX/GND", "CP210x, FT232 or CH34x bridge with macOS driver"],
                      supportsProtocols: ["uart", "serial"], detection: "Serial bridge chip detected over USB (voltage not verifiable).",
                      safetyNotes: ["Never connect 5 V logic to 3.3 V pins (Raspberry Pi GPIO is 3.3 V)."]),
        EquipmentSpec(id: "adapter.hdmi-cec", name: "USB HDMI-CEC adapter", kind: .adapter,
                      requiredSpecifications: ["Passes through HDMI and exposes CEC over USB", "macOS driver / libcec support"],
                      supportsProtocols: ["hdmi.cec"], detection: "Declare if owned."),
        EquipmentSpec(id: "reader.nfc", name: "USB NFC reader (PC/SC)", kind: .diagnosticInterface,
                      requiredSpecifications: ["PC/SC (CCID) compliant", "ISO 14443 A/B"], supportsProtocols: ["nfc"],
                      detection: "Smart-card class (0x0B) USB device present."),
        EquipmentSpec(id: "sdr.receiver", name: "Receive-only SDR", kind: .diagnosticInterface,
                      requiredSpecifications: ["Receive-only hardware for the band of interest"], supportsProtocols: ["sdr.receive"],
                      detection: "Owned by HCG Signal Contractor.")
    ]

    public static func spec(_ id: String) -> EquipmentSpec? { all.first { $0.id == id } }
}
