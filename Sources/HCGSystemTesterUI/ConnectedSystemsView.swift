#if os(macOS)
import SwiftUI
import HCGCore

struct ConnectedSystemsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = ""

    var filtered: [DeviceRecord] {
        guard !filter.isEmpty else { return model.records }
        let q = filter.lowercased()
        return model.records.filter { r in
            [r.device.displayName, r.identification.profileName ?? "", r.device.usb?.vendorIDHex ?? "", r.device.usb?.productIDHex ?? "",
             r.identification.category.displayName].contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                    TextField("Filter by name, VID/PID or category", text: $filter).textFieldStyle(.plain)
                }
                .padding(10)
                .background(Theme.navy.opacity(0.6))
                List(selection: $model.selectedDeviceID) {
                    ForEach(filtered) { record in
                        DeviceListRow(record: record).tag(record.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .overlay {
                    if model.records.isEmpty {
                        EmptyStateView(symbol: "cable.connector.slash", title: "No systems yet",
                                       message: "Connect a USB-C or USB device. Every enumerated device appears here, including ones System Tester cannot identify.")
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
            .background(Theme.obsidian.opacity(0.6))

            Group {
                if let record = model.selectedRecord {
                    DeviceDetailView(record: record)
                } else {
                    EmptyStateView(symbol: "sidebar.left", title: "Select a system",
                                   message: "Choose a device to see its descriptors, interfaces, connectivity layers, adapters and diagnostics.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(WorkspaceBackground())
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DeviceListRow: View {
    let record: DeviceRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.identification.category.symbolName)
                .foregroundStyle(record.device.isPresent ? (record.device.provenance.isSynthetic ? Theme.synthetic : Theme.cyan) : Theme.dim)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.device.displayName).lineLimit(1).foregroundStyle(record.device.isPresent ? Theme.text : Theme.dim)
                Text(record.identification.profileName ?? "Unidentified · \(record.device.usb?.vendorIDHex ?? "—"):\(record.device.usb?.productIDHex ?? "—")")
                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer()
            Circle().fill(Theme.color(for: record.status)).frame(width: 9, height: 9)
                .help(record.status.displayName)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(record.status.displayName)
    }
}

struct DeviceDetailView: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeviceHeader(record: record)
            ConnectivityLayersPanel(record: record)
            HStack(alignment: .top, spacing: 18) {
                IdentityPanel(record: record).frame(maxWidth: .infinity)
                IdentificationPanel(record: record).frame(maxWidth: .infinity)
            }
            if let usb = record.device.usb {
                InterfacesPanel(usb: usb)
            }
            if let tb = record.device.thunderbolt {
                ThunderboltPanel(tb: tb)
            }
            AdaptersPanel(record: record)
            DeviceActionsPanel(record: record)
            RawEvidencePanel(record: record)
        }
        .workspacePage()
    }
}

private struct DeviceHeader: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: record.identification.category.symbolName)
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(record.device.provenance.isSynthetic ? AnyShapeStyle(Theme.synthetic) : AnyShapeStyle(Theme.accentGradient))
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(record.device.displayName).font(.title2.weight(.semibold)).foregroundStyle(Theme.text).textSelection(.enabled)
                    ProvenanceBadge(provenance: record.device.provenance)
                }
                HStack(spacing: 8) {
                    StatusBadge(status: record.status)
                    Text(record.statusReason).font(.callout).foregroundStyle(Theme.dim)
                }
                Text(record.status.meaning).font(.caption).foregroundStyle(Theme.dim.opacity(0.85))
            }
            Spacer()
            if record.device.isPresent {
                Button {
                    model.runDefaultSuite(on: record)
                } label: {
                    Label(model.activeRuns[record.id] == nil ? "Run read-only diagnostics" : "Running…", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cyan.opacity(0.7))
                .disabled(model.activeRuns[record.id] != nil)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        .glassPanel(padding: 18, glow: Theme.color(for: record.status))
    }
}

struct ConnectivityLayersPanel: View {
    let record: DeviceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Connectivity layers", subtitle: "A connected cable does not mean the device communicates. Each layer is verified separately.", symbol: "square.3.layers.3d")
            ForEach(record.assessment.layers) { layer in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: Theme.symbol(for: layer.state)).foregroundStyle(Theme.color(for: layer.state)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(layer.layer.displayName).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(layer.state.displayName.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(Theme.color(for: layer.state))
                        }
                        Text(layer.reason).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        ForEach(layer.evidence, id: \.self) { e in
                            Text("• " + e).font(.caption2.monospaced()).foregroundStyle(Theme.dim.opacity(0.85))
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            if let limiting = record.assessment.limitingLayer {
                Label("Limited at: \(limiting.layer.displayName)", systemImage: "exclamationmark.bubble")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
            }
        }
        .glassPanel()
    }
}

private struct IdentityPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord

    var body: some View {
        let d = record.device
        let usb = d.usb
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Device information", subtitle: d.source, symbol: "info.circle")
            Group {
                KeyValueRow(key: "Name", value: d.displayName)
                KeyValueRow(key: "Manufacturer", value: d.manufacturer ?? "Not reported")
                KeyValueRow(key: "Vendor ID", value: usb?.vendorIDHex ?? "—", monospaced: true)
                KeyValueRow(key: "Product ID", value: usb?.productIDHex ?? "—", monospaced: true)
                KeyValueRow(key: "Device class", value: usb.map { "\(Hex.format8($0.deviceClass ?? 0)) \($0.usbClass.name)" } ?? "—")
            }
            Group {
                KeyValueRow(key: "Link speed", value: usb?.speed?.displayName ?? "Not reported")
                KeyValueRow(key: "USB spec / release", value: "\(usb?.usbSpecification ?? "—") / \(usb?.firmwareRevision ?? "—")")
                KeyValueRow(key: "Serial number", value: model.displaySerial(usb?.serialNumber), monospaced: true)
                KeyValueRow(key: "Topology", value: topology(usb))
            }
            if let usb = usb, !usb.bsdNames.isEmpty {
                KeyValueRow(key: "Storage", value: usb.bsdNames.joined(separator: ", ") + (usb.mediaSizeBytes.map { " · " + Formatters.bytes($0) } ?? ""))
            }
            if let usb = usb, !usb.serialDevicePaths.isEmpty {
                KeyValueRow(key: "Serial ports", value: usb.serialDevicePaths.joined(separator: ", "), monospaced: true)
            }
            KeyValueRow(key: "First seen", value: Formatters.dateTime.string(from: d.firstSeen))
        }
        .glassPanel()
    }

    func topology(_ usb: USBDeviceDescriptor?) -> String {
        guard let usb = usb, let loc = usb.locationID else { return "—" }
        let path = usb.portPath.map(String.init).joined(separator: " → ")
        return "Bus \(String(usb.busNumber ?? 0, radix: 16)) · port \(path.isEmpty ? "root" : path) · \(Hex.format32(loc))"
    }
}

private struct IdentificationPanel: View {
    let record: DeviceRecord

    var body: some View {
        let id = record.identification
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Identification", subtitle: "Confidence: \(id.confidence.displayName)", symbol: "person.text.rectangle")
            KeyValueRow(key: "Category", value: id.category.displayName)
            KeyValueRow(key: "Profile", value: id.profileName.map { "\($0) (\(id.profileID ?? ""))" } ?? "No profile matched")
            KeyValueRow(key: "Family", value: id.family)
            KeyValueRow(key: "Role", value: id.role.displayName)
            KeyValueRow(key: "Protocols", value: id.exposedProtocols.isEmpty ? "None evidenced" : id.exposedProtocols.joined(separator: ", "))
            if !id.evidence.isEmpty {
                Text("Evidence").font(.caption.weight(.bold)).foregroundStyle(Theme.dim).padding(.top, 4)
                ForEach(id.evidence, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.text) }
            }
            if !id.knownLimitations.isEmpty {
                Text("Known limitations").font(.caption.weight(.bold)).foregroundStyle(Theme.warning).padding(.top, 4)
                ForEach(id.knownLimitations, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true) }
            }
            if !id.alternatives.isEmpty {
                Text("Also matched: " + id.alternatives.joined(separator: "; ")).font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .glassPanel()
    }
}

private struct InterfacesPanel: View {
    let usb: USBDeviceDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "USB interfaces", subtitle: "\(usb.interfaces.count) interface(s) · drivers attached by macOS", symbol: "square.stack.3d.up")
            if usb.interfaces.isEmpty {
                Text("No interfaces were published (yet). Drivers may still be attaching; the view refreshes automatically.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(usb.interfaces) { i in
                HStack(alignment: .top) {
                    Text("#\(i.number)").font(.callout.monospaced()).foregroundStyle(Theme.cyan).frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.functionDescription).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                        Text("Class \(DeviceMatchRules.triple(i))" + (i.name.map { " · \($0)" } ?? "")).font(.caption.monospaced()).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if i.hasDriver {
                        Label(i.attachedServices.joined(separator: ", "), systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.success)
                    } else {
                        Label("No driver", systemImage: "circle.dashed").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Divider().opacity(0.15)
            }
        }
        .glassPanel()
    }
}

private struct ThunderboltPanel: View {
    let tb: ThunderboltDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Thunderbolt / USB4 switch", subtitle: tb.ioClassName, symbol: "bolt.horizontal")
            KeyValueRow(key: "Vendor", value: tb.vendorName ?? "—")
            KeyValueRow(key: "Model", value: tb.modelName ?? "—")
            KeyValueRow(key: "Depth", value: tb.depth.map(String.init) ?? "—")
            KeyValueRow(key: "Route string", value: tb.routeString.map { "0x" + String($0, radix: 16) } ?? "—", monospaced: true)
        }
        .glassPanel()
    }
}

private struct AdaptersPanel: View {
    let record: DeviceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Adapters", subtitle: "Interchangeable modules that can work with this device", symbol: "puzzlepiece.extension")
            if record.compatibility.isEmpty {
                Text(record.device.isPresent ? "No adapter applies to this device. It is recorded as compatibility evidence." : "Device disconnected.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(record.compatibility) { c in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(c.adapterName).font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(c.status.rawValue.uppercased()).font(.caption2.weight(.heavy))
                            .foregroundStyle(c.status == .compatible ? Theme.success : (c.status == .partial ? Theme.cyan : Theme.warning))
                        Spacer()
                        Text("\(c.availableOperations.count) operation(s)").font(.caption).foregroundStyle(Theme.dim)
                    }
                    ForEach(c.reasons, id: \.self) { Text("• " + $0).font(.caption2).foregroundStyle(Theme.dim) }
                    if !c.unavailableOperations.isEmpty {
                        Text("Unavailable: " + c.unavailableOperations.joined(separator: "; ")).font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))
                    }
                }
                Divider().opacity(0.15)
            }
        }
        .glassPanel()
    }
}

private struct DeviceActionsPanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Actions", subtitle: "Discovery is read-only. Nothing here modifies the device.", symbol: "hand.tap")
            HStack(spacing: 10) {
                Toggle("Authorise this device for sessions", isOn: Binding(
                    get: { model.isAuthorized(record) },
                    set: { model.setAuthorized(record, $0) }))
                    .help("Authorisation is recorded per physical unit and is required before any privileged adapter operation. It does not change the device.")
                Spacer()
                Button("Open in Diagnostics") {
                    model.selectedDeviceID = record.id
                    model.section = .diagnostics
                }
                Button("Record compatibility evidence") {
                    model.laboratory.recordCompatibility(record, notes: notes)
                    model.banner = "Compatibility evidence recorded for \(record.device.displayName)."
                }
            }
            TextField("Notes for compatibility evidence (optional)", text: $notes)
            if record.device.provenance.isSynthetic {
                HStack {
                    Text("Synthetic fixture controls:").font(.caption).foregroundStyle(Theme.synthetic)
                    Button("Simulate unplug") { model.simulateSynthetic(detach: record.id) }
                        .disabled(!record.device.isPresent)
                    Button("Simulate re-plug") { model.simulateSynthetic(attach: record.id) }
                        .disabled(record.device.isPresent)
                }
            }
        }
        .glassPanel()
    }
}

private struct RawEvidencePanel: View {
    @EnvironmentObject var model: AppModel
    let record: DeviceRecord
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(record.device.rawProperties.keys.sorted(), id: \.self) { key in
                    KeyValueRow(key: key, value: display(key), monospaced: true)
                }
                Divider().opacity(0.2)
                Text("Status history").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                ForEach(Array(record.state.history.enumerated()), id: \.offset) { _, change in
                    Text("\(Formatters.time.string(from: change.at))  \(change.from?.displayName ?? "—") → \(change.to.displayName): \(change.reason)")
                        .font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Raw registry evidence & status history", systemImage: "doc.text.magnifyingglass").foregroundStyle(Theme.text)
        }
        .glassPanel()
    }

    func display(_ key: String) -> String {
        let value = record.device.rawProperties[key] ?? ""
        if key.lowercased().contains("serial") { return model.displaySerial(value) }
        return value
    }
}
#endif
