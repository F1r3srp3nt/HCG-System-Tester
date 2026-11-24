import Foundation

/// Role a device plays on the connection it was discovered on.
public enum DeviceRole: String, Codable, CaseIterable, Hashable {
    case usbDevice
    case usbHost
    case usbHub
    case accessory
    case networkNode
    case unknown

    public var displayName: String {
        switch self {
        case .usbDevice: return "USB device (peripheral role)"
        case .usbHost: return "USB host"
        case .usbHub: return "USB hub"
        case .accessory: return "Accessory"
        case .networkNode: return "Network node"
        case .unknown: return "Unknown role"
        }
    }
}

/// Declarative rules used to match a device to a profile. All specified
/// criteria must match; unspecified criteria are ignored.
public struct DeviceMatchRules: Codable, Hashable {
    public var vendorIDs: [UInt16]
    public var productIDs: [UInt16]
    public var deviceClasses: [UInt8]
    /// Matches when any interface has one of these class codes.
    public var interfaceClasses: [UInt8]
    /// Matches when any interface has this exact (class, subclass, protocol) triple, written "FF.42.01".
    public var interfaceTriples: [String]
    /// Case-insensitive substrings matched against product and vendor names.
    public var nameContains: [String]
    public var connectionTypes: [ConnectionType]

    public init(vendorIDs: [UInt16] = [], productIDs: [UInt16] = [], deviceClasses: [UInt8] = [], interfaceClasses: [UInt8] = [],
                interfaceTriples: [String] = [], nameContains: [String] = [], connectionTypes: [ConnectionType] = []) {
        self.vendorIDs = vendorIDs
        self.productIDs = productIDs
        self.deviceClasses = deviceClasses
        self.interfaceClasses = interfaceClasses
        self.interfaceTriples = interfaceTriples
        self.nameContains = nameContains
        self.connectionTypes = connectionTypes
    }

    public var isEmpty: Bool {
        vendorIDs.isEmpty && productIDs.isEmpty && deviceClasses.isEmpty && interfaceClasses.isEmpty
            && interfaceTriples.isEmpty && nameContains.isEmpty && connectionTypes.isEmpty
    }

    /// Returns matched-criteria evidence and a specificity score, or nil when any criterion fails.
    public func evaluate(_ device: DiscoveredDevice) -> (score: Double, evidence: [String])? {
        if isEmpty { return nil }
        var score = 0.0
        var evidence: [String] = []
        let usb = device.usb

        if !connectionTypes.isEmpty {
            guard connectionTypes.contains(device.connectionType) else { return nil }
            score += 0.05
            evidence.append("Connection type \(device.connectionType.displayName)")
        }
        if !vendorIDs.isEmpty {
            guard let v = usb?.vendorID, vendorIDs.contains(v) else { return nil }
            score += 0.35
            evidence.append("Vendor ID \(Hex.format16(v)) (\(USBVendorDatabase.name(for: v) ?? "unlisted vendor"))")
        }
        if !productIDs.isEmpty {
            guard let p = usb?.productID, productIDs.contains(p) else { return nil }
            score += 0.45
            evidence.append("Product ID \(Hex.format16(p))")
        }
        if !deviceClasses.isEmpty {
            guard let c = usb?.deviceClass, deviceClasses.contains(c) else { return nil }
            score += 0.2
            evidence.append("Device class \(Hex.format8(c)) \(USBClass(code: c).name)")
        }
        if !interfaceClasses.isEmpty {
            guard let match = usb?.interfaces.first(where: { interfaceClasses.contains($0.classCode) }) else { return nil }
            score += 0.2
            evidence.append("Interface \(match.number): \(match.functionDescription)")
        }
        if !interfaceTriples.isEmpty {
            let triples = Set(interfaceTriples.map { $0.uppercased() })
            guard let match = usb?.interfaces.first(where: { triples.contains(Self.triple($0)) }) else { return nil }
            score += 0.3
            evidence.append("Interface \(match.number) triple \(Self.triple(match)): \(match.functionDescription)")
        }
        if !nameContains.isEmpty {
            let haystack = [device.name, usb?.productName, usb?.vendorName, device.manufacturer]
                .compactMap { $0?.lowercased() }.joined(separator: " | ")
            guard let needle = nameContains.first(where: { haystack.contains($0.lowercased()) }) else { return nil }
            score += 0.15
            evidence.append("Name contains \"\(needle)\"")
        }
        return (min(score, 1.0), evidence)
    }

    public static func triple(_ i: USBInterfaceInfo) -> String {
        "\(Hex.pad(UInt64(i.classCode), digits: 2)).\(Hex.pad(UInt64(i.subclassCode), digits: 2)).\(Hex.pad(UInt64(i.protocolCode), digits: 2))"
    }
}

/// A device profile describes a family of systems and what is actually known about
/// communicating with them. Profiles are data and can be supplied by adapters.
public struct DeviceProfile: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var category: DeviceCategory
    public var family: String
    public var role: DeviceRole
    public var match: DeviceMatchRules
    /// Protocols the device is known to expose on this connection (catalog IDs).
    public var exposedProtocols: [String]
    /// Adapters that can provide deeper support (by adapter ID).
    public var recommendedAdapters: [String]
    /// What this connection can and cannot do — shown verbatim to the user.
    public var knownLimitations: [String]
    public var notes: String
    /// Higher priority wins when scores tie.
    public var priority: Int

    public init(id: String, name: String, category: DeviceCategory, family: String, role: DeviceRole = .usbDevice,
                match: DeviceMatchRules, exposedProtocols: [String] = [], recommendedAdapters: [String] = [],
                knownLimitations: [String] = [], notes: String = "", priority: Int = 0) {
        self.id = id
        self.name = name
        self.category = category
        self.family = family
        self.role = role
        self.match = match
        self.exposedProtocols = exposedProtocols
        self.recommendedAdapters = recommendedAdapters
        self.knownLimitations = knownLimitations
        self.notes = notes
        self.priority = priority
    }
}

public enum IdentificationConfidence: String, Codable, CaseIterable, Hashable, Comparable {
    case none
    case low
    case medium
    case high

    public init(score: Double) {
        switch score {
        case ..<0.01: self = .none
        case ..<0.35: self = .low
        case ..<0.6: self = .medium
        default: self = .high
        }
    }

    private var rank: Int {
        switch self { case .none: return 0; case .low: return 1; case .medium: return 2; case .high: return 3 }
    }

    public static func < (lhs: IdentificationConfidence, rhs: IdentificationConfidence) -> Bool { lhs.rank < rhs.rank }

    public var displayName: String { rawValue.capitalized }
}

public struct IdentificationResult: Codable, Hashable {
    public var category: DeviceCategory
    public var profileID: String?
    public var profileName: String?
    public var family: String
    public var role: DeviceRole
    public var score: Double
    public var confidence: IdentificationConfidence
    public var evidence: [String]
    public var exposedProtocols: [String]
    public var recommendedAdapters: [String]
    public var knownLimitations: [String]
    /// Lower-scoring profiles that also matched (for transparency).
    public var alternatives: [String]

    public var isIdentified: Bool { profileID != nil && confidence >= .low }

    public static func unidentified(reason: String) -> IdentificationResult {
        IdentificationResult(category: .unknown, profileID: nil, profileName: nil, family: "Unknown", role: .unknown,
                             score: 0, confidence: .none, evidence: [reason], exposedProtocols: [], recommendedAdapters: [],
                             knownLimitations: ["No profile matched. The device is shown with raw descriptor data only."],
                             alternatives: [])
    }
}
