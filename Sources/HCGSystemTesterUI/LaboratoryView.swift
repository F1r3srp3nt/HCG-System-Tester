#if os(macOS)
import SwiftUI
import Charts
import HCGCore

struct LaboratoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedKey: String?
    @State private var measurement: String?
    @State private var compareKeys: Set<String> = []

    var profiles: [SavedDeviceProfile] {
        _ = model.labRevision
        return model.laboratory.profiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Device Laboratory",
                          subtitle: "Saved device profiles, connection history, sessions, measurements over time and compatibility evidence. Synthetic data is always marked.",
                          symbol: "flask")
            HStack(alignment: .top, spacing: 18) {
                ProfileList(profiles: profiles, selectedKey: $selectedKey, compareKeys: $compareKeys)
                    .frame(width: 330)
                VStack(alignment: .leading, spacing: 18) {
                    if let key = selectedKey, let profile = model.laboratory.profile(key) {
                        ProfileDetail(profile: profile, measurement: $measurement)
                    } else {
                        EmptyStateView(symbol: "flask", title: "Select a device profile",
                                       message: "Every device that connects is saved here (keyed by a privacy-preserving fingerprint, never the raw serial number).")
                            .glassPanel()
                    }
                    if compareKeys.count >= 2 {
                        ComparisonPanel(keys: Array(compareKeys).sorted())
                    }
                    SessionsPanel()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .workspacePage()
    }
}

private struct ProfileList: View {
    @EnvironmentObject var model: AppModel
    let profiles: [SavedDeviceProfile]
    @Binding var selectedKey: String?
    @Binding var compareKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved profiles (\(profiles.count))").font(.headline).foregroundStyle(Theme.text)
            if profiles.isEmpty {
                Text("Profiles are created automatically when devices connect.").font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(profiles) { p in
                HStack {
                    Toggle("", isOn: Binding(get: { compareKeys.contains(p.key) },
                                             set: { if $0 { compareKeys.insert(p.key) } else { compareKeys.remove(p.key) } }))
                        .labelsHidden()
                        .help("Select two or more to compare")
                    Image(systemName: p.category.symbolName).foregroundStyle(p.provenance.isSynthetic ? Theme.synthetic : Theme.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.nickname.isEmpty ? p.displayName : p.nickname).font(.callout).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(p.vendorIDHex):\(p.productIDHex) · \(p.history.count) events").font(.caption2).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(selectedKey == p.key ? Theme.cyan.opacity(0.15) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { selectedKey = p.key }
            }
        }
        .glassPanel()
    }
}

private struct ProfileDetail: View {
    @EnvironmentObject var model: AppModel
    let profile: SavedDeviceProfile
    @Binding var measurement: String?
    @State private var notes = ""
    @State private var nickname = ""

    var body: some View {
        let names = model.laboratory.measurementNames(deviceKey: profile.key)
        let chosen = measurement.flatMap { names.contains($0) ? $0 : nil } ?? names.first
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.displayName).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                ProvenanceBadge(provenance: profile.provenance)
                Spacer()
                Text("First seen \(Formatters.dateTime.string(from: profile.firstSeen))").font(.caption).foregroundStyle(Theme.dim)
            }
            HStack {
                TextField("Nickname", text: $nickname, onCommit: { model.laboratory.setNickname(nickname, for: profile.key) })
                    .frame(maxWidth: 240)
                Text("Key \(profile.key)").font(.caption2.monospaced()).foregroundStyle(Theme.dim).textSelection(.enabled)
            }
            if names.isEmpty {
                Text("No measurements yet. Run diagnostics on this device to start a timeline.").font(.caption).foregroundStyle(Theme.dim)
            } else {
                Picker("Measurement", selection: Binding(get: { chosen ?? "" }, set: { measurement = $0 })) {
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 360)
                if let name = chosen {
                    MeasurementChart(points: model.laboratory.series(deviceKey: profile.key, measurement: name), name: name)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONNECTION HISTORY").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                    ForEach(Array(profile.history.suffix(12).reversed().enumerated()), id: \.offset) { _, h in
                        Text("\(Formatters.dateTime.string(from: h.at)) · \(h.event) · \(h.status.displayName)").font(.caption2).foregroundStyle(Theme.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPATIBILITY EVIDENCE").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                    if profile.compatibility.isEmpty {
                        Text("None recorded. Use “Record compatibility evidence” on the device page — unsuccessful connections are valuable too.")
                            .font(.caption2).foregroundStyle(Theme.dim)
                    }
                    ForEach(profile.compatibility.reversed()) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Formatters.dateTime.string(from: c.at)) · \(c.connectionType.displayName) · \(c.outcome)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.text)
                            if let l = c.limitingLayer { Text(l).font(.caption2).foregroundStyle(Theme.warning) }
                            Text(c.notes).font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTES").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                TextEditor(text: $notes).frame(minHeight: 70).font(.callout).scrollContentBackground(.hidden)
                    .background(Theme.obsidian.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                Button("Save notes") { model.laboratory.setNotes(notes, for: profile.key) }
            }
        }
        .glassPanel()
        .onAppear { notes = profile.notes; nickname = profile.nickname }
        .onChange(of: profile.key) { _, _ in notes = profile.notes; nickname = profile.nickname }
    }
}

struct MeasurementChart: View {
    let points: [MeasurementPoint]
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(points) { p in
                LineMark(x: .value("Time", p.at), y: .value(name, p.value))
                    .foregroundStyle(Theme.accentGradient)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Time", p.at), y: .value(name, p.value))
                    .foregroundStyle(p.provenance.isSynthetic ? Theme.synthetic : Theme.cyan)
                    .symbol(p.provenance.isSynthetic ? BasicChartSymbolShape.diamond : BasicChartSymbolShape.circle)
            }
            .chartYAxisLabel(points.first?.unit ?? "")
            .frame(height: 180)
            if points.contains(where: { $0.provenance.isSynthetic }) {
                Text("◆ Synthetic points are simulated and not real measurements.").font(.caption2).foregroundStyle(Theme.synthetic)
            }
        }
        .accessibilityLabel("\(name) over time, \(points.count) measurements")
    }
}

private struct ComparisonPanel: View {
    @EnvironmentObject var model: AppModel
    let keys: [String]

    var body: some View {
        let rows = model.laboratory.comparison(deviceKeys: keys)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Device comparison (latest values)").font(.headline).foregroundStyle(Theme.text)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Measurement").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                    ForEach(keys, id: \.self) { k in
                        Text(model.laboratory.profile(k)?.displayName ?? k).font(.caption.weight(.bold)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                ForEach(rows, id: \.measurement) { row in
                    GridRow {
                        Text(row.measurement).font(.caption).foregroundStyle(Theme.text)
                        ForEach(keys, id: \.self) { k in
                            let m = row.values[k]
                            Text(m.map { $0.formatted + ($0.provenance.isSynthetic ? " ◆" : "") } ?? "—").font(.caption.monospacedDigit())
                                .foregroundStyle(m?.provenance.isSynthetic == true ? Theme.synthetic : Theme.cyan)
                        }
                    }
                }
            }
        }
        .glassPanel()
    }
}

private struct SessionsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        _ = model.labRevision
        let sessions = model.laboratory.sessions
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostic sessions").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("New session") {
                    let s = model.laboratory.createSession(title: "Session \(Formatters.dateTime.string(from: Date()))")
                    model.activeSessionID = s.id
                }
            }
            if sessions.isEmpty {
                Text("Runs are grouped into sessions automatically.").font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(sessions.prefix(12)) { s in
                HStack {
                    Image(systemName: model.activeSessionID == s.id ? "record.circle.fill" : "folder").foregroundStyle(model.activeSessionID == s.id ? Theme.danger : Theme.cyan)
                    Text(s.title).font(.callout).foregroundStyle(Theme.text)
                    if s.containsSyntheticData { ProvenanceBadge(provenance: .synthetic) }
                    Spacer()
                    Text("\(s.runs.count) run(s) · \(s.deviceKeys.count) device(s)").font(.caption).foregroundStyle(Theme.dim)
                    Button("Report") {
                        model.generateReport(title: s.title, runs: s.runs, deviceIDs: [], notes: s.notes)
                        model.section = .reports
                    }
                    .disabled(s.runs.isEmpty)
                    Button("Make active") { model.activeSessionID = s.id }
                        .disabled(model.activeSessionID == s.id)
                }
            }
        }
        .glassPanel()
    }
}
#endif
