#if os(macOS)
import SwiftUI
import Charts
import HCGCore

/// Live Device Monitor: uptime, availability, response latency and events for connected devices.
/// Samples are real measurements only (IOKit re-reads; CoreDevice queries for paired Apple devices).
struct LiveMonitorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        _ = model.monitorRevision
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeader(title: "Live Device Monitor",
                              subtitle: "Real measurements only. Presence is sampled cheaply from IOKit; CoreDevice latency only for paired Apple devices, at a slower interval.",
                              symbol: "waveform.path.ecg")
                Toggle(model.monitorPaused ? "Paused" : "Live", isOn: Binding(get: { !model.monitorPaused }, set: { model.monitorPaused = !$0 }))
                    .toggleStyle(.switch)
            }
            MonitorSettingsBar()
            if model.presentRecords.isEmpty {
                EmptyStateView(symbol: "waveform.path.ecg", title: "No connected devices",
                               message: "Connect a device. Monitoring starts automatically and stops when the device disconnects.")
                    .glassPanel()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), spacing: 18, alignment: .top)], spacing: 18) {
                ForEach(model.presentRecords) { r in
                    MonitorCard(record: r)
                }
            }
            RecentEventsPanel()
        }
        .workspacePage()
    }
}

private struct MonitorSettingsBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            Picker("Presence interval", selection: $model.settings.monitorIntervalSeconds) {
                ForEach([2.0, 5.0, 10.0, 30.0], id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            .frame(width: 220)
            Toggle("CoreDevice latency (paired Apple devices)", isOn: $model.settings.monitorCoreDevice)
            Picker("every", selection: $model.settings.coreDeviceIntervalSeconds) {
                ForEach([15.0, 30.0, 60.0, 300.0], id: \.self) { Text($0 < 60 ? "\(Int($0)) s" : "\(Int($0 / 60)) min").tag($0) }
            }
            .frame(width: 150)
            .disabled(!model.settings.monitorCoreDevice)
            Toggle("Auto-refresh device intelligence", isOn: $model.settings.autoRefreshIntelligence)
            Spacer()
        }
        .font(.callout)
        .glassPanel(padding: 12)
    }
}

private struct MonitorCard: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let stats = model.liveMonitor.stats(key: record.stableKey)
        let samples = Array(model.liveMonitor.samples(key: record.stableKey).suffix(240))
        let snap = model.snapshot(record.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: record.identification.category.symbolName).foregroundStyle(record.device.provenance.isSynthetic ? Theme.synthetic : Theme.cyan)
                Text(record.device.displayName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                if let s = snap { IntelligenceStateBadge(state: s.state) }
            }
            HStack(spacing: 18) {
                Stat(title: "Uptime", value: duration(stats.uptimeSeconds))
                Stat(title: "Availability", value: stats.availabilityPercent.map { String(format: "%.1f %%", $0) } ?? "—")
                Stat(title: "Drop-outs", value: "\(stats.dropouts)")
                Stat(title: "Samples", value: "\(stats.samples)")
            }
            ForEach(stats.latencyBySource.keys.sorted(), id: \.self) { source in
                if let l = stats.latencyBySource[source] {
                    HStack {
                        Text(source).font(.caption).foregroundStyle(Theme.dim)
                        Spacer()
                        Text(String(format: "last %.2f ms · mean %.2f · min %.2f · max %.2f (%ld)", l.last, l.mean, l.min, l.max, l.count))
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.text)
                    }
                }
            }
            if samples.contains(where: { $0.latencyMs != nil }) {
                LatencyChart(samples: samples.filter { $0.latencyMs != nil })
            } else {
                Text("Collecting samples…").font(.caption).foregroundStyle(Theme.dim)
            }
            HStack {
                Button("Open workspace") {
                    model.selectedDeviceID = record.id
                    model.workspaceTab = .overview
                    model.section = .connectedSystems
                }
                .buttonStyle(.link)
                Spacer()
                Button("Reset measurements") { model.liveMonitor.reset(key: record.stableKey) }.buttonStyle(.link)
            }
        }
        .glassPanel()
    }

    func duration(_ s: Double) -> String {
        let t = Int(s)
        return t >= 3600 ? String(format: "%ldh %02ldm", t / 3600, (t % 3600) / 60) : String(format: "%ldm %02lds", t / 60, t % 60)
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.dim)
            Text(value).font(.system(.title3, design: .rounded).monospacedDigit()).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecentEventsPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Event history", subtitle: "Automatic connect / disconnect detection", symbol: "list.bullet.rectangle")
            ForEach(model.events.prefix(25)) { e in
                Text("\(Formatters.time.string(from: e.at)) · \(e.kind.rawValue) · \(e.deviceName) — \(e.detail)").font(.caption).foregroundStyle(Theme.text).lineLimit(1)
            }
        }
        .glassPanel()
    }
}
#endif
