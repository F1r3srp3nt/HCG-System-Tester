#if os(macOS)
import SwiftUI
import Charts
import UniformTypeIdentifiers
import HCGCore

// MARK: - Device illustration

/// Vector illustration of the device. iPhone / iPad get device-specific shapes; others a category glyph.
struct DeviceIllustration: View {
    let record: DeviceRecord
    var state: IntelligenceState?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject var model: AppModel
    @State private var glow = false

    var kind: String {
        let n = (record.device.usb?.productName ?? record.device.name).lowercased()
        if record.device.usb?.vendorID == 0x05AC && n.contains("ipad") { return "ipad" }
        if record.device.usb?.vendorID == 0x05AC && n.contains("iphone") { return "iphone" }
        return "generic"
    }

    var tint: Color {
        if record.device.provenance.isSynthetic { return Theme.synthetic }
        guard let s = state else { return Theme.color(for: record.status) }
        switch s {
        case .diagnosticsAvailable, .communicationEstablished: return Theme.success
        case .authorizationRequired, .pairingAvailable, .connectionLimited: return Theme.warning
        case .disconnected, .unsupported: return Theme.dim
        default: return Theme.cyan
        }
    }

    var body: some View {
        ZStack {
            switch kind {
            case "iphone": phone
            case "ipad": tablet
            default:
                Circle().fill(Theme.navyHigh).overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                    .overlay(Image(systemName: record.identification.category.symbolName).font(.system(size: 34, weight: .thin)).foregroundStyle(tint))
                    .frame(width: 92, height: 92)
            }
        }
        .shadow(color: tint.opacity(glow ? 0.65 : 0.25), radius: glow ? 22 : 10)
        .onAppear {
            guard !(systemReduceMotion || model.settings.reduceMotion), state?.needsUserAttention == true else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityLabel("Illustration of \(record.device.displayName)")
    }

    var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.metal.opacity(0.55), Theme.metal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, tint.opacity(0.35), Theme.obsidian], startPoint: .top, endPoint: .bottom))
                .padding(4)
            VStack {
                Capsule().fill(Color.black).frame(width: 30, height: 9).padding(.top, 11)
                Spacer()
                Image(systemName: state?.symbolName ?? "iphone").font(.system(size: 22, weight: .light)).foregroundStyle(tint)
                Spacer()
                Capsule().fill(Theme.metal.opacity(0.5)).frame(width: 34, height: 3).padding(.bottom, 8)
            }
        }
        .frame(width: 86, height: 170)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(0.8), lineWidth: 1.2))
    }

    var tablet: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.metal.opacity(0.55), Theme.metal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, tint.opacity(0.35), Theme.obsidian], startPoint: .top, endPoint: .bottom))
                .padding(5)
            VStack {
                Circle().fill(Color.black).frame(width: 6, height: 6).padding(.top, 9)
                Spacer()
                Image(systemName: state?.symbolName ?? "ipad").font(.system(size: 24, weight: .light)).foregroundStyle(tint)
                Spacer()
            }
        }
        .frame(width: 150, height: 112)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.8), lineWidth: 1.2))
    }
}

// MARK: - Overview

struct DeviceOverviewTab: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let snap = model.snapshot(record.id)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                DeviceIllustration(record: record, state: snap?.state).frame(width: 170)
                VStack(alignment: .leading, spacing: 8) {
                    Text(snap?.value("apple.name") ?? record.device.displayName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
                    Text([snap?.value("apple.marketingName"), snap?.value("apple.productType")].compactMap { $0 }.joined(separator: " · ").ifEmpty(record.identification.profileName ?? record.identification.category.displayName))
                        .font(.callout).foregroundStyle(Theme.dim)
                    if let os = snap?.value("apple.osVersion") {
                        Label("\(snap?.field("apple.platform")?.value ?? "OS") \(os)\(snap?.value("apple.osBuild").map { " (\($0))" } ?? "")", systemImage: "gearshape.2")
                            .font(.callout).foregroundStyle(Theme.text)
                    }
                    HStack(spacing: 8) {
                        StatusBadge(status: record.status)
                        if let s = snap { IntelligenceStateBadge(state: s.state) }
                        ProvenanceBadge(provenance: record.device.provenance)
                    }
                    CapabilityChips(snapshot: snap, record: record)
                }
                Spacer()
            }
            .glassPanel(padding: 18)
            if let s = snap {
                ConnectionLadderCard(record: record, snapshot: s)
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.busyIntelligence.contains(record.id) ? "Reading device intelligence…" : "Device intelligence not read yet.").foregroundStyle(Theme.dim)
                    Spacer()
                    Button("Read now") { model.scheduleIntelligence(record.id, delay: 0, force: true) }
                }
                .glassPanel()
            }
            HStack(alignment: .top, spacing: 18) {
                IntelligenceFieldsPanel(record: record, groups: [.overview, .battery, .storage], title: "At a glance").frame(maxWidth: .infinity)
                TimelinePanel(record: record, limit: 10).frame(maxWidth: .infinity)
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

struct IntelligenceStateBadge: View {
    let state: IntelligenceState
    var color: Color {
        switch state {
        case .diagnosticsAvailable, .communicationEstablished, .pairingEstablished: return Theme.success
        case .authorizationRequired, .pairingAvailable, .connectionLimited: return Theme.warning
        case .unsupported, .disconnected: return Theme.dim
        default: return Theme.cyan
        }
    }
    var body: some View {
        Label("\(state.number)/13 · \(state.displayName)", systemImage: state.symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: Capsule())
            .accessibilityLabel("Connection state \(state.number) of 13: \(state.displayName)")
    }
}

struct CapabilityChips: View {
    let snapshot: IntelligenceSnapshot?
    let record: DeviceRecord

    var body: some View {
        let protocols = record.identification.exposedProtocols.compactMap { ProtocolCatalog.descriptor($0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(protocols) { p in
                    Text(p.name).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .foregroundStyle(Theme.color(for: p.support))
                        .background(Theme.color(for: p.support).opacity(0.12), in: Capsule())
                        .help("\(p.support.displayName): \(p.summary)")
                }
                if let n = snapshot?.services.count, n > 0 {
                    Text("\(n) service(s)").font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .foregroundStyle(Theme.violet).background(Theme.violet.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

/// The 13-state ladder, current verified state and the next available action.
struct ConnectionLadderCard: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    let snapshot: IntelligenceSnapshot
    @State private var confirmPair = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Connection intelligence", subtitle: snapshot.stateReason, symbol: "arrow.triangle.branch")
                if model.busyIntelligence.contains(record.id) { ProgressView().controlSize(.small) }
                Button { model.scheduleIntelligence(record.id, delay: 0, force: true) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.busyIntelligence.contains(record.id))
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.ladder) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.reached ? "checkmark.circle.fill" : (step.state == snapshot.state ? "circle.inset.filled" : "circle"))
                                .foregroundStyle(step.reached ? Theme.success : (step.state == snapshot.state ? Theme.warning : Theme.dim.opacity(0.6)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(step.state.number). \(step.state.displayName)").font(.callout.weight(step.state == snapshot.state ? .bold : .regular))
                                    .foregroundStyle(step.reached ? Theme.text : Theme.dim)
                                if let e = step.evidence { Text(e).font(.caption2).foregroundStyle(Theme.dim).lineLimit(2) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if [.connectionLimited, .unsupported, .disconnected].contains(snapshot.state) {
                        Label("\(snapshot.state.number). \(snapshot.state.displayName)", systemImage: snapshot.state.symbolName)
                            .font(.callout.weight(.bold)).foregroundStyle(Theme.warning).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NextActionPanel(record: record, snapshot: snapshot, confirmPair: $confirmPair)
                    .frame(maxWidth: 380)
            }
            if !snapshot.limitations.isEmpty {
                DetailList(title: "Limitations", items: snapshot.limitations, color: Theme.warning)
            }
            if !snapshot.errors.isEmpty {
                DetailList(title: "Errors", items: snapshot.errors, color: Theme.danger)
            }
        }
        .glassPanel(glow: snapshot.state.needsUserAttention ? Theme.warning : nil)
        .alert("Pair with this Mac?", isPresented: $confirmPair) {
            Button("Start pairing") { model.performIntelligenceAction(.pairDevice, on: record) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts Apple's own pairing flow. Unlock the device, then tap “Trust” and enter your passcode on it. A pairing record is created on both devices; you can remove it later (Finder, or Settings › General › Transfer or Reset › Reset Location & Privacy on the device). Nothing else on the device is changed.")
        }
    }
}

struct NextActionPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    let snapshot: IntelligenceSnapshot
    @Binding var confirmPair: Bool

    var body: some View {
        let a = snapshot.nextAction
        return VStack(alignment: .leading, spacing: 8) {
            Text("NEXT ACTION").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
            Label(a.title, systemImage: icon(a.kind)).font(.headline).foregroundStyle(a.kind == .none || a.kind == .runDiagnostics ? Theme.success : Theme.warning)
            ForEach(Array(a.instructions.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(i + 1).").font(.caption.monospacedDigit()).foregroundStyle(Theme.cyan)
                    Text(step).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if a.kind == .pairDevice && a.performable {
                    Button { confirmPair = true } label: { Label("Pair…", systemImage: "link.badge.plus") }
                        .buttonStyle(.borderedProminent).tint(Theme.warning.opacity(0.8))
                        .disabled(model.busyIntelligence.contains(record.id))
                }
                if a.kind == .runDiagnostics {
                    Button { model.workspaceTab = .diagnostics } label: { Label("Open diagnostics", systemImage: "stethoscope") }
                        .buttonStyle(.borderedProminent).tint(Theme.cyan.opacity(0.7))
                }
                if a.kind == .installXcode || a.kind == .selectXcode {
                    Button("Re-inspect Xcode") { model.refreshToolchain() }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.navyHigh.opacity(0.55)))
    }

    func icon(_ k: NextActionKind) -> String {
        switch k {
        case .unlockDevice: return "lock.open"
        case .trustComputer, .pairDevice: return "hand.raised"
        case .enableDeveloperMode: return "hammer"
        case .installXcode, .selectXcode: return "wrench.and.screwdriver"
        case .useDataCable: return "cable.connector"
        case .runDiagnostics: return "checkmark.seal"
        case .reconnect, .connectDevice: return "cable.connector.horizontal"
        default: return "arrow.right.circle"
        }
    }
}

// MARK: - Sourced fields

struct IntelligenceFieldsPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    let groups: [IntelligenceGroup]
    let title: String

    var body: some View {
        let snap = model.snapshot(record.id)
        let fields = groups.flatMap { g in snap?.fields(in: g) ?? [] }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: title, subtitle: "Every value shows its source. Unavailable values say why.", symbol: "list.bullet.rectangle.portrait")
                Toggle("Mask identifiers", isOn: $model.settings.maskDeviceIdentifiers).toggleStyle(.switch).controlSize(.small)
            }
            if fields.isEmpty {
                Text(snap == nil ? "Not read yet." : "No fields in this section for this device.").font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(fields) { f in
                FieldRow(field: f, mask: model.settings.maskDeviceIdentifiers)
            }
        }
        .glassPanel()
    }
}

struct FieldRow: View {
    let field: IntelligenceField
    let mask: Bool
    @State private var showSource = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(field.label).foregroundStyle(Theme.dim).frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if field.isAvailable {
                    HStack(spacing: 4) {
                        Text(field.displayValue(maskSensitive: mask)).foregroundStyle(Theme.text).textSelection(.enabled)
                            .font(field.sensitive ? .system(.callout, design: .monospaced) : .callout)
                        if field.sensitive { Image(systemName: "eye.slash").font(.caption2).foregroundStyle(Theme.dim).help("Sensitive identifier — redacted in exports by default") }
                    }
                } else {
                    Text("Unavailable — \(field.unavailableReason ?? "")").font(.caption).foregroundStyle(Theme.warning.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                Text(field.source.description).font(.caption2.monospaced()).foregroundStyle(Theme.dim.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Software

struct ApplicationsPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let snap = model.snapshot(record.id)
        let paired = snap?.value("apple.pairingState")?.lowercased() == "paired"
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Applications", subtitle: "Read only on your request, from a paired device (devicectl device info apps).", symbol: "square.grid.2x2")
            if model.appleProvider(for: record) == nil {
                Text("No device-family adapter offers application information for this device.").font(.caption).foregroundStyle(Theme.dim)
            } else {
                HStack {
                    Button("List installed apps") { model.loadApps(for: record) }
                        .disabled(!paired || model.busyIntelligence.contains(record.id))
                    if !paired { Text("Requires pairing.").font(.caption).foregroundStyle(Theme.warning) }
                }
                if let apps = model.appleApps[record.id] {
                    Text("\(apps.count) app(s)").font(.caption).foregroundStyle(Theme.dim)
                    ForEach(apps.prefix(200)) { a in
                        HStack {
                            Text(a.name).font(.callout).foregroundStyle(Theme.text)
                            Text(a.bundleID).font(.caption.monospaced()).foregroundStyle(Theme.dim)
                            Spacer()
                            Text(a.version ?? "").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .glassPanel()
    }
}

// MARK: - Diagnostics

struct DeviceDiagnosticsTab: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var appleIDs: [String] { AppleDiagnostics.descriptors.map(\.id) }

    var body: some View {
        let isApple = model.appleProvider(for: record) != nil
        let samples = model.liveMonitor.samples(key: record.stableKey).filter { $0.latencyMs != nil }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if isApple {
                    Button {
                        model.run(testIDs: appleIDs.filter { $0 != "apple.reconnect-handling" } + ["apple.reconnect-handling"], on: record, authorization: .readOnly)
                    } label: { Label("Run Apple device diagnostics", systemImage: "play.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.cyan.opacity(0.75))
                    .disabled(model.activeRuns[record.id] != nil || !record.device.isPresent)
                }
                Button { model.runDefaultSuite(on: record) } label: { Label("Run host read-only suite", systemImage: "play.circle") }
                    .disabled(model.activeRuns[record.id] != nil || !record.device.isPresent)
                Spacer()
                Text("All tests are read-only.").font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel(padding: 12)
            if isApple {
                IntelligenceFieldsPanel(record: record, groups: [.battery, .storage], title: "Battery & storage")
            }
            if !samples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Response latency (Live Monitor)", subtitle: "Real samples only, by source.", symbol: "timer")
                    LatencyChart(samples: samples)
                }
                .glassPanel()
            }
            ResultsPanel(record: record)
        }
    }
}

struct LatencyChart: View {
    let samples: [MonitorSample]
    var body: some View {
        Chart(samples) { s in
            LineMark(x: .value("Time", s.at), y: .value("ms", max(0.001, s.latencyMs ?? 0)))
                .foregroundStyle(by: .value("Source", s.source))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Time", s.at), y: .value("ms", max(0.001, s.latencyMs ?? 0)))
                .foregroundStyle(by: .value("Source", s.source))
                .symbolSize(18)
        }
        .chartYAxisLabel("ms")
        .chartYScale(type: .log)
        .frame(height: 170)
        .accessibilityLabel("Response latency over time, \(samples.count) samples")
    }
}

// MARK: - Authorization

struct AuthorizationTab: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let snap = model.snapshot(record.id)
        return VStack(alignment: .leading, spacing: 18) {
            if let s = snap { ConnectionLadderCard(record: record, snapshot: s) }
            IntelligenceFieldsPanel(record: record, groups: [.authorization], title: "Trust, pairing & Developer Mode")
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "How authorization works", subtitle: "System Tester respects the device's own security controls.", symbol: "lock.shield")
                GuideRow(n: 1, text: "Unlock your iPhone or iPad. Locked devices (USB Restricted Mode) expose fewer services.")
                GuideRow(n: 2, text: "When “Trust This Computer?” appears, tap Trust and enter your passcode. Use “Pair…” to start this flow from System Tester.")
                GuideRow(n: 3, text: "Pairing lets System Tester read model, OS and service information through Xcode's CoreDevice. Nothing on the device is changed.")
                GuideRow(n: 4, text: "Developer Mode is only needed for developer capabilities (installing development builds, debugging). It is never required for System Tester's read-only information and is never enabled for you.")
                Text("Never bypassed: passcodes, pairing, device locks, USB Restricted Mode, Activation Lock.").font(.caption.weight(.semibold)).foregroundStyle(Theme.violet)
                if let paired = snap?.value("apple.pairingState"), paired.lowercased() == "paired" {
                    Text("To remove this Mac's pairing: in Finder select the device and choose “Forget”, or on the device use Settings › General › Transfer or Reset › Reset › Reset Location & Privacy.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .glassPanel()
        }
    }
}

struct GuideRow: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).frame(width: 20, height: 20).background(Circle().fill(Theme.cyan.opacity(0.2))).foregroundStyle(Theme.cyan)
            Text(text).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Activity

struct TimelinePanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    var limit = 60

    var body: some View {
        let entries = model.timeline(for: record).suffix(limit).reversed()
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Connection timeline", subtitle: nil, symbol: "clock.arrow.circlepath")
            if entries.isEmpty { Text("No events yet.").font(.caption).foregroundStyle(Theme.dim) }
            ForEach(Array(entries)) { e in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(e.kind)).foregroundStyle(color(e.kind)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.message).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        Text("\(Formatters.time.string(from: e.at)) · \(e.kind.rawValue)\(e.provenance.isSynthetic ? " · SYNTHETIC" : "")").font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .glassPanel()
    }

    func symbol(_ k: IntelligenceTimelineEntry.Kind) -> String {
        switch k {
        case .connect: return "arrow.down.circle.fill"
        case .disconnect: return "bolt.slash.fill"
        case .reconnect: return "arrow.triangle.2.circlepath"
        case .stateChange: return "arrow.right.circle"
        case .diagnostic: return "stethoscope"
        case .action: return "hand.tap"
        case .error: return "exclamationmark.triangle.fill"
        case .refresh: return "arrow.clockwise"
        }
    }

    func color(_ k: IntelligenceTimelineEntry.Kind) -> Color {
        switch k {
        case .connect, .reconnect: return Theme.success
        case .disconnect, .error: return Theme.danger
        case .action: return Theme.warning
        default: return Theme.cyan
        }
    }
}

struct DeviceActivityTab: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let events = model.events.filter { $0.deviceID == record.id || $0.deviceName == record.device.displayName }
        let audits = model.auditEntries.filter { $0.targetKey == record.stableKey }.suffix(40).reversed()
        let runs = model.recentRuns.filter { $0.deviceKey == record.stableKey }
        return HStack(alignment: .top, spacing: 18) {
            TimelinePanel(record: record).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Discovery events", subtitle: nil, symbol: "antenna.radiowaves.left.and.right")
                    ForEach(events.prefix(30)) { e in
                        Text("\(Formatters.time.string(from: e.at)) · \(e.kind.rawValue) · \(e.detail)").font(.caption).foregroundStyle(Theme.text)
                    }
                    if events.isEmpty { Text("None.").font(.caption).foregroundStyle(Theme.dim) }
                }
                .glassPanel()
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Diagnostic operations", subtitle: "\(runs.count) run(s) this session", symbol: "stethoscope")
                    ForEach(Array(audits)) { a in
                        Text("\(Formatters.time.string(from: a.timestamp)) · \(a.operation) · \(a.decision) · \(a.outcome)").font(.caption.monospaced()).foregroundStyle(Theme.text)
                    }
                    if audits.isEmpty { Text("None.").font(.caption).foregroundStyle(Theme.dim) }
                }
                .glassPanel()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Reports

struct DeviceReportsTab: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    @State private var kind: DeviceIntelligenceReport.Kind = .deviceInformation
    @State private var includeSensitive = false
    @State private var confirmSensitive = false
    @State private var exporting = false
    @State private var document: ExportDocument?
    @State private var exportJSON = true

    init(record: DeviceRecord) { self.record = record }

    var report: DeviceIntelligenceReport {
        DeviceIntelligenceReport.make(kind: kind, record: record, snapshot: model.snapshot(record.id), runs: model.recentRuns,
                                      includeSensitive: includeSensitive, privacy: model.settings.privacy)
    }

    var body: some View {
        let r = report
        let md = r.markdown()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Report", selection: $kind) {
                    ForEach(DeviceIntelligenceReport.Kind.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 340)
                Toggle("Include sensitive identifiers", isOn: Binding(get: { includeSensitive }, set: { on in
                    if on { confirmSensitive = true } else { includeSensitive = false }
                }))
                Spacer()
                Button("Export JSON…") { export(json: true, r: r, md: md) }
                Button("Export summary…") { export(json: false, r: r, md: md) }
            }
            Text(includeSensitive ? "⚠︎ UDID, ECID and serial numbers are INCLUDED in this export." : "UDID, ECID and serial numbers are redacted (default).")
                .font(.caption).foregroundStyle(includeSensitive ? Theme.danger : Theme.dim)
            ScrollView {
                Text(md).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .frame(minHeight: 380)
            .background(Theme.obsidian.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        }
        .glassPanel()
        .confirmationDialog("Include sensitive identifiers?", isPresented: $confirmSensitive) {
            Button("Include UDID, ECID and serial numbers", role: .destructive) { includeSensitive = true }
        } message: {
            Text("These identifiers uniquely identify the physical device. Only include them when the recipient needs them.")
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportJSON ? .json : .plainText,
                      defaultFilename: document?.filename ?? "device-report") { result in
            if case .failure(let e) = result { model.banner = "Export failed: \(e.localizedDescription)" }
        }
    }

    func export(json: Bool, r: DeviceIntelligenceReport, md: String) {
        do {
            let data = json ? try r.json() : Data(md.utf8)
            let stamp = ISO8601DateFormatter().string(from: r.generatedAt).replacingOccurrences(of: ":", with: "-")
            document = ExportDocument(data: data, filename: "hcg-\(kind.rawValue)-\(stamp).\(json ? "json" : "md")")
            exportJSON = json
            exporting = true
            model.auditLog.record(AuditEntry(actor: "user", operation: "report.export.\(kind.rawValue)", impact: .readOnly,
                                             target: r.deviceName, targetKey: record.stableKey,
                                             decision: includeSensitive ? "sensitive-included" : "redacted", outcome: "ok", provenance: record.device.provenance))
        } catch {
            model.banner = "Export failed: \(error.localizedDescription)"
        }
    }
}
#endif
