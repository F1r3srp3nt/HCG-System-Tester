#if os(macOS)
import SwiftUI
import HCGCore

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var chosenTests: Set<String> = []
    @State private var allowExtended = false
    @State private var authorizedStateChanging: Set<String> = []
    @State private var pendingAuthorization: DiagnosticTestDescriptor?

    var target: DeviceRecord? {
        model.selectedRecord.flatMap { $0.device.isPresent ? $0 : nil } ?? model.presentRecords.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Diagnostic Engine",
                          subtitle: "Read-only by default. Extended and state-changing tests run only with your explicit authorisation.",
                          symbol: "waveform.path.ecg.rectangle")
            if model.presentRecords.isEmpty {
                EmptyStateView(symbol: "stethoscope", title: "No device to diagnose",
                               message: "Connect a device, or enable labelled synthetic fixtures in Settings to try the engine.")
                    .glassPanel()
            } else {
                TargetPicker()
                if let t = target {
                    HStack(alignment: .top, spacing: 18) {
                        testCatalog(for: t).frame(maxWidth: .infinity)
                        ResultsPanel(record: t).frame(maxWidth: .infinity)
                    }
                }
            }
            UncoveredCategoriesNote()
        }
        .workspacePage()
        .onChange(of: target?.id) { _, _ in
            chosenTests = []
            authorizedStateChanging = []
        }
        .alert(item: $pendingAuthorization) { d in
            Alert(title: Text("Authorise “\(d.name)”?"),
                  message: Text("\(d.impact.displayName).\n\n\(d.effects ?? d.summary)\n\nThis authorisation applies to this device for this run only and is written to the audit log."),
                  primaryButton: .destructive(Text("Authorise")) {
                      authorizedStateChanging.insert(d.id)
                      chosenTests.insert(d.id)
                  },
                  secondaryButton: .cancel())
        }
    }

    func testCatalog(for record: DeviceRecord) -> some View {
        let descriptors = model.engine.tests.map(\.descriptor)
        let applicable = Set(model.engine.applicableTests(for: record.device, identification: record.identification).map(\.id))
        let selected = chosenTests.isEmpty ? Set(model.engine.defaultSuite(for: record.device, identification: record.identification)) : chosenTests
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tests").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Toggle("Allow extended tests", isOn: $allowExtended).toggleStyle(.switch).controlSize(.small)
                    .help("Extended tests are read-only but long-running (e.g. 60 s stability).")
            }
            ForEach(descriptors) { d in
                TestRow(descriptor: d, applicable: applicable.contains(d.id), selected: selected.contains(d.id),
                        authorized: authorizedStateChanging.contains(d.id)) { on in
                    var current = selected
                    if on {
                        if d.impact == .stateChanging && !authorizedStateChanging.contains(d.id) {
                            pendingAuthorization = d
                            return
                        }
                        if d.impact == .extended { allowExtended = true }
                        current.insert(d.id)
                    } else {
                        current.remove(d.id)
                    }
                    chosenTests = current
                }
            }
            HStack {
                Button {
                    let ordered = descriptors.map(\.id).filter { selected.contains($0) }
                    model.run(testIDs: ordered, on: record,
                              authorization: DiagnosticAuthorization(allowExtended: allowExtended, authorizedStateChangingTests: authorizedStateChanging))
                } label: {
                    Label(model.activeRuns[record.id] == nil ? "Run \(selected.count) test(s)" : "Running…", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan.opacity(0.75))
                .disabled(selected.isEmpty || model.activeRuns[record.id] != nil)
                Button("Reset to default suite") { chosenTests = []; authorizedStateChanging = [] }
                ForEach(model.laboratory.collections) { c in
                    Button(c.name) {
                        chosenTests = Set(c.testIDs)
                        allowExtended = c.authorization.allowExtended
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .glassPanel()
    }
}

private struct TargetPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            Text("Target").foregroundStyle(Theme.dim)
            Picker("Target", selection: Binding<DeviceIdentifier?>(
                get: { model.selectedRecord?.device.isPresent == true ? model.selectedDeviceID : model.presentRecords.first?.id },
                set: { model.selectedDeviceID = $0 })) {
                ForEach(model.presentRecords) { r in
                    Text(r.device.displayName + (r.device.provenance.isSynthetic ? "" : "  ·  real hardware")).tag(Optional(r.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 520)
            Spacer()
            if let r = model.selectedRecord ?? model.presentRecords.first {
                StatusBadge(status: r.status)
                ProvenanceBadge(provenance: r.device.provenance)
            }
        }
        .glassPanel(padding: 12)
    }
}

private struct TestRow: View {
    let descriptor: DiagnosticTestDescriptor
    let applicable: Bool
    let selected: Bool
    let authorized: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { selected && applicable }, set: { toggle($0) }))
                .labelsHidden()
                .disabled(!applicable)
            Image(systemName: descriptor.category.symbolName).foregroundStyle(applicable ? Theme.cyan : Theme.dim).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(descriptor.name).font(.callout.weight(.medium)).foregroundStyle(applicable ? Theme.text : Theme.dim)
                    if descriptor.impact != .readOnly {
                        Text(descriptor.impact == .extended ? "EXTENDED" : "STATE-CHANGING")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(descriptor.impact == .extended ? Theme.warning : Theme.danger)
                    }
                    if authorized { Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.success).help("Authorised for this run") }
                }
                Text(descriptor.summary).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if !applicable {
                    Text("Not applicable to this device").font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))
                }
            }
            Spacer()
            Text(descriptor.category.displayName).font(.caption2).foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ResultsPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results").font(.headline).foregroundStyle(Theme.text)
            if let active = model.activeRuns[record.id] {
                ProgressView(value: Double(active.results.count), total: Double(max(1, active.total))) {
                    Text("Running \(active.results.count + 1) of \(active.total)…").font(.caption)
                }
                .tint(Theme.cyan)
                ForEach(active.results) { ResultCard(result: $0) }
            } else if let last = model.recentRuns.first(where: { $0.deviceKey == record.stableKey }) {
                RunSummary(run: last)
                ForEach(last.results) { ResultCard(result: $0) }
            } else {
                Text("No runs yet for this device. Run the default read-only suite to begin.").font(.callout).foregroundStyle(Theme.dim)
            }
        }
        .glassPanel()
    }
}

struct RunSummary: View {
    let run: DiagnosticRun

    var body: some View {
        HStack(spacing: 14) {
            ForEach([DiagnosticOutcome.passed, .warning, .failed, .aborted, .notSupported, .skipped], id: \.self) { o in
                let n = run.count(o)
                if n > 0 {
                    Label("\(n) \(o.displayName)", systemImage: Theme.symbol(for: o)).font(.caption).foregroundStyle(Theme.color(for: o))
                }
            }
            Spacer()
            Text(Formatters.dateTime.string(from: run.startedAt)).font(.caption).foregroundStyle(Theme.dim)
            if run.provenance.isSynthetic { ProvenanceBadge(provenance: .synthetic) }
        }
    }
}

struct ResultCard: View {
    let result: DiagnosticResult
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                OutcomeBadge(outcome: result.outcome)
                Text(result.testName).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(String(format: "%.2f s", result.durationSeconds)).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(expanded ? "Collapse details" : "Expand details")
            }
            Text(result.summary).font(.caption).foregroundStyle(Theme.text)
            if !result.measurements.isEmpty {
                HStack(spacing: 12) {
                    ForEach(result.measurements) { m in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.formatted).font(.system(.callout, design: .rounded).monospacedDigit()).foregroundStyle(Theme.cyan)
                            Text(m.name).font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
            if expanded {
                DetailList(title: "Evidence", items: result.evidence, color: Theme.text)
                DetailList(title: "Limitations", items: result.limitations, color: Theme.warning)
                DetailList(title: "Errors", items: result.errors, color: Theme.danger)
                Text("Next: \(result.recommendedNextAction)").font(.caption).foregroundStyle(Theme.violet)
                Text("\(result.testID) · \(result.category.displayName) · \(result.impact.displayName) · \(Formatters.time.string(from: result.startedAt)) → \(Formatters.time.string(from: result.finishedAt)) · \(result.provenance.displayName)")
                    .font(.caption2.monospaced()).foregroundStyle(Theme.dim)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.navyHigh.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.color(for: result.outcome).opacity(0.35)))
    }
}

struct DetailList: View {
    let title: String
    let items: [String]
    let color: Color

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                ForEach(items, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(color).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

private struct UncoveredCategoriesNote: View {
    var body: some View {
        let uncovered = HostOperationCatalog.uncoveredCategories
        return Group {
            if !uncovered.isEmpty {
                Label("Not yet implemented as host tests: " + uncovered.map(\.displayName).joined(separator: ", ") +
                      ". These need device-specific adapters (e.g. SMART via a supported bridge) and are reported as \"not tested\" in exports.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }
}
#endif
