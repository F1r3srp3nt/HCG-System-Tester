#if os(macOS)
import SwiftUI
import HCGCore

struct CommandCenterView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroHeader()
            MetricsRow()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    LiveDevicesPanel()
                    ConnectionMatrixPanel()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 20) {
                    EventFeedPanel()
                    HostPanel()
                }
                .frame(width: 380)
            }
        }
        .workspacePage()
    }
}

private struct HeroHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().stroke(Theme.accentGradient, lineWidth: 2).frame(width: 58, height: 58)
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.cyan)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Command Center").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                Text(HCGSystemTesterInfo.motto).font(.callout.weight(.medium)).foregroundStyle(Theme.accentGradient)
                Text("Connect a device by USB-C. If macOS enumerates it, it appears here within a second.")
                    .font(.callout).foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(HCGSystemTesterInfo.principle).font(.caption.weight(.heavy)).foregroundStyle(Theme.violet)
                Button {
                    model.restartDiscovery()
                } label: {
                    Label("Restart discovery", systemImage: "arrow.clockwise")
                }
                .help("Re-arm IOKit notifications (⇧⌘R)")
            }
        }
        .glassPanel(padding: 20, glow: Theme.cyan)
    }
}

private struct MetricsRow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let hardware = model.hardwareRecords
        let synthetic = model.presentRecords.filter { $0.device.provenance.isSynthetic }.count
        let diagnosable = hardware.filter { $0.status == .diagnosticsAvailable || $0.status == .connected || $0.status == .authenticated }.count
        let needsAdapter = hardware.filter { $0.status == .adapterRequired || $0.status == .unsupported }.count
        return HStack(spacing: 14) {
            MetricTile(title: "Real devices", value: "\(hardware.count)", detail: "Enumerated by IOKit now", symbol: "cable.connector", tint: Theme.cyan)
            MetricTile(title: "Diagnosable", value: "\(diagnosable)", detail: "Read-only host diagnostics", symbol: "stethoscope", tint: Theme.success)
            MetricTile(title: "Adapter / unsupported", value: "\(needsAdapter)", detail: "Recorded as compatibility evidence", symbol: "puzzlepiece.extension", tint: Theme.warning)
            MetricTile(title: "Diagnostic runs", value: "\(model.recentRuns.count)", detail: "This session", symbol: "waveform.path.ecg", tint: Theme.violet)
            if synthetic > 0 {
                MetricTile(title: "Synthetic", value: "\(synthetic)", detail: "Labelled fixtures — not hardware", symbol: "flask", tint: Theme.synthetic)
            }
        }
    }
}

private struct LiveDevicesPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Live systems", subtitle: "Newest first. Status reflects verified layers only.", symbol: "dot.radiowaves.up.forward")
            if model.presentRecords.isEmpty {
                EmptyStateView(symbol: "cable.connector.slash", title: "Waiting for a device",
                               message: "Plug in a USB device (storage, phone, controller, hub, serial board). Charge-only cables and host-to-host links such as Mac ↔ console never enumerate, so nothing will appear for them — that is itself useful evidence.")
            } else {
                ForEach(model.presentRecords.prefix(8)) { record in
                    DeviceRow(record: record, pulse: model.newDevicePulse == record.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedDeviceID = record.id
                            model.section = .connectedSystems
                        }
                }
                if model.presentRecords.count > 8 {
                    Button("Show all \(model.presentRecords.count) systems") { model.section = .connectedSystems }
                        .buttonStyle(.link)
                }
            }
        }
        .glassPanel()
    }
}

struct DeviceRow: View {
    let record: DeviceRecord
    var pulse = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject var model: AppModel
    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.identification.category.symbolName)
                .font(.title2).frame(width: 34)
                .foregroundStyle(record.device.provenance.isSynthetic ? Theme.synthetic : Theme.cyan)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.device.displayName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    ProvenanceBadge(provenance: record.device.provenance)
                }
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            StatusBadge(status: record.status)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.navyHigh.opacity(glow ? 0.9 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyan.opacity(glow ? 0.8 : 0.0), lineWidth: 1))
        .onAppear {
            guard pulse, !(systemReduceMotion || model.settings.reduceMotion) else { return }
            withAnimation(.easeOut(duration: 0.4)) { glow = true }
            withAnimation(.easeIn(duration: 1.4).delay(0.6)) { glow = false }
        }
        .accessibilityElement(children: .combine)
    }

    var subtitle: String {
        var parts: [String] = []
        if let usb = record.device.usb {
            parts.append("\(usb.vendorIDHex):\(usb.productIDHex)")
            if let s = usb.speed { parts.append(s.shortName) }
        }
        parts.append(record.identification.profileName ?? "Unidentified")
        parts.append(record.device.connectionType.displayName)
        return parts.joined(separator: " · ")
    }
}

private struct ConnectionMatrixPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Universal Connection Engine", subtitle: "What each interface can honestly verify on this Mac today.", symbol: "square.grid.3x3")
            ForEach(ConnectionCapabilityRegistry.macOS) { cap in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: cap.connectionType.symbolName).frame(width: 22).foregroundStyle(Theme.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(cap.connectionType.displayName).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            SupportBadge(support: cap.support)
                        }
                        Text(cap.discoveryMethod).font(.caption).foregroundStyle(Theme.dim)
                        if let first = cap.limitations.first {
                            Text(first).font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))
                        }
                    }
                    Spacer()
                    LayerDots(layers: cap.verifiableLayers)
                }
                Divider().opacity(0.2)
            }
        }
        .glassPanel()
    }
}

/// Five dots, one per connectivity layer, filled when the interface can verify that layer.
struct LayerDots: View {
    let layers: [ConnectivityLayer]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConnectivityLayer.allCases) { layer in
                Circle()
                    .fill(layers.contains(layer) ? Theme.success : Theme.dim.opacity(0.25))
                    .frame(width: 8, height: 8)
                    .help(layer.displayName)
            }
        }
        .accessibilityLabel("Verifiable layers: " + (layers.isEmpty ? "none" : layers.map(\.displayName).joined(separator: ", ")))
    }
}

private struct EventFeedPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Event stream", subtitle: "Connection and disconnection events", symbol: "list.bullet.rectangle")
            if model.events.isEmpty {
                Text("No events yet.").font(.callout).foregroundStyle(Theme.dim)
            }
            ForEach(model.events.prefix(14)) { e in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(e.kind)).foregroundStyle(color(e.kind)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(e.deviceName).font(.caption.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            if e.provenance.isSynthetic { Text("SYN").font(.caption2.weight(.heavy)).foregroundStyle(Theme.synthetic) }
                        }
                        Text(e.detail).font(.caption2).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                    Spacer()
                    Text(Formatters.time.string(from: e.at)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                }
            }
        }
        .glassPanel()
    }

    func symbol(_ k: InventoryEvent.Kind) -> String {
        switch k {
        case .attached: return "arrow.down.circle.fill"
        case .detached: return "arrow.up.circle"
        case .reattached: return "arrow.triangle.2.circlepath"
        case .statusChanged: return "arrow.right.circle"
        case .backend: return "antenna.radiowaves.left.and.right"
        }
    }

    func color(_ k: InventoryEvent.Kind) -> Color {
        switch k {
        case .attached, .reattached: return Theme.success
        case .detached: return Theme.warning
        case .statusChanged: return Theme.violet
        case .backend: return Theme.cyan
        }
    }
}

private struct HostPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Host", subtitle: nil, symbol: "laptopcomputer")
            KeyValueRow(key: "Name", value: model.host.name)
            KeyValueRow(key: "Model", value: model.host.modelIdentifier)
            KeyValueRow(key: "Chip", value: model.host.chip)
            KeyValueRow(key: "Memory", value: Formatters.bytes(Int64(model.host.memoryBytes)))
            KeyValueRow(key: "macOS", value: model.host.osVersion)
            KeyValueRow(key: "Architecture", value: model.host.architecture)
        }
        .glassPanel()
    }
}
#endif
