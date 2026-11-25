#if os(macOS)
import SwiftUI
import HCGCore

/// Explains why a device does or does not communicate. Read-only: no USB control requests are sent.
struct USBInspectorView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: DeviceIdentifier?

    var usbRecords: [DeviceRecord] { model.records.filter { $0.device.usb != nil } }

    var body: some View {
        let current = (selected ?? model.selectedDeviceID).flatMap { id in usbRecords.first { $0.id == id } } ?? usbRecords.first
        return VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "USB Connection Inspector",
                          subtitle: "Why a device does — or does not — communicate. Built from descriptors macOS already read; no USB requests are sent to devices.",
                          symbol: "magnifyingglass.circle")
            ConnectionClassesPanel(current: current)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("USB devices").font(.headline).foregroundStyle(Theme.text)
                    if usbRecords.isEmpty { Text("Nothing enumerated. See “Charging-only” above.").font(.caption).foregroundStyle(Theme.dim) }
                    ForEach(usbRecords) { r in
                        HStack {
                            Circle().fill(Theme.color(for: r.status)).frame(width: 8, height: 8)
                            Text(r.device.displayName).font(.callout).foregroundStyle(r.device.isPresent ? Theme.text : Theme.dim).lineLimit(1)
                            Spacer()
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(current?.id == r.id ? Theme.cyan.opacity(0.15) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selected = r.id }
                    }
                }
                .frame(width: 300)
                .glassPanel(padding: 12)
                if let r = current {
                    InspectorDetail(record: r).frame(maxWidth: .infinity)
                }
            }
        }
        .workspacePage()
    }
}

enum ConnectionClass: String, CaseIterable, Identifiable {
    case chargingOnly, dataCapable, hostToHost, enumerated, functional
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chargingOnly: return "Charging-only"
        case .dataCapable: return "Data-capable link"
        case .hostToHost: return "Host-to-host"
        case .enumerated: return "Enumerated USB device"
        case .functional: return "Functional communication"
        }
    }
    var explanation: String {
        switch self {
        case .chargingOnly: return "Power flows (USB Power Delivery), but the cable or device provides no data lines. macOS sees nothing, so no app can — there is no event to detect."
        case .dataCapable: return "The cable carries USB data. Only then can the host enumerate the device. Many USB-C cables are USB 2 only (480 Mbit/s)."
        case .hostToHost: return "Two hosts (Mac ↔ PC, Mac ↔ console) cannot talk over a plain USB cable: neither side presents a device. Nothing enumerates."
        case .enumerated: return "macOS read the descriptors: vendor, product, class and interfaces. This proves a working data link — not that the device's functions work."
        case .functional: return "A supported protocol exchanged data (e.g. CoreDevice answered with live device properties). Only this proves communication."
        }
    }
    var symbol: String {
        switch self {
        case .chargingOnly: return "bolt.fill"
        case .dataCapable: return "cable.connector"
        case .hostToHost: return "arrow.left.arrow.right"
        case .enumerated: return "list.bullet.rectangle"
        case .functional: return "checkmark.seal.fill"
        }
    }
}

private struct ConnectionClassesPanel: View {
    let current: DeviceRecord?

    func applies(_ c: ConnectionClass) -> Bool {
        guard let r = current, r.device.isPresent else { return false }
        switch c {
        case .dataCapable, .enumerated: return true
        case .functional: return r.assessment.state(of: .functionalCommunication) == .verified
        default: return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(ConnectionClass.allCases) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: c.symbol).foregroundStyle(applies(c) ? Theme.success : Theme.dim)
                        Text(c.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    Text(c.explanation).font(.caption2).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    if applies(c) { Text("APPLIES TO SELECTION").font(.caption2.weight(.heavy)).foregroundStyle(Theme.success) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(applies(c) ? Theme.success.opacity(0.08) : Theme.navyHigh.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(applies(c) ? Theme.success.opacity(0.5) : Theme.metal.opacity(0.15)))
            }
        }
    }
}

private struct InspectorDetail: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let usb = record.device.usb!
        let profile = model.laboratory.profile(record.stableKey)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "Device descriptor", subtitle: record.device.source, symbol: "doc.text.magnifyingglass")
                Group {
                    KeyValueRow(key: "idVendor / idProduct", value: "\(usb.vendorIDHex) / \(usb.productIDHex)", monospaced: true)
                    KeyValueRow(key: "Strings", value: "\(usb.vendorName ?? "—") · \(usb.productName ?? "—")")
                    KeyValueRow(key: "bDeviceClass", value: "\(Hex.format8(usb.deviceClass ?? 0)) \(usb.usbClass.name)", monospaced: true)
                    KeyValueRow(key: "bcdUSB / bcdDevice", value: "\(usb.usbSpecification ?? "—") / \(usb.firmwareRevision ?? "—")", monospaced: true)
                    KeyValueRow(key: "Configurations", value: usb.configurationCount.map(String.init) ?? "—")
                }
                Group {
                    KeyValueRow(key: "Negotiated speed", value: usb.speed?.displayName ?? "Not reported")
                    KeyValueRow(key: "Declared capability", value: usb.maximumSupportedSpeed.map { "at least \($0.displayName) (from bcdUSB)" } ?? "—")
                    KeyValueRow(key: "Topology", value: usb.locationID.map { "Bus \(USBTopology.busNumber(locationID: $0)) · port path \(USBTopology.portPath(locationID: $0).map(String.init).joined(separator: " → ")) · \(Hex.format32($0))" } ?? "—")
                    KeyValueRow(key: "Role", value: record.identification.role.displayName)
                    KeyValueRow(key: "Serial number", value: model.displaySerial(usb.serialNumber), monospaced: true)
                }
                if let max = usb.maximumSupportedSpeed, let s = usb.speed, s.rawValue < max.rawValue, max.rawValue >= USBSpeed.superSpeed.rawValue {
                    Label("Running below the device's declared USB 3 capability — check the cable, hub or port.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Interfaces, endpoints & drivers", subtitle: "Endpoint counts come from bNumEndpoints when macOS publishes it.", symbol: "square.stack.3d.up")
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow {
                        ForEach(["#", "Class.Sub.Proto", "Function", "Endpoints", "Driver"], id: \.self) { Text($0).font(.caption.weight(.bold)).foregroundStyle(Theme.dim) }
                    }
                    ForEach(usb.interfaces) { i in
                        GridRow {
                            Text("\(i.number)").font(.caption.monospaced()).foregroundStyle(Theme.cyan)
                            Text(DeviceMatchRules.triple(i)).font(.caption.monospaced()).foregroundStyle(Theme.text)
                            Text(i.functionDescription).font(.caption).foregroundStyle(Theme.text)
                            Text(i.endpointCount.map(String.init) ?? "—").font(.caption.monospacedDigit()).foregroundStyle(Theme.text)
                            Text(i.hasDriver ? i.attachedServices.joined(separator: ", ") : "none").font(.caption).foregroundStyle(i.hasDriver ? Theme.success : Theme.dim)
                        }
                    }
                }
                if usb.interfaces.isEmpty { Text("No interfaces published.").font(.caption).foregroundStyle(Theme.dim) }
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Protocols & why", subtitle: "What could speak to this device, and what is limiting it.", symbol: "questionmark.circle")
                ForEach(record.identification.exposedProtocols.compactMap { ProtocolCatalog.descriptor($0) }) { p in
                    HStack(alignment: .top) {
                        SupportBadge(support: p.support).frame(width: 120, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(p.summary).font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
                if let limiting = record.assessment.limitingLayer {
                    Label("Limiting layer: \(limiting.layer.displayName) — \(limiting.reason)", systemImage: "exclamationmark.bubble")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                }
                DetailList(title: "Role & known limitations", items: record.identification.knownLimitations, color: Theme.dim)
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Compatibility evidence", subtitle: "From the Device Laboratory", symbol: "flask")
                if let p = profile, !p.compatibility.isEmpty {
                    ForEach(p.compatibility.reversed()) { c in
                        Text("\(Formatters.dateTime.string(from: c.at)) · \(c.connectionType.displayName) · \(c.outcome)\(c.limitingLayer.map { " · \($0)" } ?? "") — \(c.notes)")
                            .font(.caption).foregroundStyle(Theme.text)
                    }
                } else {
                    Text("None recorded yet. Use “Record compatibility evidence” on the device's Authorization tab.").font(.caption).foregroundStyle(Theme.dim)
                }
                DisclosureGroup("Raw registry properties") {
                    ForEach(record.device.rawProperties.keys.sorted(), id: \.self) { k in
                        KeyValueRow(key: k, value: k.lowercased().contains("serial") ? model.displaySerial(record.device.rawProperties[k]) : (record.device.rawProperties[k] ?? ""), monospaced: true)
                    }
                }
            }
            .glassPanel()
        }
    }
}
#endif
