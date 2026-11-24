#if canImport(IOKit)
import Foundation
import IOKit
import HCGCore

/// Read-only Thunderbolt / USB4 switch discovery (`IOThunderboltSwitch`, depth > 0).
public final class IOKitThunderboltDiscovery: DeviceDiscoveryBackend {
    public let backendID = "iokit.thunderbolt"
    public let displayName = "IOKit Thunderbolt / USB4"
    public let provenance = DataProvenance.hardware
    public let connectionTypes: [ConnectionType] = [.thunderbolt]

    private let monitor: IOKitRegistryMonitor
    private let lock = NSLock()
    private var state: DiscoveryBackendStatus.State = .stopped
    private var detail = "Not started."

    public init() {
        monitor = IOKitRegistryMonitor(className: "IOThunderboltSwitch", queueLabel: "com.hakmicapitalgroup.systemtester.iokit.thunderbolt",
                                       makeID: DeviceIdentifier.thunderboltRegistry, build: IOKitThunderboltDiscovery.makeDevice)
        monitor.settleDelays = [1.5]
    }

    public var status: DiscoveryBackendStatus {
        lock.lock(); defer { lock.unlock() }
        return DiscoveryBackendStatus(backendID: backendID, displayName: displayName, state: state, detail: detail,
                                      provenance: .hardware, connectionTypes: connectionTypes)
    }

    private func set(_ s: DiscoveryBackendStatus.State, _ d: String) {
        lock.lock(); state = s; detail = d; lock.unlock()
    }

    public func start(handler: @escaping (DiscoveryEvent) -> Void) {
        if let error = monitor.start(handler: handler) {
            set(.failed, error)
        } else {
            set(.running, "Live: IOThunderboltSwitch notifications armed (the Mac's own switches are excluded).")
        }
        handler(.backendStatus(status))
    }

    public func stop() {
        monitor.stop()
        set(.stopped, "Stopped by the user.")
    }

    public func snapshot() -> [DiscoveredDevice] { monitor.snapshot() }

    public func refresh(_ id: DeviceIdentifier) -> DiscoveredDevice? {
        guard id.rawValue.hasPrefix("tb:"), let entryID = UInt64(id.rawValue.dropFirst(3), radix: 16) else { return nil }
        return monitor.read(entryID)
    }

    static func makeDevice(_ service: io_registry_entry_t, _ entryID: UInt64) -> DiscoveredDevice? {
        let props = Registry.properties(service)
        let depth = USBRegistryParser.int(props["Depth"])
        // Depth 0 is the Mac's own host switch: not an attached device.
        guard let d = depth, d > 0 else { return nil }
        let tb = ThunderboltDescriptor(
            vendorName: USBRegistryParser.firstString(props, ["Device Vendor Name"]),
            modelName: USBRegistryParser.firstString(props, ["Device Model Name"]),
            vendorID: USBRegistryParser.uint32(props["Device Vendor ID"] ?? props["Vendor ID"]),
            deviceID: USBRegistryParser.uint32(props["Device Model ID"] ?? props["Device ID"]),
            routeString: (props["Route String"] as? NSNumber)?.uint64Value,
            depth: d, registryEntryID: entryID, ioClassName: Registry.className(service))
        let name = [tb.vendorName, tb.modelName].compactMap { $0 }.joined(separator: " ")
        var evidence: [String: String] = [:]
        for key in ["Device Vendor Name", "Device Model Name", "Depth", "Route String", "Device Vendor ID", "Device Model ID", "Max Port Number"] {
            if let v = props[key] { evidence[key] = USBRegistryParser.stringify(v) }
        }
        return DiscoveredDevice(id: .thunderboltRegistry(entryID), provenance: .hardware, connectionType: .thunderbolt,
                                name: name.isEmpty ? "Thunderbolt device" : name, manufacturer: tb.vendorName,
                                thunderbolt: tb, source: "IOKit · \(tb.ioClassName ?? "IOThunderboltSwitch")",
                                rawProperties: evidence)
    }
}
#endif
