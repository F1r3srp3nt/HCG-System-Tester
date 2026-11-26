import Foundation

/// Persistent Universal Connectivity state (Application Support/connectivity.json).
public struct ConnectivityState: Codable {
    public var schemaVersion = 1
    public var evidence: [ConnectivityEvidence] = []
    public var roadmapItems: [String: RoadmapItem] = [:]
    public var declaredEquipment: [String: Bool] = [:]
    public var gapPriorities: [String: Int] = [:]
    /// Exact model / firmware details you provided per profile (information requests).
    public var profileAnnotations: [String: [String: String]] = [:]
    public var endpoints: [String: ObservedEndpoint] = [:]
    public init() {}
}

public final class ConnectivityStore {
    public private(set) var state: ConnectivityState
    public let fileURL: URL?
    public let roadmap: DevelopmentRoadmap
    public private(set) var userProfiles: [EncyclopediaProfile] = []
    public private(set) var profileLoadErrors: [String] = []
    public var maxEvidence = 5000

    public init(fileURL: URL? = nil, userProfilesDirectory: URL? = nil) {
        self.fileURL = fileURL
        if let url = fileURL, let data = try? Data(contentsOf: url), let s = try? ConnectivityStore.decoder.decode(ConnectivityState.self, from: data) {
            state = s
        } else {
            state = ConnectivityState()
        }
        roadmap = DevelopmentRoadmap(items: state.roadmapItems)
        if let dir = userProfilesDirectory { loadUserProfiles(from: dir) }
    }

    /// Built-in profiles plus valid user profiles (user profiles with the same ID override built-ins).
    public var profiles: [EncyclopediaProfile] {
        var byID: [String: EncyclopediaProfile] = [:]
        for p in EncyclopediaData.all { byID[p.id] = p }
        for p in userProfiles { byID[p.id] = p }
        for (id, ann) in state.profileAnnotations {
            if ann["model"] != nil { byID[id]?.model = ann["model"] }
            if ann["modelYear"] != nil { byID[id]?.modelYear = ann["modelYear"] }
            if ann["firmwareVersion"] != nil { byID[id]?.firmwareVersion = ann["firmwareVersion"] }
            if ann["hardwareRevision"] != nil { byID[id]?.hardwareRevision = ann["hardwareRevision"] }
        }
        return byID.values.sorted { ($0.category.rawValue, $0.displayName) < ($1.category.rawValue, $1.displayName) }
    }

    public func profile(_ id: String) -> EncyclopediaProfile? { profiles.first { $0.id == id } }

    public func loadUserProfiles(from dir: URL) {
        userProfiles = []
        profileLoadErrors = []
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            do {
                var p = try JSONDecoder().decode(EncyclopediaProfile.self, from: Data(contentsOf: f))
                if let problem = ProfileValidator.problems(p).first { throw NSError(domain: "profile", code: 1, userInfo: [NSLocalizedDescriptionKey: problem]) }
                p.origin = "user: \(f.lastPathComponent)"
                userProfiles.append(p)
            } catch {
                profileLoadErrors.append("\(f.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    public func record(_ e: ConnectivityEvidence) {
        state.evidence.append(e)
        if state.evidence.count > maxEvidence { state.evidence.removeFirst(state.evidence.count - maxEvidence) }
        save()
    }

    public func observe(_ endpoint: ObservedEndpoint) {
        var e = endpoint
        if let existing = state.endpoints[endpoint.id] { e.firstSeen = existing.firstSeen }
        state.endpoints[endpoint.id] = e
    }

    public func setDeclared(_ equipmentID: String, owned: Bool) {
        state.declaredEquipment[equipmentID] = owned ? true : nil
        save()
    }

    public func setPriority(_ gapID: String, _ p: Int) {
        state.gapPriorities[gapID] = max(1, min(5, p))
        save()
    }

    public func annotate(_ profileID: String, key: String, value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profileAnnotations[profileID, default: [:]][key] = v.isEmpty ? nil : v
        save()
    }

    /// Equipment status from detections plus your declarations.
    public func equipmentStatus(detected: [String: EquipmentStatus]) -> [String: EquipmentStatus] {
        var out: [String: EquipmentStatus] = [:]
        for spec in EquipmentCatalog.all {
            if let d = detected[spec.id], d.availability == .detected { out[spec.id] = d }
            else if state.declaredEquipment[spec.id] == true { out[spec.id] = EquipmentStatus(.declaredOwned, "Declared by you") }
            else { out[spec.id] = detected[spec.id] ?? EquipmentStatus(.unknown, spec.detection) }
        }
        return out
    }

    public func environment(detected: [String: EquipmentStatus]) -> RoadmapEnvironment {
        RoadmapEnvironment(equipment: equipmentStatus(detected: detected), implementedDrivers: RoadmapEngine.builtInDrivers, evidence: state.evidence)
    }

    public func recomputeRoadmap(detected: [String: EquipmentStatus], at date: Date = Date()) {
        roadmap.recompute(profiles: profiles, protocols: UniversalProtocolRegistry.all, env: environment(detected: detected), at: date)
        state.roadmapItems = roadmap.items
        save()
    }

    @discardableResult
    public func decide(_ id: String, state newState: RoadmapState, note: String) -> String? {
        let r = roadmap.decide(id, state: newState, note: note)
        state.roadmapItems = roadmap.items
        save()
        return r
    }

    public func clearDecision(_ id: String) {
        roadmap.clearDecision(id)
        state.roadmapItems = roadmap.items
        save()
    }

    public func save() {
        guard let url = fileURL else { return }
        state.roadmapItems = roadmap.items
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? ConnectivityStore.encoder.encode(state) { try? data.write(to: url, options: .atomic) }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Validates encyclopedia profiles (built-in and user-supplied).
public enum ProfileValidator {
    public static func problems(_ p: EncyclopediaProfile) -> [String] {
        var out: [String] = []
        if p.id.isEmpty || p.id.contains(" ") { out.append("id must be non-empty without spaces") }
        if p.manufacturer.isEmpty || p.productFamily.isEmpty { out.append("manufacturer and productFamily are required") }
        for m in p.connectionMethods where UniversalProtocolRegistry.protocolInfo(m.protocolID) == nil {
            out.append("method \(m.id): unknown protocol \(m.protocolID)")
        }
        for m in p.connectionMethods {
            for e in m.requiredEquipment + m.requiredSoftware where EquipmentCatalog.spec(e) == nil {
                out.append("method \(m.id): unknown equipment \(e)")
            }
        }
        if p.allFacts.contains(where: { $0.source == .hcgVerified }) && p.origin != "built-in" {
            out.append("user profiles may not mark facts as physically verified; verification comes only from recorded evidence")
        }
        return out
    }
}
