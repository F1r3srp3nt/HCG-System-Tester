import Foundation

public struct DeviceRecord: Identifiable, Hashable {
    public var device: DiscoveredDevice
    public var identification: IdentificationResult
    public var compatibility: [AdapterCompatibility]
    public var assessment: ConnectivityAssessment
    public var state: DeviceStateMachine
    public var statusReason: String
    public var functionalEvidence: [String]
    public var stableKey: String

    public var id: DeviceIdentifier { device.id }
    public var status: DeviceStatus { state.status }
}

public struct InventoryEvent: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable { case attached, detached, reattached, statusChanged, backend }
    public var id: UUID
    public var at: Date
    public var kind: Kind
    public var deviceID: DeviceIdentifier?
    public var deviceName: String
    public var detail: String
    public var provenance: DataProvenance

    public init(at: Date = Date(), kind: Kind, deviceID: DeviceIdentifier?, deviceName: String, detail: String, provenance: DataProvenance) {
        self.id = UUID()
        self.at = at
        self.kind = kind
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.detail = detail
        self.provenance = provenance
    }
}

/// Live model of every system seen this session. Not thread-safe: call from one queue (the main actor in the app).
public final class DeviceInventory {
    public let identification: IdentificationEngine
    public let adapters: AdapterRegistry
    public let authorization: AuthorizationStore
    public var keySalt: String
    public private(set) var records: [DeviceIdentifier: DeviceRecord] = [:]
    public private(set) var events: [InventoryEvent] = []
    public private(set) var backendStatuses: [String: DiscoveryBackendStatus] = [:]
    public var maxEvents = 500
    public var onChange: (() -> Void)?

    public init(identification: IdentificationEngine = IdentificationEngine(), adapters: AdapterRegistry = AdapterRegistry(),
                authorization: AuthorizationStore = AuthorizationStore(), keySalt: String = "") {
        self.identification = identification
        self.adapters = adapters
        self.authorization = authorization
        self.keySalt = keySalt
        identification.register(contentsOf: adapters.contributedProfiles)
    }

    /// Records ordered for display: present devices first (real before synthetic), then most recent.
    public var orderedRecords: [DeviceRecord] {
        records.values.sorted { a, b in
            if a.device.isPresent != b.device.isPresent { return a.device.isPresent }
            if a.device.provenance.isSynthetic != b.device.provenance.isSynthetic { return !a.device.provenance.isSynthetic }
            if a.device.firstSeen != b.device.firstSeen { return a.device.firstSeen > b.device.firstSeen }
            return a.id < b.id
        }
    }

    public var presentRecords: [DeviceRecord] { orderedRecords.filter { $0.device.isPresent } }

    public func record(_ id: DeviceIdentifier) -> DeviceRecord? { records[id] }

    public func apply(_ event: DiscoveryEvent) {
        switch event {
        case .attached(let device): attach(device)
        case .detached(let id, let at): detach(id, at: at)
        case .backendStatus(let s):
            let previous = backendStatuses[s.backendID]
            backendStatuses[s.backendID] = s
            if previous?.state != s.state {
                log(InventoryEvent(kind: .backend, deviceID: nil, deviceName: s.displayName, detail: "\(s.state.rawValue): \(s.detail)", provenance: s.provenance))
            }
        }
        onChange?()
    }

    private func attach(_ incoming: DiscoveredDevice) {
        var device = incoming
        device.isPresent = true
        let key = device.stableKey(salt: keySalt)

        // Same physical unit re-plugged: continue its record and history.
        if records[device.id] == nil,
           let previous = records.values.first(where: { !$0.device.isPresent && $0.stableKey == key && $0.device.provenance == device.provenance }) {
            records.removeValue(forKey: previous.id)
            device.firstSeen = previous.device.firstSeen
            var state = previous.state
            state.advance(to: .detected, reason: "Re-attached")
            records[device.id] = evaluate(device: device, state: state, functionalEvidence: [])
            log(InventoryEvent(kind: .reattached, deviceID: device.id, deviceName: device.displayName,
                               detail: "Re-attached; continuing previous record.", provenance: device.provenance))
            return
        }

        if let existing = records[device.id] {
            device.firstSeen = existing.device.firstSeen
            var state = existing.state
            if state.status == .disconnected { state.advance(to: .detected, reason: "Re-attached") }
            records[device.id] = evaluate(device: device, state: state, functionalEvidence: existing.functionalEvidence)
            return
        }
        records[device.id] = evaluate(device: device, state: DeviceStateMachine(initial: .detected, at: device.firstSeen, reason: "Discovered by \(device.source)"),
                                      functionalEvidence: [])
        log(InventoryEvent(kind: .attached, deviceID: device.id, deviceName: device.displayName,
                           detail: "\(device.connectionType.displayName) · \(device.source)", provenance: device.provenance))
    }

    private func detach(_ id: DeviceIdentifier, at: Date) {
        guard var r = records[id], r.device.isPresent else { return }
        r.device.isPresent = false
        r.device.lastSeen = at
        r.functionalEvidence = []
        let assessment = ConnectivityAssessor.assess(device: r.device, identification: r.identification, compatibility: [],
                                                     deviceAuthorized: false, functionalEvidence: [])
        r.assessment = assessment
        r.compatibility = []
        let previous = r.status
        r.state.advance(to: .disconnected, at: at, reason: "Removed from the bus")
        r.statusReason = "The device left the bus."
        records[id] = r
        log(InventoryEvent(at: at, kind: .detached, deviceID: id, deviceName: r.device.displayName,
                           detail: "Was \(previous.displayName).", provenance: r.device.provenance))
    }

    private func evaluate(device: DiscoveredDevice, state: DeviceStateMachine, functionalEvidence: [String]) -> DeviceRecord {
        let ident = identification.identify(device)
        let compat = adapters.compatibility(for: device, identification: ident)
        let key = device.stableKey(salt: keySalt)
        let assessment = ConnectivityAssessor.assess(device: device, identification: ident, compatibility: compat,
                                                     deviceAuthorized: authorization.isDeviceAuthorized(key),
                                                     functionalEvidence: functionalEvidence)
        let (target, reason) = ConnectivityAssessor.status(device: device, identification: ident, compatibility: compat, assessment: assessment)
        var s = state
        let before = s.status
        if ident.isIdentified && s.status == .detected && target != .identified {
            s.advance(to: .identified, reason: "Matched profile \(ident.profileID ?? "")")
        }
        s.advance(to: target, reason: reason)
        if before != s.status && before != .detected {
            log(InventoryEvent(kind: .statusChanged, deviceID: device.id, deviceName: device.displayName,
                               detail: "\(before.displayName) → \(s.status.displayName)", provenance: device.provenance))
        }
        return DeviceRecord(device: device, identification: ident, compatibility: compat, assessment: assessment, state: s,
                            statusReason: reason, functionalEvidence: functionalEvidence, stableKey: key)
    }

    /// Re-runs identification and assessment (after adapters, profiles or authorisations change).
    public func reevaluateAll() {
        identification.register(contentsOf: adapters.contributedProfiles)
        for (id, r) in records where r.device.isPresent {
            records[id] = evaluate(device: r.device, state: r.state, functionalEvidence: r.functionalEvidence)
        }
        onChange?()
    }

    /// Records verified functional communication (only adapters that actually exchanged data may call this).
    public func recordFunctionalCommunication(_ id: DeviceIdentifier, evidence: [String]) {
        guard let r = records[id], r.device.isPresent, !evidence.isEmpty else { return }
        records[id] = evaluate(device: r.device, state: r.state, functionalEvidence: evidence)
        onChange?()
    }

    /// Removes disconnected records from the live view (history is kept in the Device Laboratory).
    public func clearDisconnected() {
        records = records.filter { $0.value.device.isPresent }
        onChange?()
    }

    private func log(_ e: InventoryEvent) {
        events.append(e)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
    }
}
