import Foundation

public enum AdapterTrust: String, Codable, Hashable {
    /// Compiled into System Tester by Hakmi Capital Group.
    case firstParty
    /// Imported declarative adapter the user reviewed and approved.
    case userApproved
    /// Imported but not reviewed. Never executed.
    case untrusted

    public var displayName: String {
        switch self {
        case .firstParty: return "First-party"
        case .userApproved: return "Approved by you"
        case .untrusted: return "Untrusted — not executed"
        }
    }
}

public struct RegisteredAdapter: Codable, Hashable, Identifiable {
    public var manifest: AdapterManifest
    public var origin: AdapterOrigin
    public var trust: AdapterTrust
    public var enabled: Bool
    public var registeredAt: Date
    public var validationIssues: [ValidationIssue]

    public var id: String { manifest.id }
}

public enum AdapterCompatibilityStatus: String, Codable, Hashable {
    case compatible
    case partial
    case incompatible
    case notExecutable
}

public struct AdapterCompatibility: Codable, Hashable, Identifiable {
    public var adapterID: String
    public var adapterName: String
    public var status: AdapterCompatibilityStatus
    public var reasons: [String]
    public var availableOperations: [DiagnosticOperationDescriptor]
    public var unavailableOperations: [String]

    public var id: String { adapterID }
}

public enum AdapterRegistryError: Error, Equatable, CustomStringConvertible {
    case invalidManifest([ValidationIssue])
    case duplicateFirstParty(String)
    case versionDowngrade(current: SemanticVersion, attempted: SemanticVersion)
    case notFound(String)
    case cannotApproveInvalid

    public var description: String {
        switch self {
        case .invalidManifest(let issues): return "Invalid manifest: " + issues.filter { $0.severity == .error }.map(\.description).joined(separator: "; ")
        case .duplicateFirstParty(let id): return "\(id) is a first-party adapter and cannot be replaced."
        case .versionDowngrade(let c, let a): return "Refusing to replace version \(c) with older version \(a)."
        case .notFound(let id): return "Adapter \(id) is not registered."
        case .cannotApproveInvalid: return "An adapter with validation errors cannot be approved."
        }
    }
}

/// Holds every adapter known to System Tester. Imported adapters start untrusted
/// and disabled; they are never executed until the user approves them, and even
/// then they can only invoke host-implemented operations.
public final class AdapterRegistry {
    public private(set) var adapters: [RegisteredAdapter] = []

    public init(builtIns: [AdapterManifest] = BuiltInAdapters.all) {
        for m in builtIns {
            adapters.append(RegisteredAdapter(manifest: m, origin: .builtIn, trust: .firstParty, enabled: true,
                                              registeredAt: Date(), validationIssues: ManifestValidator.validate(m, origin: .builtIn)))
        }
    }

    public func adapter(_ id: String) -> RegisteredAdapter? { adapters.first { $0.manifest.id == id } }

    /// Imports a manifest from JSON. The adapter is stored untrusted and disabled.
    @discardableResult
    public func importManifest(data: Data, origin: AdapterOrigin = .imported) throws -> RegisteredAdapter {
        let manifest: AdapterManifest
        do {
            manifest = try AdapterManifest.decode(data)
        } catch {
            throw AdapterRegistryError.invalidManifest([ValidationIssue(.error, "$", "Not a valid \(AdapterManifest.currentSchema) document: \(error)")])
        }
        return try register(manifest, origin: origin)
    }

    @discardableResult
    public func register(_ manifest: AdapterManifest, origin: AdapterOrigin) throws -> RegisteredAdapter {
        let issues = ManifestValidator.validate(manifest, origin: origin)
        if issues.contains(where: { $0.severity == .error }) { throw AdapterRegistryError.invalidManifest(issues) }
        if let existing = adapter(manifest.id) {
            if existing.origin == .builtIn && origin != .builtIn { throw AdapterRegistryError.duplicateFirstParty(manifest.id) }
            if manifest.version < existing.manifest.version {
                throw AdapterRegistryError.versionDowngrade(current: existing.manifest.version, attempted: manifest.version)
            }
            adapters.removeAll { $0.manifest.id == manifest.id }
        }
        let entry = RegisteredAdapter(
            manifest: manifest, origin: origin,
            trust: origin == .builtIn ? .firstParty : .untrusted,
            enabled: origin == .builtIn,
            registeredAt: Date(), validationIssues: issues)
        adapters.append(entry)
        return entry
    }

    /// The user reviewed the manifest and approves it. It becomes enabled but stays declarative.
    public func approve(_ id: String) throws {
        guard let index = adapters.firstIndex(where: { $0.manifest.id == id }) else { throw AdapterRegistryError.notFound(id) }
        guard !adapters[index].validationIssues.contains(where: { $0.severity == .error }) else { throw AdapterRegistryError.cannotApproveInvalid }
        if adapters[index].trust == .untrusted { adapters[index].trust = .userApproved }
        adapters[index].enabled = true
    }

    public func setEnabled(_ id: String, _ enabled: Bool) throws {
        guard let index = adapters.firstIndex(where: { $0.manifest.id == id }) else { throw AdapterRegistryError.notFound(id) }
        if enabled && adapters[index].trust == .untrusted { try approve(id); return }
        adapters[index].enabled = enabled
    }

    public func remove(_ id: String) throws {
        guard let a = adapter(id) else { throw AdapterRegistryError.notFound(id) }
        if a.origin == .builtIn { throw AdapterRegistryError.duplicateFirstParty(id) }
        adapters.removeAll { $0.manifest.id == id }
    }

    /// Profiles contributed by enabled, trusted adapters.
    public var contributedProfiles: [DeviceProfile] {
        adapters.filter { $0.enabled && $0.trust != .untrusted }.flatMap(\.manifest.profiles)
    }

    /// Evaluates every adapter against a device.
    public func compatibility(for device: DiscoveredDevice, identification: IdentificationResult) -> [AdapterCompatibility] {
        let caps = DeviceCapability.derive(for: device)
        return adapters.compactMap { entry -> AdapterCompatibility? in
            let m = entry.manifest
            var reasons: [String] = []
            let familyOK = m.deviceFamilies.contains(identification.category)
            let connectionOK = m.connectionTypes.contains(device.connectionType)
            let recommended = identification.recommendedAdapters.contains(m.id)
            guard connectionOK else { return nil }
            let matched: (score: Double, evidence: [String])?
            if m.match.isEmpty {
                matched = familyOK ? (0, ["Applies to \(identification.category.displayName) devices over \(device.connectionType.displayName)"]) : nil
            } else {
                matched = m.match.evaluate(device)
            }
            guard matched != nil || recommended else { return nil }
            reasons += matched?.evidence ?? []
            if recommended { reasons.append("Recommended by the device profile") }

            if !entry.enabled || entry.trust == .untrusted {
                return AdapterCompatibility(adapterID: m.id, adapterName: m.name, status: .notExecutable,
                                            reasons: reasons + [entry.trust == .untrusted ? "Imported adapter not yet approved." : "Adapter is disabled."],
                                            availableOperations: [], unavailableOperations: m.operations.map(\.name))
            }
            var available: [DiagnosticOperationDescriptor] = []
            var unavailable: [String] = []
            for op in m.operations {
                let hostCaps = HostOperationCatalog.descriptor(op.hostOperation)?.requiredCapabilities ?? []
                let need = Set(op.requiredCapabilities + hostCaps)
                if need.isSubset(of: caps) { available.append(op) } else {
                    unavailable.append("\(op.name) (needs \(need.subtracting(caps).map(\.displayName).sorted().joined(separator: ", ")))")
                }
            }
            if !m.driverRequirements.filter({ !$0.providedByMacOS }).isEmpty {
                reasons.append("Requires a driver that macOS does not provide.")
            }
            if !m.hardwareRequirements.isEmpty {
                reasons.append("Hardware requirements: " + m.hardwareRequirements.joined(separator: "; "))
            }
            let status: AdapterCompatibilityStatus = available.isEmpty ? (m.operations.isEmpty ? .partial : .incompatible)
                : (unavailable.isEmpty ? .compatible : .partial)
            return AdapterCompatibility(adapterID: m.id, adapterName: m.name, status: status, reasons: reasons,
                                        availableOperations: available, unavailableOperations: unavailable)
        }
    }
}
