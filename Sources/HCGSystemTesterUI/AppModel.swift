#if os(macOS)
import Foundation
import SwiftUI
import AppKit
import HCGCore
import HCGHardware

enum WorkspaceSection: String, CaseIterable, Identifiable, Hashable {
    case commandCenter, connectedSystems, visualizer, diagnostics, laboratory, adapterLibrary, developerStudio, ecosystem, reports, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandCenter: return "Command Center"
        case .connectedSystems: return "Connected Systems"
        case .visualizer: return "Connection Visualizer"
        case .diagnostics: return "Diagnostics"
        case .laboratory: return "Device Laboratory"
        case .adapterLibrary: return "Adapter Library"
        case .developerStudio: return "Adapter Developer Studio"
        case .ecosystem: return "HCG Ecosystem"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .commandCenter: return "square.grid.3x3.topleft.filled"
        case .connectedSystems: return "cable.connector.horizontal"
        case .visualizer: return "point.3.connected.trianglepath.dotted"
        case .diagnostics: return "waveform.path.ecg.rectangle"
        case .laboratory: return "flask"
        case .adapterLibrary: return "puzzlepiece.extension"
        case .developerStudio: return "hammer"
        case .ecosystem: return "circle.hexagongrid"
        case .reports: return "doc.richtext"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .commandCenter: return "1"
        case .connectedSystems: return "2"
        case .visualizer: return "3"
        case .diagnostics: return "4"
        case .laboratory: return "5"
        case .adapterLibrary: return "6"
        case .developerStudio: return "7"
        case .ecosystem: return "8"
        case .reports: return "9"
        case .settings: return "0"
        }
    }

    var route: SystemTesterRoute {
        switch self {
        case .commandCenter: return .commandCenter
        case .connectedSystems: return .connectedSystems
        case .visualizer: return .visualizer
        case .diagnostics: return .diagnostics
        case .laboratory: return .laboratory
        case .adapterLibrary: return .adapterLibrary
        case .developerStudio: return .developerStudio
        case .ecosystem: return .ecosystem
        case .reports: return .reports
        case .settings: return .settings
        }
    }

    init(route: SystemTesterRoute) {
        self = WorkspaceSection.allCases.first { $0.route == route } ?? .commandCenter
    }
}

struct StoredReport: Identifiable, Hashable {
    var id: UUID { report.id }
    var report: SystemTesterReport
    var markdown: String
}

/// Diagnostic run in progress for one device.
struct ActiveRun: Identifiable, Equatable {
    let id = UUID()
    let deviceID: DeviceIdentifier
    let deviceName: String
    let total: Int
    var results: [DiagnosticResult] = []
    var currentTest: String?
}

/// Central, main-actor model. Discovery backends deliver events on their own queues;
/// they are hopped onto the main actor before touching the inventory.
@MainActor
final class AppModel: ObservableObject {
    @Published var section: WorkspaceSection = .commandCenter
    @Published var selectedDeviceID: DeviceIdentifier?
    @Published private(set) var records: [DeviceRecord] = []
    @Published private(set) var events: [InventoryEvent] = []
    @Published private(set) var backendStatuses: [DiscoveryBackendStatus] = []
    @Published private(set) var activeRuns: [DeviceIdentifier: ActiveRun] = [:]
    @Published private(set) var recentRuns: [DiagnosticRun] = []
    @Published private(set) var reports: [StoredReport] = []
    @Published private(set) var adapters: [RegisteredAdapter] = []
    @Published private(set) var auditEntries: [AuditEntry] = []
    @Published var labRevision = 0
    @Published var banner: String?
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            applySettingsChange(from: oldValue)
        }
    }
    @Published var newDevicePulse: DeviceIdentifier?

    let host = HostInfo.current()
    let identification: IdentificationEngine
    let adapterRegistry: AdapterRegistry
    let authorization: AuthorizationStore
    let inventory: DeviceInventory
    let laboratory: DeviceLaboratory
    let auditLog: AuditLog
    let engine: DiagnosticEngine
    private var hardwareBackends: [DeviceDiscoveryBackend] = []
    private let syntheticBackend = SyntheticDiscoveryBackend()
    private var started = false
    var activeSessionID: UUID?

    init() {
        let s = AppSettings.load()
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
        let ident = IdentificationEngine()
        let registry = AdapterRegistry()
        let authStore = AuthorizationStore()
        let audit = AuditLog(fileURL: AppPaths.auditFile)
        settings = s
        identification = ident
        adapterRegistry = registry
        authorization = authStore
        inventory = DeviceInventory(identification: ident, adapters: registry, authorization: authStore, keySalt: s.fingerprintSalt)
        laboratory = DeviceLaboratory(fileURL: AppPaths.laboratoryFile)
        auditLog = audit
        engine = DiagnosticEngine(auditLog: audit, redactor: Redactor(settings: s.privacy))
        loadStoredAdapters()
        inventory.reevaluateAll()
        adapters = adapterRegistry.adapters
        auditEntries = auditLog.entries
        auditLog.onAppend = { [weak self] _ in
            Task { @MainActor in self?.auditEntries = self?.auditLog.entries ?? [] }
        }
        laboratory.onChange = { [weak self] in
            Task { @MainActor in self?.labRevision += 1 }
        }
    }

    // MARK: Discovery

    func startIfNeeded() {
        guard !started else { return }
        started = true
        if settings.hardwareDiscoveryEnabled { startHardware() }
        if settings.syntheticFixturesEnabled { startSynthetic() }
        refreshPublishedState()
    }

    private func startHardware() {
        guard hardwareBackends.isEmpty else { return }
        hardwareBackends = HostDiscovery.makeHardwareBackends()
        if hardwareBackends.isEmpty {
            banner = "Real hardware discovery is unavailable on this platform."
        }
        for backend in hardwareBackends {
            backend.start { @Sendable [weak self] event in self?.deliver(event) }
        }
    }

    private func stopHardware() {
        hardwareBackends.forEach { $0.stop() }
        hardwareBackends.removeAll()
    }

    private func startSynthetic() {
        syntheticBackend.start { @Sendable [weak self] event in self?.deliver(event) }
    }

    private func applySettingsChange(from old: AppSettings) {
        if old.syntheticFixturesEnabled != settings.syntheticFixturesEnabled {
            if settings.syntheticFixturesEnabled { startSynthetic() } else { syntheticBackend.stop() }
        }
        if old.hardwareDiscoveryEnabled != settings.hardwareDiscoveryEnabled {
            if settings.hardwareDiscoveryEnabled { startHardware() } else { stopHardware() }
        }
        engine.redactor = Redactor(settings: settings.privacy)
        refreshPublishedState()
    }

    /// Snapshot mode only: shows labelled fixtures without persisting the preference.
    func enableSyntheticFixturesForSnapshot() {
        guard !settings.syntheticFixturesEnabled else { return }
        startSynthetic()
        refreshPublishedState()
        snapshotSyntheticOverride = true
        refreshPublishedState()
    }

    private var snapshotSyntheticOverride = false

    func restartDiscovery() {
        stopHardware()
        if settings.hardwareDiscoveryEnabled { startHardware() }
        banner = "Discovery restarted."
    }

    /// Called on a backend's queue. The main queue is FIFO, so attach/detach order is preserved
    /// (separate `Task`s would not guarantee ordering).
    nonisolated private func deliver(_ event: DiscoveryEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: DiscoveryEvent) {
        inventory.apply(event)
        switch event {
        case .attached(let d):
            // IOKit re-reads a new device a few times while drivers attach; log the attachment once.
            if let r = inventory.record(d.id), settings.recordConnectionsInLaboratory {
                let last = laboratory.profile(r.stableKey)?.history.last
                if last?.event != "Attached" { laboratory.observe(r, event: "Attached") }
            }
            if d.provenance == .hardware { newDevicePulse = d.id }
        case .detached(let id, _):
            if let r = inventory.record(id), settings.recordConnectionsInLaboratory {
                laboratory.observe(r, event: "Detached")
            }
            if let run = activeRuns[id] { banner = "\(run.deviceName) disconnected during diagnostics." }
        case .backendStatus:
            break
        }
        refreshPublishedState()
    }

    func refreshPublishedState() {
        var list = inventory.orderedRecords
        if !settings.showDisconnectedDevices { list = list.filter { $0.device.isPresent } }
        if !settings.syntheticFixturesEnabled && !snapshotSyntheticOverride {
            list = list.filter { !$0.device.provenance.isSynthetic || $0.device.isPresent }
        }
        records = list
        events = inventory.events.reversed()
        backendStatuses = Array(inventory.backendStatuses.values).sorted { $0.backendID < $1.backendID }
        adapters = adapterRegistry.adapters
        if let sel = selectedDeviceID, inventory.record(sel) == nil { selectedDeviceID = nil }
    }

    var presentRecords: [DeviceRecord] { records.filter { $0.device.isPresent } }
    var hardwareRecords: [DeviceRecord] { presentRecords.filter { $0.device.provenance == .hardware } }
    var selectedRecord: DeviceRecord? { selectedDeviceID.flatMap { inventory.record($0) } }

    func record(_ id: DeviceIdentifier) -> DeviceRecord? { inventory.record(id) }

    func clearDisconnected() {
        inventory.clearDisconnected()
        refreshPublishedState()
    }

    func simulateSynthetic(detach id: DeviceIdentifier) { syntheticBackend.simulateDetach(id) }
    func simulateSynthetic(attach id: DeviceIdentifier) { syntheticBackend.simulateAttach(id) }

    func probe(for device: DiscoveredDevice) -> DeviceProbe? {
        if device.provenance.isSynthetic { return syntheticBackend }
        return hardwareBackends.first { $0.connectionTypes.contains(device.connectionType) }
    }

    // MARK: Authorisation

    func isAuthorized(_ r: DeviceRecord) -> Bool { authorization.isDeviceAuthorized(r.stableKey) }

    func setAuthorized(_ r: DeviceRecord, _ authorized: Bool) {
        if authorized { authorization.authorizeDevice(r.stableKey) } else { authorization.revokeDevice(r.stableKey) }
        auditLog.record(AuditEntry(actor: "user", operation: authorized ? "device.authorize" : "device.revoke", impact: .readOnly,
                                   target: engine.redactor.redact(r.device.displayName), targetKey: r.stableKey,
                                   decision: authorized ? "granted" : "revoked", outcome: "ok", provenance: r.device.provenance))
        inventory.reevaluateAll()
        refreshPublishedState()
    }

    // MARK: Diagnostics

    func run(testIDs: [String], on record: DeviceRecord, authorization auth: DiagnosticAuthorization) {
        guard activeRuns[record.id] == nil else { return }
        guard let probe = probe(for: record.device) else {
            banner = "No discovery backend can re-read \(record.device.displayName)."
            return
        }
        let ctx = DiagnosticContext(device: record.device, identification: record.identification, probe: probe, deviceKey: record.stableKey)
        activeRuns[record.id] = ActiveRun(deviceID: record.id, deviceName: record.device.displayName, total: testIDs.count)
        let engine = self.engine
        let deviceID = record.id
        Task { @MainActor in
            let run = await engine.run(testIDs: testIDs, context: ctx, authorization: auth) { @Sendable [weak self] result in
                Task { @MainActor in
                    self?.activeRuns[deviceID]?.results.append(result)
                }
            }
            self.finish(run, record: record)
        }
    }

    private func finish(_ run: DiagnosticRun, record: DeviceRecord) {
        activeRuns[record.id] = nil
        recentRuns.insert(run, at: 0)
        if recentRuns.count > 100 { recentRuns.removeLast(recentRuns.count - 100) }
        let sessionID: UUID
        if let s = activeSessionID, laboratory.sessions.contains(where: { $0.id == s }) {
            sessionID = s
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            sessionID = laboratory.createSession(title: "Session \(formatter.string(from: Date()))").id
            activeSessionID = sessionID
        }
        laboratory.append(run, to: sessionID)
        // Synthetic fixtures exchange data with the engine; record it (labelled) so the full state machine can be exercised.
        if record.device.provenance.isSynthetic,
           run.results.contains(where: { $0.testID == "synthetic.fault-injection" && $0.outcome == .passed }) {
            inventory.recordFunctionalCommunication(record.id, evidence: ["SYNTHETIC: fault-injection exchange with fixture"])
        }
        refreshPublishedState()
    }

    func runDefaultSuite(on record: DeviceRecord) {
        run(testIDs: engine.defaultSuite(for: record.device, identification: record.identification), on: record, authorization: .readOnly)
    }

    // MARK: Reports

    @discardableResult
    func generateReport(title: String, runs: [DiagnosticRun], deviceIDs: [DeviceIdentifier], notes: String = "") -> StoredReport {
        var keys = Set(runs.map(\.deviceKey))
        for id in deviceIDs { if let r = inventory.record(id) { keys.insert(r.stableKey) } }
        let recs = inventory.orderedRecords.filter { keys.contains($0.stableKey) }
        var redactor = Redactor(settings: settings.privacy)
        redactor.registerHostName(host.name)
        let report = ReportGenerator.make(title: title, runs: runs, records: recs, redactor: redactor, notes: notes)
        let stored = StoredReport(report: report, markdown: ReportGenerator.markdown(report))
        reports.insert(stored, at: 0)
        return stored
    }

    func export(_ stored: StoredReport, format: ReportFormat) throws -> Data {
        switch format {
        case .markdown: return Data(stored.markdown.utf8)
        case .json: return try ReportGenerator.json(stored.report)
        case .deviceLink:
            var r = Redactor(settings: settings.privacy)
            r.registerHostName(host.name)
            let link = ReportGenerator.deviceLinkReport(stored.report, installationID: settings.installationID,
                                                        deviceName: r.redact(host.name))
            let problems = link.problems()
            guard problems.isEmpty else { throw ExportError.invalid(problems) }
            return try link.encoded()
        }
    }

    enum ExportError: LocalizedError {
        case invalid([String])
        var errorDescription: String? {
            switch self { case .invalid(let p): return "The report cannot be exported: " + p.joined(separator: "; ") }
        }
    }

    // MARK: Adapters

    private func loadStoredAdapters() {
        let dir = AppPaths.adaptersDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url) {
                _ = try? adapterRegistry.importManifest(data: data, origin: .imported)
            }
        }
    }

    /// Imports a manifest. It is stored untrusted and disabled; it never executes until approved.
    func importAdapter(data: Data, origin: AdapterOrigin = .imported) throws -> RegisteredAdapter {
        let entry = try adapterRegistry.importManifest(data: data, origin: origin)
        try FileManager.default.createDirectory(at: AppPaths.adaptersDirectory, withIntermediateDirectories: true)
        try entry.manifest.encoded().write(to: AppPaths.adaptersDirectory.appendingPathComponent(entry.manifest.id + ".json"), options: .atomic)
        auditLog.record(AuditEntry(actor: "user", operation: "adapter.import", impact: .readOnly, target: entry.manifest.id, targetKey: entry.manifest.id,
                                   decision: "stored-untrusted", outcome: "ok", provenance: .imported))
        adapters = adapterRegistry.adapters
        return entry
    }

    func approveAdapter(_ id: String) {
        do {
            try adapterRegistry.approve(id)
            auditLog.record(AuditEntry(actor: "user", operation: "adapter.approve", impact: .readOnly, target: id, targetKey: id,
                                       decision: "approved", outcome: "ok", provenance: .imported))
            inventory.reevaluateAll()
        } catch {
            banner = String(describing: error)
        }
        refreshPublishedState()
    }

    func setAdapterEnabled(_ id: String, _ enabled: Bool) {
        do { try adapterRegistry.setEnabled(id, enabled) } catch { banner = String(describing: error) }
        inventory.reevaluateAll()
        refreshPublishedState()
    }

    func removeAdapter(_ id: String) {
        do {
            try adapterRegistry.remove(id)
            try? FileManager.default.removeItem(at: AppPaths.adaptersDirectory.appendingPathComponent(id + ".json"))
        } catch { banner = String(describing: error) }
        inventory.reevaluateAll()
        refreshPublishedState()
    }

    // MARK: Ecosystem

    func ecosystemStatus(_ integration: EcosystemIntegration) -> EcosystemIntegration.Status {
        guard let scheme = integration.urlScheme, let url = URL(string: "\(scheme)://open/dashboard") else { return integration.status }
        return NSWorkspace.shared.urlForApplication(toOpen: url) == nil ? .notInstalled : .available
    }

    /// Opens an allow-listed navigation link. Never forwards data from devices or manifests.
    func openNavigationLink(_ url: URL) {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            banner = "No application on this Mac handles \(url.scheme ?? "this link")://."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func handleIncoming(_ url: URL) {
        guard let route = SystemTesterRoute.parse(url) else {
            banner = "Ignored an unsupported link. System Tester accepts navigation links only."
            return
        }
        section = WorkspaceSection(route: route)
    }

    // MARK: Helpers

    func displaySerial(_ serial: String?) -> String {
        guard let s = serial else { return "Not reported" }
        return settings.privacy.hideSerialNumbersInInterface ? Redactor.maskSerial(s) : s
    }
}
#endif
