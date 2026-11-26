import Foundation

/// A sentence produced by an assistant, tagged with where its knowledge came from.
public struct AssistantStatement: Codable, Hashable, Identifiable {
    public var id: UUID = UUID()
    public var text: String
    public var source: KnowledgeSource

    public init(_ text: String, _ source: KnowledgeSource) {
        self.text = text
        self.source = source
    }
}

public struct AssistantAnswer: Codable, Hashable {
    public var question: String
    public var provider: String
    public var statements: [AssistantStatement]
    /// Commands or code are never executed; suggestions are shown for manual review only.
    public var suggestedActions: [String]
}

public protocol ConnectionAssistantProvider {
    var name: String { get }
    var isAI: Bool { get }
    func answer(_ question: String, profile: EncyclopediaProfile?, env: RoadmapEnvironment, gaps: [DevelopmentRequirement]) -> AssistantAnswer
}

/// Offline, deterministic guidance built only from the encyclopedia, registry and evidence. Not AI.
public struct RuleBasedConnectionAssistant: ConnectionAssistantProvider {
    public let name = "Rule-based guidance (offline — not AI)"
    public let isAI = false
    public init() {}

    public func answer(_ question: String, profile: EncyclopediaProfile?, env: RoadmapEnvironment, gaps: [DevelopmentRequirement]) -> AssistantAnswer {
        var s: [AssistantStatement] = []
        var actions: [String] = []
        let q = question.lowercased()
        guard let p = profile else {
            let mentioned = UniversalProtocolRegistry.all.filter { q.contains($0.id.lowercased()) || q.contains($0.name.lowercased().components(separatedBy: " ").first ?? "§") }
            for proto in mentioned.prefix(3) {
                s.append(.init("\(proto.name): \(proto.summary)", .hcgResearchNote))
                s.append(.init("Discovery: \(proto.discovery.displayName). Communication: \(proto.communication.displayName). Status: \(proto.validation.displayName).", .hcgResearchNote))
                proto.safetyNotes.forEach { s.append(.init("Safety: \($0)", .hcgResearchNote)) }
            }
            if s.isEmpty { s.append(.init("Select a device profile or name a protocol (e.g. OBD-II, BLE, ROS 2) for guidance.", .hcgResearchNote)) }
            return AssistantAnswer(question: question, provider: name, statements: s, suggestedActions: actions)
        }
        let (state, reason, blockers) = RoadmapEngine.evaluate(profile: p, env: env)
        s.append(.init("\(p.displayName) is at “\(state.displayName)”: \(reason)", .hcgResearchNote))
        let verified = env.evidence.filter { $0.profileID == p.id && $0.countsForRoadmap }
        if verified.isEmpty {
            s.append(.init("No physical HCG evidence exists for this device yet — everything below is research.", .hcgResearchNote))
        } else {
            verified.suffix(3).forEach { s.append(.init("Recorded \($0.kind.rawValue) (\($0.outcome.rawValue)): \($0.summary)", .hcgVerified)) }
        }
        if q.contains("how") || q.contains("connect") || q.contains("method") || q.isEmpty {
            for m in p.connectionMethods {
                s.append(.init("Method: \(m.title) over \(m.protocolID)\(m.safety == .prohibitedControl ? " — prohibited" : "").", m.source))
                m.steps.forEach { s.append(.init("• \($0)", m.source)) }
            }
        }
        if q.contains("need") || q.contains("hardware") || q.contains("require") || q.contains("buy") || q.isEmpty {
            let equipment = Set(p.connectionMethods.flatMap { $0.requiredEquipment + $0.requiredSoftware })
            for e in equipment.sorted() {
                let spec = EquipmentCatalog.spec(e)
                s.append(.init("\(spec?.name ?? e): \(env.equipment[e]?.availability.displayName ?? "Unknown"). Required specifications: \((spec?.requiredSpecifications ?? []).joined(separator: "; ")).", .hcgResearchNote))
            }
        }
        if q.contains("why") || q.contains("fail") || q.contains("troubleshoot") || q.isEmpty {
            p.troubleshooting.forEach { s.append(.init($0.text, $0.source)) }
            blockers.forEach { s.append(.init("Blocker: \($0)", .hcgResearchNote)) }
        }
        if q.contains("develop") || q.contains("build") || q.contains("gap") || q.isEmpty {
            for g in gaps.filter({ $0.profileIDs.contains(p.id) }).prefix(6) {
                s.append(.init("To develop: \(g.title) (\(g.kind.displayName), priority \(g.priority)).", .hcgResearchNote))
            }
            actions.append("Export the development requirements as proposed LifeOS quests (Gap Analyzer).")
        }
        p.safety.forEach { s.append(.init("Safety: \($0.text)", $0.source)) }
        p.informationRequests.forEach { actions.append("Provide: \($0)") }
        return AssistantAnswer(question: question, provider: name, statements: s, suggestedActions: actions)
    }

    /// A redacted research request you can copy into HCG AI manually. Nothing is sent automatically.
    public static func researchRequest(profile: EncyclopediaProfile, gaps: [DevelopmentRequirement], question: String) -> String {
        var l = ["HCG System Tester — research request (manual transfer; contains no device identifiers)", "",
                 "Device: \(profile.displayName) [\(profile.category.displayName)]",
                 "Question: \(question.isEmpty ? "How can this device be connected read-only, and what must HCG develop?" : question)", "",
                 "Known facts (with sources):"]
        profile.allFacts.forEach { l.append("- \($0.text) [\($0.source.displayName)]") }
        l.append("")
        l.append("Open development requirements:")
        gaps.filter { $0.profileIDs.contains(profile.id) }.forEach { l.append("- \($0.title) (\($0.kind.displayName))") }
        l.append("")
        l.append("Constraints: read-only only; no control, actuation, flashing, ECU modification, transmission or security bypass. Cite official documentation; mark anything unverified as a suggestion.")
        return l.joined(separator: "\n")
    }
}
