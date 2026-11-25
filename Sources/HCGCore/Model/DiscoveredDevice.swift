import Foundation

/// Stable identifier for a discovered device within one discovery session.
public struct DeviceIdentifier: RawRepresentable, Codable, Hashable, Comparable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func usbRegistry(_ entryID: UInt64) -> DeviceIdentifier {
        DeviceIdentifier("usb:" + String(entryID, radix: 16))
    }

    public static func thunderboltRegistry(_ entryID: UInt64) -> DeviceIdentifier {
        DeviceIdentifier("tb:" + String(entryID, radix: 16))
    }

    public static func synthetic(_ name: String) -> DeviceIdentifier {
        DeviceIdentifier("synthetic:" + name)
    }

    public var isSynthetic: Bool { rawValue.hasPrefix("synthetic:") }
    public var description: String { rawValue }
    public static func < (lhs: DeviceIdentifier, rhs: DeviceIdentifier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Negotiated USB link speed as reported by the host controller.
public enum USBSpeed: Int, Codable, CaseIterable, Hashable {
    case low = 0
    case full = 1
    case high = 2
    case superSpeed = 3
    case superSpeedPlus = 4
    case superSpeedPlusBy2 = 5

    public var displayName: String {
        switch self {
        case .low: return "Low Speed (1.5 Mbit/s)"
        case .full: return "Full Speed (12 Mbit/s)"
        case .high: return "High Speed (480 Mbit/s)"
        case .superSpeed: return "SuperSpeed (5 Gbit/s)"
        case .superSpeedPlus: return "SuperSpeed+ (10 Gbit/s)"
        case .superSpeedPlusBy2: return "SuperSpeed+ 2x2 (20 Gbit/s)"
        }
    }

    public var shortName: String {
        switch self {
        case .low: return "USB 1.x Low"
        case .full: return "USB 1.x Full"
        case .high: return "USB 2.0"
        case .superSpeed: return "USB 3.2 Gen 1"
        case .superSpeedPlus: return "USB 3.2 Gen 2"
        case .superSpeedPlusBy2: return "USB 3.2 Gen 2x2"
        }
    }

    public var megabitsPerSecond: Double {
        switch self {
        case .low: return 1.5
        case .full: return 12
        case .high: return 480
        case .superSpeed: return 5_000
        case .superSpeedPlus: return 10_000
        case .superSpeedPlusBy2: return 20_000
        }
    }

    /// The speed class a device's `bcdUSB` release guarantees it can reach.
    ///
    /// bcdUSB ≥ 3.00 only guarantees SuperSpeed (5 Gbit/s): USB 3.1/3.2 releases also cover Gen 1
    /// devices, and Gen 2 capability is only declared in the BOS descriptor, which macOS does not publish
    /// in the registry. Claiming more would produce false "slow link" warnings.
    public static func maximumSupported(bcdUSB: UInt16) -> USBSpeed {
        switch bcdUSB {
        case 0x0300...: return .superSpeed
        case 0x0200..<0x0300: return .high
        default: return .full
        }
    }
}

/// One USB interface exposed by a device configuration.
public struct USBInterfaceInfo: Codable, Hashable, Identifiable {
    public var number: Int
    public var alternateSetting: Int
    public var classCode: UInt8
    public var subclassCode: UInt8
    public var protocolCode: UInt8
    public var name: String?
    /// IOKit class names of drivers/services attached to the interface (empty when no driver matched).
    public var attachedServices: [String]
    /// bNumEndpoints from the interface descriptor, when macOS publishes it.
    public var endpointCount: Int?

    public var id: String { "\(number).\(alternateSetting)" }

    public init(number: Int, alternateSetting: Int = 0, classCode: UInt8, subclassCode: UInt8 = 0, protocolCode: UInt8 = 0,
                name: String? = nil, attachedServices: [String] = [], endpointCount: Int? = nil) {
        self.number = number
        self.alternateSetting = alternateSetting
        self.classCode = classCode
        self.subclassCode = subclassCode
        self.protocolCode = protocolCode
        self.name = name
        self.attachedServices = attachedServices
        self.endpointCount = endpointCount
    }

    public var usbClass: USBClass { USBClass(code: classCode) }
    public var hasDriver: Bool { !attachedServices.isEmpty }

    public var functionDescription: String {
        USBClass.describeInterface(classCode: classCode, subclass: subclassCode, protocolCode: protocolCode)
    }
}

/// Descriptor-level information about a USB device as read from the host.
public struct USBDeviceDescriptor: Codable, Hashable {
    public var vendorID: UInt16?
    public var productID: UInt16?
    public var vendorName: String?
    public var productName: String?
    public var serialNumber: String?
    public var deviceClass: UInt8?
    public var deviceSubClass: UInt8?
    public var deviceProtocol: UInt8?
    public var bcdDevice: UInt16?
    public var bcdUSB: UInt16?
    public var speed: USBSpeed?
    public var locationID: UInt32?
    public var registryEntryID: UInt64?
    public var configurationCount: Int?
    public var interfaces: [USBInterfaceInfo]
    /// BSD disk names (e.g. `disk4`) published beneath this device by the storage stack.
    public var bsdNames: [String]
    /// Serial callout device paths (e.g. `/dev/cu.usbmodem1101`) published beneath this device.
    public var serialDevicePaths: [String]
    /// Size in bytes of the largest whole medium published beneath this device.
    public var mediaSizeBytes: Int64?
    public var ioClassName: String?
    public var isBuiltIn: Bool

    public init(vendorID: UInt16? = nil, productID: UInt16? = nil, vendorName: String? = nil, productName: String? = nil,
                serialNumber: String? = nil, deviceClass: UInt8? = nil, deviceSubClass: UInt8? = nil, deviceProtocol: UInt8? = nil,
                bcdDevice: UInt16? = nil, bcdUSB: UInt16? = nil, speed: USBSpeed? = nil, locationID: UInt32? = nil,
                registryEntryID: UInt64? = nil, configurationCount: Int? = nil, interfaces: [USBInterfaceInfo] = [],
                bsdNames: [String] = [], serialDevicePaths: [String] = [], mediaSizeBytes: Int64? = nil,
                ioClassName: String? = nil, isBuiltIn: Bool = false) {
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.serialNumber = serialNumber
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.bcdDevice = bcdDevice
        self.bcdUSB = bcdUSB
        self.speed = speed
        self.locationID = locationID
        self.registryEntryID = registryEntryID
        self.configurationCount = configurationCount
        self.interfaces = interfaces
        self.bsdNames = bsdNames
        self.serialDevicePaths = serialDevicePaths
        self.mediaSizeBytes = mediaSizeBytes
        self.ioClassName = ioClassName
        self.isBuiltIn = isBuiltIn
    }

    public var vendorIDHex: String { vendorID.map { Hex.format16($0) } ?? "—" }
    public var productIDHex: String { productID.map { Hex.format16($0) } ?? "—" }

    /// Device-level class (0x00 means "defined per interface").
    public var usbClass: USBClass { USBClass(code: deviceClass ?? 0) }

    /// All class codes present at device or interface level.
    public var allClassCodes: Set<UInt8> {
        var set = Set(interfaces.map(\.classCode))
        if let c = deviceClass, c != 0 { set.insert(c) }
        return set
    }

    public var isHub: Bool { deviceClass == USBClass.hub.code || interfaces.contains { $0.classCode == USBClass.hub.code } }

    /// e.g. "2.10" for bcdDevice 0x0210.
    public var firmwareRevision: String? { bcdDevice.map(Hex.bcdVersion) }
    public var usbSpecification: String? { bcdUSB.map(Hex.bcdVersion) }

    public var maximumSupportedSpeed: USBSpeed? { bcdUSB.map(USBSpeed.maximumSupported(bcdUSB:)) }

    /// USB bus number (top byte of locationID).
    public var busNumber: Int? { locationID.map { Int($0 >> 24) } }

    /// Port path from the root, e.g. [1, 2] for "bus root → port 1 → hub port 2".
    public var portPath: [Int] { locationID.map(USBTopology.portPath(locationID:)) ?? [] }
}

/// Descriptor-level information about a Thunderbolt / USB4 switch.
public struct ThunderboltDescriptor: Codable, Hashable {
    public var vendorName: String?
    public var modelName: String?
    public var vendorID: UInt32?
    public var deviceID: UInt32?
    public var routeString: UInt64?
    public var depth: Int?
    public var registryEntryID: UInt64?
    public var ioClassName: String?

    public init(vendorName: String? = nil, modelName: String? = nil, vendorID: UInt32? = nil, deviceID: UInt32? = nil,
                routeString: UInt64? = nil, depth: Int? = nil, registryEntryID: UInt64? = nil, ioClassName: String? = nil) {
        self.vendorName = vendorName
        self.modelName = modelName
        self.vendorID = vendorID
        self.deviceID = deviceID
        self.routeString = routeString
        self.depth = depth
        self.registryEntryID = registryEntryID
        self.ioClassName = ioClassName
    }
}

/// A system observed by a discovery backend. This is raw observation, not a claim of support.
public struct DiscoveredDevice: Identifiable, Codable, Hashable {
    public var id: DeviceIdentifier
    public var provenance: DataProvenance
    public var connectionType: ConnectionType
    public var name: String
    public var manufacturer: String?
    public var usb: USBDeviceDescriptor?
    public var thunderbolt: ThunderboltDescriptor?
    /// Name of the backend that produced the observation, e.g. "IOKit · IOUSBHostDevice".
    public var source: String
    public var firstSeen: Date
    public var lastSeen: Date
    public var isPresent: Bool
    /// Selected raw properties (stringified) kept as evidence. Redacted before export.
    public var rawProperties: [String: String]

    public init(id: DeviceIdentifier, provenance: DataProvenance, connectionType: ConnectionType, name: String,
                manufacturer: String? = nil, usb: USBDeviceDescriptor? = nil, thunderbolt: ThunderboltDescriptor? = nil,
                source: String, firstSeen: Date = Date(), lastSeen: Date = Date(), isPresent: Bool = true,
                rawProperties: [String: String] = [:]) {
        self.id = id
        self.provenance = provenance
        self.connectionType = connectionType
        self.name = name
        self.manufacturer = manufacturer
        self.usb = usb
        self.thunderbolt = thunderbolt
        self.source = source
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isPresent = isPresent
        self.rawProperties = rawProperties
    }

    /// Name shown in the UI. Synthetic devices are always prefixed.
    public var displayName: String {
        provenance.isSynthetic && !name.hasPrefix("[SYNTHETIC]") ? "[SYNTHETIC] " + name : name
    }

    /// A key that is stable across re-plugging the same physical unit (used by the Device Laboratory).
    /// Uses VID:PID plus a salted fingerprint of the serial number, or the port location when no serial exists.
    public func stableKey(salt: String = "") -> String {
        if let usb = usb {
            let base = "\(usb.vendorIDHex):\(usb.productIDHex)"
            if let serial = usb.serialNumber, !serial.isEmpty {
                return base + ":sn-" + Fingerprint.short(salt + serial)
            }
            if let loc = usb.locationID {
                return base + ":loc-" + String(loc, radix: 16)
            }
            return base + ":" + Fingerprint.short(salt + name)
        }
        if let tb = thunderbolt {
            return "tb:\(tb.vendorID.map { String($0, radix: 16) } ?? "?"):\(tb.deviceID.map { String($0, radix: 16) } ?? "?"):\(tb.routeString.map { String($0, radix: 16) } ?? "?")"
        }
        return id.rawValue
    }
}

public enum Hex {
    public static func pad(_ value: UInt64, digits: Int) -> String {
        let raw = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, digits - raw.count)) + raw
    }

    public static func format16(_ value: UInt16) -> String { "0x" + pad(UInt64(value), digits: 4) }
    public static func format8(_ value: UInt8) -> String { "0x" + pad(UInt64(value), digits: 2) }
    public static func format32(_ value: UInt32) -> String { "0x" + pad(UInt64(value), digits: 8) }

    /// Formats a binary-coded-decimal version such as 0x0210 as "2.10".
    public static func bcdVersion(_ value: UInt16) -> String {
        let v = Int(value)
        let major = ((v >> 12) & 0xF) * 10 + ((v >> 8) & 0xF)
        let minor = ((v >> 4) & 0xF) * 10 + (v & 0xF)
        return "\(major)." + (minor < 10 ? "0\(minor)" : "\(minor)")
    }

    /// Parses a 16-bit identifier written in hexadecimal, with or without a `0x` prefix ("0x054C", "054c").
    public static func parse16(_ text: String) -> UInt16? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return UInt16(t.dropFirst(2), radix: 16) }
        return UInt16(t, radix: 16)
    }
}

/// Small, dependency-free FNV-1a fingerprint used for privacy-preserving local keys.
/// Not a cryptographic hash; used only so raw serial numbers need not be stored as keys.
public enum Fingerprint {
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static func short(_ text: String) -> String {
        String(String(fnv1a64(text), radix: 16).suffix(10))
    }
}
