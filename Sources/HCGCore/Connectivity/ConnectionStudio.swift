import Foundation

/// The 14 guided steps of the Connection Studio.
public enum StudioStepKind: Int, Codable, CaseIterable, Hashable {
    case identify = 1, methods, recommend, hardware, software, checkDependencies, permissions, instructions, approval, attempt, handshake, capabilities, record, updateRoadmap

    public var title: String {
        switch self {
        case .identify: return "Identify the device"
        case .methods: return "Available connection methods"
        case .recommend: return "Recommended method"
        case .hardware: return "Required hardware"
        case .software: return "Required software"
        case .checkDependencies: return "Check installed dependencies"
        case .permissions: return "Permissions"
        case .instructions: return "Step-by-step instructions"
        case .approval: return "Explicit connection approval"
        case .attempt: return "Attempt the supported connection"
        case .handshake: return "Verify the communication handshake"
        case .capabilities: return "Available diagnostic capabilities"
        case .record: return "Record the actual result"
        case .updateRoadmap: return "Update the development roadmap"
        }
    }
}

public enum StudioStepStatus: String, Codable, Hashable { case done, pending, blocked, notApplicable }

public struct StudioStep: Codable, Hashable, Identifiable {
    public var kind: StudioStepKind
    public var status: StudioStepStatus
    public var lines: [String]
    public var id: Int { kind.rawValue }
}

public struct ConnectionPlan: Codable, Hashable {
    public var profileID: String
    public var method: ConnectionMethod?
    public var steps: [StudioStep]
    public var canAttempt: Bool
    public var blockedReason: String?
    /// What must be developed when no adapter exists.
    public var developmentNeeded: [DevelopmentRequirement]
}

/// Result of a driver's attempt. Drivers must report what actually happened.
public struct ConnectionAttemptResult: Hashable {
    public var outcome: EvidenceOutcome
    public var summary: String
    public var handshake: [String]
    public var capabilities: [String]
    public var errors: [String]
    public var provenance: DataProvenance

    public init(outcome: EvidenceOutcome, summary: String, handshake: [String] = [], capabilities: [String] = [], errors: [String] = [], provenance: DataProvenance) {
        self.outcome = outcome
        self.summary = summary
        self.handshake = handshake
        self.capabilities = capabilities
        self.errors = errors
        self.provenance = provenance
    }
}

public enum ConnectionStudio {
    public static func plan(profile: EncyclopediaProfile, env: RoadmapEnvironment, approved: Bool = false,
                            lastResult: ConnectionAttemptResult? = nil, matchedEndpoint: ObservedEndpoint? = nil) -> ConnectionPlan {
        let methods = profile.connectionMethods
        let allowed = methods.filter { $0.safety != .prohibitedControl }
        func readiness(_ m: ConnectionMethod) -> Int {
            var s = 0
            if let d = m.driverID, env.implementedDrivers.contains(d) { s += 100 }
            s -= m.requiredEquipment.filter { !env.has($0) }.count * 10
            s -= m.requiredSoftware.filter { !env.has($0) }.count * 5
            s += m.source.trustRank
            return s
        }
        let best = allowed.max { readiness($0) < readiness($1) }
        let implemented = best?.driverID.map { env.implementedDrivers.contains($0) } ?? false
        let missingHW = best?.requiredEquipment.filter { EquipmentCatalog.spec($0)?.kind != .software && !env.has($0) } ?? []
        let missingSW = ((best?.requiredSoftware ?? []) + (best?.requiredEquipment.filter { EquipmentCatalog.spec($0)?.kind == .software } ?? [])).filter { !env.has($0) }
        let canAttempt = best != nil && implemented && missingHW.isEmpty && missingSW.isEmpty
        var steps: [StudioStep] = []
        func step(_ k: StudioStepKind, _ s: StudioStepStatus, _ lines: [String]) { steps.append(StudioStep(kind: k, status: s, lines: lines)) }
        let name = { (id: String) in EquipmentCatalog.spec(id)?.name ?? id }

        step(.identify, matchedEndpoint == nil ? .pending : .done,
             [profile.displayName, matchedEndpoint.map { "Observed: \($0.name) via \($0.transport.displayName)" } ?? "Not observed yet — select or scan. Research profile only."]
             + profile.informationRequests.map { "Please provide: \($0)" })
        step(.methods, allowed.isEmpty ? .blocked : .done,
             methods.map { "\($0.title) — \($0.protocolID) [\($0.source.displayName)]\($0.safety == .prohibitedControl ? " — PROHIBITED" : "")" }.ifEmptyList("No documented method yet."))
        step(.recommend, best == nil ? .blocked : .done, best.map { ["\($0.title)", implemented ? "System Tester implements this method." : "No adapter implements this method yet."] } ?? ["No safe method identified."])
        step(.hardware, missingHW.isEmpty ? .done : .blocked,
             (best?.requiredEquipment.filter { EquipmentCatalog.spec($0)?.kind != .software } ?? []).map { "\(name($0)): \(env.equipment[$0]?.availability.displayName ?? "Unknown")" }.ifEmptyList("No additional hardware."))
        step(.software, missingSW.isEmpty ? .done : .blocked,
             ((best?.requiredSoftware ?? []) + (best?.requiredEquipment.filter { EquipmentCatalog.spec($0)?.kind == .software } ?? [])).map { "\(name($0)): \(env.equipment[$0]?.availability.displayName ?? "Unknown")" }.ifEmptyList("No additional software."))
        step(.checkDependencies, missingHW.isEmpty && missingSW.isEmpty ? .done : .blocked,
             missingHW.isEmpty && missingSW.isEmpty ? ["All dependencies satisfied."] : (missingHW + missingSW).map { "Missing: \(name($0))" })
        step(.permissions, .pending, ((best?.permissions ?? []) + (best?.authentication.map { ["Authentication: \($0)"] } ?? [])).ifEmptyList("No special permissions.")
             + profile.safety.map { "Safety: \($0.text)" })
        step(.instructions, best?.steps.isEmpty == false ? .done : .pending, best?.steps ?? ["No step-by-step instructions recorded yet."])
        step(.approval, !canAttempt ? .notApplicable : (approved ? .done : .pending), canAttempt ? [approved ? "Approved by you for this attempt." : "Waiting for your explicit approval. Opening the app never authorises a connection."] : ["Not possible until the method is implemented and dependencies are satisfied."])
        let attempted = lastResult != nil
        step(.attempt, !canAttempt ? .notApplicable : (attempted ? .done : .pending), lastResult.map { [$0.summary] } ?? ["Not attempted."])
        step(.handshake, !attempted ? (canAttempt ? .pending : .notApplicable) : (lastResult!.outcome == .success ? .done : .blocked),
             lastResult.map { $0.handshake.isEmpty ? ["No handshake evidence: \($0.errors.joined(separator: "; "))"] : $0.handshake } ?? ["Not yet."])
        step(.capabilities, lastResult?.outcome == .success ? .done : .pending, lastResult?.capabilities.ifEmptyList("No diagnostic capabilities reported.") ?? ["Shown after a successful handshake."])
        step(.record, attempted ? .done : .pending, attempted ? ["Result recorded as connection evidence (\(lastResult!.provenance.displayName))."] : ["Recorded after the attempt — failures are recorded too."])
        step(.updateRoadmap, attempted ? .done : .pending, attempted ? ["Roadmap re-evaluated from the recorded evidence."] : ["Pending."])

        let gaps = canAttempt ? [] : GapAnalyzer.requirements(for: profile, env: env)
        let reason: String? = canAttempt ? nil : (best == nil ? "No safe connection method is documented yet."
            : !implemented ? "No System Tester adapter implements “\(best!.title)”. See the development requirements."
            : "Dependencies are missing: " + (missingHW + missingSW).map(name).joined(separator: ", "))
        return ConnectionPlan(profileID: profile.id, method: best, steps: steps, canAttempt: canAttempt, blockedReason: reason, developmentNeeded: gaps)
    }
}

extension Array where Element == String {
    func ifEmptyList(_ fallback: String) -> [String] { isEmpty ? [fallback] : self }
}
