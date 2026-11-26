import Foundation

// MARK: - Universal Connectivity: knowledge model
//
// Every statement about a device carries a knowledge source, so manufacturer documentation,
// community reports, AI suggestions and physically verified HCG results are never confused.

/// Where a piece of connectivity knowledge comes from.
public enum KnowledgeSource: String, Codable, CaseIterable, Hashable, Identifiable {
    case manufacturerDocumented
    case communityReported
    case aiSuggestion
    case hcgVerified
    case hcgResearchNote

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manufacturerDocumented: return "Manufacturer-documented"
        case .communityReported: return "Community-reported"
        case .aiSuggestion: return "AI suggestion (unverified)"
        case .hcgVerified: return "Physically verified by HCG"
        case .hcgResearchNote: return "HCG research note"
        }
    }

    public var shortLabel: String {
        switch self {
        case .manufacturerDocumented: return "MFR"
        case .communityReported: return "COMMUNITY"
        case .aiSuggestion: return "AI"
        case .hcgVerified: return "VERIFIED"
        case .hcgResearchNote: return "RESEARCH"
        }
    }

    /// Weight used when deciding whether a fact is reliable enough to plan with.
    public var trustRank: Int {
        switch self {
        case .hcgVerified: return 4
        case .manufacturerDocumented: return 3
        case .hcgResearchNote: return 2
        case .communityReported: return 1
        case .aiSuggestion: return 0
        }
    }
}

public struct SourcedFact: Codable, Hashable, Identifiable {
    public var text: String
    public var source: KnowledgeSource
    /// Reference ID from the profile's documentation list, if any.
    public var reference: String?

    public var id: String { text + "|" + source.rawValue }

    public init(_ text: String, _ source: KnowledgeSource, reference: String? = nil) {
        self.text = text
        self.source = source
        self.reference = reference
    }
}

public struct DocumentationReference: Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var publisher: String
    public var url: String
    public var source: KnowledgeSource
    /// HCG has not fetched or verified reachability unless this is set.
    public var lastChecked: Date?

    public init(id: String, title: String, publisher: String, url: String, source: KnowledgeSource = .manufacturerDocumented, lastChecked: Date? = nil) {
        self.id = id
        self.title = title
        self.publisher = publisher
        self.url = url
        self.source = source
        self.lastChecked = lastChecked
    }
}

/// The 25 Universal Connectivity Center categories.
public enum ConnectivityCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case desktopComputer, laptop, server, smartphone, tablet, gamingConsole, smartTelevision, vehicle, motorcycle
    case agriculturalMachinery, constructionEquipment, industrialMachinery, robot, roboticArm, drone, smartHome, iot
    case networkEquipment, microcontroller, singleBoardComputer, sensor, radioReceiver, laboratoryInstrument, storageDevice, wearable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .desktopComputer: return "Desktop computers"
        case .laptop: return "Laptops"
        case .server: return "Servers"
        case .smartphone: return "Smartphones"
        case .tablet: return "Tablets"
        case .gamingConsole: return "Gaming consoles"
        case .smartTelevision: return "Smart televisions"
        case .vehicle: return "Vehicles"
        case .motorcycle: return "Motorcycles"
        case .agriculturalMachinery: return "Agricultural machinery"
        case .constructionEquipment: return "Construction equipment"
        case .industrialMachinery: return "Industrial machinery"
        case .robot: return "Robots"
        case .roboticArm: return "Robotic arms"
        case .drone: return "Drones"
        case .smartHome: return "Smart-home devices"
        case .iot: return "IoT devices"
        case .networkEquipment: return "Network equipment"
        case .microcontroller: return "Microcontrollers"
        case .singleBoardComputer: return "Single-board computers"
        case .sensor: return "Sensors"
        case .radioReceiver: return "Radio receivers"
        case .laboratoryInstrument: return "Laboratory instruments"
        case .storageDevice: return "Storage devices"
        case .wearable: return "Wearables"
        }
    }

    public var symbolName: String {
        switch self {
        case .desktopComputer: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .server: return "server.rack"
        case .smartphone: return "iphone"
        case .tablet: return "ipad"
        case .gamingConsole: return "gamecontroller"
        case .smartTelevision: return "tv"
        case .vehicle: return "car"
        case .motorcycle: return "bicycle"
        case .agriculturalMachinery: return "leaf"
        case .constructionEquipment: return "hammer"
        case .industrialMachinery: return "gearshape.2"
        case .robot: return "figure.walk"
        case .roboticArm: return "hand.point.up.braille"
        case .drone: return "airplane"
        case .smartHome: return "homekit"
        case .iot: return "sensor"
        case .networkEquipment: return "network"
        case .microcontroller: return "cpu"
        case .singleBoardComputer: return "memorychip"
        case .sensor: return "thermometer.medium"
        case .radioReceiver: return "antenna.radiowaves.left.and.right"
        case .laboratoryInstrument: return "testtube.2"
        case .storageDevice: return "externaldrive"
        case .wearable: return "applewatch"
        }
    }

    /// Typical connection families for the category (guidance only, never a compatibility claim).
    public var typicalProtocols: [String] {
        switch self {
        case .desktopComputer, .laptop, .server: return ["network.mdns", "ethernet", "usb", "thunderbolt", "bluetooth.le"]
        case .smartphone, .tablet: return ["usb", "apple.coredevice", "bluetooth.le", "network.mdns"]
        case .gamingConsole: return ["hdmi.cec", "network.mdns", "bluetooth.classic", "usb"]
        case .smartTelevision: return ["network.ssdp", "network.mdns", "hdmi.cec", "manufacturer.api", "matter"]
        case .vehicle, .motorcycle: return ["obd2", "can", "bluetooth.le"]
        case .agriculturalMachinery, .constructionEquipment: return ["j1939", "isobus", "can", "manufacturer.api"]
        case .industrialMachinery: return ["modbus", "opcua", "mqtt", "ethernet"]
        case .robot, .roboticArm: return ["ros2", "ethernet", "modbus", "manufacturer.api"]
        case .drone: return ["manufacturer.api", "usb", "wifi"]
        case .smartHome, .iot: return ["matter", "thread", "bluetooth.le", "network.mdns", "mqtt"]
        case .networkEquipment: return ["ethernet", "network.ssdp", "network.mdns"]
        case .microcontroller, .singleBoardComputer: return ["usb", "serial", "uart", "network.mdns", "bluetooth.le"]
        case .sensor, .wearable: return ["bluetooth.le", "matter", "thread"]
        case .radioReceiver: return ["sdr.receive", "usb"]
        case .laboratoryInstrument: return ["usb", "serial", "ethernet"]
        case .storageDevice: return ["usb", "thunderbolt"]
        }
    }
}

public enum SafetyClass: String, Codable, CaseIterable, Hashable {
    /// Observing only (discovery, descriptors, read-only queries).
    case readOnly
    /// Writes state that is easily reversible (e.g. pairing). Needs explicit approval.
    case reversibleChange
    /// Controls physical motion, safety functions, firmware or transmission. Prohibited in System Tester.
    case prohibitedControl

    public var displayName: String {
        switch self {
        case .readOnly: return "Read-only"
        case .reversibleChange: return "Reversible change — explicit approval"
        case .prohibitedControl: return "Prohibited (control / safety-critical)"
        }
    }
}

public struct SafetyRestriction: Codable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var safetyClass: SafetyClass
    public var source: KnowledgeSource

    public init(_ id: String, _ text: String, _ safetyClass: SafetyClass = .prohibitedControl, _ source: KnowledgeSource = .hcgResearchNote) {
        self.id = id
        self.text = text
        self.safetyClass = safetyClass
        self.source = source
    }
}

/// One concrete way to connect to a device.
public struct ConnectionMethod: Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var protocolID: String
    /// Connection driver implemented by System Tester, if any (e.g. "apple.coredevice", "ble.gatt-read").
    public var driverID: String?
    public var requiredEquipment: [String]
    public var requiredSoftware: [String]
    public var permissions: [String]
    public var authentication: String?
    public var steps: [String]
    public var safety: SafetyClass
    public var source: KnowledgeSource
    public var osRestriction: String?
    public var notes: String?

    public init(id: String, title: String, protocolID: String, driverID: String? = nil, requiredEquipment: [String] = [],
                requiredSoftware: [String] = [], permissions: [String] = [], authentication: String? = nil, steps: [String] = [],
                safety: SafetyClass = .readOnly, source: KnowledgeSource, osRestriction: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.protocolID = protocolID
        self.driverID = driverID
        self.requiredEquipment = requiredEquipment
        self.requiredSoftware = requiredSoftware
        self.permissions = permissions
        self.authentication = authentication
        self.steps = steps
        self.safety = safety
        self.source = source
        self.osRestriction = osRestriction
        self.notes = notes
    }
}

/// Rules that link an observed endpoint (USB, BLE, Bonjour, SSDP) to a profile.
public struct EndpointMatchRule: Codable, Hashable {
    public var transports: [EndpointTransport]
    public var usbVendorIDs: [UInt16]
    public var usbProductIDs: [UInt16]
    public var nameContains: [String]
    public var serviceTypes: [String]
    /// Attribute key → substring (case-insensitive), e.g. "manufacturer" → "samsung", "model" → "Mac".
    public var attributeContains: [String: String]
    public var bleServiceUUIDs: [String]

    public init(transports: [EndpointTransport] = [], usbVendorIDs: [UInt16] = [], usbProductIDs: [UInt16] = [], nameContains: [String] = [],
                serviceTypes: [String] = [], attributeContains: [String: String] = [:], bleServiceUUIDs: [String] = []) {
        self.transports = transports
        self.usbVendorIDs = usbVendorIDs
        self.usbProductIDs = usbProductIDs
        self.nameContains = nameContains
        self.serviceTypes = serviceTypes
        self.attributeContains = attributeContains
        self.bleServiceUUIDs = bleServiceUUIDs
    }
}

/// Research status of a profile itself (separate from the development roadmap).
public enum ProfileResearchStatus: String, Codable, Hashable {
    case researchTarget
    case partiallyResearched
    case implemented

    public var displayName: String {
        switch self {
        case .researchTarget: return "Research target — no compatibility claimed"
        case .partiallyResearched: return "Partially researched"
        case .implemented: return "Adapter implemented"
        }
    }
}

/// A structured Device Connectivity Encyclopedia profile.
public struct EncyclopediaProfile: Codable, Hashable, Identifiable {
    public var id: String
    public var category: ConnectivityCategory
    public var manufacturer: String
    public var productFamily: String
    public var model: String?
    public var modelYear: String?
    public var hardwareRevision: String?
    public var firmwareVersion: String?
    public var operatingSystem: SourcedFact?
    public var physicalInterfaces: [SourcedFact]
    public var wirelessInterfaces: [SourcedFact]
    public var protocols: [SourcedFact]
    public var sdks: [SourcedFact]
    public var requiredCables: [String]
    public var requiredAdapters: [String]
    public var requiredSoftware: [String]
    public var requiredDrivers: [SourcedFact]
    public var authentication: [SourcedFact]
    public var permissions: [SourcedFact]
    public var safety: [SafetyRestriction]
    public var connectionMethods: [ConnectionMethod]
    public var troubleshooting: [SourcedFact]
    public var references: [DocumentationReference]
    /// Questions HCG needs answered before planning (e.g. exact model year, firmware).
    public var informationRequests: [String]
    public var match: EndpointMatchRule
    public var researchStatus: ProfileResearchStatus
    public var priority: Int
    public var origin: String

    public init(id: String, category: ConnectivityCategory, manufacturer: String, productFamily: String, model: String? = nil,
                modelYear: String? = nil, hardwareRevision: String? = nil, firmwareVersion: String? = nil, operatingSystem: SourcedFact? = nil,
                physicalInterfaces: [SourcedFact] = [], wirelessInterfaces: [SourcedFact] = [], protocols: [SourcedFact] = [],
                sdks: [SourcedFact] = [], requiredCables: [String] = [], requiredAdapters: [String] = [], requiredSoftware: [String] = [],
                requiredDrivers: [SourcedFact] = [], authentication: [SourcedFact] = [], permissions: [SourcedFact] = [],
                safety: [SafetyRestriction] = [], connectionMethods: [ConnectionMethod] = [], troubleshooting: [SourcedFact] = [],
                references: [DocumentationReference] = [], informationRequests: [String] = [], match: EndpointMatchRule = EndpointMatchRule(),
                researchStatus: ProfileResearchStatus = .researchTarget, priority: Int = 3, origin: String = "built-in") {
        self.id = id
        self.category = category
        self.manufacturer = manufacturer
        self.productFamily = productFamily
        self.model = model
        self.modelYear = modelYear
        self.hardwareRevision = hardwareRevision
        self.firmwareVersion = firmwareVersion
        self.operatingSystem = operatingSystem
        self.physicalInterfaces = physicalInterfaces
        self.wirelessInterfaces = wirelessInterfaces
        self.protocols = protocols
        self.sdks = sdks
        self.requiredCables = requiredCables
        self.requiredAdapters = requiredAdapters
        self.requiredSoftware = requiredSoftware
        self.requiredDrivers = requiredDrivers
        self.authentication = authentication
        self.permissions = permissions
        self.safety = safety
        self.connectionMethods = connectionMethods
        self.troubleshooting = troubleshooting
        self.references = references
        self.informationRequests = informationRequests
        self.match = match
        self.researchStatus = researchStatus
        self.priority = priority
        self.origin = origin
    }

    public var displayName: String { [manufacturer, productFamily, model].compactMap { $0 }.joined(separator: " ") }

    /// All facts in the profile (for source statistics and validation).
    public var allFacts: [SourcedFact] {
        [operatingSystem].compactMap { $0 } + physicalInterfaces + wirelessInterfaces + protocols + sdks + requiredDrivers
            + authentication + permissions + troubleshooting
    }
}

// MARK: - Observed endpoints (discovery results across transports)

public enum EndpointTransport: String, Codable, CaseIterable, Hashable {
    case usb, thunderbolt, ble, bluetoothClassic, bonjour, ssdp, host, coreDevice
    public var displayName: String {
        switch self {
        case .usb: return "USB"
        case .thunderbolt: return "Thunderbolt"
        case .ble: return "Bluetooth LE"
        case .bluetoothClassic: return "Bluetooth Classic"
        case .bonjour: return "Wi-Fi / LAN (Bonjour)"
        case .ssdp: return "Wi-Fi / LAN (SSDP/UPnP)"
        case .host: return "This Mac"
        case .coreDevice: return "Apple CoreDevice"
        }
    }
}

/// Something observed on a transport. Observation is not connection.
public struct ObservedEndpoint: Codable, Hashable, Identifiable {
    public var id: String
    public var transport: EndpointTransport
    public var name: String
    /// Normalised attributes: "serviceType", "manufacturer", "model", "vid", "pid", "serviceUUIDs", "host", "address", …
    public var attributes: [String: String]
    /// Keys whose values identify a physical unit or person (redacted in exports).
    public var sensitiveKeys: [String]
    public var firstSeen: Date
    public var lastSeen: Date
    public var provenance: DataProvenance

    public init(id: String, transport: EndpointTransport, name: String, attributes: [String: String] = [:], sensitiveKeys: [String] = [],
                firstSeen: Date = Date(), lastSeen: Date = Date(), provenance: DataProvenance) {
        self.id = id
        self.transport = transport
        self.name = name
        self.attributes = attributes
        self.sensitiveKeys = sensitiveKeys
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.provenance = provenance
    }

    public static func fromUSB(_ d: DiscoveredDevice) -> ObservedEndpoint {
        var a: [String: String] = ["source": d.source]
        if let u = d.usb {
            a["vid"] = u.vendorIDHex
            a["pid"] = u.productIDHex
            if let m = u.vendorName { a["manufacturer"] = m }
            if let p = u.productName { a["model"] = p }
            if let s = u.serialNumber { a["serial"] = s }
        }
        if let tb = d.thunderbolt { a["manufacturer"] = tb.vendorName ?? ""; a["model"] = tb.modelName ?? "" }
        return ObservedEndpoint(id: "usb:" + d.id.rawValue, transport: d.thunderbolt != nil ? .thunderbolt : .usb, name: d.displayName,
                                attributes: a, sensitiveKeys: ["serial"], firstSeen: d.firstSeen, lastSeen: d.lastSeen, provenance: d.provenance)
    }
}

public struct EndpointMatch: Hashable {
    public var profileID: String
    public var score: Int
    public var evidence: [String]
}

public enum EndpointMatcher {
    /// Returns matching profiles, best first. Requires at least one positive criterion; transport alone never matches.
    public static func match(_ e: ObservedEndpoint, profiles: [EncyclopediaProfile]) -> [EndpointMatch] {
        profiles.compactMap { p -> EndpointMatch? in
            let r = p.match
            var score = 0
            var evidence: [String] = []
            if !r.transports.isEmpty {
                guard r.transports.contains(e.transport) else { return nil }
            }
            if !r.usbVendorIDs.isEmpty {
                guard let v = e.attributes["vid"].flatMap(Hex.parse16), r.usbVendorIDs.contains(v) else { return nil }
                score += 3; evidence.append("USB vendor \(Hex.format16(v))")
            }
            if !r.usbProductIDs.isEmpty {
                guard let pid = e.attributes["pid"].flatMap(Hex.parse16), r.usbProductIDs.contains(pid) else { return nil }
                score += 3; evidence.append("USB product \(Hex.format16(pid))")
            }
            if !r.serviceTypes.isEmpty {
                guard let st = e.attributes["serviceType"], r.serviceTypes.contains(where: { st.lowercased().hasPrefix($0.lowercased()) }) else { return nil }
                score += 2; evidence.append("Service \(st)")
            }
            if !r.bleServiceUUIDs.isEmpty {
                let uuids = (e.attributes["serviceUUIDs"] ?? "").uppercased()
                guard let u = r.bleServiceUUIDs.first(where: { uuids.contains($0.uppercased()) }) else { return nil }
                score += 2; evidence.append("BLE service \(u)")
            }
            for (key, needle) in r.attributeContains.sorted(by: { $0.key < $1.key }) {
                guard let v = e.attributes[key], v.lowercased().contains(needle.lowercased()) else { return nil }
                score += 2; evidence.append("\(key) contains “\(needle)”")
            }
            if !r.nameContains.isEmpty {
                let hay = (e.name + " " + (e.attributes["model"] ?? "")).lowercased()
                guard let n = r.nameContains.first(where: { hay.contains($0.lowercased()) }) else { return nil }
                score += 1; evidence.append("Name contains “\(n)”")
            }
            return score > 0 ? EndpointMatch(profileID: p.id, score: score, evidence: evidence) : nil
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.profileID < $1.profileID }
    }
}

// MARK: - Tolerant decoding (user-supplied profile JSON may omit any optional section)

extension EndpointMatchRule {
    enum CodingKeys: String, CodingKey { case transports, usbVendorIDs, usbProductIDs, nameContains, serviceTypes, attributeContains, bleServiceUUIDs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(transports: try c.decodeIfPresent([EndpointTransport].self, forKey: .transports) ?? [],
                  usbVendorIDs: (try c.decodeIfPresent([FlexibleHexInteger<UInt16>].self, forKey: .usbVendorIDs) ?? []).map(\.value),
                  usbProductIDs: (try c.decodeIfPresent([FlexibleHexInteger<UInt16>].self, forKey: .usbProductIDs) ?? []).map(\.value),
                  nameContains: try c.decodeIfPresent([String].self, forKey: .nameContains) ?? [],
                  serviceTypes: try c.decodeIfPresent([String].self, forKey: .serviceTypes) ?? [],
                  attributeContains: try c.decodeIfPresent([String: String].self, forKey: .attributeContains) ?? [:],
                  bleServiceUUIDs: try c.decodeIfPresent([String].self, forKey: .bleServiceUUIDs) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transports, forKey: .transports)
        try c.encode(usbVendorIDs.map { FlexibleHexInteger($0) }, forKey: .usbVendorIDs)
        try c.encode(usbProductIDs.map { FlexibleHexInteger($0) }, forKey: .usbProductIDs)
        try c.encode(nameContains, forKey: .nameContains)
        try c.encode(serviceTypes, forKey: .serviceTypes)
        try c.encode(attributeContains, forKey: .attributeContains)
        try c.encode(bleServiceUUIDs, forKey: .bleServiceUUIDs)
    }
}

extension EncyclopediaProfile {
    enum CodingKeys: String, CodingKey {
        case id, category, manufacturer, productFamily, model, modelYear, hardwareRevision, firmwareVersion, operatingSystem
        case physicalInterfaces, wirelessInterfaces, protocols, sdks, requiredCables, requiredAdapters, requiredSoftware, requiredDrivers
        case authentication, permissions, safety, connectionMethods, troubleshooting, references, informationRequests, match
        case researchStatus, priority, origin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list<T: Decodable>(_ k: CodingKeys) throws -> [T] { try c.decodeIfPresent([T].self, forKey: k) ?? [] }
        self.init(id: try c.decode(String.self, forKey: .id),
                  category: try c.decode(ConnectivityCategory.self, forKey: .category),
                  manufacturer: try c.decode(String.self, forKey: .manufacturer),
                  productFamily: try c.decode(String.self, forKey: .productFamily),
                  model: try c.decodeIfPresent(String.self, forKey: .model),
                  modelYear: try c.decodeIfPresent(String.self, forKey: .modelYear),
                  hardwareRevision: try c.decodeIfPresent(String.self, forKey: .hardwareRevision),
                  firmwareVersion: try c.decodeIfPresent(String.self, forKey: .firmwareVersion),
                  operatingSystem: try c.decodeIfPresent(SourcedFact.self, forKey: .operatingSystem),
                  physicalInterfaces: try list(.physicalInterfaces), wirelessInterfaces: try list(.wirelessInterfaces),
                  protocols: try list(.protocols), sdks: try list(.sdks), requiredCables: try list(.requiredCables),
                  requiredAdapters: try list(.requiredAdapters), requiredSoftware: try list(.requiredSoftware),
                  requiredDrivers: try list(.requiredDrivers), authentication: try list(.authentication), permissions: try list(.permissions),
                  safety: try list(.safety), connectionMethods: try list(.connectionMethods), troubleshooting: try list(.troubleshooting),
                  references: try list(.references), informationRequests: try list(.informationRequests),
                  match: try c.decodeIfPresent(EndpointMatchRule.self, forKey: .match) ?? EndpointMatchRule(),
                  researchStatus: try c.decodeIfPresent(ProfileResearchStatus.self, forKey: .researchStatus) ?? .researchTarget,
                  priority: try c.decodeIfPresent(Int.self, forKey: .priority) ?? 3,
                  origin: try c.decodeIfPresent(String.self, forKey: .origin) ?? "user")
    }
}
