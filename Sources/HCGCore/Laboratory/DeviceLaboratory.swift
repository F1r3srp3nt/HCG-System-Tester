import Foundation

public struct ConnectionHistoryEntry: Codable, Hashable {
    public var at: Date
    public var event: String
    public var status: DeviceStatus
}

public struct CompatibilityEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    public var at: Date
    public var connectionType: ConnectionType
    public var outcome: String
    public var limitingLayer: String?
    public var notes: String
    public var provenance: DataProvenance

    public init(at: Date = Date(), connectionType: ConnectionType, outcome: String, limitingLayer: String?, notes: String, provenance: DataProvenance) {
        self.id = UUID()
        self.at = at
        self.connectionType = connectionType
        self.outcome = outcome
        self.limitingLayer = limitingLayer
        self.notes = notes
        self.provenance = provenance
    }
}

/// A saved profile of one physical unit, keyed by its stable key (never by raw serial number).
public struct SavedDeviceProfile: Codable, Hashable, Identifiable {
    public var key: String
    public var displayName: String
    public var nickname: String
    public var category: DeviceCategory
    public var profileID: String?
    public var vendorIDHex: String
    public var productIDHex: String
    public var provenance: DataProvenance
    public var firstSeen: Date
    public var lastSeen: Date
    public var notes: String
    public var history: [ConnectionHistoryEntry]
    public var compatibility: [CompatibilityEntry]

    public var id: String { key }
}

public struct DiagnosticSession: Codable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var deviceKeys: [String]
    public var runs: [DiagnosticRun]
    public var notes: String

    public init(title: String, createdAt: Date = Date(), deviceKeys: [String] = [], runs: [DiagnosticRun] = [], notes: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.deviceKeys = deviceKeys
        self.runs = runs
        self.notes = notes
    }

    public var containsSyntheticData: Bool { runs.contains { $0.provenance.isSynthetic } }
}

public struct TestCollection: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var testIDs: [String]
    public var authorization: DiagnosticAuthorization

    public init(name: String, testIDs: [String], authorization: DiagnosticAuthorization = .readOnly) {
        self.id = UUID()
        self.name = name
        self.testIDs = testIDs
        self.authorization = authorization
    }
}

public struct MeasurementPoint: Codable, Hashable, Identifiable {
    public var at: Date
    public var value: Double
    public var unit: String
    public var runID: UUID
    public var provenance: DataProvenance
    public var id: String { runID.uuidString + "@" + String(at.timeIntervalSince1970) }
}

public struct LabState: Codable, Hashable {
    public var schemaVersion: Int = 1
    public var profiles: [SavedDeviceProfile] = []
    public var sessions: [DiagnosticSession] = []
    public var collections: [TestCollection] = []
    public init() {}
}

/// Workspace for organising devices, sessions and measurements over time. Persists as JSON.
public final class DeviceLaboratory {
    public private(set) var state: LabState
    public let fileURL: URL?
    public var onChange: (() -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let url = fileURL, let data = try? Data(contentsOf: url), let s = try? Self.decoder.decode(LabState.self, from: data) {
            state = s
        } else {
            state = LabState()
        }
        if state.collections.isEmpty {
            state.collections = [
                TestCollection(name: "Quick read-only check", testIDs: ["host.presence", "host.identification", "host.interfaces", "host.link-speed"]),
                TestCollection(name: "Full read-only suite", testIDs: ["host.presence", "host.identification", "host.interfaces", "host.protocol-validation",
                                                                      "host.link-speed", "host.firmware-info", "host.storage-info", "host.enumeration-errors",
                                                                      "host.registry-latency", "host.presence-stability"]),
                TestCollection(name: "Cable & port qualification (extended)", testIDs: ["host.link-speed", "host.presence-stability-extended", "host.registry-latency"],
                               authorization: DiagnosticAuthorization(allowExtended: true))
            ]
        }
    }

    public var profiles: [SavedDeviceProfile] { state.profiles.sorted { $0.lastSeen > $1.lastSeen } }
    public var sessions: [DiagnosticSession] { state.sessions.sorted { $0.createdAt > $1.createdAt } }
    public var collections: [TestCollection] { state.collections }

    public func profile(_ key: String) -> SavedDeviceProfile? { state.profiles.first { $0.key == key } }

    /// Creates or updates the saved profile for a record and appends a history entry.
    public func observe(_ record: DeviceRecord, event: String, at date: Date = Date()) {
        let d = record.device
        let entry = ConnectionHistoryEntry(at: date, event: event, status: record.status)
        if let i = state.profiles.firstIndex(where: { $0.key == record.stableKey }) {
            state.profiles[i].lastSeen = date
            state.profiles[i].displayName = d.displayName
            state.profiles[i].category = record.identification.category
            state.profiles[i].profileID = record.identification.profileID
            state.profiles[i].history.append(entry)
            if state.profiles[i].history.count > 500 { state.profiles[i].history.removeFirst(state.profiles[i].history.count - 500) }
        } else {
            state.profiles.append(SavedDeviceProfile(
                key: record.stableKey, displayName: d.displayName, nickname: "", category: record.identification.category,
                profileID: record.identification.profileID, vendorIDHex: d.usb?.vendorIDHex ?? "—", productIDHex: d.usb?.productIDHex ?? "—",
                provenance: d.provenance, firstSeen: date, lastSeen: date, notes: "", history: [entry], compatibility: []))
        }
        changed()
    }

    public func setNotes(_ notes: String, for key: String) {
        guard let i = state.profiles.firstIndex(where: { $0.key == key }) else { return }
        state.profiles[i].notes = notes
        changed()
    }

    public func setNickname(_ nickname: String, for key: String) {
        guard let i = state.profiles.firstIndex(where: { $0.key == key }) else { return }
        state.profiles[i].nickname = nickname
        changed()
    }

    /// Records compatibility evidence, including unsuccessful connections.
    public func recordCompatibility(_ record: DeviceRecord, notes: String = "") {
        if profile(record.stableKey) == nil { observe(record, event: "Profile created for compatibility evidence") }
        guard let i = state.profiles.firstIndex(where: { $0.key == record.stableKey }) else { return }
        state.profiles[i].compatibility.append(CompatibilityEntry(
            connectionType: record.device.connectionType, outcome: record.status.displayName,
            limitingLayer: record.assessment.limitingLayer.map { "\($0.layer.displayName): \($0.reason)" },
            notes: notes.isEmpty ? record.statusReason : notes, provenance: record.device.provenance))
        changed()
    }

    @discardableResult
    public func createSession(title: String, deviceKeys: [String] = []) -> DiagnosticSession {
        let s = DiagnosticSession(title: title, deviceKeys: deviceKeys)
        state.sessions.append(s)
        changed()
        return s
    }

    public func append(_ run: DiagnosticRun, to sessionID: UUID) {
        guard let i = state.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        state.sessions[i].runs.append(run)
        if !state.sessions[i].deviceKeys.contains(run.deviceKey) { state.sessions[i].deviceKeys.append(run.deviceKey) }
        changed()
    }

    public func setSessionNotes(_ notes: String, for sessionID: UUID) {
        guard let i = state.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        state.sessions[i].notes = notes
        changed()
    }

    public func deleteSession(_ id: UUID) {
        state.sessions.removeAll { $0.id == id }
        changed()
    }

    public func addCollection(_ c: TestCollection) {
        state.collections.append(c)
        changed()
    }

    public var allRuns: [DiagnosticRun] { state.sessions.flatMap(\.runs).sorted { $0.startedAt < $1.startedAt } }

    /// Time series of one measurement for one physical unit, across all sessions.
    public func series(deviceKey: String, measurement name: String) -> [MeasurementPoint] {
        allRuns.filter { $0.deviceKey == deviceKey }.flatMap { run in
            run.results.flatMap { r in
                r.measurements.filter { $0.name == name }.map {
                    MeasurementPoint(at: r.finishedAt, value: $0.value, unit: $0.unit, runID: run.id, provenance: $0.provenance)
                }
            }
        }
    }

    public func measurementNames(deviceKey: String) -> [String] {
        Array(Set(allRuns.filter { $0.deviceKey == deviceKey }.flatMap { $0.results.flatMap { $0.measurements.map(\.name) } })).sorted()
    }

    /// Compares the latest value of each measurement across devices.
    public func comparison(deviceKeys: [String]) -> [(measurement: String, values: [String: DiagnosticMeasurement])] {
        var table: [String: [String: DiagnosticMeasurement]] = [:]
        for run in allRuns where deviceKeys.contains(run.deviceKey) {
            for r in run.results {
                for m in r.measurements { table[m.name, default: [:]][run.deviceKey] = m }
            }
        }
        return table.keys.sorted().map { ($0, table[$0] ?? [:]) }
    }

    public func reset() {
        state = LabState()
        changed()
    }

    private func changed() {
        save()
        onChange?()
    }

    public func save() {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            // Persistence failures are surfaced by the caller through `lastSaveError`.
            lastSaveError = String(describing: error)
        }
    }

    public private(set) var lastSaveError: String?

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
