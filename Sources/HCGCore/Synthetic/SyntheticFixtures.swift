import Foundation

/// Clearly labelled synthetic devices for exercising the engine without hardware.
/// Every fixture has provenance `.synthetic`, an identifier prefixed `synthetic:` and a
/// name prefixed `[SYNTHETIC]`. They are never mixed into hardware discovery.
public enum SyntheticFixtures {
    static let source = "Synthetic fixture backend"

    public static func device(_ key: String, name: String, manufacturer: String, usb: USBDeviceDescriptor) -> DiscoveredDevice {
        DiscoveredDevice(id: .synthetic(key), provenance: .synthetic, connectionType: .synthetic,
                         name: "[SYNTHETIC] " + name, manufacturer: manufacturer, usb: usb, source: source,
                         rawProperties: ["fixture": key])
    }

    public static let flashDrive = device("flash-drive", name: "Flash Drive 64 GB", manufacturer: "Synthetic Storage Co.",
        usb: USBDeviceDescriptor(vendorID: 0xF00D, productID: 0x0001, vendorName: "Synthetic Storage Co.", productName: "Flash Drive 64 GB",
                                 serialNumber: "SYN-0000-0001", deviceClass: 0, bcdDevice: 0x0110, bcdUSB: 0x0320, speed: .high,
                                 locationID: 0xFE100000, interfaces: [
                                    USBInterfaceInfo(number: 0, classCode: 0x08, subclassCode: 0x06, protocolCode: 0x50, attachedServices: ["SyntheticMassStorageDriver"])
                                 ], bsdNames: ["disk-synthetic"], mediaSizeBytes: 64_000_000_000))

    public static let serialBoard = device("serial-board", name: "Microcontroller Dev Board", manufacturer: "Synthetic Embedded",
        usb: USBDeviceDescriptor(vendorID: 0xF00D, productID: 0x0002, vendorName: "Synthetic Embedded", productName: "Microcontroller Dev Board",
                                 serialNumber: "SYN-0000-0002", deviceClass: 0xEF, bcdDevice: 0x0100, bcdUSB: 0x0200, speed: .full,
                                 locationID: 0xFE200000, interfaces: [
                                    USBInterfaceInfo(number: 0, classCode: 0x02, subclassCode: 0x02, protocolCode: 0x01, attachedServices: ["SyntheticACMDriver"]),
                                    USBInterfaceInfo(number: 1, classCode: 0x0A, subclassCode: 0x00, protocolCode: 0x00, attachedServices: ["SyntheticACMDriver"])
                                 ], serialDevicePaths: ["/dev/cu.synthetic-0002"]))

    public static let hub = device("hub", name: "4-Port USB Hub", manufacturer: "Synthetic Hubs",
        usb: USBDeviceDescriptor(vendorID: 0xF00D, productID: 0x0003, vendorName: "Synthetic Hubs", productName: "4-Port USB Hub",
                                 deviceClass: 0x09, bcdDevice: 0x0001, bcdUSB: 0x0210, speed: .high, locationID: 0xFE300000,
                                 interfaces: [USBInterfaceInfo(number: 0, classCode: 0x09, attachedServices: ["SyntheticHubDriver"])]))

    public static let controllerBehindHub = device("controller", name: "Game Controller", manufacturer: "Synthetic Gaming",
        usb: USBDeviceDescriptor(vendorID: 0xF00D, productID: 0x0004, vendorName: "Synthetic Gaming", productName: "Game Controller",
                                 serialNumber: "SYN-0000-0004", deviceClass: 0, bcdDevice: 0x0100, bcdUSB: 0x0200, speed: .full,
                                 locationID: 0xFE320000, interfaces: [
                                    USBInterfaceInfo(number: 0, classCode: 0x03, attachedServices: ["SyntheticHIDDriver"])
                                 ]))

    public static let degradedSSD = device("degraded-ssd", name: "USB 3 SSD on a USB 2 cable", manufacturer: "Synthetic Storage Co.",
        usb: USBDeviceDescriptor(vendorID: 0xF00D, productID: 0x0005, vendorName: "Synthetic Storage Co.", productName: "USB 3 SSD on a USB 2 cable",
                                 serialNumber: "SYN-0000-0005", bcdDevice: 0x0200, bcdUSB: 0x0310, speed: .high, locationID: 0xFE340000,
                                 interfaces: [USBInterfaceInfo(number: 0, classCode: 0x08, subclassCode: 0x06, protocolCode: 0x62, attachedServices: [])]))

    public static let unknownDevice = device("unknown", name: "Unknown Vendor Device", manufacturer: "Unknown",
        usb: USBDeviceDescriptor(vendorID: 0xF00E, productID: 0xBEEF, bcdUSB: 0x0200, speed: .full, locationID: 0xFE400000,
                                 interfaces: [USBInterfaceInfo(number: 0, classCode: 0xFF, subclassCode: 0x12, protocolCode: 0x34)]))

    public static let all: [DiscoveredDevice] = [flashDrive, serialBoard, hub, controllerBehindHub, degradedSSD, unknownDevice, AppleSyntheticFixtures.iPhone]
}

/// Discovery backend that serves synthetic fixtures. Opt-in, and every event it emits is labelled synthetic.
public final class SyntheticDiscoveryBackend: DeviceDiscoveryBackend, SyntheticFaultInjectable {
    public let backendID = "synthetic"
    public let displayName = "Synthetic fixtures"
    public let provenance = DataProvenance.synthetic
    public let connectionTypes: [ConnectionType] = [.synthetic]

    private let lock = NSLock()
    private var devices: [DeviceIdentifier: DiscoveredDevice]
    private var suppressed: Set<DeviceIdentifier> = []
    private var handler: ((DiscoveryEvent) -> Void)?
    private var running = false

    public init(fixtures: [DiscoveredDevice] = SyntheticFixtures.all) {
        var map: [DeviceIdentifier: DiscoveredDevice] = [:]
        for f in fixtures { map[f.id] = f }
        devices = map
    }

    public var status: DiscoveryBackendStatus {
        DiscoveryBackendStatus(backendID: backendID, displayName: displayName, state: running ? .running : .stopped,
                               detail: "Serves \(devices.count) labelled synthetic fixtures. Not real hardware.",
                               provenance: .synthetic, connectionTypes: connectionTypes)
    }

    public func start(handler: @escaping (DiscoveryEvent) -> Void) {
        lock.lock()
        self.handler = handler
        running = true
        let current = devices.values.filter { !suppressed.contains($0.id) }.sorted { $0.id < $1.id }
        lock.unlock()
        handler(.backendStatus(status))
        current.forEach { handler(.attached($0)) }
    }

    public func stop() {
        lock.lock()
        let wasRunning = running
        let h = handler
        let ids = Array(devices.keys)
        running = false
        handler = nil
        lock.unlock()
        guard wasRunning else { return }
        ids.forEach { h?(.detached($0, at: Date())) }
        h?(.backendStatus(status))
    }

    public func snapshot() -> [DiscoveredDevice] {
        lock.lock(); defer { lock.unlock() }
        return devices.values.filter { !suppressed.contains($0.id) }.sorted { $0.id < $1.id }
    }

    public func refresh(_ id: DeviceIdentifier) -> DiscoveredDevice? {
        lock.lock(); defer { lock.unlock() }
        guard !suppressed.contains(id), var d = devices[id] else { return nil }
        d.lastSeen = Date()
        return d
    }

    /// Simulates unplugging a fixture.
    public func simulateDetach(_ id: DeviceIdentifier) {
        lock.lock()
        suppressed.insert(id)
        let h = running ? handler : nil
        lock.unlock()
        h?(.detached(id, at: Date()))
    }

    /// Simulates re-plugging a fixture.
    public func simulateAttach(_ id: DeviceIdentifier) {
        lock.lock()
        suppressed.remove(id)
        let d = devices[id]
        let h = running ? handler : nil
        lock.unlock()
        if let d = d { h?(.attached(d)) }
    }

    public func injectDisconnect(_ id: DeviceIdentifier) {
        lock.lock(); suppressed.insert(id); lock.unlock()
    }

    public func restore(_ id: DeviceIdentifier) {
        lock.lock(); suppressed.remove(id); lock.unlock()
    }
}
