import Foundation

public struct TopologyNode: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable { case host, bus, hub, device, thunderbolt, syntheticBus, networkGroup }
    public var id: String
    public var kind: Kind
    public var label: String
    public var subtitle: String
    public var deviceID: DeviceIdentifier?
    public var status: DeviceStatus?
    public var category: DeviceCategory?
    public var connectionType: ConnectionType?
    public var provenance: DataProvenance
    public var depth: Int
}

public struct TopologyEdge: Codable, Hashable, Identifiable {
    public var from: String
    public var to: String
    public var connectionType: ConnectionType
    public var label: String
    public var active: Bool
    public var id: String { from + "→" + to }
}

public struct TopologyGraph: Codable, Hashable {
    public var nodes: [TopologyNode]
    public var edges: [TopologyEdge]

    public func node(_ id: String) -> TopologyNode? { nodes.first { $0.id == id } }
    public func children(of id: String) -> [TopologyNode] {
        edges.filter { $0.from == id }.compactMap { e in node(e.to) }
    }
}

/// Builds the connection graph strictly from discovery data. Nothing is drawn that was not observed;
/// intermediate hubs that macOS did not report are not invented — their children attach to the bus.
public enum TopologyBuilder {
    public static let hostID = "host"

    public static func build(records: [DeviceRecord], hostName: String, includeDisconnected: Bool = false) -> TopologyGraph {
        var nodes: [TopologyNode] = [TopologyNode(id: hostID, kind: .host, label: hostName, subtitle: "Host · \(HCGSystemTesterInfo.productName)",
                                                  deviceID: nil, status: nil, category: .computer, connectionType: nil, provenance: .hardware, depth: 0)]
        var edges: [TopologyEdge] = []
        let visible = records.filter { includeDisconnected || $0.device.isPresent }

        // Index USB devices by locationID per provenance.
        var byLocation: [String: DeviceRecord] = [:]
        func locKey(_ p: DataProvenance, _ loc: UInt32) -> String { "\(p.rawValue):\(loc)" }
        for r in visible { if let loc = r.device.usb?.locationID { byLocation[locKey(r.device.provenance, loc)] = r } }

        var busNodes: Set<String> = []
        func ensureBus(_ id: String, label: String, subtitle: String, kind: TopologyNode.Kind, provenance: DataProvenance, type: ConnectionType) {
            guard !busNodes.contains(id) else { return }
            busNodes.insert(id)
            nodes.append(TopologyNode(id: id, kind: kind, label: label, subtitle: subtitle, deviceID: nil, status: nil, category: nil,
                                      connectionType: type, provenance: provenance, depth: 1))
            edges.append(TopologyEdge(from: hostID, to: id, connectionType: type, label: subtitle, active: true))
        }

        for r in visible.sorted(by: { ($0.device.usb?.locationID ?? 0, $0.id.rawValue) < ($1.device.usb?.locationID ?? 0, $1.id.rawValue) }) {
            let d = r.device
            let nodeID = "dev:" + d.id.rawValue
            var parentID: String
            var depth = 2

            if d.provenance.isSynthetic {
                ensureBus("bus:synthetic", label: "SYNTHETIC fixture bus", subtitle: "Simulated — not hardware", kind: .syntheticBus, provenance: .synthetic, type: .synthetic)
                parentID = "bus:synthetic"
            } else if d.connectionType == .thunderbolt {
                ensureBus("bus:thunderbolt", label: "Thunderbolt / USB4", subtitle: "IOThunderboltSwitch", kind: .bus, provenance: .hardware, type: .thunderbolt)
                parentID = "bus:thunderbolt"
            } else if d.connectionType == .usb || d.usb != nil {
                let bus = d.usb?.busNumber ?? 0
                let busID = "bus:usb:\(bus)"
                ensureBus(busID, label: "USB bus \(bus)", subtitle: "Root hub", kind: .bus, provenance: .hardware, type: .usb)
                parentID = busID
            } else {
                ensureBus("bus:\(d.connectionType.rawValue)", label: d.connectionType.displayName, subtitle: "Discovery group",
                          kind: .networkGroup, provenance: d.provenance, type: d.connectionType)
                parentID = "bus:\(d.connectionType.rawValue)"
            }

            // Walk up the port path to the nearest observed hub.
            if let loc = d.usb?.locationID {
                var cursor = USBTopology.parentLocationID(of: loc)
                while let parentLoc = cursor {
                    if let hub = byLocation[locKey(d.provenance, parentLoc)], hub.id != r.id {
                        parentID = "dev:" + hub.id.rawValue
                        break
                    }
                    cursor = USBTopology.parentLocationID(of: parentLoc)
                }
                depth = 1 + USBTopology.depth(locationID: loc)
            }

            let kind: TopologyNode.Kind = d.usb?.isHub == true ? .hub : (d.connectionType == .thunderbolt ? .thunderbolt : .device)
            nodes.append(TopologyNode(id: nodeID, kind: kind, label: d.displayName,
                                      subtitle: r.identification.profileName ?? r.identification.category.displayName,
                                      deviceID: d.id, status: r.status, category: r.identification.category,
                                      connectionType: d.connectionType, provenance: d.provenance, depth: depth))
            let speed = d.usb?.speed?.shortName ?? d.connectionType.displayName
            edges.append(TopologyEdge(from: parentID, to: nodeID, connectionType: d.connectionType, label: speed, active: d.isPresent))
        }
        return TopologyGraph(nodes: nodes, edges: edges)
    }
}
