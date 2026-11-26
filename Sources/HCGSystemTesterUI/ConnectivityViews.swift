#if os(macOS)
import SwiftUI
import AppKit
import HCGCore

/// Hosts every Universal Connectivity section. The connectivity model is created on first use only.
struct ConnectivitySectionHost: View {
    @EnvironmentObject var model: AppModel
    let section: WorkspaceSection

    var body: some View {
        content
            .environmentObject(model.connectivity)
            .onAppear { model.connectivity.refreshEquipmentIfStale() }
    }

    @ViewBuilder var content: some View {
        switch section {
        case .connectivityCenter: ConnectivityCenterView()
        case .encyclopedia: EncyclopediaView()
        case .connectionStudio: ConnectionStudioView()
        case .connectedDevices: ConnectedDevicesView()
        case .protocolRegistry: ProtocolRegistryView()
        case .hardwareRequirements: HardwareRequirementsView()
        case .roadmap: RoadmapView()
        case .gapAnalyzer: GapAnalyzerView()
        case .compatibilityMatrix: CompatibilityMatrixView()
        case .assistant: AssistantView()
        case .connectionHistory: ConnectionHistoryView()
        default: EmptyView()
        }
    }
}

// MARK: - Shared badges

struct Chip: View {
    let text: String
    var color: Color = Theme.cyan
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let s = symbol { Image(systemName: s) }
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.6))
    }
}

extension KnowledgeSource {
    var color: Color {
        switch self {
        case .manufacturerDocumented: return Theme.cyan
        case .communityReported: return Theme.warning
        case .aiSuggestion: return Theme.violet
        case .hcgVerified: return Theme.success
        case .hcgResearchNote: return Theme.metal
        }
    }
}

struct SourceBadge: View {
    let source: KnowledgeSource
    var body: some View { Chip(text: source.shortLabel.uppercased(), color: source.color).help(source.displayName) }
}

extension RoadmapState {
    var color: Color {
        switch self {
        case .researchRequired, .documentationIdentified, .connectionMethodIdentified: return Theme.metal
        case .hardwareRequired, .softwareRequired, .adapterDevelopmentRequired: return Theme.warning
        case .adapterImplemented, .readyForConnection: return Theme.cyan
        case .deviceDiscovered, .connectionAttempted: return Theme.violet
        case .connectionEstablished, .diagnosticsPartiallyVerified: return Theme.success.opacity(0.8)
        case .diagnosticsFullyVerified, .compatibilityValidated, .ecosystemIntegrationAvailable: return Theme.success
        case .blocked, .unsupported: return Theme.danger
        }
    }
}

struct RoadmapStateBadge: View {
    let state: RoadmapState
    var manual = false
    var body: some View {
        Chip(text: state.displayName.uppercased() + (manual ? " · MANUAL" : ""), color: state.color, symbol: manual ? "hand.raised.fill" : nil)
    }
}

extension EvidenceOutcome {
    var color: Color {
        switch self {
        case .observed: return Theme.cyan
        case .success: return Theme.success
        case .partial: return Theme.warning
        case .failure: return Theme.danger
        }
    }
}

extension ValidationStatus {
    var color: Color {
        switch self {
        case .researchOnly: return Theme.metal
        case .planned: return Theme.violet
        case .implementedUnverified: return Theme.cyan
        case .verifiedOnHardware: return Theme.success
        case .delegated: return Theme.warning
        case .prohibited: return Theme.danger
        }
    }
}

extension EquipmentAvailability {
    var color: Color {
        switch self {
        case .detected: return Theme.success
        case .declaredOwned: return Theme.cyan
        case .missing: return Theme.danger
        case .unknown: return Theme.dim
        }
    }
}

struct EvidenceProvenanceBadge: View {
    let evidence: ConnectivityEvidence
    var body: some View {
        if evidence.kind == .userReport {
            Chip(text: "PHYSICALLY TESTED (YOUR REPORT)", color: Theme.success, symbol: "person.fill.checkmark")
        } else {
            ProvenanceBadge(provenance: evidence.provenance)
        }
    }
}

struct SafetyNotice: View {
    var text = "Read-only. System Tester never controls vehicles, machinery, robots or drones, never flashes firmware, never bypasses pairing or security controls, and never transmits on radio bands."
    var body: some View {
        Label(text, systemImage: "shield.lefthalf.filled")
            .font(.caption).foregroundStyle(Theme.warning)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BulletList: View {
    let items: [String]
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(Theme.dim)
                    Text(t).foregroundStyle(color).textSelection(.enabled)
                }
                .font(.callout)
            }
        }
    }
}

struct ProfilePicker: View {
    @EnvironmentObject var c: ConnectivityModel
    var body: some View {
        Picker("Device profile", selection: Binding(get: { c.selectedProfileID ?? "" }, set: { c.selectedProfileID = $0 })) {
            ForEach(ConnectivityCategory.allCases) { cat in
                let ps = c.profiles.filter { $0.category == cat }
                if !ps.isEmpty {
                    Section(cat.displayName) {
                        ForEach(ps) { p in Text(p.displayName).tag(p.id) }
                    }
                }
            }
        }
        .frame(maxWidth: 420)
    }
}

// MARK: - Universal Connectivity Center

struct ConnectivityCenterView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Universal Connectivity Center",
                          subtitle: "EVERYTHING IS INTERCHANGEABLE — discover, research and develop connections to any device, honestly.",
                          symbol: "dot.radiowaves.left.and.right")
            metrics
            DiscoveryControls()
            Text("Connectivity categories").font(.headline).foregroundStyle(Theme.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(ConnectivityCategory.allCases) { cat in CategoryCard(category: cat) }
            }
            SafetyNotice()
        }
        .workspacePage()
    }

    var metrics: some View {
        let ev = c.evidence
        return HStack(spacing: 12) {
            MetricTile(title: "Profiles", value: "\(c.profiles.count)", detail: "\(c.store.userProfiles.count) user-supplied", symbol: "books.vertical")
            MetricTile(title: "Protocols", value: "\(UniversalProtocolRegistry.all.count)", detail: "\(UniversalProtocolRegistry.all.filter(\.isImplemented).count) implemented", symbol: "list.bullet.rectangle", tint: Theme.violet)
            MetricTile(title: "Live endpoints", value: "\(c.liveIDs.count)", detail: "\(c.allEndpoints.count) incl. history", symbol: "link.circle", tint: Theme.success)
            MetricTile(title: "Physical evidence", value: "\(ev.filter(\.countsForRoadmap).count)", detail: "\(ev.filter { !$0.countsForRoadmap }.count) synthetic (excluded)", symbol: "checkmark.seal", tint: Theme.cyan)
            MetricTile(title: "Development gaps", value: "\(c.gaps.count)", detail: "See Gap Analyzer", symbol: "exclamationmark.triangle", tint: Theme.warning)
        }
    }
}

struct CategoryCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    let category: ConnectivityCategory

    var body: some View {
        let profiles = c.profiles.filter { $0.category == category }
        Button {
            c.selectedProfileID = profiles.first?.id ?? c.selectedProfileID
            model.section = .encyclopedia
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: category.symbolName).foregroundStyle(Theme.accentGradient).font(.title3)
                    Text(category.displayName).font(.callout.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    Spacer()
                    Text("\(profiles.count)").font(.caption.weight(.bold)).foregroundStyle(profiles.isEmpty ? Theme.dim : Theme.cyan)
                }
                Text(category.typicalProtocols.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.dim).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .glassPanel(padding: 10)
        }
        .buttonStyle(.plain)
        .help(profiles.isEmpty ? "No profile yet — add one as JSON in the Encyclopedia folder." : profiles.map(\.displayName).joined(separator: "\n"))
    }
}

/// Discovery controls. Discovery is separate from communication and starts only when you press a button.
struct DiscoveryControls: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discovery (you start it — nothing runs at launch)").font(.headline).foregroundStyle(Theme.text)
            Text("Discovery only lists what is advertised. It never connects, pairs or validates compatibility.").font(.caption).foregroundStyle(Theme.dim)
            HStack(alignment: .top, spacing: 14) {
                row("USB / Thunderbolt", "IOKit (\(model.hardwareRecords.count) real device(s))", running: model.settings.hardwareDiscoveryEnabled) {
                    Button("Restart") { model.restartDiscovery() }
                }
                row("Bluetooth LE", c.bleStatus, running: c.bleScanning) {
                    Button(c.bleScanning ? "Stop scan" : "Scan") { c.toggleBLEScan() }.disabled(!c.bleAvailable)
                    Button("Paired Classic") { c.listPairedClassic() }.disabled(!c.bleAvailable)
                }
                row("Local network", c.networkStatus, running: c.bonjourRunning || c.ssdpRunning) {
                    Button(c.bonjourRunning ? "Stop Bonjour" : "Bonjour") { c.toggleBonjour() }
                    Button("SSDP once") { c.runSSDP() }.disabled(c.ssdpRunning)
                }
            }
            if !c.bleAvailable {
                Text("Bluetooth requires the app bundle (Xcode or scripts/build-app.sh), because macOS needs its Bluetooth usage description.").font(.caption2).foregroundStyle(Theme.warning)
            }
        }
        .glassPanel()
    }

    func row<Buttons: View>(_ title: String, _ status: String, running: Bool, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(running ? Theme.success : Theme.dim).frame(width: 7, height: 7)
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
            }
            Text(status).font(.caption).foregroundStyle(Theme.dim).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            HStack { buttons() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Device Encyclopedia

struct EncyclopediaView: View {
    @EnvironmentObject var c: ConnectivityModel
    @State private var search = ""

    var filtered: [EncyclopediaProfile] {
        let q = search.lowercased()
        return q.isEmpty ? c.profiles : c.profiles.filter { $0.displayName.lowercased().contains(q) || $0.category.displayName.lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search profiles", text: $search).textFieldStyle(.roundedBorder).padding(10)
                List(selection: Binding(get: { c.selectedProfileID }, set: { c.selectedProfileID = $0 })) {
                    ForEach(ConnectivityCategory.allCases) { cat in
                        let ps = filtered.filter { $0.category == cat }
                        if !ps.isEmpty {
                            Section(cat.displayName) {
                                ForEach(ps) { p in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.displayName).foregroundStyle(Theme.text)
                                        Text(c.roadmapItem("device." + p.id)?.state.displayName ?? p.researchStatus.displayName).font(.caption2).foregroundStyle(Theme.dim)
                                    }
                                    .tag(p.id)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button("Open profile folder") {
                        try? FileManager.default.createDirectory(at: AppPaths.encyclopediaDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppPaths.encyclopediaDirectory)
                    }
                    Button("Reload") { c.reloadUserProfiles() }
                }
                .controlSize(.small).padding(8)
            }
            .frame(width: 300)
            Divider()
            if let p = c.profile(c.selectedProfileID) {
                EncyclopediaProfileDetail(profile: p).id(p.id)
            } else {
                EmptyStateView(symbol: "books.vertical", title: "Select a profile", message: "Profiles describe how a device can be reached and what is still unknown.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WorkspaceBackground())
    }
}

struct EncyclopediaProfileDetail: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    let profile: EncyclopediaProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            InformationRequestForm(profile: profile)
            factsPanel
            methodsPanel
            if !profile.safety.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Safety restrictions").font(.headline).foregroundStyle(Theme.text)
                    ForEach(profile.safety) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Chip(text: s.safetyClass.displayName.uppercased(), color: s.safetyClass == .prohibitedControl ? Theme.danger : Theme.warning)
                            Text(s.text).font(.callout).foregroundStyle(Theme.text)
                        }
                    }
                }
                .glassPanel()
            }
            referencesPanel
            if !c.store.profileLoadErrors.isEmpty {
                Text("Profile files with problems: " + c.store.profileLoadErrors.joined(separator: "; ")).font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .workspacePage()
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: profile.category.symbolName).font(.largeTitle).foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading) {
                    Text(profile.displayName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("\(profile.category.displayName) · \(profile.origin)").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if let item = c.roadmapItem("device." + profile.id) { RoadmapStateBadge(state: item.state, manual: item.isManual) }
            }
            HStack {
                Chip(text: profile.researchStatus.displayName.uppercased(), color: Theme.violet)
                let physical = c.evidence.contains { $0.profileID == profile.id && $0.countsForRoadmap && $0.outcome == .success }
                Chip(text: physical ? "PHYSICAL CONNECTION EVIDENCE" : "RESEARCH ONLY — NOT PHYSICALLY TESTED", color: physical ? Theme.success : Theme.warning)
                Spacer()
                Button("Open in Connection Studio") { c.selectedProfileID = profile.id; model.section = .connectionStudio }
            }
        }
        .glassPanel()
    }

    var factsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is known (by source)").font(.headline).foregroundStyle(Theme.text)
            factGroup("Operating system", profile.operatingSystem.map { [$0] } ?? [])
            factGroup("Physical interfaces", profile.physicalInterfaces)
            factGroup("Wireless interfaces", profile.wirelessInterfaces)
            factGroup("Protocols", profile.protocols)
            factGroup("SDKs", profile.sdks)
            factGroup("Drivers", profile.requiredDrivers)
            factGroup("Authentication", profile.authentication)
            factGroup("Permissions", profile.permissions)
            factGroup("Troubleshooting", profile.troubleshooting)
            let equipment = profile.requiredCables + profile.requiredAdapters + profile.requiredSoftware
            if !equipment.isEmpty {
                Text("Required equipment").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                BulletList(items: equipment.map { id in "\(EquipmentCatalog.spec(id)?.name ?? id) — \(c.equipment[id]?.availability.displayName ?? "Unknown")" })
            }
        }
        .glassPanel()
    }

    @ViewBuilder func factGroup(_ title: String, _ facts: [SourcedFact]) -> some View {
        if !facts.isEmpty {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
            ForEach(facts) { f in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SourceBadge(source: f.source)
                    Text(f.text).font(.callout).foregroundStyle(Theme.text).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    var methodsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection methods").font(.headline).foregroundStyle(Theme.text)
            if profile.connectionMethods.isEmpty { Text("No method documented yet.").foregroundStyle(Theme.dim) }
            ForEach(profile.connectionMethods) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        SourceBadge(source: m.source)
                        Chip(text: m.safety.displayName.uppercased(), color: m.safety == .prohibitedControl ? Theme.danger : (m.safety == .readOnly ? Theme.success : Theme.warning))
                        Spacer()
                        let implemented = m.driverID.map { RoadmapEngine.builtInDrivers.contains($0) } ?? false
                        Chip(text: implemented ? "ADAPTER IMPLEMENTED" : "NO ADAPTER YET", color: implemented ? Theme.cyan : Theme.dim)
                    }
                    Text("Protocol: \(UniversalProtocolRegistry.protocolInfo(m.protocolID)?.name ?? m.protocolID)\(m.osRestriction.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(Theme.dim)
                    if !m.steps.isEmpty { BulletList(items: m.steps) }
                    if let n = m.notes { Text(n).font(.caption).foregroundStyle(Theme.dim) }
                }
                .padding(8)
                .background(Theme.navyHigh.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .glassPanel()
    }

    var referencesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References").font(.headline).foregroundStyle(Theme.text)
            if profile.references.isEmpty { Text("No references recorded.").foregroundStyle(Theme.dim) }
            ForEach(profile.references) { r in
                HStack {
                    SourceBadge(source: r.source)
                    if let url = URL(string: r.url), url.scheme == "https" {
                        Link(r.title, destination: url)
                    } else {
                        Text(r.title)
                    }
                    Text("— \(r.publisher)").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Text("Links open in your browser; System Tester does not fetch them.").font(.caption2).foregroundStyle(Theme.dim)
        }
        .glassPanel()
    }
}

/// Asks for the exact model, year, firmware and hardware revision before claiming anything specific.
struct InformationRequestForm: View {
    @EnvironmentObject var c: ConnectivityModel
    let profile: EncyclopediaProfile
    @State private var model = ""
    @State private var year = ""
    @State private var firmware = ""
    @State private var revision = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your exact device").font(.headline).foregroundStyle(Theme.text)
            Text("Connection details differ by model, year and firmware. Provide them so research and requirements become specific. Stored locally only.")
                .font(.caption).foregroundStyle(Theme.dim)
            if !profile.informationRequests.isEmpty { BulletList(items: profile.informationRequests, color: Theme.warning) }
            HStack {
                TextField("Exact model", text: $model)
                TextField("Model year", text: $year)
                TextField("Firmware / software version", text: $firmware)
                TextField("Hardware revision", text: $revision)
                Button("Save") {
                    c.annotate(profile.id, key: "model", value: model)
                    c.annotate(profile.id, key: "modelYear", value: year)
                    c.annotate(profile.id, key: "firmwareVersion", value: firmware)
                    c.annotate(profile.id, key: "hardwareRevision", value: revision)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .glassPanel()
        .onAppear {
            let a = c.store.state.profileAnnotations[profile.id] ?? [:]
            model = a["model"] ?? ""
            year = a["modelYear"] ?? ""
            firmware = a["firmwareVersion"] ?? ""
            revision = a["hardwareRevision"] ?? ""
        }
    }
}

// MARK: - Connection Studio

struct ConnectionStudioView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Guided Connection Studio",
                          subtitle: "Fourteen steps from identification to roadmap update. Every attempt needs your explicit, single-use approval.",
                          symbol: "wand.and.rays")
            HStack { ProfilePicker(); Spacer() }
            if let p = c.profile(c.selectedProfileID) {
                StudioPlanView(profile: p)
            }
            SafetyNotice()
        }
        .workspacePage()
    }
}

struct StudioPlanView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    let profile: EncyclopediaProfile

    var body: some View {
        let plan = c.plan(for: profile)
        VStack(alignment: .leading, spacing: 14) {
            endpointChooser
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.steps) { step in StudioStepRow(step: step) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .glassPanel()
                VStack(alignment: .leading, spacing: 12) {
                    actionPanel(plan)
                    if !plan.developmentNeeded.isEmpty { developmentPanel(plan) }
                }
                .frame(width: 400)
            }
        }
    }

    var endpointChooser: some View {
        let candidates = c.endpoints(for: profile.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Target").font(.headline).foregroundStyle(Theme.text)
            if candidates.isEmpty {
                Text("No matching device observed yet. Connect it or run a discovery (Universal Connectivity Center). Matching needs a positive identifier — the transport alone never matches.")
                    .font(.caption).foregroundStyle(Theme.dim)
            } else {
                Picker("Observed device", selection: Binding(get: { c.chosenEndpoint(for: profile.id)?.id ?? "" },
                                                             set: { c.selectedEndpointByProfile[profile.id] = $0 })) {
                    ForEach(candidates) { e in
                        Text("\(e.name) · \(e.transport.displayName)\(c.isLive(e) ? " · live" : " · history")").tag(e.id)
                    }
                }
                .frame(maxWidth: 520)
            }
            if profile.connectionMethods.contains(where: { $0.driverID == "samsung.tv-info" }) {
                HStack {
                    Text("Or LAN address").font(.caption).foregroundStyle(Theme.dim)
                    TextField("192.168.x.x", text: Binding(get: { c.manualHosts[profile.id] ?? "" }, set: { c.manualHosts[profile.id] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                    Text("Private addresses only.").font(.caption2).foregroundStyle(Theme.dim)
                }
            }
        }
        .glassPanel()
    }

    func actionPanel(_ plan: ConnectionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approval and attempt").font(.headline).foregroundStyle(Theme.text)
            if let m = plan.method {
                KeyValueRow(key: "Recommended method", value: m.title)
                KeyValueRow(key: "Safety class", value: m.safety.displayName)
            }
            if plan.canAttempt {
                if c.approvals.contains(profile.id) {
                    Label("Approved once — the next attempt consumes it.", systemImage: "checkmark.shield").foregroundStyle(Theme.success).font(.callout)
                    HStack {
                        Button("Attempt read-only connection") { c.attempt(profile) }
                            .buttonStyle(.borderedProminent)
                            .disabled(c.busy.contains(profile.id))
                        Button("Withdraw approval") { c.revokeApproval(profile.id) }
                    }
                    if c.busy.contains(profile.id) { ProgressView().controlSize(.small) }
                } else {
                    Text("Review steps 7–8, then approve this single attempt. Approval is never remembered between attempts.").font(.caption).foregroundStyle(Theme.dim)
                    Button("I approve one read-only attempt") { c.approve(profile.id) }.buttonStyle(.borderedProminent)
                }
            } else {
                Label(plan.blockedReason ?? "Not possible yet.", systemImage: "hand.raised").foregroundStyle(Theme.warning).font(.callout)
            }
            if let r = c.lastResults[profile.id] {
                Divider()
                HStack { Chip(text: r.outcome.rawValue.uppercased(), color: r.outcome.color); ProvenanceBadge(provenance: r.provenance) }
                Text(r.summary).font(.callout).foregroundStyle(Theme.text)
                if !r.errors.isEmpty { BulletList(items: r.errors, color: Theme.danger) }
            }
        }
        .glassPanel()
    }

    func developmentPanel(_ plan: ConnectionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What must be developed").font(.headline).foregroundStyle(Theme.text)
            Text("No adapter exists for every requirement below. These are tracked in the Gap Analyzer.").font(.caption).foregroundStyle(Theme.dim)
            ForEach(plan.developmentNeeded.prefix(8)) { g in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Chip(text: g.kind.displayName.uppercased(), color: Theme.warning); Text(g.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text) }
                    Text(g.detail).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Button("Open Gap Analyzer") { model.section = .gapAnalyzer }
        }
        .glassPanel()
    }
}

struct StudioStepRow: View {
    let step: StudioStep

    var color: Color {
        switch step.status {
        case .done: return Theme.success
        case .pending: return Theme.cyan
        case .blocked: return Theme.danger
        case .notApplicable: return Theme.dim
        }
    }

    var symbol: String {
        switch step.status {
        case .done: return "checkmark.circle.fill"
        case .pending: return "circle.dotted"
        case .blocked: return "xmark.octagon.fill"
        case .notApplicable: return "minus.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.kind.rawValue)").font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 18)
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                ForEach(Array(step.lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.caption).foregroundStyle(Theme.dim).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
#endif
