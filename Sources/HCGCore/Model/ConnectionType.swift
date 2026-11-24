import Foundation

/// Physical or logical connection families handled by the Universal Connection Engine.
public enum ConnectionType: String, Codable, CaseIterable, Hashable, Identifiable {
    case usb
    case usbSerial
    case hid
    case thunderbolt
    case ethernet
    case bluetooth
    case localNetwork
    case remoteAuthenticated
    case manufacturerAPI
    case synthetic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .usb: return "USB / USB-C"
        case .usbSerial: return "USB Serial"
        case .hid: return "HID"
        case .thunderbolt: return "Thunderbolt"
        case .ethernet: return "Ethernet"
        case .bluetooth: return "Bluetooth"
        case .localNetwork: return "Local Network"
        case .remoteAuthenticated: return "Authenticated Remote"
        case .manufacturerAPI: return "Manufacturer API"
        case .synthetic: return "Synthetic Fixture"
        }
    }

    /// SF Symbol used by the interface.
    public var symbolName: String {
        switch self {
        case .usb: return "cable.connector"
        case .usbSerial: return "point.3.connected.trianglepath.dotted"
        case .hid: return "keyboard"
        case .thunderbolt: return "bolt.horizontal"
        case .ethernet: return "network"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .localNetwork: return "wifi"
        case .remoteAuthenticated: return "lock.shield"
        case .manufacturerAPI: return "server.rack"
        case .synthetic: return "flask"
        }
    }
}

/// The five layers that must each be satisfied before a device can be said to
/// communicate. A connected cable only proves the first layer at best.
public enum ConnectivityLayer: String, Codable, CaseIterable, Hashable, Identifiable {
    case physical
    case enumeration
    case protocolCompatibility
    case authorization
    case functionalCommunication

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .physical: return "Physical connectivity"
        case .enumeration: return "Device enumeration"
        case .protocolCompatibility: return "Protocol compatibility"
        case .authorization: return "Authorization"
        case .functionalCommunication: return "Functional communication"
        }
    }

    public var explanation: String {
        switch self {
        case .physical: return "An electrical link exists between the host and the device."
        case .enumeration: return "The operating system enumerated the device and read its descriptors."
        case .protocolCompatibility: return "A protocol both sides support has been identified and a driver or adapter can speak it."
        case .authorization: return "The user (and, where required, the device) has authorised the session."
        case .functionalCommunication: return "Data was actually exchanged with the device through a supported protocol."
        }
    }
}

public enum LayerState: String, Codable, CaseIterable, Hashable {
    case verified
    case partial
    case notVerified
    case unavailable
    case notApplicable

    public var displayName: String {
        switch self {
        case .verified: return "Verified"
        case .partial: return "Partial"
        case .notVerified: return "Not verified"
        case .unavailable: return "Unavailable"
        case .notApplicable: return "Not applicable"
        }
    }
}

public struct LayerAssessment: Codable, Hashable, Identifiable {
    public var layer: ConnectivityLayer
    public var state: LayerState
    public var reason: String
    public var evidence: [String]

    public var id: ConnectivityLayer { layer }

    public init(layer: ConnectivityLayer, state: LayerState, reason: String, evidence: [String] = []) {
        self.layer = layer
        self.state = state
        self.reason = reason
        self.evidence = evidence
    }
}

/// Layered connectivity report for a single device.
public struct ConnectivityAssessment: Codable, Hashable {
    public var layers: [LayerAssessment]

    public init(layers: [LayerAssessment]) {
        // Always keep the canonical layer order.
        self.layers = ConnectivityLayer.allCases.map { layer in
            layers.first(where: { $0.layer == layer })
                ?? LayerAssessment(layer: layer, state: .notVerified, reason: "No evidence collected yet.")
        }
    }

    public func state(of layer: ConnectivityLayer) -> LayerState {
        layers.first(where: { $0.layer == layer })?.state ?? .notVerified
    }

    public func assessment(of layer: ConnectivityLayer) -> LayerAssessment? {
        layers.first(where: { $0.layer == layer })
    }

    /// The first layer that is not verified (or not applicable) — the reason communication is limited.
    public var limitingLayer: LayerAssessment? {
        layers.first(where: { $0.state != .verified && $0.state != .notApplicable })
    }
}
