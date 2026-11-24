import Foundation

public enum DiscoveryEvent {
    /// A device appeared (or was present when the backend started).
    case attached(DiscoveredDevice)
    /// A device left the bus.
    case detached(DeviceIdentifier, at: Date)
    /// The backend's own health changed.
    case backendStatus(DiscoveryBackendStatus)
}

public struct DiscoveryBackendStatus: Codable, Hashable, Identifiable {
    public enum State: String, Codable, Hashable { case starting, running, stopped, unavailable, failed }
    public var backendID: String
    public var displayName: String
    public var state: State
    public var detail: String
    public var provenance: DataProvenance
    public var connectionTypes: [ConnectionType]

    public var id: String { backendID }

    public init(backendID: String, displayName: String, state: State, detail: String, provenance: DataProvenance, connectionTypes: [ConnectionType]) {
        self.backendID = backendID
        self.displayName = displayName
        self.state = state
        self.detail = detail
        self.provenance = provenance
        self.connectionTypes = connectionTypes
    }
}

/// A source of discovery events (IOKit, synthetic fixtures, future network/Bluetooth backends).
public protocol DeviceDiscoveryBackend: DeviceProbe {
    var backendID: String { get }
    var displayName: String { get }
    var provenance: DataProvenance { get }
    var connectionTypes: [ConnectionType] { get }
    var status: DiscoveryBackendStatus { get }

    /// Starts discovery. Existing devices are delivered as `.attached` events, followed by live changes.
    /// Events are delivered on the queue chosen by the backend; consumers must hop to their own queue.
    func start(handler: @escaping (DiscoveryEvent) -> Void)
    func stop()
    /// One-shot snapshot of currently present devices.
    func snapshot() -> [DiscoveredDevice]
}
