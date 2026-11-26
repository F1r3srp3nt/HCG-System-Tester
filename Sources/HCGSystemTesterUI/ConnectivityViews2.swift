#if os(macOS)
import SwiftUI
import AppKit
import HCGCore

// MARK: - Connected Devices / Live Connection Center

struct ConnectedDevicesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    @State private var confirmRead: ObservedEndpoint?
    @State private var showHistory = true

    var shown: [ObservedEndpoint] { c.allEndpoints.filter { showHistory || c.isLive($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Live Connection Center",
                          subtitle: "Live status is shown separately from history. Connections happen only when you press Connect, and end when you press Disconnect or the read finishes.",
                          symbol: "link.circle")
            DiscoveryControls()
            Toggle("Show remembered (not live) devices", isOn: $showHistory)
            if shown.isEmpty {
                EmptyStateView(symbol: "antenna.radiowaves.left.and.right.slash", title: "Nothing observed",
                               message: "Connect a USB device or start a Bluetooth or network discovery. System Tester never invents devices.")
            }
            ForEach(shown) { e in endpointCard(e) }
        }
        .workspacePage()
        .confirmationDialog("Connect to this Bluetooth device?", isPresented: Binding(get: { confirmRead != nil }, set: { if !$0 { confirmRead = nil } }),
                            presenting: confirmRead) { e in
            Button("Connect, read device information, disconnect") { c.readBLEInformation(e) }
            Button("Cancel", role: .cancel) {}
        } message: { e in
            Text("System Tester will connect to “\(e.name)”, read only the standard Device Information and Battery characteristics, and disconnect. Nothing is written. Only do this for a device you own or are authorised to use.")
        }
    }

    func endpointCard(_ e: ObservedEndpoint) -> some View {
        let ms = c.matches(e)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(c.isLive(e) ? Theme.success : Theme.dim).frame(width: 8, height: 8)
                Text(e.name).font(.headline).foregroundStyle(Theme.text)
                Chip(text: e.transport.displayName.uppercased(), color: Theme.violet)
                Chip(text: c.isLive(e) ? "LIVE" : "HISTORY · last seen \(Formatters.dateTime.string(from: e.lastSeen))", color: c.isLive(e) ? Theme.success : Theme.dim)
                ProvenanceBadge(provenance: e.provenance)
                Spacer()
                if e.transport == .ble {
                    if c.bleConnectedID == e.id {
                        Button("Disconnect") { c.disconnectBLE() }
                    } else {
                        Button("Connect (read-only)…") { confirmRead = e }
                            .disabled(!c.isLive(e) || c.busy.contains(e.id) || e.attributes["connectable"] == "no")
                    }
                    if c.busy.contains(e.id) { ProgressView().controlSize(.small) }
                }
            }
            if ms.isEmpty {
                Text("No encyclopedia profile matches this device. It is shown as discovered only.").font(.caption).foregroundStyle(Theme.dim)
            } else {
                ForEach(ms.prefix(3), id: \.profileID) { m in
                    HStack {
                        Text("Matches \(c.profile(m.profileID)?.displayName ?? m.profileID)").font(.callout).foregroundStyle(Theme.cyan)
                        Text("(\(m.evidence.joined(separator: ", ")))").font(.caption).foregroundStyle(Theme.dim)
                        Spacer()
                        Button("Studio") { c.selectedProfileID = m.profileID; c.selectedEndpointByProfile[m.profileID] = e.id; model.section = .connectionStudio }
                            .controlSize(.small)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)], alignment: .leading, spacing: 2) {
                ForEach(e.attributes.keys.sorted(), id: \.self) { k in
                    Text("\(k): \(c.display(e, k))").font(.caption.monospaced()).foregroundStyle(Theme.dim).lineLimit(1).textSelection(.enabled)
                }
            }
        }
        .glassPanel(padding: 12)
    }
}

// MARK: - Protocol Registry

struct ProtocolRegistryView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Universal Protocol Registry",
                          subtitle: "Each protocol declares discovery and communication support separately, with dependencies, permissions and validation status.",
                          symbol: "list.bullet.rectangle")
            ForEach(UniversalProtocolRegistry.all) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
                    } label: {
                        HStack {
                            Image(systemName: expanded.contains(p.id) ? "chevron.down" : "chevron.right").foregroundStyle(Theme.dim).frame(width: 12)
                            Text(p.name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(p.layer).font(.caption).foregroundStyle(Theme.dim)
                            Spacer()
                            Text("Discovery").font(.caption2).foregroundStyle(Theme.dim)
                            SupportBadge(support: p.discovery)
                            Text("Communication").font(.caption2).foregroundStyle(Theme.dim)
                            SupportBadge(support: p.communication)
                            Chip(text: p.validation.displayName.uppercased(), color: p.validation.color)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if expanded.contains(p.id) { detail(p) }
                }
                .glassPanel(padding: 10)
            }
        }
        .workspacePage()
    }

    func detail(_ p: ConnectivityProtocol) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.summary).font(.callout).foregroundStyle(Theme.text)
            if let o = p.owner { KeyValueRow(key: "Owned by", value: o) }
            if let a = p.adapterID { KeyValueRow(key: "Adapter", value: a, monospaced: true) }
            group("Capabilities", p.capabilities)
            group("Dependencies", p.dependencies.map { EquipmentCatalog.spec($0)?.name ?? $0 })
            group("Permissions", p.permissions)
            group("Device categories", p.supportedCategories.map(\.displayName))
            if !p.safetyNotes.isEmpty { group("Safety", p.safetyNotes, color: Theme.warning) }
            ForEach(p.references) { r in
                if let url = URL(string: r.url), url.scheme == "https" { Link(r.title, destination: url).font(.caption) }
            }
        }
        .padding(.leading, 20)
    }

    @ViewBuilder func group(_ title: String, _ items: [String], color: Color = Theme.text) -> some View {
        if !items.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            BulletList(items: items, color: color)
        }
    }
}

// MARK: - Hardware Requirements Center

struct HardwareRequirementsView: View {
    @EnvironmentObject var c: ConnectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Hardware Requirements Center",
                              subtitle: "Cables, adapters, interfaces and software each method needs — detected where possible, otherwise declared by you.",
                              symbol: "cable.coaxial")
                Button("Re-check this Mac") { c.refreshEquipment() }
            }
            if !c.interfaces.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network interfaces").font(.headline).foregroundStyle(Theme.text)
                    ForEach(c.interfaces, id: \.name) { i in
                        Text("\(i.name) — \(i.type)\(i.hasAddress ? " · has address" : " · no address")").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .glassPanel()
            }
            ForEach(EquipmentKind.allCases, id: \.self) { kind in
                let specs = EquipmentCatalog.all.filter { $0.kind == kind }
                if !specs.isEmpty {
                    Text(kind.displayName).font(.headline).foregroundStyle(Theme.text)
                    ForEach(specs) { spec in EquipmentRow(spec: spec) }
                }
            }
        }
        .workspacePage()
    }
}

struct EquipmentRow: View {
    @EnvironmentObject var c: ConnectivityModel
    let spec: EquipmentSpec

    var body: some View {
        let status = c.equipment[spec.id] ?? EquipmentStatus(.unknown, spec.detection)
        let neededBy = c.profiles.filter { p in p.connectionMethods.contains { $0.requiredEquipment.contains(spec.id) || $0.requiredSoftware.contains(spec.id) } }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(spec.name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Chip(text: status.availability.displayName.uppercased(), color: status.availability.color)
                Spacer()
                Toggle("I own this", isOn: Binding(get: { c.store.state.declaredEquipment[spec.id] == true },
                                                   set: { c.setDeclared(spec.id, owned: $0) }))
                    .toggleStyle(.checkbox)
            }
            Text(status.evidence).font(.caption).foregroundStyle(Theme.dim)
            if !spec.requiredSpecifications.isEmpty { BulletList(items: spec.requiredSpecifications) }
            if !spec.examples.isEmpty { Text("Examples: " + spec.examples.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.dim) }
            if !spec.safetyNotes.isEmpty { BulletList(items: spec.safetyNotes, color: Theme.warning) }
            if !neededBy.isEmpty { Text("Needed by: " + neededBy.map(\.displayName).joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.cyan) }
        }
        .glassPanel(padding: 10)
    }
}

// MARK: - Development Roadmap

struct RoadmapView: View {
    @EnvironmentObject var c: ConnectivityModel
    @State private var selected: String?
    @State private var kindFilter: RoadmapItemKind = .device

    var items: [RoadmapItem] { c.roadmapItems.filter { $0.kind == kindFilter } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("", selection: $kindFilter) {
                    Text("Devices").tag(RoadmapItemKind.device)
                    Text("Protocols").tag(RoadmapItemKind.`protocol`)
                }
                .pickerStyle(.segmented).padding(10)
                List(selection: $selected) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).foregroundStyle(Theme.text)
                            RoadmapStateBadge(state: item.state, manual: item.isManual)
                        }
                        .tag(item.id)
                    }
                }
            }
            .frame(width: 330)
            Divider()
            if let id = selected ?? items.first?.id, let item = c.roadmapItem(id) {
                RoadmapDetail(item: item).id(item.id)
            } else {
                EmptyStateView(symbol: "map", title: "No roadmap items", message: "Items appear for every profile and protocol.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WorkspaceBackground())
    }
}

struct RoadmapDetail: View {
    @EnvironmentObject var c: ConnectivityModel
    let item: RoadmapItem
    @State private var target: RoadmapState = .blocked
    @State private var note = ""
    @State private var refusal: String?
    @State private var reportOutcome: EvidenceOutcome = .success
    @State private var reportNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    RoadmapStateBadge(state: item.state, manual: item.isManual)
                }
                KeyValueRow(key: "Automatic state", value: "\(item.automaticState.displayName) — \(item.automaticReason)")
                if let m = item.manual {
                    KeyValueRow(key: "Manual decision", value: "\(m.state.displayName) by \(m.actor), \(Formatters.dateTime.string(from: m.at)): \(m.note)")
                    Button("Clear manual decision") { c.clearDecision(item.id) }
                }
                if !item.blockers.isEmpty { BulletList(items: item.blockers, color: Theme.warning) }
                Text("The roadmap updates itself from genuine evidence (real hardware or your physical-test reports). Synthetic data and discovery alone never validate compatibility.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel()
            decisionPanel
            if item.kind == .device { reportPanel }
            historyPanel
        }
        .workspacePage()
    }

    var decisionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record a manual decision").font(.headline).foregroundStyle(Theme.text)
            Text("Manual decisions are recorded with your note and kept in history. Evidence-based states cannot be set by hand.").font(.caption).foregroundStyle(Theme.dim)
            HStack {
                Picker("State", selection: $target) {
                    ForEach(RoadmapState.allCases) { s in Text(s.displayName).tag(s) }
                }
                .frame(width: 320)
                TextField("Reason (required)", text: $note).textFieldStyle(.roundedBorder)
                Button("Record") {
                    refusal = c.decide(item.id, state: target, note: note)
                    if refusal == nil { note = "" }
                }
                .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let r = refusal { Label(r, systemImage: "hand.raised").foregroundStyle(Theme.danger).font(.callout) }
        }
        .glassPanel()
    }

    var reportPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report a physical test you performed").font(.headline).foregroundStyle(Theme.text)
            Text("Recorded as “physically tested (your report)” evidence — distinct from automatic measurements.").font(.caption).foregroundStyle(Theme.dim)
            HStack {
                Picker("Result", selection: $reportOutcome) {
                    Text("Worked").tag(EvidenceOutcome.success)
                    Text("Partly worked").tag(EvidenceOutcome.partial)
                    Text("Did not work").tag(EvidenceOutcome.failure)
                }
                .frame(width: 220)
                TextField("What you did and what happened", text: $reportNote).textFieldStyle(.roundedBorder)
                Button("Record report") {
                    c.recordUserReport(profileID: String(item.id.dropFirst("device.".count)), outcome: reportOutcome, note: reportNote)
                    reportNote = ""
                }
                .disabled(reportNote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .glassPanel()
    }

    var historyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History").font(.headline).foregroundStyle(Theme.text)
            ForEach(item.history.reversed()) { t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Formatters.dateTime.string(from: t.at)).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 140, alignment: .leading)
                    Chip(text: t.automatic ? "AUTOMATIC" : "MANUAL", color: t.automatic ? Theme.cyan : Theme.violet)
                    Text("\(t.from?.displayName ?? "—") → \(t.to.displayName)").font(.callout).foregroundStyle(Theme.text)
                    Text(t.reason).font(.caption).foregroundStyle(Theme.dim)
                }
            }
        }
        .glassPanel()
    }
}

// MARK: - Gap Analyzer

struct GapAnalyzerView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    @State private var selected: Set<String> = []
    @State private var document: ExportDocument?
    @State private var exporting = false
    @State private var kind: GapKind?

    var body: some View {
        let all = GapAnalyzer.topologicalOrder(c.gaps)
        let shown = all.filter { kind == nil || $0.kind == kind }
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Development Gap Analyzer",
                          subtitle: "Structured requirements with dependencies, acceptance criteria and your priorities. Export proposed LifeOS quests — no XP, never auto-completed.",
                          symbol: "exclamationmark.triangle")
            HStack {
                Picker("Kind", selection: $kind) {
                    Text("All kinds").tag(GapKind?.none)
                    ForEach(GapKind.allCases, id: \.self) { k in Text(k.displayName).tag(GapKind?.some(k)) }
                }
                .frame(width: 300)
                Spacer()
                Text("\(selected.count) selected").foregroundStyle(Theme.dim)
                Button("Export proposed LifeOS quests…") {
                    do {
                        document = ExportDocument(data: try c.lifeOSExport(selected), filename: "hcg-system-tester.lifeos-backlog.json")
                        exporting = true
                    } catch { model.banner = "Export failed: \(error.localizedDescription)" }
                }
                .disabled(selected.isEmpty)
            }
            Text("Dependencies of selected requirements are included automatically. Quest keys are stable (hcg.systemtester.<gap-id>) so importing again never duplicates. You approve and complete quests in LifeOS.")
                .font(.caption).foregroundStyle(Theme.dim)
            ForEach(shown) { g in gapRow(g) }
        }
        .workspacePage()
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: document?.filename ?? "lifeos-backlog") { result in
            if case .failure(let e) = result { model.banner = "Export failed: \(e.localizedDescription)" }
        }
    }

    func gapRow(_ g: DevelopmentRequirement) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle("", isOn: Binding(get: { selected.contains(g.id) }, set: { if $0 { selected.insert(g.id) } else { selected.remove(g.id) } }))
                    .toggleStyle(.checkbox).labelsHidden()
                Chip(text: g.kind.displayName.uppercased(), color: Theme.warning)
                Text(g.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Stepper("Priority \(g.priority)", value: Binding(get: { g.priority }, set: { c.setPriority(g.id, $0) }), in: 1...5)
                    .frame(width: 150)
            }
            Text(g.detail).font(.caption).foregroundStyle(Theme.dim)
            Text(g.id).font(.caption2.monospaced()).foregroundStyle(Theme.dim).textSelection(.enabled)
            if !g.dependsOn.isEmpty { Text("Depends on: " + g.dependsOn.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.cyan) }
            if !g.profileIDs.isEmpty { Text("Affects: " + g.profileIDs.compactMap { c.profile($0)?.displayName }.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.dim) }
            if !g.acceptanceCriteria.isEmpty { BulletList(items: g.acceptanceCriteria.map { "Done when: \($0)" }, color: Theme.text) }
        }
        .glassPanel(padding: 10)
    }
}

// MARK: - Compatibility Matrix

struct CompatibilityMatrixView: View {
    @EnvironmentObject var c: ConnectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Compatibility Matrix",
                          subtitle: "Separates research from physical evidence. Compatibility is “validated” only after verified diagnostics and your recorded decision.",
                          symbol: "tablecells")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(["Device", "Research", "Discovered (real)", "Connected (real)", "Diagnostics", "Your test report", "Roadmap"], id: \.self) { h in
                        Text(h.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(c.profiles) { p in row(p) }
            }
            .glassPanel()
            Text("“Real” columns count only evidence from real hardware. Synthetic fixtures are recorded in Connection History but never counted.").font(.caption).foregroundStyle(Theme.dim)
        }
        .workspacePage()
    }

    func row(_ p: EncyclopediaProfile) -> some View {
        let ev = c.evidence.filter { $0.profileID == p.id && $0.countsForRoadmap }
        let discovered = ev.contains { $0.kind == .discovered }
        let connected = ev.contains { $0.kind == .connectionAttempt && $0.outcome == .success }
        let diag = ev.last { $0.kind == .diagnostics }
        let report = ev.last { $0.kind == .userReport }
        let item = c.roadmapItem("device." + p.id)
        return GridRow {
            Text(p.displayName).font(.callout).foregroundStyle(Theme.text)
            Text(p.researchStatus.displayName).font(.caption).foregroundStyle(Theme.violet)
            mark(discovered)
            mark(connected)
            Text(diag.map { "\($0.testsPassed ?? 0)/\($0.testsApplicable ?? 0) passed" } ?? "—").font(.caption).foregroundStyle(diag == nil ? Theme.dim : Theme.text)
            Text(report.map { $0.outcome.rawValue.capitalized } ?? "—").font(.caption).foregroundStyle(report?.outcome.color ?? Theme.dim)
            if let i = item { RoadmapStateBadge(state: i.state, manual: i.isManual) } else { Text("—") }
        }
    }

    func mark(_ yes: Bool) -> some View {
        Image(systemName: yes ? "checkmark.circle.fill" : "circle").foregroundStyle(yes ? Theme.success : Theme.dim)
    }
}

// MARK: - AI Connection Assistant

struct AssistantView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var c: ConnectivityModel
    @State private var question = "How do I connect this device, and what is missing?"
    @State private var answer: AssistantAnswer?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "AI Connection Assistant",
                          subtitle: "Verified facts are kept apart from suggestions. Nothing is executed, sent or changed automatically.",
                          symbol: "sparkles")
            hcgAIPanel
            VStack(alignment: .leading, spacing: 8) {
                HStack { ProfilePicker(); Spacer() }
                HStack {
                    TextField("Ask about connecting this device", text: $question).textFieldStyle(.roundedBorder)
                    Button("Ask") {
                        answer = RuleBasedConnectionAssistant().answer(question, profile: c.profile(c.selectedProfileID), env: c.env, gaps: c.gaps)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                Text("Provider: \(RuleBasedConnectionAssistant().name). HCG AI is not connected (see above).").font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel()
            if let a = answer { answerPanel(a) }
        }
        .workspacePage()
    }

    var hcgAIPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HCG AI").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Check availability") { c.checkHCGAI() }.disabled(c.busy.contains("hcg-ai"))
            }
            Text("The check reads HCG AI's public handoff document only and sends no device data.").font(.caption).foregroundStyle(Theme.dim)
            if let s = c.aiStatus {
                KeyValueRow(key: "Status", value: "\(s.state.rawValue) — \(s.detail)")
                KeyValueRow(key: "Checked", value: Formatters.dateTime.string(from: s.checkedAt))
            }
            HStack {
                Button("Copy redacted research request") {
                    guard let p = c.profile(c.selectedProfileID) else { return }
                    let text = RuleBasedConnectionAssistant.researchRequest(profile: p, gaps: c.gaps.filter { $0.profileIDs.contains(p.id) }, question: question)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    model.banner = "Research request copied. Review it before pasting it anywhere — this is the manual transfer step."
                }
                Text("Contains the profile and gaps only — no serials, addresses or identifiers.").font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .glassPanel()
    }

    func answerPanel(_ a: AssistantAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer").font(.headline).foregroundStyle(Theme.text)
            ForEach(a.statements) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SourceBadge(source: s.source)
                    Text(s.text).font(.callout).foregroundStyle(Theme.text).textSelection(.enabled)
                }
            }
            if !a.suggestedActions.isEmpty {
                Text("Suggested next steps (for you to review — never executed)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                BulletList(items: a.suggestedActions)
            }
        }
        .glassPanel()
    }
}

// MARK: - Connection History

struct ConnectionHistoryView: View {
    @EnvironmentObject var c: ConnectivityModel
    @State private var physicalOnly = false

    var body: some View {
        let list = c.evidence.reversed().filter { !physicalOnly || $0.countsForRoadmap }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Connection History",
                          subtitle: "Every discovery, attempt (including failures), diagnostic run and report. History is kept when devices disconnect.",
                          symbol: "clock.arrow.circlepath")
            Toggle("Physical evidence only (hide synthetic)", isOn: $physicalOnly)
            if list.isEmpty {
                EmptyStateView(symbol: "clock", title: "No history yet", message: "Evidence appears when you connect devices, run diagnostics or attempt connections.")
            }
            ForEach(Array(list.prefix(300))) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Formatters.dateTime.string(from: e.at)).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                        Chip(text: e.kind.rawValue.uppercased(), color: Theme.violet)
                        Chip(text: e.outcome.rawValue.uppercased(), color: e.outcome.color)
                        EvidenceProvenanceBadge(evidence: e)
                        if !e.countsForRoadmap { Chip(text: "NOT COUNTED", color: Theme.dim) }
                        Text(c.profile(e.profileID)?.displayName ?? "No profile").font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(e.source).font(.caption2).foregroundStyle(Theme.dim)
                    }
                    Text("\(c.masking ? "" : e.endpointName + " — ")\(e.summary)").font(.callout).foregroundStyle(Theme.text)
                    if !e.details.isEmpty {
                        Text(e.details.prefix(6).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                }
                .glassPanel(padding: 10)
            }
        }
        .workspacePage()
    }
}
#endif
