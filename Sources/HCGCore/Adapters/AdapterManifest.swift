import Foundation

// MARK: - Hardware Adapter SDK: manifest types
//
// An adapter is described by a typed, validated manifest. Adapters imported from
// outside System Tester are *declarative*: they can only compose operations that
// the host already implements (see `HostOperationCatalog`), with narrowly scoped
// permissions. They can never ship executable code into the host process.

public struct SemanticVersion: Codable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        self.init(a, b, c)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (l: SemanticVersion, r: SemanticVersion) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = SemanticVersion(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "\"\(s)\" is not a semantic version (major.minor.patch)")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Narrowly scoped permissions an adapter may request. Privileged permissions
/// always require an explicit, per-device user grant.
public enum AdapterPermission: String, Codable, CaseIterable, Hashable {
    case readDeviceDescriptors
    case readStorageMetadata
    case readSerialPortList
    case readHIDDescriptors
    case readThunderboltRegistry
    case openSerialPort
    case localNetworkDiscovery
    case networkConnect
    case bluetoothScan
    case useStoredCredential
    case changeDeviceConfiguration

    public var isPrivileged: Bool {
        switch self {
        case .openSerialPort, .networkConnect, .useStoredCredential, .changeDeviceConfiguration: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .readDeviceDescriptors: return "Read device descriptors"
        case .readStorageMetadata: return "Read storage metadata (no file access)"
        case .readSerialPortList: return "List serial ports"
        case .readHIDDescriptors: return "Read HID descriptors (no input capture)"
        case .readThunderboltRegistry: return "Read Thunderbolt registry"
        case .openSerialPort: return "Open a serial port"
        case .localNetworkDiscovery: return "Discover local-network services"
        case .networkConnect: return "Connect to a network host"
        case .bluetoothScan: return "Scan for Bluetooth devices"
        case .useStoredCredential: return "Use a stored credential"
        case .changeDeviceConfiguration: return "Change device configuration"
        }
    }
}

/// How disruptive an operation can be.
public enum OperationImpact: String, Codable, CaseIterable, Hashable, Comparable {
    /// Observes host-side state only. Runs without confirmation.
    case readOnly
    /// Read-only but long-running or repeated; needs a single confirmation.
    case extended
    /// May change device state. Needs explicit, per-device, per-operation authorisation.
    case stateChanging

    public var displayName: String {
        switch self {
        case .readOnly: return "Read-only"
        case .extended: return "Extended (read-only, long-running)"
        case .stateChanging: return "State-changing — requires authorisation"
        }
    }

    private var rank: Int { switch self { case .readOnly: return 0; case .extended: return 1; case .stateChanging: return 2 } }
    public static func < (l: OperationImpact, r: OperationImpact) -> Bool { l.rank < r.rank }
}

public enum AdapterExecutionModel: String, Codable, Hashable {
    /// Composes host-implemented operations only. The only model allowed for imported adapters.
    case declarative
    /// Compiled into System Tester by Hakmi Capital Group. Cannot be imported.
    case builtIn
}

public struct DiagnosticOperationDescriptor: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// The host-implemented operation this maps to (see `HostOperationCatalog`).
    public var hostOperation: String
    public var category: DiagnosticCategory
    public var impact: OperationImpact
    public var requiredCapabilities: [DeviceCapability]
    public var summary: String
    /// Plain-language description of effects; mandatory for non read-only operations.
    public var effects: String?
    public var timeoutSeconds: Double

    public init(id: String, name: String, hostOperation: String, category: DiagnosticCategory, impact: OperationImpact = .readOnly,
                requiredCapabilities: [DeviceCapability] = [], summary: String, effects: String? = nil, timeoutSeconds: Double = 30) {
        self.id = id
        self.name = name
        self.hostOperation = hostOperation
        self.category = category
        self.impact = impact
        self.requiredCapabilities = requiredCapabilities
        self.summary = summary
        self.effects = effects
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum ConfigFieldType: String, Codable, Hashable {
    case string
    case integer
    case boolean
    case choice
}

public struct ConfigField: Codable, Hashable, Identifiable {
    public var key: String
    public var label: String
    public var type: ConfigFieldType
    public var required: Bool
    public var defaultValue: String?
    public var choices: [String]?
    public var minimum: Int?
    public var maximum: Int?
    /// Secret values are stored in the Keychain, never in manifests or logs, and may not have defaults.
    public var secret: Bool

    public var id: String { key }

    public init(key: String, label: String, type: ConfigFieldType, required: Bool = false, defaultValue: String? = nil,
                choices: [String]? = nil, minimum: Int? = nil, maximum: Int? = nil, secret: Bool = false) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
        self.secret = secret
    }

    /// Validates one value; returns a problem description or nil.
    public func problem(with value: String?) -> String? {
        guard let value = value, !value.isEmpty else {
            return required ? "\(key) is required" : nil
        }
        switch type {
        case .string:
            return value.count > 1024 ? "\(key) is longer than 1024 characters" : nil
        case .integer:
            guard let n = Int(value) else { return "\(key) must be an integer" }
            if let lo = minimum, n < lo { return "\(key) must be ≥ \(lo)" }
            if let hi = maximum, n > hi { return "\(key) must be ≤ \(hi)" }
            return nil
        case .boolean:
            return ["true", "false"].contains(value) ? nil : "\(key) must be true or false"
        case .choice:
            return (choices ?? []).contains(value) ? nil : "\(key) must be one of \((choices ?? []).joined(separator: ", "))"
        }
    }
}

public struct ConfigurationSchema: Codable, Hashable {
    public var fields: [ConfigField]
    public init(fields: [ConfigField] = []) { self.fields = fields }

    public func validate(_ values: [String: String]) -> [String] {
        var problems = fields.compactMap { $0.problem(with: values[$0.key] ?? $0.defaultValue) }
        let known = Set(fields.map(\.key))
        for key in values.keys.sorted() where !known.contains(key) {
            problems.append("\(key) is not a configuration field of this adapter")
        }
        return problems
    }
}

public struct DriverRequirement: Codable, Hashable {
    public var name: String
    /// True when macOS provides the driver itself.
    public var providedByMacOS: Bool
    public var notes: String

    public init(name: String, providedByMacOS: Bool, notes: String = "") {
        self.name = name
        self.providedByMacOS = providedByMacOS
        self.notes = notes
    }
}

public struct CompatibilityRequirements: Codable, Hashable {
    public var platforms: [String]
    public var minimumHostVersion: SemanticVersion
    public var minimumOSVersion: String?

    public init(platforms: [String] = ["macOS"], minimumHostVersion: SemanticVersion = SemanticVersion(0, 1, 0), minimumOSVersion: String? = "14.0") {
        self.platforms = platforms
        self.minimumHostVersion = minimumHostVersion
        self.minimumOSVersion = minimumOSVersion
    }
}

public enum LifecycleStage: String, Codable, CaseIterable, Hashable {
    case discover
    case identify
    case authorize
    case open
    case diagnose
    case close
}

public struct ConnectionLifecycle: Codable, Hashable {
    public var stages: [LifecycleStage]
    public var requiresExplicitAuthorization: Bool
    public var closeOnDisconnect: Bool

    public init(stages: [LifecycleStage] = [.discover, .identify, .diagnose], requiresExplicitAuthorization: Bool = false,
                closeOnDisconnect: Bool = true) {
        self.stages = stages
        self.requiresExplicitAuthorization = requiresExplicitAuthorization
        self.closeOnDisconnect = closeOnDisconnect
    }
}

public struct AdapterErrorDescriptor: Codable, Hashable {
    public var code: String
    public var meaning: String
    public var recovery: String

    public init(code: String, meaning: String, recovery: String) {
        self.code = code
        self.meaning = meaning
        self.recovery = recovery
    }
}

public struct HealthCheckDescriptor: Codable, Hashable {
    public var id: String
    public var hostOperation: String
    public var intervalSeconds: Double

    public init(id: String, hostOperation: String, intervalSeconds: Double) {
        self.id = id
        self.hostOperation = hostOperation
        self.intervalSeconds = intervalSeconds
    }
}

/// The adapter manifest (`hcg.adapter-manifest/1`).
public struct AdapterManifest: Codable, Hashable, Identifiable {
    public static let currentSchema = "hcg.adapter-manifest/1"

    public var schema: String
    public var id: String
    public var name: String
    public var version: SemanticVersion
    public var publisher: String
    public var summary: String
    public var execution: AdapterExecutionModel
    public var deviceFamilies: [DeviceCategory]
    public var connectionTypes: [ConnectionType]
    public var protocols: [String]
    public var match: DeviceMatchRules
    public var hardwareRequirements: [String]
    public var driverRequirements: [DriverRequirement]
    public var permissions: [AdapterPermission]
    public var operations: [DiagnosticOperationDescriptor]
    public var configuration: ConfigurationSchema
    public var compatibility: CompatibilityRequirements
    public var lifecycle: ConnectionLifecycle
    public var errors: [AdapterErrorDescriptor]
    public var healthChecks: [HealthCheckDescriptor]
    /// Optional device profiles contributed to the identification engine.
    public var profiles: [DeviceProfile]
    public var experimental: Bool

    public init(schema: String = AdapterManifest.currentSchema, id: String, name: String, version: SemanticVersion, publisher: String,
                summary: String, execution: AdapterExecutionModel = .declarative, deviceFamilies: [DeviceCategory],
                connectionTypes: [ConnectionType], protocols: [String], match: DeviceMatchRules,
                hardwareRequirements: [String] = [], driverRequirements: [DriverRequirement] = [],
                permissions: [AdapterPermission], operations: [DiagnosticOperationDescriptor],
                configuration: ConfigurationSchema = ConfigurationSchema(), compatibility: CompatibilityRequirements = CompatibilityRequirements(),
                lifecycle: ConnectionLifecycle = ConnectionLifecycle(), errors: [AdapterErrorDescriptor] = [],
                healthChecks: [HealthCheckDescriptor] = [], profiles: [DeviceProfile] = [], experimental: Bool = false) {
        self.schema = schema
        self.id = id
        self.name = name
        self.version = version
        self.publisher = publisher
        self.summary = summary
        self.execution = execution
        self.deviceFamilies = deviceFamilies
        self.connectionTypes = connectionTypes
        self.protocols = protocols
        self.match = match
        self.hardwareRequirements = hardwareRequirements
        self.driverRequirements = driverRequirements
        self.permissions = permissions
        self.operations = operations
        self.configuration = configuration
        self.compatibility = compatibility
        self.lifecycle = lifecycle
        self.errors = errors
        self.healthChecks = healthChecks
        self.profiles = profiles
        self.experimental = experimental
    }

    public static func decode(_ data: Data) throws -> AdapterManifest {
        try JSONDecoder().decode(AdapterManifest.self, from: data)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
}
