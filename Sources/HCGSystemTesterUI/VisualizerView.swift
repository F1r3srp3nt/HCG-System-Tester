#if os(macOS)
import SwiftUI
import HCGCore

/// Tidy-tree layout of the topology graph (host on the left, devices to the right).
enum TopologyLayout {
    static func positions(for graph: TopologyGraph, in size: CGSize) -> [String: CGPoint] {
        var children: [String: [String]] = [:]
        for e in graph.edges { children[e.from, default: []].append(e.to) }
        var level: [String: Int] = [:]
        var row: [String: Double] = [:]
        var nextLeaf = 0.0
        var visited: Set<String> = []

        func visit(_ id: String, depth: Int) -> Double {
            visited.insert(id)
            level[id] = depth
            let kids = (children[id] ?? []).filter { !visited.contains($0) }
            if kids.isEmpty {
                let y = nextLeaf
                nextLeaf += 1
                row[id] = y
                return y
            }
            let ys = kids.map { visit($0, depth: depth + 1) }
            let y = (ys.min()! + ys.max()!) / 2
            row[id] = y
            return y
        }
        _ = visit(TopologyBuilder.hostID, depth: 0)
        // Nodes not reachable from the host (should not happen) are placed in a trailing column.
        for n in graph.nodes where !visited.contains(n.id) {
            level[n.id] = 1
            row[n.id] = nextLeaf
            nextLeaf += 1
        }
        let maxLevel = max(1, level.values.max() ?? 1)
        let rows = max(1, nextLeaf)
        let marginX: CGFloat = 90, marginY: CGFloat = 60
        let usableW = max(200, size.width - marginX * 2 - 120)
        let usableH = max(100, size.height - marginY * 2)
        var out: [String: CGPoint] = [:]
        for n in graph.nodes {
            let lx = CGFloat(level[n.id] ?? 0) / CGFloat(maxLevel)
            let ry = rows <= 1 ? 0.5 : CGFloat(row[n.id] ?? 0) / CGFloat(rows - 1)
            out[n.id] = CGPoint(x: marginX + lx * usableW, y: marginY + ry * usableH)
        }
        return out
    }
}

struct VisualizerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var includeDisconnected = false
    @State private var selectedNode: String?

    var graph: TopologyGraph {
        TopologyBuilder.build(records: model.records, hostName: model.host.name, includeDisconnected: includeDisconnected)
    }

    var reduceMotion: Bool { systemReduceMotion || model.settings.reduceMotion }

    var body: some View {
        let g = graph
        return HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionHeader(title: "Connection Visualizer", subtitle: "Drawn only from live discovery data — nothing is fabricated.", symbol: "point.3.connected.trianglepath.dotted")
                    Toggle("Show disconnected", isOn: $includeDisconnected).toggleStyle(.switch).controlSize(.small)
                }
                .padding([.horizontal, .top], 20)
                GeometryReader { geo in
                    let positions = TopologyLayout.positions(for: g, in: geo.size)
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                        Canvas { context, size in
                            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                            draw(graph: g, positions: positions, time: t, in: &context)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        selectedNode = positions.min { a, b in a.value.distance(to: point) < b.value.distance(to: point) }
                            .flatMap { $0.value.distance(to: point) < 40 ? $0.key : nil }
                        if let id = selectedNode, let node = g.node(id), let deviceID = node.deviceID {
                            model.selectedDeviceID = deviceID
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary(g))
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkspaceBackground())

            VisualizerSidePanel(graph: g, selectedNode: selectedNode)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        }
    }

    func accessibilitySummary(_ g: TopologyGraph) -> String {
        let devices = g.nodes.filter { $0.deviceID != nil }
        return "Topology with \(devices.count) device(s): " + devices.map { "\($0.label), \($0.status?.displayName ?? "")" }.joined(separator: "; ")
    }

    func draw(graph g: TopologyGraph, positions: [String: CGPoint], time: Double, in context: inout GraphicsContext) {
        // Edges
        for e in g.edges {
            guard let a = positions[e.from], let b = positions[e.to] else { continue }
            var path = Path()
            path.move(to: a)
            let mid = (a.x + b.x) / 2
            path.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            let synthetic = e.connectionType == .synthetic
            let base: Color = synthetic ? Theme.synthetic : (e.connectionType == .thunderbolt ? Theme.violet : Theme.cyan)
            context.stroke(path, with: .color(base.opacity(e.active ? 0.28 : 0.1)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if e.active {
                let phase = CGFloat(time * 28).truncatingRemainder(dividingBy: 24)
                context.stroke(path, with: .linearGradient(Gradient(colors: [base, Theme.violet]), startPoint: a, endPoint: b),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [8, 16], dashPhase: -phase))
            } else {
                context.stroke(path, with: .color(Theme.dim.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
            let label = Text(e.label).font(.system(size: 9, weight: .medium)).foregroundColor(Theme.dim)
            context.draw(label, at: CGPoint(x: mid, y: (a.y + b.y) / 2 - 8))
        }
        // Nodes
        for n in g.nodes {
            guard let p = positions[n.id] else { continue }
            let radius: CGFloat = n.kind == .host ? 30 : (n.kind == .bus || n.kind == .syntheticBus || n.kind == .networkGroup ? 16 : 22)
            let color = nodeColor(n)
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            if let id = n.deviceID, model.activeRuns[id] != nil {
                let pulse = 1 + 0.25 * CGFloat(sin(time * 4))
                let r2 = radius * 1.35 * pulse
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r2, y: p.y - r2, width: r2 * 2, height: r2 * 2)),
                               with: .color(Theme.cyan.opacity(0.7)), lineWidth: 2)
            }
            context.fill(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(color.opacity(0.10)))
            context.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [Theme.navyHigh, Theme.obsidian]),
                                                                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: selectedNode == n.id ? 2.5 : 1.2)
            var symbol = context.resolve(Image(systemName: symbolName(n)))
            symbol.shading = .color(color)
            context.draw(symbol, in: CGRect(x: p.x - radius * 0.5, y: p.y - radius * 0.5, width: radius, height: radius))
            let title = Text(n.label).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text)
            context.draw(title, at: CGPoint(x: p.x, y: p.y + radius + 11))
            let sub = Text(n.status?.displayName ?? n.subtitle).font(.system(size: 9)).foregroundColor(n.status.map { Theme.color(for: $0) } ?? Theme.dim)
            context.draw(sub, at: CGPoint(x: p.x, y: p.y + radius + 24))
        }
    }

    func nodeColor(_ n: TopologyNode) -> Color {
        if n.provenance == .synthetic { return Theme.synthetic }
        if let s = n.status { return Theme.color(for: s) }
        switch n.kind {
        case .host: return Theme.cyan
        case .thunderbolt: return Theme.violet
        default: return Theme.metal
        }
    }

    func symbolName(_ n: TopologyNode) -> String {
        switch n.kind {
        case .host: return "laptopcomputer"
        case .bus: return n.connectionType == .thunderbolt ? "bolt.horizontal" : "cable.connector"
        case .syntheticBus: return "flask"
        case .networkGroup: return "network"
        case .hub: return "point.3.filled.connected.trianglepath.dotted"
        case .thunderbolt: return "bolt.horizontal.fill"
        case .device: return n.category?.symbolName ?? "questionmark.square.dashed"
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

private struct VisualizerSidePanel: View {
    @EnvironmentObject var model: AppModel
    let graph: TopologyGraph
    let selectedNode: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = selectedNode, let node = graph.node(id) {
                    NodeDetail(node: node)
                } else {
                    Text("Click a node for details.").font(.callout).foregroundStyle(Theme.dim)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEGEND").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                    ForEach(DeviceStatus.allCases) { s in
                        HStack { Circle().fill(Theme.color(for: s)).frame(width: 8, height: 8); Text(s.displayName).font(.caption) }
                    }
                    HStack { Circle().fill(Theme.synthetic).frame(width: 8, height: 8); Text("Synthetic fixture (not hardware)").font(.caption) }
                    Text("Animated paths: live links. Pulsing ring: diagnostics running. Hubs that macOS does not report are never invented; their devices attach to the bus.")
                        .font(.caption2).foregroundStyle(Theme.dim).padding(.top, 4)
                }
                .glassPanel(padding: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOT YET VISUALISED").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
                    ForEach(ConnectionCapabilityRegistry.macOS.filter { $0.support == .planned || $0.support == .requiresAdapter }) { c in
                        HStack { Image(systemName: c.connectionType.symbolName); Text(c.connectionType.displayName).font(.caption); Spacer(); SupportBadge(support: c.support) }
                    }
                }
                .glassPanel(padding: 12)
            }
            .padding(16)
        }
        .background(Theme.obsidian.opacity(0.7))
    }
}

private struct NodeDetail: View {
    @EnvironmentObject var model: AppModel
    let node: TopologyNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(node.label).font(.headline).foregroundStyle(Theme.text)
                ProvenanceBadge(provenance: node.provenance)
            }
            Text(node.subtitle).font(.caption).foregroundStyle(Theme.dim)
            if let s = node.status { StatusBadge(status: s) }
            if let id = node.deviceID, let r = model.record(id) {
                Text("Adapters").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                ForEach(r.compatibility) { c in
                    Text("• \(c.adapterName) (\(c.status.rawValue))").font(.caption)
                }
                HStack {
                    Button("Details") { model.selectedDeviceID = id; model.section = .connectedSystems }
                    if r.device.isPresent {
                        Button("Diagnose") { model.runDefaultSuite(on: r) }
                            .disabled(model.activeRuns[id] != nil)
                    }
                }
            } else if node.kind == .host {
                KeyValueRow(key: "Model", value: model.host.modelIdentifier)
                KeyValueRow(key: "Chip", value: model.host.chip)
            }
        }
        .glassPanel(padding: 12)
    }
}
#endif
