import Foundation

/// Catalogue of host-implemented operations that adapters may reference.
public enum HostOperationCatalog {
    public static func standardTests() -> [DiagnosticTest] {
        [
            PresenceTest(),
            IdentificationTest(),
            InterfaceInventoryTest(),
            ProtocolValidationTest(),
            LinkSpeedTest(),
            FirmwareInfoTest(),
            StorageInfoTest(),
            ThunderboltSwitchTest(),
            EnumerationErrorReport(),
            RegistryLatencyTest(),
            PresenceStabilityTest(extended: false),
            PresenceStabilityTest(extended: true),
            ConsoleInterfaceResearchTest(),
            SyntheticFaultInjectionTest()
        ]
    }

    /// Every host operation adapters may reference, including device-family operations whose
    /// implementations need a provider (e.g. the Apple Device Intelligence Adapter).
    public static let descriptors: [DiagnosticTestDescriptor] = standardTests().map(\.descriptor) + AppleDiagnostics.descriptors
    public static var ids: Set<String> { Set(descriptors.map(\.id)) }
    public static func descriptor(_ id: String) -> DiagnosticTestDescriptor? { descriptors.first { $0.id == id } }

    /// Categories from the specification that have no host test yet (shown honestly in the UI).
    public static var uncoveredCategories: [DiagnosticCategory] {
        let covered = Set(descriptors.map(\.category))
        return DiagnosticCategory.allCases.filter { !covered.contains($0) }
    }
}

/// Shared diagnostic framework. Runs tests sequentially, enforces authorisation,
/// converts disconnections into aborted results and records an audit trail.
public final class DiagnosticEngine {
    public let tests: [DiagnosticTest]
    public var auditLog: AuditLog?
    public var redactor: Redactor

    public init(tests: [DiagnosticTest] = HostOperationCatalog.standardTests(), auditLog: AuditLog? = nil, redactor: Redactor = Redactor()) {
        self.tests = tests
        self.auditLog = auditLog
        self.redactor = redactor
    }

    public func test(id: String) -> DiagnosticTest? { tests.first { $0.descriptor.id == id } }

    public enum Applicability: Equatable {
        case applicable
        case missingCapabilities([DeviceCapability])
        case wrongCategory
    }

    public func applicability(of d: DiagnosticTestDescriptor, device: DiscoveredDevice, identification: IdentificationResult) -> Applicability {
        if !d.categories.isEmpty && !d.categories.contains(identification.category) { return .wrongCategory }
        if !d.vendorIDs.isEmpty && !(device.usb?.vendorID.map { d.vendorIDs.contains($0) } ?? false) { return .wrongCategory }
        let caps = DeviceCapability.derive(for: device)
        let missing = d.requiredCapabilities.filter { !caps.contains($0) }
        return missing.isEmpty ? .applicable : .missingCapabilities(missing)
    }

    public func applicableTests(for device: DiscoveredDevice, identification: IdentificationResult) -> [DiagnosticTestDescriptor] {
        tests.map(\.descriptor).filter { applicability(of: $0, device: device, identification: identification) == .applicable }
    }

    /// The default read-only suite for a device.
    public func defaultSuite(for device: DiscoveredDevice, identification: IdentificationResult) -> [String] {
        applicableTests(for: device, identification: identification).filter { $0.impact == .readOnly }.map(\.id)
    }

    public func run(testIDs: [String], context: DiagnosticContext, authorization: DiagnosticAuthorization = .readOnly,
                    progress: ((DiagnosticResult) -> Void)? = nil) async -> DiagnosticRun {
        let runStart = Date()
        var results: [DiagnosticResult] = []
        var disconnected = false

        for testID in testIDs {
            let started = Date()
            func result(_ name: String, _ category: DiagnosticCategory, _ impact: OperationImpact, _ out: DiagnosticTestOutput) -> DiagnosticResult {
                DiagnosticResult(
                    id: UUID(), testID: testID, testName: name, category: category, impact: impact,
                    targetDeviceID: context.device.id, targetDeviceName: context.device.displayName, targetDeviceKey: context.deviceKey,
                    startedAt: started, finishedAt: Date(), outcome: out.outcome, summary: out.summary,
                    measurements: out.measurements, evidence: out.evidence, limitations: out.limitations, errors: out.errors,
                    recommendedNextAction: out.recommendedNextAction, provenance: context.device.provenance)
            }

            guard let test = test(id: testID) else {
                let r = result(testID, .errorReporting, .readOnly,
                               DiagnosticTestOutput(outcome: .error, summary: "Unknown test \(testID).", errors: ["No host operation with this ID."]))
                results.append(r); progress?(r)
                continue
            }
            let d = test.descriptor

            if disconnected {
                let r = result(d.name, d.category, d.impact, DiagnosticTestOutput(
                    outcome: .aborted, summary: "Not run: the device disconnected earlier in this run.",
                    errors: [DiagnosticError.deviceDisconnected(context.device.id).description],
                    recommendedNextAction: "Reconnect the device and run the diagnostics again."))
                results.append(r); progress?(r)
                continue
            }

            guard authorization.permits(d) else {
                let reason = d.impact == .extended
                    ? "Extended tests need confirmation before they run."
                    : "State-changing operations need explicit authorisation for this device."
                audit(d, context: context, decision: "denied", outcome: .skipped)
                let r = result(d.name, d.category, d.impact, DiagnosticTestOutput(
                    outcome: .skipped, summary: "Skipped: \(reason)",
                    limitations: [d.effects ?? d.impact.displayName],
                    recommendedNextAction: "Authorise the test explicitly if you accept its effects."))
                results.append(r); progress?(r)
                continue
            }

            switch applicability(of: d, device: context.device, identification: context.identification) {
            case .wrongCategory:
                let r = result(d.name, d.category, d.impact, DiagnosticTestOutput(
                    outcome: .notSupported, summary: "Not applicable to \(context.identification.category.displayName) devices."))
                results.append(r); progress?(r)
                continue
            case .missingCapabilities(let missing):
                let r = result(d.name, d.category, d.impact, DiagnosticTestOutput(
                    outcome: .notSupported,
                    summary: "The device does not expose: \(missing.map(\.displayName).joined(separator: ", ")).",
                    limitations: ["Recorded as compatibility evidence."]))
                results.append(r); progress?(r)
                continue
            case .applicable:
                break
            }

            let out: DiagnosticTestOutput
            do {
                out = try await test.run(context)
            } catch let error as DiagnosticError {
                if case .deviceDisconnected = error { disconnected = true }
                out = DiagnosticTestOutput(
                    outcome: .aborted, summary: error.description, errors: [error.description],
                    recommendedNextAction: "Reconnect the device and re-run. Repeated disconnects suggest a cable, port or power problem.")
            } catch is CancellationError {
                out = DiagnosticTestOutput(outcome: .aborted, summary: "Cancelled.", errors: ["Cancelled by the user."])
            } catch {
                out = DiagnosticTestOutput(outcome: .error, summary: "The test failed to run.", errors: [String(describing: error)])
            }
            audit(d, context: context, decision: "permitted", outcome: out.outcome)
            let r = result(d.name, d.category, d.impact, out)
            results.append(r); progress?(r)
        }

        return DiagnosticRun(id: UUID(), deviceID: context.device.id, deviceName: context.device.displayName,
                             deviceKey: context.deviceKey, provenance: context.device.provenance,
                             startedAt: runStart, finishedAt: Date(), results: results)
    }

    private func audit(_ d: DiagnosticTestDescriptor, context: DiagnosticContext, decision: String, outcome: DiagnosticOutcome) {
        auditLog?.record(AuditEntry(
            actor: "user", operation: d.id, impact: d.impact,
            target: redactor.redact(context.device.displayName), targetKey: context.deviceKey,
            decision: decision, outcome: outcome.rawValue, provenance: context.device.provenance))
    }
}
