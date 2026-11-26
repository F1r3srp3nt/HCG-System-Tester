import Foundation

// MARK: - Evidence

public enum EvidenceKind: String, Codable, Hashable {
    case discovered
    case connectionAttempt
    case diagnostics
    case userReport
}

public enum EvidenceOutcome: String, Codable, Hashable {
    case observed, success, partial, failure
}

/// A genuine development fact recorded by System Tester (or reported by you). Kept when devices disconnect.
public struct ConnectivityEvidence: Codable, Hashable, Identifiable {
    public var id: UUID
    public var at: Date
    public var kind: EvidenceKind
    public var outcome: EvidenceOutcome
    public var profileID: String?
    public var protocolID: String?
    public var methodID: String?
    public var endpointName: String
    public var summary: String
    public var details: [String]
    /// Physically observed hardware vs synthetic fixture. Only hardware (and user reports) move the roadmap.
    public var provenance: DataProvenance
    public var source: String
    /// For diagnostics: number of applicable tests and number passed.
    public var testsPassed: Int?
    public var testsApplicable: Int?

    public init(at: Date = Date(), kind: EvidenceKind, outcome: EvidenceOutcome, profileID: String?, protocolID: String? = nil, methodID: String? = nil,
                endpointName: String, summary: String, details: [String] = [], provenance: DataProvenance, source: String,
                testsPassed: Int? = nil, testsApplicable: Int? = nil) {
        self.id = UUID()
        self.at = at
        self.kind = kind
        self.outcome = outcome
        self.profileID = profileID
        self.protocolID = protocolID
        self.methodID = methodID
        self.endpointName = endpointName
        self.summary = summary
        self.details = details
        self.provenance = provenance
        self.source = source
        self.testsPassed = testsPassed
        self.testsApplicable = testsApplicable
    }

    /// Evidence that may change development state.
    public var countsForRoadmap: Bool { provenance == .hardware || kind == .userReport }
}

// MARK: - Roadmap

public enum RoadmapState: String, Codable, CaseIterable, Hashable, Identifiable {
    case researchRequired
    case documentationIdentified
    case connectionMethodIdentified
    case hardwareRequired
    case softwareRequired
    case adapterDevelopmentRequired
    case adapterImplemented
    case readyForConnection
    case deviceDiscovered
    case connectionAttempted
    case connectionEstablished
    case diagnosticsPartiallyVerified
    case diagnosticsFullyVerified
    case compatibilityValidated
    case ecosystemIntegrationAvailable
    case blocked
    case unsupported

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .researchRequired: return "Research required"
        case .documentationIdentified: return "Documentation identified"
        case .connectionMethodIdentified: return "Connection method identified"
        case .hardwareRequired: return "Hardware required"
        case .softwareRequired: return "Software required"
        case .adapterDevelopmentRequired: return "Adapter development required"
        case .adapterImplemented: return "Adapter implemented"
        case .readyForConnection: return "Ready for connection"
        case .deviceDiscovered: return "Device discovered"
        case .connectionAttempted: return "Connection attempted"
        case .connectionEstablished: return "Connection established"
        case .diagnosticsPartiallyVerified: return "Diagnostics partially verified"
        case .diagnosticsFullyVerified: return "Diagnostics fully verified"
        case .compatibilityValidated: return "Compatibility validated"
        case .ecosystemIntegrationAvailable: return "Ecosystem integration available"
        case .blocked: return "Blocked"
        case .unsupported: return "Unsupported"
        }
    }

    public var rank: Int { RoadmapState.allCases.firstIndex(of: self)! }
    public var isRequirement: Bool { [.hardwareRequired, .softwareRequired, .adapterDevelopmentRequired].contains(self) }
    public var isTerminalCondition: Bool { self == .blocked || self == .unsupported }
    /// States that can only be set by a person (with prerequisites checked).
    public var requiresManualDecision: Bool { [.compatibilityValidated, .ecosystemIntegrationAvailable, .blocked, .unsupported].contains(self) }
}

public enum RoadmapItemKind: String, Codable, Hashable { case device, `protocol`, adapter }

public struct RoadmapTransition: Codable, Hashable, Identifiable {
    public var id: UUID
    public var at: Date
    public var from: RoadmapState?
    public var to: RoadmapState
    public var automatic: Bool
    public var reason: String
    public var evidence: [String]

    public init(at: Date = Date(), from: RoadmapState?, to: RoadmapState, automatic: Bool, reason: String, evidence: [String] = []) {
        self.id = UUID()
        self.at = at
        self.from = from
        self.to = to
        self.automatic = automatic
        self.reason = reason
        self.evidence = evidence
    }
}

public struct ManualDecision: Codable, Hashable {
    public var state: RoadmapState
    public var note: String
    public var at: Date
    public var actor: String
}

public struct RoadmapItem: Codable, Hashable, Identifiable {
    public var id: String
    public var kind: RoadmapItemKind
    public var title: String
    public var automaticState: RoadmapState
    public var automaticReason: String
    public var manual: ManualDecision?
    public var history: [RoadmapTransition]
    public var blockers: [String]

    public var state: RoadmapState { manual?.state ?? automaticState }
    public var isManual: Bool { manual != nil }
}

public struct RoadmapEnvironment {
    public var equipment: [String: EquipmentStatus]
    public var implementedDrivers: Set<String>
    public var evidence: [ConnectivityEvidence]

    public init(equipment: [String: EquipmentStatus], implementedDrivers: Set<String>, evidence: [ConnectivityEvidence]) {
        self.equipment = equipment
        self.implementedDrivers = implementedDrivers
        self.evidence = evidence
    }

    public func has(_ equipmentID: String) -> Bool { equipment[equipmentID]?.availability.satisfied ?? false }
}

public enum RoadmapEngine {
    /// Drivers that System Tester implements (connection attempts can be made).
    public static let builtInDrivers: Set<String> = ["usb.enumeration", "apple.coredevice", "ble.gatt-read", "network.discovery", "samsung.tv-info"]

    /// Computes the evidence-based state of a device profile.
    public static func evaluate(profile: EncyclopediaProfile, env: RoadmapEnvironment) -> (RoadmapState, String, [String]) {
        let ev = env.evidence.filter { $0.profileID == profile.id && $0.countsForRoadmap }
        var state = RoadmapState.researchRequired
        var reason = "No manufacturer documentation recorded yet."
        var blockers: [String] = []
        if profile.references.contains(where: { $0.source == .manufacturerDocumented }) || profile.allFacts.contains(where: { $0.source == .manufacturerDocumented }) {
            state = .documentationIdentified; reason = "Manufacturer documentation identified."
        }
        let methods = profile.connectionMethods.filter { $0.safety != .prohibitedControl }
        if !methods.isEmpty { state = .connectionMethodIdentified; reason = "\(methods.count) connection method(s) identified." }

        // Best method: implemented driver with satisfied dependencies first.
        func missing(_ m: ConnectionMethod) -> (hw: [String], sw: [String], adapter: Bool) {
            let hw = m.requiredEquipment.filter { id in EquipmentCatalog.spec(id)?.kind != .software && !env.has(id) }
            let sw = (m.requiredSoftware + m.requiredEquipment.filter { EquipmentCatalog.spec($0)?.kind == .software }).filter { !env.has($0) }
            let adapter = m.driverID.map { !env.implementedDrivers.contains($0) } ?? true
            return (hw, sw, adapter)
        }
        if let best = methods.min(by: { score(missing($0)) < score(missing($1)) }) {
            let m = missing(best)
            if m.adapter {
                state = .adapterDevelopmentRequired; reason = "No System Tester adapter implements “\(best.title)”."
                blockers.append("Adapter for \(best.protocolID)")
            } else if !m.hw.isEmpty {
                state = .hardwareRequired; reason = "Missing equipment: " + m.hw.map { EquipmentCatalog.spec($0)?.name ?? $0 }.joined(separator: ", ")
                blockers += m.hw
            } else if !m.sw.isEmpty {
                state = .softwareRequired; reason = "Missing software: " + m.sw.map { EquipmentCatalog.spec($0)?.name ?? $0 }.joined(separator: ", ")
                blockers += m.sw
            } else {
                state = .readyForConnection; reason = "“\(best.title)” has an implemented adapter and all dependencies are satisfied."
            }
        }
        // Evidence-driven progress (never regresses when a device disconnects: evidence is historical).
        if ev.contains(where: { $0.kind == .discovered }) {
            state = furthest(state, .deviceDiscovered); reason = "Discovered on real hardware (\(ev.first { $0.kind == .discovered }!.source))."
        }
        if ev.contains(where: { $0.kind == .connectionAttempt }) {
            state = furthest(state, .connectionAttempted); reason = "A connection was attempted."
        }
        if let ok = ev.last(where: { $0.kind == .connectionAttempt && $0.outcome == .success }) {
            state = furthest(state, .connectionEstablished); reason = "Connection established: \(ok.summary)"
        }
        let diag = ev.filter { $0.kind == .diagnostics }
        if let full = diag.last(where: { ($0.testsApplicable ?? 0) > 0 && $0.testsPassed == $0.testsApplicable }) {
            state = furthest(state, .diagnosticsFullyVerified); reason = "All \(full.testsApplicable!) applicable diagnostics passed on real hardware."
        } else if let part = diag.last(where: { ($0.testsPassed ?? 0) > 0 }) {
            state = furthest(state, .diagnosticsPartiallyVerified); reason = "\(part.testsPassed!) of \(part.testsApplicable ?? 0) diagnostics passed on real hardware."
        }
        return (state, reason, blockers)
    }

    static func score(_ m: (hw: [String], sw: [String], adapter: Bool)) -> Int { (m.adapter ? 100 : 0) + m.hw.count * 10 + m.sw.count }

    public static func evaluate(protocolInfo p: ConnectivityProtocol, env: RoadmapEnvironment) -> (RoadmapState, String, [String]) {
        if p.validation == .prohibited { return (.unsupported, "Prohibited by System Tester's safety policy.", []) }
        if p.validation == .delegated { return (.ecosystemIntegrationAvailable, "Owned by \(p.owner ?? "another HCG product").", []) }
        let ev = env.evidence.filter { $0.protocolID == p.id && $0.countsForRoadmap }
        var state: RoadmapState = p.references.isEmpty ? .researchRequired : .documentationIdentified
        var reason = p.summary
        var blockers: [String] = []
        if p.isImplemented {
            state = .adapterImplemented; reason = "Adapter implemented (\(p.validation.displayName))."
            let missingDeps = p.dependencies.filter { !env.has($0) }
            if missingDeps.isEmpty { state = .readyForConnection } else { blockers = missingDeps }
        } else {
            state = .adapterDevelopmentRequired; reason = "\(p.validation.displayName): adapter not implemented."
            blockers = ["Adapter for \(p.name)"]
        }
        if ev.contains(where: { $0.kind == .discovered }) { state = furthest(state, .deviceDiscovered); reason = "Devices discovered over \(p.name) on real hardware." }
        if ev.contains(where: { $0.kind == .connectionAttempt }) { state = furthest(state, .connectionAttempted) }
        if ev.contains(where: { $0.kind == .connectionAttempt && $0.outcome == .success }) { state = furthest(state, .connectionEstablished); reason = "Connection established over \(p.name) on real hardware." }
        return (state, reason, blockers)
    }

    /// Validates a manual decision against prerequisites. Returns an error message when refused.
    public static func refusal(for target: RoadmapState, automatic: RoadmapState) -> String? {
        switch target {
        case .compatibilityValidated:
            return automatic.rank >= RoadmapState.diagnosticsFullyVerified.rank ? nil
                : "Compatibility can only be validated after a real connection and fully verified diagnostics (current: \(automatic.displayName)). Discovery alone never validates compatibility."
        case .ecosystemIntegrationAvailable:
            return automatic.rank >= RoadmapState.connectionEstablished.rank ? nil
                : "An ecosystem integration needs an established connection first (current: \(automatic.displayName))."
        case .connectionEstablished, .diagnosticsPartiallyVerified, .diagnosticsFullyVerified, .deviceDiscovered, .connectionAttempted:
            return "“\(target.displayName)” is set only by recorded evidence, never manually."
        default:
            return nil
        }
    }
}

func furthest(_ a: RoadmapState, _ b: RoadmapState) -> RoadmapState {
    // Requirement states sit below "adapter implemented" in rank order but represent unmet work; progress evidence beats them.
    a.rank >= b.rank ? a : b
}

/// Persistent roadmap: recomputes automatic states, records transitions, applies manual decisions.
public final class DevelopmentRoadmap {
    public private(set) var items: [String: RoadmapItem]

    public init(items: [String: RoadmapItem] = [:]) {
        self.items = items
    }

    public var sorted: [RoadmapItem] { items.values.sorted { ($0.kind.rawValue, $0.title) < ($1.kind.rawValue, $1.title) } }

    public func recompute(profiles: [EncyclopediaProfile], protocols: [ConnectivityProtocol], env: RoadmapEnvironment, at date: Date = Date()) {
        for p in profiles {
            let (s, r, b) = RoadmapEngine.evaluate(profile: p, env: env)
            update(id: "device.\(p.id)", kind: .device, title: p.displayName, state: s, reason: r, blockers: b, evidence: evidenceSummary(env, profileID: p.id), at: date)
        }
        for p in protocols {
            let (s, r, b) = RoadmapEngine.evaluate(protocolInfo: p, env: env)
            update(id: "protocol.\(p.id)", kind: .protocol, title: p.name, state: s, reason: r, blockers: b, evidence: [], at: date)
        }
    }

    func evidenceSummary(_ env: RoadmapEnvironment, profileID: String) -> [String] {
        env.evidence.filter { $0.profileID == profileID && $0.countsForRoadmap }.suffix(3).map { "\($0.kind.rawValue): \($0.summary)" }
    }

    func update(id: String, kind: RoadmapItemKind, title: String, state: RoadmapState, reason: String, blockers: [String], evidence: [String], at: Date) {
        if var item = items[id] {
            if item.automaticState != state {
                item.history.append(RoadmapTransition(at: at, from: item.automaticState, to: state, automatic: true, reason: reason, evidence: evidence))
            }
            item.automaticState = state
            item.automaticReason = reason
            item.blockers = blockers
            item.title = title
            items[id] = item
        } else {
            items[id] = RoadmapItem(id: id, kind: kind, title: title, automaticState: state, automaticReason: reason, manual: nil,
                                    history: [RoadmapTransition(at: at, from: nil, to: state, automatic: true, reason: reason, evidence: evidence)],
                                    blockers: blockers)
        }
    }

    /// Applies a manual decision. Returns a refusal message when prerequisites are not met.
    @discardableResult
    public func decide(_ id: String, state: RoadmapState, note: String, actor: String = "user", at: Date = Date()) -> String? {
        guard var item = items[id] else { return "Unknown roadmap item." }
        if let refusal = RoadmapEngine.refusal(for: state, automatic: item.automaticState) { return refusal }
        let previous = item.state
        item.manual = ManualDecision(state: state, note: note, at: at, actor: actor)
        item.history.append(RoadmapTransition(at: at, from: previous, to: state, automatic: false, reason: "Manual decision by \(actor): \(note)"))
        items[id] = item
        return nil
    }

    public func clearDecision(_ id: String, actor: String = "user", at: Date = Date()) {
        guard var item = items[id], item.manual != nil else { return }
        let previous = item.state
        item.manual = nil
        item.history.append(RoadmapTransition(at: at, from: previous, to: item.automaticState, automatic: false, reason: "Manual decision cleared by \(actor)."))
        items[id] = item
    }
}

// MARK: - Development Gap Analyzer

public enum GapKind: String, Codable, CaseIterable, Hashable {
    case missingAdapter, missingSDK, missingDriver, missingDiagnosticInterface, missingProtocolImplementation, missingAuthentication
    case unsupportedFirmware, missingHardware, operatingSystemRestriction, safetyReview, missingInformation

    public var displayName: String {
        switch self {
        case .missingAdapter: return "Missing adapter"
        case .missingSDK: return "Missing manufacturer SDK / software"
        case .missingDriver: return "Missing driver"
        case .missingDiagnosticInterface: return "Missing diagnostic interface"
        case .missingProtocolImplementation: return "Missing protocol implementation"
        case .missingAuthentication: return "Missing authentication"
        case .unsupportedFirmware: return "Firmware compatibility unknown"
        case .missingHardware: return "Missing physical hardware"
        case .operatingSystemRestriction: return "Operating-system restriction"
        case .safetyReview: return "Safety review required"
        case .missingInformation: return "Exact model/firmware information needed"
        }
    }
}

public struct DevelopmentRequirement: Codable, Hashable, Identifiable {
    public var id: String
    public var kind: GapKind
    public var title: String
    public var detail: String
    public var dependsOn: [String]
    public var profileIDs: [String]
    public var protocolID: String?
    /// 1 (highest) … 5 (lowest). User-adjustable.
    public var priority: Int
    public var acceptanceCriteria: [String]
}

public enum GapAnalyzer {
    /// Structured development requirements for a profile, deduplicated across profiles by stable IDs.
    public static func requirements(for profile: EncyclopediaProfile, env: RoadmapEnvironment) -> [DevelopmentRequirement] {
        var out: [DevelopmentRequirement] = []
        let basePriority = max(1, min(5, 6 - profile.priority))
        func add(_ r: DevelopmentRequirement) { if !out.contains(where: { $0.id == r.id }) { out.append(r) } }

        for q in profile.informationRequests {
            add(DevelopmentRequirement(id: "gap.\(profile.id).info.\(slug(q))", kind: q.lowercased().contains("firmware") || q.lowercased().contains("software version") ? .unsupportedFirmware : .missingInformation,
                                       title: "\(profile.displayName): \(q)", detail: "Needed to choose the right connection method and confirm compatibility.",
                                       dependsOn: [], profileIDs: [profile.id], protocolID: nil, priority: basePriority,
                                       acceptanceCriteria: ["Value recorded in the profile with its source"]))
        }
        for m in profile.connectionMethods where m.safety != .prohibitedControl {
            var deps: [String] = []
            if m.safety != .readOnly || !profile.safety.filter({ $0.safetyClass == .prohibitedControl }).isEmpty && [.vehicle, .motorcycle, .agriculturalMachinery, .constructionEquipment, .industrialMachinery, .robot, .roboticArm, .drone].contains(profile.category) {
                let id = "gap.safety.\(profile.category.rawValue).\(m.protocolID)"
                add(DevelopmentRequirement(id: id, kind: .safetyReview, title: "Safety review: read-only \(m.protocolID) on \(profile.category.displayName.lowercased())",
                                           detail: "Confirm the adapter is listen-only/read-only and document prohibited operations before any connection.",
                                           dependsOn: [], profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Written review of read-only guarantees", "Prohibited operations enumerated and blocked in code"]))
                deps.append(id)
            }
            for e in m.requiredEquipment where !env.has(e) {
                let spec = EquipmentCatalog.spec(e)
                let kind: GapKind = spec?.kind == .diagnosticInterface ? .missingDiagnosticInterface : (spec?.kind == .software ? .missingSDK : .missingHardware)
                let id = "gap.equipment.\(e)"
                add(DevelopmentRequirement(id: id, kind: kind, title: "Obtain \(spec?.name ?? e)",
                                           detail: (spec?.requiredSpecifications ?? []).joined(separator: "; "),
                                           dependsOn: [], profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Equipment detected or declared in Hardware Requirements", "Specifications checked against the requirement list"]))
                deps.append(id)
            }
            for s in m.requiredSoftware where !env.has(s) {
                let id = "gap.software.\(s)"
                add(DevelopmentRequirement(id: id, kind: .missingSDK, title: "Install \(EquipmentCatalog.spec(s)?.name ?? s)",
                                           detail: (EquipmentCatalog.spec(s)?.requiredSpecifications ?? []).joined(separator: "; "),
                                           dependsOn: [], profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Software detected by System Tester"]))
                deps.append(id)
            }
            if let auth = m.authentication, m.driverID == nil || !env.implementedDrivers.contains(m.driverID!) {
                let id = "gap.auth.\(m.protocolID).\(slug(profile.manufacturer))"
                add(DevelopmentRequirement(id: id, kind: .missingAuthentication, title: "Authentication for \(profile.manufacturer) (\(auth))",
                                           detail: "Credentials must be governed by HCG Connect; no client IDs or secrets are invented.",
                                           dependsOn: [], profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Owner authorisation flow documented", "Credentials stored in the Keychain only"]))
                deps.append(id)
            }
            if let restriction = m.osRestriction {
                let id = "gap.os.\(m.protocolID)"
                add(DevelopmentRequirement(id: id, kind: .operatingSystemRestriction, title: "macOS restriction for \(m.protocolID)", detail: restriction,
                                           dependsOn: [], profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Workaround chosen (e.g. Linux VM/container) and documented"]))
                deps.append(id)
            }
            if m.driverID == nil || !env.implementedDrivers.contains(m.driverID!) {
                let proto = UniversalProtocolRegistry.protocolInfo(m.protocolID)
                let protoImplemented = proto?.isImplemented ?? false
                let id = protoImplemented ? "gap.adapter.\(profile.id).\(m.id)" : "gap.protocol.\(m.protocolID)"
                add(DevelopmentRequirement(id: id, kind: protoImplemented ? .missingAdapter : .missingProtocolImplementation,
                                           title: protoImplemented ? "Develop \(profile.displayName) adapter (\(m.title))" : "Implement read-only \(proto?.name ?? m.protocolID) adapter",
                                           detail: (proto?.safetyNotes ?? []).joined(separator: " "), dependsOn: deps.filter { $0 != id },
                                           profileIDs: [profile.id], protocolID: m.protocolID, priority: basePriority,
                                           acceptanceCriteria: ["Adapter manifest validated", "Read-only connection verified on real hardware", "Diagnostics recorded as evidence"]))
            }
        }
        return out
    }

    /// All requirements across profiles, merged by ID (profile lists combined), with user priority overrides.
    public static func all(profiles: [EncyclopediaProfile], env: RoadmapEnvironment, priorities: [String: Int] = [:]) -> [DevelopmentRequirement] {
        var merged: [String: DevelopmentRequirement] = [:]
        for p in profiles {
            for r in requirements(for: p, env: env) {
                if var existing = merged[r.id] {
                    existing.profileIDs = Array(Set(existing.profileIDs + r.profileIDs)).sorted()
                    existing.dependsOn = Array(Set(existing.dependsOn + r.dependsOn)).sorted()
                    existing.priority = min(existing.priority, r.priority)
                    merged[r.id] = existing
                } else {
                    merged[r.id] = r
                }
            }
        }
        for (id, p) in priorities { merged[id]?.priority = p }
        return merged.values.sorted { ($0.priority, $0.kind.rawValue, $0.id) < ($1.priority, $1.kind.rawValue, $1.id) }
    }

    /// Requirements ordered so that dependencies come first.
    public static func topologicalOrder(_ reqs: [DevelopmentRequirement]) -> [DevelopmentRequirement] {
        let byID = Dictionary(uniqueKeysWithValues: reqs.map { ($0.id, $0) })
        var visited = Set<String>()
        var out: [DevelopmentRequirement] = []
        func visit(_ id: String, _ depth: Int) {
            guard depth < 50, !visited.contains(id), let r = byID[id] else { return }
            visited.insert(id)
            r.dependsOn.forEach { visit($0, depth + 1) }
            out.append(r)
        }
        reqs.forEach { visit($0.id, 0) }
        return out
    }

    public static func slug(_ s: String) -> String {
        let lower = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(lower).split(separator: "-").prefix(6).joined(separator: "-")
    }
}

// MARK: - LifeOS quest proposals

/// Builds an `hcg.lifeos.backlog` (schema 2) document from development requirements.
/// Stable keys make re-imports idempotent; no XP is set and nothing is marked completed.
public enum LifeOSQuestExporter {
    public static let epicKey = "hcg.systemtester.epic.platform"

    public static func questKey(_ requirementID: String) -> String { "hcg.systemtester.\(requirementID)" }

    public static func document(for selected: [DevelopmentRequirement], all: [DevelopmentRequirement], at date: Date = Date()) -> [String: Any] {
        // Include dependencies so every dependsOn key resolves inside the file.
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var included: [String: DevelopmentRequirement] = [:]
        func include(_ r: DevelopmentRequirement, _ depth: Int) {
            guard depth < 50, included[r.id] == nil else { return }
            included[r.id] = r
            r.dependsOn.compactMap { byID[$0] }.forEach { include($0, depth + 1) }
        }
        selected.forEach { include($0, 0) }
        let ordered = GapAnalyzer.topologicalOrder(Array(included.values))
        var quests: [[String: Any]] = [[
            "key": epicKey, "title": "HCG System Tester — modular hardware discovery & diagnostics platform", "kind": "epic",
            "realm": "Sovereign Technology", "project": "HCG System Tester", "category": "development", "priority": "high", "status": "inProgress",
            "tags": ["HCG System Tester"]
        ]]
        for r in ordered {
            quests.append([
                "key": questKey(r.id), "title": r.title, "details": r.detail.isEmpty ? r.kind.displayName : r.detail,
                "realm": "Sovereign Technology", "project": "HCG System Tester", "kind": "quest", "parent": epicKey,
                "dependsOn": r.dependsOn.filter { included[$0] != nil }.map(questKey),
                "category": "development", "priority": priority(r.priority), "status": "backlog",
                "subtasks": r.acceptanceCriteria, "notes": "Generated by HCG System Tester Gap Analyzer (\(r.kind.displayName)). Profiles: \(r.profileIDs.joined(separator: ", ")).",
                "tags": ["HCG System Tester", "Connectivity", r.kind.displayName]
            ])
        }
        return ["format": "hcg.lifeos.backlog", "schemaVersion": 2,
                "source": "HCG System Tester \(HCGSystemTesterInfo.version) — Development Gap Analyzer, \(ISO8601DateFormatter().string(from: date)). Proposed quests: review before importing; no XP is awarded.",
                "quests": quests]
    }

    public static func json(for selected: [DevelopmentRequirement], all: [DevelopmentRequirement], at date: Date = Date()) throws -> Data {
        try JSONSerialization.data(withJSONObject: document(for: selected, all: all, at: date), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func priority(_ p: Int) -> String {
        switch p { case ...1: return "critical"; case 2: return "high"; case 3: return "medium"; default: return "low" }
    }
}
