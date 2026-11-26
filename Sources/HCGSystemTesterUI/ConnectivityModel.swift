#if os(macOS)
import Foundation
import SwiftUI
import HCGCore
import HCGHardware

/// Universal Connectivity state for the UI. Created lazily the first time it is needed.
///
/// Rules enforced here:
/// - Nothing scans, connects or queries a device unless the user starts it.
/// - A connection attempt needs a fresh, single-use approval for that profile.
/// - Roadmap state changes only from genuine (hardware or user-reported) evidence or recorded manual decisions.
/// - Unmatched scan results stay in memory; only profile-matched or user-used endpoints are kept in history.
@MainActor
final class ConnectivityModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var detected: [String: EquipmentStatus] = [:]
    @Published private(set) var interfaces: [HostNetwork.Interface] = []
    @Published private(set) var sessionEndpoints: [String: ObservedEndpoint] = [:]
    @Published private(set) var liveIDs: Set<String> = []
    @Published private(set) var lastResults: [String: ConnectionAttemptResult] = [:]
    @Published private(set) var approvals: Set<String> = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var aiStatus: HCGAIHandoffStatus?
    @Published private(set) var bleStatus = "Not started — nothing is scanned until you press Scan."
    @Published private(set) var bleScanning = false
    @Published private(set) var bonjourRunning = false
    @Published private(set) var networkStatus = "Not started — nothing is discovered until you press Discover."
    @Published private(set) var ssdpRunning = false
    @Published private(set) var lastEquipmentRefresh: Date?
    @Published var selectedProfileID: String?
    @Published var selectedEndpointByProfile: [String: String] = [:]
    @Published var manualHosts: [String: String] = [:]

    let store: ConnectivityStore
    private weak var app: AppModel?
    private var ble: BLEExplorer?
    private var bonjour: BonjourBrowser?
    private var recordedThisSession: Set<String> = []
    private(set) var profiles: [EncyclopediaProfile]

    init(app: AppModel) {
        self.app = app
        store = ConnectivityStore(fileURL: AppPaths.connectivityFile, userProfilesDirectory: AppPaths.encyclopediaDirectory)
        profiles = store.profiles
        selectedProfileID = profiles.first { $0.id == "apple.iphone-ipad" }?.id ?? profiles.first?.id
        if store.roadmap.items.isEmpty { store.recomputeRoadmap(detected: [:]) }
    }

    // MARK: Derived data

    var env: RoadmapEnvironment { store.environment(detected: detected) }
    var equipment: [String: EquipmentStatus] { store.equipmentStatus(detected: detected) }
    var evidence: [ConnectivityEvidence] { store.state.evidence }
    var roadmapItems: [RoadmapItem] { store.roadmap.sorted }
    var gaps: [DevelopmentRequirement] { GapAnalyzer.all(profiles: profiles, env: env, priorities: store.state.gapPriorities) }

    func profile(_ id: String?) -> EncyclopediaProfile? { id.flatMap { pid in profiles.first { $0.id == pid } } }
    func roadmapItem(_ id: String) -> RoadmapItem? { store.roadmap.items[id] }

    /// Session endpoints plus remembered history (history entries are not live unless re-observed).
    var allEndpoints: [ObservedEndpoint] {
        var byID = store.state.endpoints
        for (k, v) in sessionEndpoints { byID[k] = v }
        return byID.values.sorted { (liveIDs.contains($0.id) ? 0 : 1, $0.transport.rawValue, $0.name) < (liveIDs.contains($1.id) ? 0 : 1, $1.transport.rawValue, $1.name) }
    }

    func matches(_ e: ObservedEndpoint) -> [EndpointMatch] { EndpointMatcher.match(e, profiles: profiles) }

    func endpoints(for profileID: String) -> [ObservedEndpoint] {
        allEndpoints.filter { e in matches(e).contains { $0.profileID == profileID } }
    }

    func isLive(_ e: ObservedEndpoint) -> Bool { liveIDs.contains(e.id) }

    func plan(for p: EncyclopediaProfile) -> ConnectionPlan {
        ConnectionStudio.plan(profile: p, env: env, approved: approvals.contains(p.id), lastResult: lastResults[p.id], matchedEndpoint: chosenEndpoint(for: p.id))
    }

    func chosenEndpoint(for profileID: String) -> ObservedEndpoint? {
        let candidates = endpoints(for: profileID)
        if let id = selectedEndpointByProfile[profileID], let e = candidates.first(where: { $0.id == id }) { return e }
        return candidates.first { isLive($0) }
    }

    /// Masks sensitive attributes (serials, MAC addresses, device IDs, addresses) when identifier masking is on.
    func display(_ e: ObservedEndpoint, _ key: String) -> String {
        let v = e.attributes[key] ?? ""
        guard e.sensitiveKeys.contains(key), app?.settings.maskDeviceIdentifiers ?? true else { return v }
        return Redactor.maskSerial(v)
    }

    var masking: Bool { app?.settings.maskDeviceIdentifiers ?? true }

    private func changed() {
        profiles = store.profiles
        revision += 1
    }

    // MARK: Equipment detection (local checks only)

    func refreshEquipmentIfStale() {
        if let t = lastEquipmentRefresh, Date().timeIntervalSince(t) < 30 { return }
        refreshEquipment()
    }

    func refreshEquipment() {
        lastEquipmentRefresh = Date()
        Task { @MainActor in
            let ifs = await HostNetwork.interfaces()
            self.interfaces = ifs
            let paths = Set(HostFacts.probedPaths.filter { FileManager.default.fileExists(atPath: $0) })
            let active = ifs.filter { $0.hasAddress && ($0.type == "Wi-Fi" || $0.type == "Ethernet") }.map { "\($0.name) (\($0.type))" }
            let facts = HostFacts(bluetoothPoweredOn: self.ble?.poweredOn, activeNetworkInterfaces: active,
                                  usbDevices: self.app?.inventory.orderedRecords.map(\.device) ?? [], toolchain: self.app?.toolchain, existingPaths: paths)
            self.detected = EquipmentDetector.detect(facts)
            self.store.recomputeRoadmap(detected: self.detected)
            self.changed()
        }
    }

    func setDeclared(_ id: String, owned: Bool) {
        store.setDeclared(id, owned: owned)
        store.recomputeRoadmap(detected: detected)
        changed()
    }

    // MARK: Evidence

    private func protocolID(for t: EndpointTransport) -> String? {
        switch t {
        case .usb: return "usb"
        case .thunderbolt: return "thunderbolt"
        case .ble: return "bluetooth.le"
        case .bluetoothClassic: return "bluetooth.classic"
        case .bonjour: return "network.mdns"
        case .ssdp: return "network.ssdp"
        case .coreDevice: return "apple.coredevice"
        case .host: return nil
        }
    }

    private func source(for t: EndpointTransport) -> String {
        switch t {
        case .usb, .thunderbolt: return "IOKit registry"
        case .ble: return "Core Bluetooth scan"
        case .bluetoothClassic: return "IOBluetooth paired-device list"
        case .bonjour: return "DNS-SD (Bonjour) browse"
        case .ssdp: return "SSDP M-SEARCH"
        case .coreDevice: return "devicectl"
        case .host: return "Host"
        }
    }

    func record(_ e: ConnectivityEvidence) {
        store.record(e)
        if e.countsForRoadmap { store.recomputeRoadmap(detected: detected) }
        changed()
    }

    /// Adds an observed endpoint. Matching profiles get one "discovered" evidence entry per session.
    /// Discovery alone never validates compatibility.
    func observe(_ e: ObservedEndpoint, live: Bool = true) {
        sessionEndpoints[e.id] = e
        if live { liveIDs.insert(e.id) }
        let found = matches(e)
        guard !found.isEmpty else { return }
        store.observe(e)
        var recorded = false
        for m in found.prefix(2) {
            let key = "discovered|\(e.id)|\(m.profileID)"
            guard !recordedThisSession.contains(key) else { continue }
            recordedThisSession.insert(key)
            recorded = true
            store.record(ConnectivityEvidence(kind: .discovered, outcome: .observed, profileID: m.profileID, protocolID: protocolID(for: e.transport),
                                              endpointName: e.name, summary: "Discovered via \(e.transport.displayName). Matched by: " + m.evidence.joined(separator: ", "),
                                              details: m.evidence, provenance: e.provenance, source: source(for: e.transport)))
        }
        guard recorded else { return }
        if e.provenance == .hardware { store.recomputeRoadmap(detected: detected) } else { store.save() }
        changed()
    }

    func markGone(_ endpointID: String) {
        guard liveIDs.contains(endpointID) else { return }
        liveIDs.remove(endpointID)
        if var e = sessionEndpoints[endpointID] {
            e.lastSeen = Date()
            sessionEndpoints[endpointID] = e
            if store.state.endpoints[endpointID] != nil { store.observe(e); store.save() }
        }
        changed()
    }

    // Hooks from AppModel (IOKit, device intelligence, diagnostics).

    func usbAttached(_ d: DiscoveredDevice) {
        guard d.usb != nil || d.thunderbolt != nil else { return }
        observe(ObservedEndpoint.fromUSB(d))
    }

    func usbDetached(_ d: DiscoveredDevice) { markGone("usb:" + d.id.rawValue) }

    func intelligenceUpdated(_ r: DeviceRecord, snapshot: IntelligenceSnapshot) {
        guard !snapshot.communicationEvidence.isEmpty else { return }
        let endpoint = ObservedEndpoint.fromUSB(r.device)
        for m in matches(endpoint).prefix(1) {
            let key = "comm|\(r.stableKey)|\(m.profileID)"
            guard !recordedThisSession.contains(key) else { continue }
            recordedThisSession.insert(key)
            let method = profile(m.profileID)?.connectionMethods.first { $0.driverID == "apple.coredevice" }
            record(ConnectivityEvidence(kind: .connectionAttempt, outcome: .success, profileID: m.profileID, protocolID: "apple.coredevice",
                                        methodID: method?.id, endpointName: r.device.displayName,
                                        summary: "Device intelligence exchanged data with the device (\(snapshot.state.displayName)).",
                                        details: snapshot.communicationEvidence, provenance: r.device.provenance, source: snapshot.providerID))
        }
    }

    func diagnosticsFinished(_ run: DiagnosticRun, record r: DeviceRecord) {
        let applicable = run.results.filter { $0.outcome != .notSupported && $0.outcome != .skipped }
        guard !applicable.isEmpty else { return }
        let passed = applicable.filter { $0.outcome == .passed }.count
        let endpoint = ObservedEndpoint.fromUSB(r.device)
        for m in matches(endpoint).prefix(1) {
            let outcome: EvidenceOutcome = passed == applicable.count ? .success : (passed > 0 ? .partial : .failure)
            record(ConnectivityEvidence(kind: .diagnostics, outcome: outcome, profileID: m.profileID, protocolID: protocolID(for: endpoint.transport),
                                        endpointName: r.device.displayName, summary: "Diagnostics: \(passed) of \(applicable.count) applicable tests passed.",
                                        details: applicable.map { "\($0.testID): \($0.outcome.displayName)" }, provenance: r.device.provenance,
                                        source: "HCG diagnostic engine", testsPassed: passed, testsApplicable: applicable.count))
        }
    }

    // MARK: Bluetooth LE (user-started)

    var bleAvailable: Bool { BLEExplorer.isUsable }

    private func bleExplorer() -> BLEExplorer {
        if let b = ble { return b }
        let b = BLEExplorer()
        b.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.syncBLE() }
        }
        ble = b
        return b
    }

    func toggleBLEScan() {
        let b = bleExplorer()
        if b.scanning { b.stopScan() } else { b.startScan() }
        syncBLE()
    }

    private func syncBLE() {
        guard let b = ble else { return }
        bleStatus = b.stateDescription
        bleScanning = b.scanning
        for p in b.peripherals.values {
            var attrs: [String: String] = ["rssi": "\(p.rssi) dBm", "connectable": p.connectable ? "yes" : "no", "identifier": p.id.uuidString]
            if !p.serviceUUIDs.isEmpty { attrs["serviceUUIDs"] = p.serviceUUIDs.joined(separator: ",") }
            if let m = p.manufacturer { attrs["manufacturer"] = m }
            let id = "ble:" + p.id.uuidString
            if let existing = sessionEndpoints[id], existing.name == p.name,
               attrs.allSatisfy({ $0.key == "rssi" || existing.attributes[$0.key] == $0.value }) { continue }
            var merged = sessionEndpoints[id]?.attributes ?? [:]
            merged.merge(attrs) { _, new in new }
            observe(ObservedEndpoint(id: id, transport: .ble, name: p.name, attributes: merged, sensitiveKeys: ["identifier"],
                                     firstSeen: sessionEndpoints[id]?.firstSeen ?? Date(), lastSeen: p.lastSeen, provenance: .hardware))
        }
        if !b.scanning {
            for id in liveIDs where id.hasPrefix("ble:") && b.connectedPeripheral?.uuidString != String(id.dropFirst(4)) {
                if Date().timeIntervalSince(sessionEndpoints[id]?.lastSeen ?? .distantPast) > 60 { markGone(id) }
            }
        }
        if b.poweredOn != nil, detected["interface.bluetooth"]?.availability != (b.poweredOn == true ? .detected : .missing),
           Date().timeIntervalSince(lastEquipmentRefresh ?? .distantPast) > 5 {
            refreshEquipment()
        }
        revision += 1
    }

    var bleConnectedID: String? { ble?.connectedPeripheral.map { "ble:" + $0.uuidString } }

    // MARK: Local network (user-started)

    func toggleBonjour() {
        if bonjour?.running == true {
            bonjour?.stop()
            bonjourRunning = false
            store.save()
            return
        }
        let b = bonjour ?? BonjourBrowser()
        b.onEndpoint = { [weak self] e in MainActor.assumeIsolated { self?.observe(e) } }
        b.onState = { [weak self] s in MainActor.assumeIsolated { self?.networkStatus = s } }
        bonjour = b
        b.start()
        bonjourRunning = true
    }

    func runSSDP() {
        guard !ssdpRunning else { return }
        ssdpRunning = true
        networkStatus = "Sending one SSDP M-SEARCH and listening for 3 s…"
        Task { @MainActor in
            let found = await SSDPDiscovery.enrich(await SSDPDiscovery.search(timeout: 3))
            for e in found { self.observe(e) }
            self.ssdpRunning = false
            self.networkStatus = "SSDP: \(found.count) device(s) answered."
            self.store.save()
        }
    }

    func listPairedClassic() {
        let list = BluetoothClassicInventory.pairedDevices()
        for e in list { observe(e, live: e.attributes["connected"] == "yes") }
        if list.isEmpty { bleStatus = BLEExplorer.isUsable ? "No paired Bluetooth Classic devices." : "Bluetooth needs the app bundle." }
        changed()
    }

    // MARK: HCG AI (explicit, sends no device data)

    func checkHCGAI() {
        busy.insert("hcg-ai")
        Task { @MainActor in
            self.aiStatus = await ReadOnlyHTTP.hcgAIHandoff()
            self.busy.remove("hcg-ai")
        }
    }

    // MARK: Studio: approval and attempts

    func approve(_ profileID: String) {
        approvals.insert(profileID)
        app?.auditLog.record(AuditEntry(actor: "user", operation: "connectivity.approve", impact: .readOnly, target: profileID, targetKey: profileID,
                                        decision: "approved-once", outcome: "ok", provenance: .hardware))
    }

    func revokeApproval(_ profileID: String) { approvals.remove(profileID) }

    /// Runs the recommended read-only driver once. Requires a fresh approval, which is consumed.
    func attempt(_ p: EncyclopediaProfile) {
        let plan = self.plan(for: p)
        guard plan.canAttempt, approvals.contains(p.id), let method = plan.method, let driver = method.driverID else { return }
        approvals.remove(p.id)
        busy.insert(p.id)
        let endpoint = chosenEndpoint(for: p.id)
        app?.auditLog.record(AuditEntry(actor: "user", operation: "connectivity.attempt.\(driver)", impact: .readOnly, target: p.id, targetKey: p.id,
                                        decision: "user-approved", outcome: "started", provenance: endpoint?.provenance ?? .hardware))
        Task { @MainActor in
            let result = await self.runDriver(driver, profile: p, endpoint: endpoint)
            self.busy.remove(p.id)
            self.lastResults[p.id] = result
            self.record(ConnectivityEvidence(kind: .connectionAttempt, outcome: result.outcome, profileID: p.id, protocolID: method.protocolID, methodID: method.id,
                                             endpointName: endpoint?.name ?? "No endpoint", summary: result.summary,
                                             details: result.handshake + result.errors.map { "Error: \($0)" }, provenance: result.provenance,
                                             source: "Connection Studio · \(driver)"))
            self.app?.banner = result.summary
        }
    }

    private func runDriver(_ driver: String, profile p: EncyclopediaProfile, endpoint: ObservedEndpoint?) async -> ConnectionAttemptResult {
        switch driver {
        case "usb.enumeration", "apple.coredevice":
            guard let e = endpoint, e.transport == .usb || e.transport == .thunderbolt,
                  let app = app, let r = app.inventory.orderedRecords.first(where: { "usb:" + $0.device.id.rawValue == e.id }), r.device.isPresent else {
                return ConnectionAttemptResult(outcome: .failure, summary: "No matching USB device is connected.", errors: ["Connect the device with a data cable, then retry."], provenance: .hardware)
            }
            if driver == "apple.coredevice" {
                await app.refreshIntelligence(r.id, force: true)
                guard let snap = app.snapshot(r.id) else {
                    return ConnectionAttemptResult(outcome: .failure, summary: "Device intelligence returned nothing.", provenance: r.device.provenance)
                }
                let ok = !snap.communicationEvidence.isEmpty
                return ConnectionAttemptResult(outcome: ok ? .success : .partial,
                                               summary: ok ? "CoreDevice exchanged data with \(r.device.displayName)." : "USB present; CoreDevice did not exchange data: \(snap.stateReason)",
                                               handshake: snap.communicationEvidence.isEmpty ? ["USB enumeration (IOKit)"] : snap.communicationEvidence,
                                               capabilities: snap.fields.prefix(8).map { "\($0.label)" },
                                               errors: snap.errors + (ok ? [] : [snap.nextAction.title]), provenance: r.device.provenance)
            }
            guard let probe = app.probe(for: r.device) else {
                return ConnectionAttemptResult(outcome: .failure, summary: "No discovery backend can re-read this device.", provenance: r.device.provenance)
            }
            let id = r.device.id
            let reread = await Task.detached { probe.refresh(id) }.value
            guard let d = reread else {
                return ConnectionAttemptResult(outcome: .failure, summary: "The device disappeared before it could be re-read.", provenance: r.device.provenance)
            }
            var hs = ["IOKit registry entry re-read"]
            if let u = d.usb { hs.append("VID \(u.vendorIDHex) · PID \(u.productIDHex)"); hs.append("Link: \(u.speed?.displayName ?? "not reported")") }
            return ConnectionAttemptResult(outcome: .success, summary: "Host-side USB connection confirmed for \(d.displayName) (enumeration only — no device protocol).",
                                           handshake: hs, capabilities: ["Read-only host-side diagnostics (Diagnostics section)"], provenance: d.provenance)

        case "ble.gatt-read":
            guard let e = endpoint, e.transport == .ble else {
                return ConnectionAttemptResult(outcome: .failure, summary: "Scan for Bluetooth LE devices and choose one first.", provenance: .hardware)
            }
            return await bleRead(e)

        case "samsung.tv-info":
            let host = (manualHosts[p.id]?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? endpoint?.attributes["address"]
            guard let h = host else {
                return ConnectionAttemptResult(outcome: .failure, summary: "Discover the TV (SSDP) or enter its LAN address first.", provenance: .hardware)
            }
            let r = await ReadOnlyHTTP.samsungTVInfo(host: h)
            guard let info = r.info else {
                return ConnectionAttemptResult(outcome: .failure, summary: "The TV did not return device information.", errors: [r.error ?? "Unknown error"], provenance: .hardware)
            }
            let shown = info.sorted { $0.key < $1.key }.map { k, v in "\(k): \(SamsungTVInfoParser.sensitiveKeys.contains(k) && masking ? Redactor.maskSerial(v) : v)" }
            return ConnectionAttemptResult(outcome: .success, summary: "Read device information from \(info["name"] ?? "the TV") in \(Int(r.durationMs)) ms (read-only, no pairing, no control).",
                                           handshake: ["HTTP GET :8001/api/v2/ → 200"] + shown, capabilities: ["Model and firmware identification"], provenance: .hardware)

        case "network.discovery":
            guard let e = endpoint, e.transport == .ssdp || e.transport == .bonjour else {
                return ConnectionAttemptResult(outcome: .failure, summary: "Run a network discovery and choose a device first.", provenance: .hardware)
            }
            if e.transport == .ssdp, e.attributes["location"] != nil {
                let enriched = await SSDPDiscovery.enrich([e]).first ?? e
                let got = enriched.attributes["model"] != nil || enriched.attributes["manufacturer"] != nil
                if got { observe(enriched) }
                return ConnectionAttemptResult(outcome: got ? .success : .partial,
                                               summary: got ? "Read the UPnP device description of \(enriched.name)." : "Device answered discovery; description unavailable.",
                                               handshake: ["SSDP response", "UPnP description GET"] + ["manufacturer", "model", "modelNumber"].compactMap { k in enriched.attributes[k].map { "\(k): \($0)" } },
                                               capabilities: ["Identification only — no device-specific protocol adapter"], provenance: e.provenance)
            }
            return ConnectionAttemptResult(outcome: .partial, summary: "\(e.name) is advertised on the network; System Tester has no application-protocol adapter for it.",
                                           handshake: ["DNS-SD advertisement \(e.attributes["serviceType"] ?? "")"], capabilities: [], provenance: e.provenance)

        default:
            return ConnectionAttemptResult(outcome: .failure, summary: "No adapter is implemented for \(driver).", provenance: .hardware)
        }
    }

    /// Connects to one approved BLE peripheral, reads allow-listed characteristics, disconnects. Never writes.
    private func bleRead(_ e: ObservedEndpoint) async -> ConnectionAttemptResult {
        guard let uuid = UUID(uuidString: String(e.id.dropFirst(4))), let b = ble else {
            return ConnectionAttemptResult(outcome: .failure, summary: "Scan for Bluetooth LE devices first.", provenance: .hardware)
        }
        let r = await b.readInformation(uuid)
        var updated = sessionEndpoints[e.id] ?? e
        if !r.services.isEmpty { updated.attributes["serviceUUIDs"] = r.services.joined(separator: ",") }
        for (k, v) in r.values {
            let key = "gatt." + (BLEAssignedNumbers.characteristics[k] ?? k)
            updated.attributes[key] = v
            if BLEAssignedNumbers.sensitiveCharacteristics.contains(k) && !updated.sensitiveKeys.contains(key) { updated.sensitiveKeys.append(key) }
        }
        updated.lastSeen = Date()
        sessionEndpoints[updated.id] = updated
        store.observe(updated)
        store.save()
        let outcome: EvidenceOutcome = r.connected ? (r.values.isEmpty ? .partial : .success) : .failure
        let shown = r.values.keys.sorted().map { k -> String in
            let name = BLEAssignedNumbers.characteristics[k] ?? k
            let v = BLEAssignedNumbers.sensitiveCharacteristics.contains(k) && masking ? Redactor.maskSerial(r.values[k] ?? "") : (r.values[k] ?? "")
            return "\(name): \(v)"
        }
        return ConnectionAttemptResult(outcome: outcome,
                                       summary: r.connected ? "Connected to \(e.name), read \(r.values.count) characteristic(s) in \(Int(r.durationMs)) ms, then disconnected." : "Could not connect to \(e.name).",
                                       handshake: r.connected ? ["GATT connection", "Services: " + r.services.map { BLEAssignedNumbers.services[$0] ?? $0 }.joined(separator: ", ")] + shown : [],
                                       capabilities: r.values.keys.sorted().map { BLEAssignedNumbers.characteristics[$0] ?? $0 },
                                       errors: r.errors, provenance: .hardware)
    }

    /// Live Connection Center: explicit, user-confirmed read of one BLE device.
    func readBLEInformation(_ e: ObservedEndpoint) {
        guard e.transport == .ble, !busy.contains(e.id) else { return }
        busy.insert(e.id)
        app?.auditLog.record(AuditEntry(actor: "user", operation: "connectivity.ble.read", impact: .readOnly, target: e.name, targetKey: e.id,
                                        decision: "user-confirmed", outcome: "started", provenance: .hardware))
        Task { @MainActor in
            let result = await self.bleRead(e)
            self.busy.remove(e.id)
            let updated = self.sessionEndpoints[e.id] ?? e
            let profileID = self.matches(updated).first?.profileID
            let method = self.profile(profileID)?.connectionMethods.first { $0.driverID == "ble.gatt-read" }
            if let pid = profileID { self.lastResults[pid] = result }
            self.record(ConnectivityEvidence(kind: .connectionAttempt, outcome: result.outcome, profileID: profileID, protocolID: "bluetooth.le", methodID: method?.id,
                                             endpointName: e.name, summary: result.summary, details: result.handshake + result.errors.map { "Error: \($0)" },
                                             provenance: .hardware, source: "Live Connection Center · ble.gatt-read"))
            self.app?.banner = result.summary
        }
    }

    func disconnectBLE() { ble?.disconnect() }

    // MARK: Roadmap, gaps, profiles

    @discardableResult
    func decide(_ id: String, state: RoadmapState, note: String) -> String? {
        let refusal = store.decide(id, state: state, note: note)
        if refusal == nil {
            app?.auditLog.record(AuditEntry(actor: "user", operation: "roadmap.manual-decision", impact: .readOnly, target: id, targetKey: id,
                                            decision: state.rawValue, outcome: "recorded", provenance: .imported))
        }
        changed()
        return refusal
    }

    func clearDecision(_ id: String) {
        store.clearDecision(id)
        changed()
    }

    func setPriority(_ gapID: String, _ p: Int) {
        store.setPriority(gapID, p)
        changed()
    }

    func annotate(_ profileID: String, key: String, value: String) {
        store.annotate(profileID, key: key, value: value)
        store.recomputeRoadmap(detected: detected)
        changed()
    }

    func reloadUserProfiles() {
        store.loadUserProfiles(from: AppPaths.encyclopediaDirectory)
        store.recomputeRoadmap(detected: detected)
        changed()
    }

    func recordUserReport(profileID: String, outcome: EvidenceOutcome, note: String) {
        record(ConnectivityEvidence(kind: .userReport, outcome: outcome, profileID: profileID, endpointName: "Reported by you", summary: note,
                                    provenance: .imported, source: "User report (physically tested by you)"))
    }

    func lifeOSExport(_ ids: Set<String>) throws -> Data {
        let all = gaps
        return try LifeOSQuestExporter.json(for: all.filter { ids.contains($0.id) }, all: all)
    }
}

extension AppPaths {
    static var connectivityFile: URL { supportDirectory.appendingPathComponent("connectivity.json") }
    static var encyclopediaDirectory: URL { supportDirectory.appendingPathComponent("Encyclopedia", isDirectory: true) }
}
#endif
