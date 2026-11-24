import Foundation

public enum DiagnosticCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case connectionHealth
    case deviceIdentification
    case interfaceAvailability
    case communicationLatency
    case protocolValidation
    case connectionStability
    case dataTransferPerformance
    case storageInformation
    case hardwareHealth
    case firmwareInformation
    case errorReporting
    case deviceSpecific

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .connectionHealth: return "Connection health"
        case .deviceIdentification: return "Device identification"
        case .interfaceAvailability: return "Interface availability"
        case .communicationLatency: return "Communication latency"
        case .protocolValidation: return "Protocol validation"
        case .connectionStability: return "Connection stability"
        case .dataTransferPerformance: return "Data-transfer performance"
        case .storageInformation: return "Storage information"
        case .hardwareHealth: return "Hardware health"
        case .firmwareInformation: return "Firmware information"
        case .errorReporting: return "Error reporting"
        case .deviceSpecific: return "Device-specific"
        }
    }

    public var symbolName: String {
        switch self {
        case .connectionHealth: return "heart.text.square"
        case .deviceIdentification: return "person.text.rectangle"
        case .interfaceAvailability: return "square.stack.3d.up"
        case .communicationLatency: return "timer"
        case .protocolValidation: return "checkmark.seal"
        case .connectionStability: return "waveform.path.ecg"
        case .dataTransferPerformance: return "speedometer"
        case .storageInformation: return "externaldrive"
        case .hardwareHealth: return "cross.case"
        case .firmwareInformation: return "memorychip"
        case .errorReporting: return "exclamationmark.triangle"
        case .deviceSpecific: return "puzzlepiece"
        }
    }
}

public enum DiagnosticOutcome: String, Codable, CaseIterable, Hashable {
    case passed
    case warning
    case failed
    case notSupported
    case skipped
    case aborted
    case error

    public var displayName: String {
        switch self {
        case .passed: return "Passed"
        case .warning: return "Warning"
        case .failed: return "Failed"
        case .notSupported: return "Not supported"
        case .skipped: return "Skipped"
        case .aborted: return "Aborted"
        case .error: return "Error"
        }
    }

    public var severityRank: Int {
        switch self {
        case .passed: return 0
        case .notSupported, .skipped: return 1
        case .warning: return 2
        case .aborted: return 3
        case .failed, .error: return 4
        }
    }
}

public struct DiagnosticMeasurement: Codable, Hashable, Identifiable {
    public var name: String
    public var value: Double
    public var unit: String
    public var provenance: DataProvenance

    public var id: String { name }

    public init(name: String, value: Double, unit: String, provenance: DataProvenance) {
        self.name = name
        self.value = value
        self.unit = unit
        self.provenance = provenance
    }

    public var formatted: String {
        let rounded = (value * 1000).rounded() / 1000
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return "\(text) \(unit)"
    }
}

public struct DiagnosticTestDescriptor: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var category: DiagnosticCategory
    public var impact: OperationImpact
    public var summary: String
    public var effects: String?
    public var requiredCapabilities: [DeviceCapability]
    /// Device categories the test is limited to (empty = any).
    public var categories: [DeviceCategory]
    public var estimatedDurationSeconds: Double

    public init(id: String, name: String, category: DiagnosticCategory, impact: OperationImpact = .readOnly, summary: String,
                effects: String? = nil, requiredCapabilities: [DeviceCapability] = [], categories: [DeviceCategory] = [],
                estimatedDurationSeconds: Double = 0.1) {
        self.id = id
        self.name = name
        self.category = category
        self.impact = impact
        self.summary = summary
        self.effects = effects
        self.requiredCapabilities = requiredCapabilities
        self.categories = categories
        self.estimatedDurationSeconds = estimatedDurationSeconds
    }
}

/// One executed diagnostic test. Every field required by the specification is mandatory.
public struct DiagnosticResult: Codable, Hashable, Identifiable {
    public var id: UUID
    public var testID: String
    public var testName: String
    public var category: DiagnosticCategory
    public var impact: OperationImpact
    public var targetDeviceID: DeviceIdentifier
    public var targetDeviceName: String
    public var targetDeviceKey: String
    public var startedAt: Date
    public var finishedAt: Date
    public var outcome: DiagnosticOutcome
    public var summary: String
    public var measurements: [DiagnosticMeasurement]
    public var evidence: [String]
    public var limitations: [String]
    public var errors: [String]
    public var recommendedNextAction: String
    public var provenance: DataProvenance

    public var durationSeconds: Double { finishedAt.timeIntervalSince(startedAt) }
}

public struct DiagnosticTestOutput {
    public var outcome: DiagnosticOutcome
    public var summary: String
    public var measurements: [DiagnosticMeasurement]
    public var evidence: [String]
    public var limitations: [String]
    public var errors: [String]
    public var recommendedNextAction: String

    public init(outcome: DiagnosticOutcome, summary: String, measurements: [DiagnosticMeasurement] = [], evidence: [String] = [],
                limitations: [String] = [], errors: [String] = [], recommendedNextAction: String = "No action needed.") {
        self.outcome = outcome
        self.summary = summary
        self.measurements = measurements
        self.evidence = evidence
        self.limitations = limitations
        self.errors = errors
        self.recommendedNextAction = recommendedNextAction
    }
}

public enum DiagnosticError: Error, Equatable, CustomStringConvertible {
    case deviceDisconnected(DeviceIdentifier)
    case timedOut(Double)
    case cancelled

    public var description: String {
        switch self {
        case .deviceDisconnected(let id): return "Device \(id) disconnected during the test."
        case .timedOut(let s): return "The test exceeded its \(Int(s)) s time limit."
        case .cancelled: return "The test was cancelled."
        }
    }
}

/// Re-reads a device from the backend that discovered it.
public protocol DeviceProbe: AnyObject {
    /// Returns the current observation, or nil when the device is no longer present.
    func refresh(_ id: DeviceIdentifier) -> DiscoveredDevice?
}

public struct DiagnosticContext {
    public var device: DiscoveredDevice
    public var identification: IdentificationResult
    public var probe: DeviceProbe
    public var deviceKey: String
    /// Injectable sleep so long-running tests are fast in unit tests.
    public var sleep: (TimeInterval) async throws -> Void
    /// Monotonic clock in seconds.
    public var monotonicSeconds: () -> Double

    public init(device: DiscoveredDevice, identification: IdentificationResult, probe: DeviceProbe, deviceKey: String? = nil,
                sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) },
                monotonicSeconds: @escaping () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }) {
        self.device = device
        self.identification = identification
        self.probe = probe
        self.deviceKey = deviceKey ?? device.stableKey()
        self.sleep = sleep
        self.monotonicSeconds = monotonicSeconds
    }

    public var capabilities: Set<DeviceCapability> { DeviceCapability.derive(for: device) }

    /// Re-reads the device or throws `deviceDisconnected`.
    public func requirePresent() throws -> DiscoveredDevice {
        guard let d = probe.refresh(device.id) else { throw DiagnosticError.deviceDisconnected(device.id) }
        return d
    }

    public func measurement(_ name: String, _ value: Double, _ unit: String) -> DiagnosticMeasurement {
        DiagnosticMeasurement(name: name, value: value, unit: unit, provenance: device.provenance)
    }
}

public protocol DiagnosticTest {
    var descriptor: DiagnosticTestDescriptor { get }
    func run(_ context: DiagnosticContext) async throws -> DiagnosticTestOutput
}

public struct DiagnosticRun: Codable, Hashable, Identifiable {
    public var id: UUID
    public var deviceID: DeviceIdentifier
    public var deviceName: String
    public var deviceKey: String
    public var provenance: DataProvenance
    public var startedAt: Date
    public var finishedAt: Date
    public var results: [DiagnosticResult]

    public var worstOutcome: DiagnosticOutcome {
        results.map(\.outcome).max(by: { $0.severityRank < $1.severityRank }) ?? .skipped
    }

    public func count(_ outcome: DiagnosticOutcome) -> Int { results.filter { $0.outcome == outcome }.count }
}

/// What the user has authorised for one diagnostic run.
public struct DiagnosticAuthorization: Codable, Hashable {
    public var allowExtended: Bool
    /// Test IDs explicitly authorised for state-changing execution on this device.
    public var authorizedStateChangingTests: Set<String>

    public init(allowExtended: Bool = false, authorizedStateChangingTests: Set<String> = []) {
        self.allowExtended = allowExtended
        self.authorizedStateChangingTests = authorizedStateChangingTests
    }

    public static let readOnly = DiagnosticAuthorization()

    public func permits(_ d: DiagnosticTestDescriptor) -> Bool {
        switch d.impact {
        case .readOnly: return true
        case .extended: return allowExtended
        case .stateChanging: return authorizedStateChangingTests.contains(d.id)
        }
    }
}
