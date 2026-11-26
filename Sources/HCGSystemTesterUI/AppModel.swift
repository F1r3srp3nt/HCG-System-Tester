#if os(macOS)
import Foundation
import SwiftUI
import AppKit
import HCGCore
import HCGHardware

enum WorkspaceSection: String, CaseIterable, Identifiable, Hashable {
    case commandCenter, connectedSystems, liveMonitor, visualizer, usbInspector, diagnostics, laboratory, adapterLibrary, developerStudio, ecosystem, reports, settings
    case connectivityCenter, encyclopedia, connectionStudio, connectedDevices, protocolRegistry, hardwareRequirements, roadmap, gapAnalyzer, compatibilityMatrix, assistant, connectionHistory

    static let workspaceSections: [WorkspaceSection] = [.commandCenter, .connectedSystems, .liveMonitor, .visualizer, .usbInspector, .diagnostics,
                                                        .laboratory, .adapterLibrary, .developerStudio, .ecosystem, .reports, .settings]
    static let connectivitySections: [WorkspaceSection] = [.connectivityCenter, .encyclopedia, .connectionStudio, .connectedDevices, .protocolRegistry,
                                                           .hardwareRequirements, .roadmap, .gapAnalyzer, .compatibilityMatrix, .assistant, .connectionHistory]
    var isConnectivity: Bool { WorkspaceSection.connectivitySections.contains(self) }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandCenter: return "Command Center"
        case .connectedSystems: return "Connected Systems"
        case .liveMonitor: return "Live Device Monitor"
        case .visualizer: return "Connection Visualizer"
        case .usbInspector: return "USB Connection Inspector"
        case .diagnostics: return "Diagnostics"
        case .laboratory: return "Device Laboratory"
        case .adapterLibrary: return "Adapter Library"
        case .developerStudio: return "Adapter Developer Studio"
        case .ecosystem: return "Ecosystem Integrations"
        case .reports: return "Reports"
        case .settings: return "Settings"
        case .connectivityCenter: return "Universal Connectivity Center"
        case .encyclopedia: return "Device Encyclopedia"
        case .connectionStudio: return "Connection Studio"
        case .connectedDevices: return "Connected Devices"
        case .protocolRegistry: return "Protocol Registry"
        case .hardwareRequirements: return "Hardware Requirements"
        case .roadmap: return "Development Roadmap"
        case .gapAnalyzer: return "Gap Analyzer"
        case .compatibilityMatrix: return "Compatibility Matrix"
        case .assistant: return "AI Connection Assistant"
        case .connectionHistory: return "Connection History"
        }
    }

    var symbol: String {
        switch self {
        case .commandCenter: return "square.grid.3x3.topleft.filled"
        case .connectedSystems: return "cable.connector.horizontal"
        case .liveMonitor: return "waveform.path.ecg"
        case .visualizer: return "point.3.connected.trianglepath.dotted"
        case .usbInspector: return "magnifyingglass.circle"
        case .diagnostics: return "waveform.path.ecg.rectangle"
        case .laboratory: return "flask"
        case .adapterLibrary: return "puzzlepiece.extension"
        case .developerStudio: return "hammer"
        case .ecosystem: return "circle.hexagongrid"
        case .reports: return "doc.richtext"
        case .settings: return "gearshape"
        case .connectivityCenter: return "dot.radiowaves.left.and.right"
        case .encyclopedia: return "books.vertical"
        case .connectionStudio: return "wand.and.rays"
        case .connectedDevices: return "link.circle"
        case .protocolRegistry: return "list.bullet.rectangle"
        case .hardwareRequirements: return "cable.coaxial"
        case .roadmap: return "map"
        case .gapAnalyzer: return "exclamationmark.triangle"
        case .compatibilityMatrix: return "tablecells"
        case .assistant: return "sparkles"
        case .connectionHistory: return "clock.arrow.circlepath"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .commandCenter: return "1"
        case .connectedSystems: return "2"
        case .liveMonitor: return "l"
        case .visualizer: return "3"
        case .usbInspector: return "u"
        case .diagnostics: return "4"
        case .laboratory: return "5"
        case .adapterLibrary: return "6"
        case .developerStudio: return "7"
        case .ecosystem: return "8"
        case .reports: return "9"
        case .settings: return "0"
        case .connectivityCenter: return "c"
        case .encyclopedia: return "e"
        case .connectionStudio: return "s"
        case .connectedDevices: return "k"
        case .protocolRegistry: return "p"
        case .hardwareRequirements: return "h"
        case .roadmap: return "m"
        case .gapAnalyzer: return "g"
        case .compatibilityMatrix: return "x"
        case .assistant: return "a"
        case .connectionHistory: return "y"
        }
    }

    var shortcutModifiers: EventModifiers {
        if isConnectivity { return [.command, .control] }
        return self == .liveMonitor || self == .usbInspector ? [.command, .option] : .command
    }

    var route: SystemTesterRoute {
        switch self {
        case .commandCenter: return .commandCenter
        case .connectedSystems: return .connectedSystems
        case .liveMonitor: return .liveMonitor
        case .visualizer: return .visualizer
        case .usbInspector: return .usbInspector
        case .diagnostics: return .diagnostics
        case .laboratory: return .laboratory
        case .adapterLibrary: return .adapterLibrary
        case .developerStudio: return .developerStudio
        case .ecosystem: return .ecosystem
        case .reports: return .reports
        case .settings: return .settings
        case .connectivityCenter: return .connectivity
        case .encyclopedia: return .encyclopedia
        case .connectionStudio: return .connectionStudio
        case .connectedDevices: return .connectedDevices
        case .protocolRegistry: return .protocols
        case .hardwareRequirements: return .hardwareRequirements
        case .roadmap: return .roadmap
        case .gapAnalyzer: return .gaps
        case .compatibilityMatrix: return .compatibility
        case .assistant: return .assistant
        case .connectionHistory: return .history
        }
    }

    init(route: SystemTesterRoute) {
        self = WorkspaceSection.allCases.first { $0.route == route } ?? .commandCenter
    }
}

enum DeviceWorkspaceTab: String, CaseIterable, Identifiable, Hashable {
    case overview, hardware, software, diagnostics, authorization, activity, reports
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: return "rectangle.on.rectangle"
        case .hardware: return "cpu"
        case .software: return "app.badge"
        case .diagnostics: return "stethoscope"
        case .authorization: return "lock.shield"
        case .activity: return "clock.arrow.circlepath"
        case .reports: return "doc.text"
        }
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
    @Published var workspaceTab: DeviceWorkspaceTab = .overview
    @Published private(set) var intelligenceRevision = 0
    @Published private(set) var monitorRevision = 0
    @Published private(set) var toolchain: AppleToolchainStatus?
    @Published private(set) var busyIntelligence: Set<DeviceIdentifier> = []
    @Published private(set) var appleApps: [DeviceIdentifier: [AppleAppInfo]] = [:]
    @Published var monitorPaused = false

    let host = HostInfo.current()
    let identification: IdentificationEngine
    let adapterRegistry: AdapterRegistry
    let authorization: AuthorizationStore
    let inventory: DeviceInventory
    let laboratory: DeviceLaboratory
    let auditLog: AuditLog
    let engine: DiagnosticEngine
    let intelligence: DeviceIntelligenceEngine
    let appleProvider: AppleDeviceIntelligenceProvider
    let syntheticAppleProvider: AppleDeviceIntelligenceProvider
    let liveMonitor = LiveMonitor()
    private var intelligenceTasks: [DeviceIdentifier: Task<Void, Never>] = [:]
    private var lastIntelligenceRefresh: [DeviceIdentifier: Date] = [:]
    private var lastCoreDeviceSample: [String: Date] = [:]
    private var monitorTask: Task<Void, Never>?
    private var hardwareBackends: [DeviceDiscoveryBackend] = []
    private let syntheticBackend = SyntheticDiscoveryBackend()
    private var started = false
    var activeSessionID: UUID?
    /// Universal Connectivity (created on first use; creating it never scans or connects).
    lazy var connectivity = ConnectivityModel(app: self)

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
        let apple = AppleDeviceIntelligenceProvider(runner: ProcessCommandRunner(), provenance: .hardware)
        let appleFixture = AppleDeviceIntelligenceProvider(runner: SyntheticAppleRunner(paired: false), provenance: .synthetic)
        appleProvider = apple
        syntheticAppleProvider = appleFixture
        intelligence = DeviceIntelligenceEngine(providers: [apple, appleFixture, GenericUSBIntelligenceProvider()])
        engine = DiagnosticEngine(tests: HostOperationCatalog.standardTests() + AppleDiagnostics.tests(providers: [apple, appleFixture]),
                                  auditLog: audit, redactor: Redactor(settings: s.privacy))
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
        let engineRef = intelligence
        apple.timelineProvider = { key in engineRef.timeline(key: key) }
        appleFixture.timelineProvider = { key in engineRef.timeline(key: key) }
    }

    // MARK: Discovery

    func startIfNeeded() {
        guard !started else { return }
        started = true
        if settings.hardwareDiscoveryEnabled { startHardware() }
        if settings.syntheticFixturesEnabled { startSynthetic() }
        refreshPublishedState()
        Task { @MainActor in self.toolchain = await self.appleProvider.toolchain() }
        startMonitor()
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
        let lastBefore = inventory.events.last?.id
        inventory.apply(event)
        let newEvents: [InventoryEvent] = {
            guard let lb = lastBefore, let i = inventory.events.lastIndex(where: { $0.id == lb }) else { return inventory.events }
            return Array(inventory.events[(i + 1)...])
        }()
        switch event {
        case .attached(let d):
            if let r = inventory.record(d.id) {
                let isNew = newEvents.contains { $0.deviceID == d.id && ($0.kind == .attached || $0.kind == .reattached) }
                if isNew {
                    let kind: IntelligenceTimelineEntry.Kind = newEvents.contains { $0.kind == .reattached } ? .reconnect : .connect
                    intelligence.append(IntelligenceTimelineEntry(kind: kind, message: kind == .reconnect ? "Reconnected; re-identifying." : "Connected: \(d.source).",
                                                                  provenance: d.provenance), key: r.stableKey)
                    liveMonitor.connected(key: r.stableKey)
                }
                // Apple devices publish their services a moment after enumeration; let IOKit settle first.
                let isApple = AppleDeviceIntelligenceProvider.isAppleMobileDevice(d)
                scheduleIntelligence(d.id, delay: isApple ? (isNew ? 1.5 : 0.8) : 0)
            }
            // IOKit re-reads a new device a few times while drivers attach; log the attachment once.
            if let r = inventory.record(d.id), settings.recordConnectionsInLaboratory {
                let last = laboratory.profile(r.stableKey)?.history.last
                if last?.event != "Attached" { laboratory.observe(r, event: "Attached") }
            }
            if d.provenance == .hardware { newDevicePulse = d.id }
            connectivity.usbAttached(d)
        case .detached(let id, _):
            intelligenceTasks[id]?.cancel()
            intelligenceTasks[id] = nil
            if let r = inventory.record(id) {
                if settings.recordConnectionsInLaboratory { laboratory.observe(r, event: "Detached") }
                intelligence.markDisconnected(id, key: r.stableKey)
                liveMonitor.disconnected(key: r.stableKey)
                connectivity.usbDetached(r.device)
                intelligenceRevision += 1
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

    // MARK: Device intelligence

    func snapshot(_ id: DeviceIdentifier) -> IntelligenceSnapshot? {
        _ = intelligenceRevision
        return intelligence.snapshots[id]
    }

    func timeline(for record: DeviceRecord) -> [IntelligenceTimelineEntry] {
        _ = intelligenceRevision
        return intelligence.timeline(key: record.stableKey)
    }

    func provider(for record: DeviceRecord) -> DeviceIntelligenceProvider? {
        intelligence.provider(for: record.device, identification: record.identification)
    }

    func appleProvider(for record: DeviceRecord) -> AppleDeviceIntelligenceProvider? {
        provider(for: record) as? AppleDeviceIntelligenceProvider
    }

    func scheduleIntelligence(_ id: DeviceIdentifier, delay: TimeInterval, force: Bool = false) {
        intelligenceTasks[id]?.cancel()
        intelligenceTasks[id] = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.refreshIntelligence(id, force: force)
        }
    }

    /// Re-reads the device through its family adapter. Never starts pairing and never prompts the device.
    func refreshIntelligence(_ id: DeviceIdentifier, force: Bool = false) async {
        guard let r = inventory.record(id), r.device.isPresent, let p = provider(for: r) else { return }
        if force, let apple = p as? AppleDeviceIntelligenceProvider { apple.invalidateCaches() }
        busyIntelligence.insert(id)
        let snap = await p.snapshot(for: r.device, identification: r.identification)
        busyIntelligence.remove(id)
        guard let current = inventory.record(id), current.device.isPresent else { return }
        intelligence.record(snap, key: current.stableKey)
        lastIntelligenceRefresh[id] = Date()
        inventory.applyIntelligence(id, communication: snap.communicationEvidence, authorization: snap.authorizationEvidence)
        connectivity.intelligenceUpdated(current, snapshot: snap)
        intelligenceRevision += 1
        refreshPublishedState()
    }

    func refreshToolchain() {
        Task { @MainActor in
            self.toolchain = await self.appleProvider.toolchain(forceRefresh: true)
            for r in self.presentRecords where AppleDeviceIntelligenceProvider.isAppleMobileDevice(r.device) {
                await self.refreshIntelligence(r.id, force: true)
            }
        }
    }

    /// Runs a user-approved action (e.g. Apple's pairing flow) and records it.
    func performIntelligenceAction(_ kind: NextActionKind, on record: DeviceRecord) {
        guard let p = provider(for: record) else { return }
        busyIntelligence.insert(record.id)
        auditLog.record(AuditEntry(actor: "user", operation: "intelligence.\(kind.rawValue)", impact: kind == .pairDevice ? .stateChanging : .readOnly,
                                   target: engine.redactor.redact(record.device.displayName), targetKey: record.stableKey,
                                   decision: "user-initiated", outcome: "started", provenance: record.device.provenance))
        Task { @MainActor in
            let outcome = await p.perform(kind, for: record.device, identification: record.identification)
            self.busyIntelligence.remove(record.id)
            self.intelligence.append(IntelligenceTimelineEntry(kind: .action, message: "\(kind.rawValue): \(outcome.message)", provenance: record.device.provenance),
                                     key: record.stableKey)
            self.banner = outcome.message
            await self.refreshIntelligence(record.id, force: true)
        }
    }

    func loadApps(for record: DeviceRecord) {
        guard let apple = appleProvider(for: record), let id = snapshot(record.id)?.value("apple.coreDeviceIdentifier") else {
            banner = "Installed-app information needs a paired device visible to CoreDevice."
            return
        }
        busyIntelligence.insert(record.id)
        auditLog.record(AuditEntry(actor: "user", operation: "apple.list-apps", impact: .readOnly, target: engine.redactor.redact(record.device.displayName),
                                   targetKey: record.stableKey, decision: "user-initiated", outcome: "started", provenance: record.device.provenance))
        Task { @MainActor in
            let result = await apple.installedApps(identifier: id)
            self.busyIntelligence.remove(record.id)
            if let e = result.error { self.banner = "Could not list apps: \(e)" }
            self.appleApps[record.id] = result.apps.map { AppleAppInfo(name: $0.name, bundleID: $0.bundleID, version: $0.version) }
        }
    }

    // MARK: Live Device Monitor

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if self.settings.monitorEnabled && !self.monitorPaused { await self.monitorTick() }
                let interval = max(1, self.settings.monitorIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func monitorTick() async {
        for r in presentRecords {
            guard let probe = probe(for: r.device) else { continue }
            let id = r.device.id
            let measured = await Task.detached { () -> (Bool, Double) in
                let t0 = DispatchTime.now().uptimeNanoseconds
                let present = probe.refresh(id) != nil
                return (present, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }.value
            let source = r.device.provenance.isSynthetic ? "SYNTHETIC fixture re-read" : "IOKit registry re-read"
            liveMonitor.record(MonitorSample(present: measured.0, latencyMs: measured.1, source: source, provenance: r.device.provenance), key: r.stableKey)

            guard let apple = appleProvider(for: r), let snap = intelligence.snapshots[r.id] else { continue }
            if settings.autoRefreshIntelligence, Date().timeIntervalSince(lastIntelligenceRefresh[r.id] ?? .distantPast) > settings.intelligenceRefreshSeconds {
                await refreshIntelligence(r.id)
            }
            if settings.monitorCoreDevice, !snap.communicationEvidence.isEmpty, let cdID = snap.value("apple.coreDeviceIdentifier"),
               Date().timeIntervalSince(lastCoreDeviceSample[r.stableKey] ?? .distantPast) >= max(15, settings.coreDeviceIntervalSeconds) {
                lastCoreDeviceSample[r.stableKey] = Date()
                let m = await apple.measureQueryLatency(identifier: cdID)
                liveMonitor.record(MonitorSample(present: m.ms != nil, latencyMs: m.ms,
                                                 source: apple.provenance == .synthetic ? "SYNTHETIC devicectl fixture" : "devicectl device info details",
                                                 provenance: r.device.provenance), key: r.stableKey)
            }
        }
        monitorRevision += 1
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
        connectivity.diagnosticsFinished(run, record: record)
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

    func exportInventorySnapshot() throws -> Data {
        var r = Redactor(settings: settings.privacy)
        r.registerHostName(host.name)
        let snap = DeviceInventorySnapshot.make(records: records, snapshots: intelligence.snapshots, installationID: settings.installationID, redactor: r)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(snap)
    }

    func exportSentinelFindings() throws -> Data {
        var r = Redactor(settings: settings.privacy)
        r.registerHostName(host.name)
        let report = ConnectionSecurityFindings.report(records: records, snapshots: intelligence.snapshots, adapters: adapterRegistry.adapters,
                                                       installationID: settings.installationID, deviceName: r.redact(host.name), redactor: r)
        return try report.encoded()
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
        return settings.privacy.hideSerialNumbersInInterface || settings.maskDeviceIdentifiers ? Redactor.maskSerial(s) : s
    }
}
#endif

#if os(macOS)
struct AppleAppInfo: Identifiable, Hashable {
    var name: String
    var bundleID: String
    var version: String?
    var id: String { bundleID }
}
#endif
