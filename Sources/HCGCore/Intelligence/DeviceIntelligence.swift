import Foundation

// MARK: - Universal Device Intelligence Engine
//
// Device-family adapters ("intelligence providers") turn a discovered device into a sourced,
// verifiable picture: every field says where it came from, every missing field says why, and the
// connection ladder only advances on evidence.

/// The 13-state connection ladder. States 2–10 are an ordered progression of verified evidence;
/// `connectionLimited`, `unsupported` and `disconnected` are terminal conditions.
public enum IntelligenceState: String, Codable, CaseIterable, Hashable, Identifiable {
    case waitingForDevice
    case physicalDeviceDetected
    case usbEnumerated
    case familyIdentified
    case protocolDiscovered
    case authorizationRequired
    case pairingAvailable
    case pairingEstablished
    case communicationEstablished
    case diagnosticsAvailable
    case connectionLimited
    case unsupported
    case disconnected

    public var id: String { rawValue }

    /// Position on the progression (terminal conditions have no rank).
    public var rank: Int? {
        switch self {
        case .waitingForDevice: return 0
        case .physicalDeviceDetected: return 1
        case .usbEnumerated: return 2
        case .familyIdentified: return 3
        case .protocolDiscovered: return 4
        case .authorizationRequired: return 5
        case .pairingAvailable: return 6
        case .pairingEstablished: return 7
        case .communicationEstablished: return 8
        case .diagnosticsAvailable: return 9
        case .connectionLimited, .unsupported, .disconnected: return nil
        }
    }

    public static let progression: [IntelligenceState] = [.physicalDeviceDetected, .usbEnumerated, .familyIdentified, .protocolDiscovered,
                                                          .authorizationRequired, .pairingAvailable, .pairingEstablished,
                                                          .communicationEstablished, .diagnosticsAvailable]

    public var number: Int {
        (IntelligenceState.allCases.firstIndex(of: self) ?? 0) + 1
    }

    public var displayName: String {
        switch self {
        case .waitingForDevice: return "Waiting for device"
        case .physicalDeviceDetected: return "Physical device detected"
        case .usbEnumerated: return "USB enumeration successful"
        case .familyIdentified: return "Device family identified"
        case .protocolDiscovered: return "Supported protocol discovered"
        case .authorizationRequired: return "Locked / authorization required"
        case .pairingAvailable: return "Pairing available"
        case .pairingEstablished: return "Pairing established"
        case .communicationEstablished: return "Authorized communication established"
        case .diagnosticsAvailable: return "Diagnostics available"
        case .connectionLimited: return "Connection limited"
        case .unsupported: return "Unsupported"
        case .disconnected: return "Disconnected"
        }
    }

    public var symbolName: String {
        switch self {
        case .waitingForDevice: return "hourglass"
        case .physicalDeviceDetected: return "cable.connector"
        case .usbEnumerated: return "list.bullet.rectangle"
        case .familyIdentified: return "person.text.rectangle"
        case .protocolDiscovered: return "point.3.connected.trianglepath.dotted"
        case .authorizationRequired: return "lock.fill"
        case .pairingAvailable: return "link.badge.plus"
        case .pairingEstablished: return "link"
        case .communicationEstablished: return "arrow.left.arrow.right.circle.fill"
        case .diagnosticsAvailable: return "stethoscope"
        case .connectionLimited: return "exclamationmark.triangle"
        case .unsupported: return "nosign"
        case .disconnected: return "bolt.slash"
        }
    }

    public var needsUserAttention: Bool {
        self == .authorizationRequired || self == .pairingAvailable || self == .connectionLimited
    }
}

public enum NextActionKind: String, Codable, Hashable {
    case none
    case connectDevice
    case useDataCable
    case unlockDevice
    case trustComputer
    case pairDevice
    case enableDeveloperMode
    case installXcode
    case selectXcode
    case refresh
    case runDiagnostics
    case reconnect
}

public struct NextAction: Codable, Hashable {
    public var kind: NextActionKind
    public var title: String
    public var instructions: [String]
    /// True when System Tester can perform the action itself after the user clicks (e.g. start pairing).
    public var performable: Bool

    public init(kind: NextActionKind, title: String, instructions: [String] = [], performable: Bool = false) {
        self.kind = kind
        self.title = title
        self.instructions = instructions
        self.performable = performable
    }

    public static let none = NextAction(kind: .none, title: "No action needed")
}

public enum IntelligenceGroup: String, Codable, CaseIterable, Hashable, Identifiable {
    case overview, hardware, software, connection, authorization, developer, battery, storage
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .software: return "Software"
        case .connection: return "Connection"
        case .authorization: return "Authorization"
        case .developer: return "Developer"
        case .battery: return "Battery"
        case .storage: return "Storage"
        }
    }
}

/// Where a value came from.
public struct FieldSource: Codable, Hashable {
    /// Tool or framework, e.g. "IOKit", "xcrun devicectl list devices", "ideviceinfo (libimobiledevice)".
    public var tool: String
    /// JSON path or registry key inside that tool's output, e.g. "hardwareProperties.productType".
    public var key: String?
    public var provenance: DataProvenance

    public init(tool: String, key: String? = nil, provenance: DataProvenance = .hardware) {
        self.tool = tool
        self.key = key
        self.provenance = provenance
    }

    public var description: String { key.map { "\(tool) · \($0)" } ?? tool }
}

public struct IntelligenceField: Codable, Hashable, Identifiable {
    public var key: String
    public var label: String
    public var group: IntelligenceGroup
    public var value: String?
    public var unavailableReason: String?
    public var source: FieldSource
    /// Identifiers such as UDID, ECID and serial numbers. Redacted in exports by default.
    public var sensitive: Bool
    public var retrievedAt: Date

    public var id: String { key }

    public init(key: String, label: String, group: IntelligenceGroup, value: String?, unavailableReason: String? = nil,
                source: FieldSource, sensitive: Bool = false, retrievedAt: Date = Date()) {
        self.key = key
        self.label = label
        self.group = group
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.unavailableReason = self.value == nil ? (unavailableReason ?? "Not reported by the source.") : nil
        self.source = source
        self.sensitive = sensitive
        self.retrievedAt = retrievedAt
    }

    public static func unavailable(_ key: String, _ label: String, _ group: IntelligenceGroup, reason: String, source: FieldSource) -> IntelligenceField {
        IntelligenceField(key: key, label: label, group: group, value: nil, unavailableReason: reason, source: source)
    }

    public var isAvailable: Bool { value != nil }

    public func displayValue(maskSensitive: Bool) -> String {
        guard let v = value else { return "Unavailable" }
        return sensitive && maskSensitive ? Redactor.maskSerial(v) : v
    }
}

public struct ServiceInfo: Codable, Hashable, Identifiable {
    public var identifier: String
    public var name: String
    public var available: Bool
    public var note: String?
    public var source: FieldSource

    public var id: String { identifier }

    public init(identifier: String, name: String, available: Bool, note: String? = nil, source: FieldSource) {
        self.identifier = identifier
        self.name = name
        self.available = available
        self.note = note
        self.source = source
    }
}

public struct LadderStep: Codable, Hashable, Identifiable {
    public var state: IntelligenceState
    public var reached: Bool
    public var evidence: String?
    public var id: IntelligenceState { state }
}

public struct IntelligenceSnapshot: Codable, Hashable {
    public var deviceID: DeviceIdentifier
    public var providerID: String
    public var family: String
    public var state: IntelligenceState
    public var stateReason: String
    public var nextAction: NextAction
    public var ladder: [LadderStep]
    public var fields: [IntelligenceField]
    public var services: [ServiceInfo]
    public var limitations: [String]
    public var errors: [String]
    /// How the USB device was matched to the higher-level service record, if at all.
    public var correlation: String?
    /// Evidence that data was actually exchanged with the device through a supported protocol.
    public var communicationEvidence: [String]
    /// Evidence of device-side authorization (e.g. an established pairing).
    public var authorizationEvidence: [String]
    public var retrievedAt: Date
    public var provenance: DataProvenance

    public init(deviceID: DeviceIdentifier, providerID: String, family: String, state: IntelligenceState, stateReason: String,
                nextAction: NextAction, ladder: [LadderStep], fields: [IntelligenceField], services: [ServiceInfo] = [],
                limitations: [String] = [], errors: [String] = [], correlation: String? = nil,
                communicationEvidence: [String] = [], authorizationEvidence: [String] = [],
                retrievedAt: Date = Date(), provenance: DataProvenance) {
        self.deviceID = deviceID
        self.providerID = providerID
        self.family = family
        self.state = state
        self.stateReason = stateReason
        self.nextAction = nextAction
        self.ladder = ladder
        self.fields = fields
        self.services = services
        self.limitations = limitations
        self.errors = errors
        self.correlation = correlation
        self.communicationEvidence = communicationEvidence
        self.authorizationEvidence = authorizationEvidence
        self.retrievedAt = retrievedAt
        self.provenance = provenance
    }

    public func field(_ key: String) -> IntelligenceField? { fields.first { $0.key == key } }
    public func value(_ key: String) -> String? { field(key)?.value }
    public func fields(in group: IntelligenceGroup) -> [IntelligenceField] { fields.filter { $0.group == group } }

    /// Copy with sensitive values removed (for exports).
    public func redacted(_ redactor: Redactor = Redactor()) -> IntelligenceSnapshot {
        var copy = self
        copy.fields = fields.map { f in
            var x = f
            if f.sensitive, let v = f.value { x.value = "[REDACTED] (" + Fingerprint.short(v) + ")" }
            else if let v = f.value { x.value = redactor.redact(v) }
            return x
        }
        copy.correlation = correlation.map { redactor.redact($0) }
        copy.errors = redactor.redact(errors)
        copy.communicationEvidence = redactor.redact(communicationEvidence)
        copy.authorizationEvidence = redactor.redact(authorizationEvidence)
        for f in fields where f.sensitive {
            guard let v = f.value else { continue }
            copy.correlation = copy.correlation?.replacingOccurrences(of: v, with: "[REDACTED]")
            copy.communicationEvidence = copy.communicationEvidence.map { $0.replacingOccurrences(of: v, with: "[REDACTED]") }
            copy.errors = copy.errors.map { $0.replacingOccurrences(of: v, with: "[REDACTED]") }
        }
        return copy
    }

    public static func ladder(reaching evidence: [IntelligenceState: String]) -> [LadderStep] {
        IntelligenceState.progression.map { LadderStep(state: $0, reached: evidence[$0] != nil, evidence: evidence[$0]) }
    }
}

public enum ActionOutcome: Hashable {
    case completed(String)
    case failed(String)
    case notPerformable(String)

    public var message: String {
        switch self {
        case .completed(let m), .failed(let m), .notPerformable(let m): return m
        }
    }
    public var succeeded: Bool { if case .completed = self { return true }; return false }
}

/// A device-family adapter that can retrieve information from, and evaluate, a family of systems.
public protocol DeviceIntelligenceProvider: AnyObject {
    var providerID: String { get }
    var familyName: String { get }
    var supportedProtocols: [String] { get }
    /// Names of interface extensions the UI may enable (e.g. "apple.device-illustration").
    var interfaceExtensions: [String] { get }

    func recognizes(_ device: DiscoveredDevice, identification: IdentificationResult) -> Bool
    func snapshot(for device: DiscoveredDevice, identification: IdentificationResult) async -> IntelligenceSnapshot
    func perform(_ action: NextActionKind, for device: DiscoveredDevice, identification: IdentificationResult) async -> ActionOutcome
    func diagnosticTests() -> [DiagnosticTest]
}

/// Device-family adapters that are designed but not implemented. Listed so the UI is honest
/// about what is and is not supported.
public struct PlannedDeviceFamily: Hashable, Identifiable {
    public var id: String
    public var name: String
    public var category: DeviceCategory
    public var intendedInterfaces: [String]
    public var status: String

    public static let all: [PlannedDeviceFamily] = [
        .init(id: "android", name: "Android", category: .smartphone, intendedInterfaces: ["ADB (user-approved RSA key)", "MTP"], status: "Planned — no adapter yet"),
        .init(id: "playstation", name: "PlayStation", category: .playStation, intendedInterfaces: ["Controller HID", "Documented network presence"], status: "Research only"),
        .init(id: "xbox", name: "Xbox", category: .xbox, intendedInterfaces: ["Controller descriptors", "Device Portal (owner-enabled)"], status: "Research only"),
        .init(id: "nintendo", name: "Nintendo", category: .nintendo, intendedInterfaces: ["Controller HID"], status: "Research only"),
        .init(id: "smart-appliances", name: "Smart appliances", category: .smartHome, intendedInterfaces: ["Matter", "Manufacturer APIs"], status: "Planned"),
        .init(id: "network", name: "Network equipment", category: .networkEquipment, intendedInterfaces: ["DNS-SD", "SNMP (read-only)"], status: "Planned"),
        .init(id: "microcontrollers", name: "Microcontrollers", category: .microcontroller, intendedInterfaces: ["CDC ACM serial (authorised)"], status: "Planned (milestone 2)"),
        .init(id: "robotics", name: "Robotics", category: .robotics, intendedInterfaces: ["Serial", "ROS 2 (network)"], status: "Planned"),
        .init(id: "storage", name: "Storage devices", category: .storage, intendedInterfaces: ["SMART via supported bridges"], status: "Partial (host-side only)"),
        .init(id: "industrial", name: "Industrial equipment", category: .industrial, intendedInterfaces: ["Modbus (read-only, authorised)"], status: "Planned")
    ]
}

/// Routes devices to the first provider that recognises them and keeps the latest snapshot + timeline.
public final class DeviceIntelligenceEngine {
    public private(set) var providers: [DeviceIntelligenceProvider]
    public private(set) var snapshots: [DeviceIdentifier: IntelligenceSnapshot] = [:]
    public private(set) var timelines: [String: [IntelligenceTimelineEntry]] = [:]

    public init(providers: [DeviceIntelligenceProvider]) {
        self.providers = providers
    }

    public func provider(for device: DiscoveredDevice, identification: IdentificationResult) -> DeviceIntelligenceProvider? {
        providers.first { $0.recognizes(device, identification: identification) }
    }

    public func provider(id: String) -> DeviceIntelligenceProvider? { providers.first { $0.providerID == id } }

    @discardableResult
    public func refresh(_ device: DiscoveredDevice, identification: IdentificationResult, key: String) async -> IntelligenceSnapshot? {
        guard let p = provider(for: device, identification: identification) else { return nil }
        let snap = await p.snapshot(for: device, identification: identification)
        record(snap, key: key)
        return snap
    }

    public func record(_ snap: IntelligenceSnapshot, key: String) {
        let previous = snapshots[snap.deviceID]
        snapshots[snap.deviceID] = snap
        if previous?.state != snap.state {
            append(IntelligenceTimelineEntry(at: snap.retrievedAt, kind: .stateChange,
                                             message: "\(previous?.state.displayName ?? "—") → \(snap.state.displayName): \(snap.stateReason)",
                                             provenance: snap.provenance), key: key)
        }
        for e in snap.errors where !(previous?.errors.contains(e) ?? false) {
            append(IntelligenceTimelineEntry(at: snap.retrievedAt, kind: .error, message: e, provenance: snap.provenance), key: key)
        }
    }

    public func markDisconnected(_ id: DeviceIdentifier, key: String, at date: Date = Date()) {
        guard var snap = snapshots[id] else { return }
        let previous = snap.state
        snap.state = .disconnected
        snap.stateReason = "The device left the bus."
        snap.nextAction = NextAction(kind: .reconnect, title: "Reconnect the device", instructions: ["Plug the cable back in. System Tester re-identifies the device and restores its record automatically."])
        snap.communicationEvidence = []
        snap.retrievedAt = date
        snapshots[id] = snap
        append(IntelligenceTimelineEntry(at: date, kind: .disconnect, message: "Disconnected (was \(previous.displayName)).", provenance: snap.provenance), key: key)
    }

    public func append(_ entry: IntelligenceTimelineEntry, key: String) {
        timelines[key, default: []].append(entry)
        if timelines[key]!.count > 400 { timelines[key]!.removeFirst(timelines[key]!.count - 400) }
    }

    public func timeline(key: String) -> [IntelligenceTimelineEntry] { timelines[key] ?? [] }

    public func forget(_ id: DeviceIdentifier) { snapshots[id] = nil }
}

public struct IntelligenceTimelineEntry: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable { case connect, disconnect, reconnect, stateChange, diagnostic, action, error, refresh }
    public var id: UUID
    public var at: Date
    public var kind: Kind
    public var message: String
    public var provenance: DataProvenance

    public init(at: Date = Date(), kind: Kind, message: String, provenance: DataProvenance) {
        self.id = UUID()
        self.at = at
        self.kind = kind
        self.message = message
        self.provenance = provenance
    }
}
