#if canImport(IOKit)
import Foundation
import IOKit
import HCGCore

/// Real USB discovery through IOKit (`IOUSBHostDevice`), with live attach/detach notifications.
public final class IOKitUSBDiscovery: DeviceDiscoveryBackend {
    public let backendID = "iokit.usb"
    public let displayName = "IOKit USB"
    public let provenance = DataProvenance.hardware
    public let connectionTypes: [ConnectionType] = [.usb, .usbSerial, .hid]

    private let monitor: IOKitRegistryMonitor
    private let lock = NSLock()
    private var state: DiscoveryBackendStatus.State = .stopped
    private var detail = "Not started."

    public init() {
        monitor = IOKitRegistryMonitor(className: "IOUSBHostDevice", queueLabel: "com.hakmicapitalgroup.systemtester.iokit.usb",
                                       makeID: DeviceIdentifier.usbRegistry, build: IOKitUSBDiscovery.makeDevice)
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
        set(.starting, "Registering IOKit matching notifications for IOUSBHostDevice.")
        handler(.backendStatus(status))
        if let error = monitor.start(handler: handler) {
            set(.failed, error)
        } else {
            set(.running, "Live: IOUSBHostDevice first-match and terminated notifications are armed.")
        }
        handler(.backendStatus(status))
    }

    public func stop() {
        monitor.stop()
        set(.stopped, "Stopped by the user.")
    }

    public func snapshot() -> [DiscoveredDevice] { monitor.snapshot() }

    public func refresh(_ id: DeviceIdentifier) -> DiscoveredDevice? {
        guard id.rawValue.hasPrefix("usb:"), let entryID = UInt64(id.rawValue.dropFirst(4), radix: 16) else { return nil }
        return monitor.read(entryID)
    }

    /// One-shot enumeration without notifications (used by `hcg-probe --once`).
    public static func enumerateOnce() -> [DiscoveredDevice] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out: [DiscoveredDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, let d = makeDevice(service, entryID) {
                out.append(d)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return out.sorted { ($0.usb?.locationID ?? 0) < ($1.usb?.locationID ?? 0) }
    }

    // MARK: - Reading a device

    static func makeDevice(_ service: io_registry_entry_t, _ entryID: UInt64) -> DiscoveredDevice? {
        let props = Registry.properties(service)
        let ioClass = Registry.className(service)
        var usb = USBRegistryParser.parseDevice(properties: props, registryEntryID: entryID, ioClassName: ioClass,
                                                registryName: Registry.name(service))
        var interfaces: [USBInterfaceInfo] = []
        var bsdNames: [String] = []
        var serialPaths: [String] = []
        var mediaSize: Int64?

        Registry.forEachChild(service) { child in
            if Registry.conforms(child, "IOUSBHostInterface") {
                var services: [String] = []
                Registry.forEachChild(child) { driver in
                    if let name = Registry.className(driver), !name.contains("UserClient") { services.append(name) }
                }
                if let i = USBRegistryParser.parseInterface(properties: Registry.properties(child), attachedServices: services) {
                    interfaces.append(i)
                }
            }
        }
        // Storage and serial nodes published beneath this device (not beneath downstream devices).
        walkDescendants(service, depth: 0) { entry in
            if Registry.conforms(entry, "IOMedia") {
                let whole = USBRegistryParser.bool(Registry.property(entry, "Whole")) ?? false
                if whole, let bsd = Registry.property(entry, "BSD Name") as? String, !bsdNames.contains(bsd) {
                    bsdNames.append(bsd)
                    if let size = Registry.property(entry, "Size") as? NSNumber {
                        mediaSize = max(mediaSize ?? 0, size.int64Value)
                    }
                }
            } else if Registry.conforms(entry, "IOSerialBSDClient") {
                if let path = Registry.property(entry, "IOCalloutDevice") as? String, !serialPaths.contains(path) {
                    serialPaths.append(path)
                }
            }
        }

        usb.interfaces = interfaces.sorted { ($0.number, $0.alternateSetting) < ($1.number, $1.alternateSetting) }
        usb.bsdNames = bsdNames.sorted()
        usb.serialDevicePaths = serialPaths.sorted()
        usb.mediaSizeBytes = mediaSize
        if usb.vendorName == nil { usb.vendorName = USBVendorDatabase.name(for: usb.vendorID) }

        return DiscoveredDevice(
            id: .usbRegistry(entryID), provenance: .hardware, connectionType: .usb,
            name: USBRegistryParser.displayName(for: usb),
            manufacturer: usb.vendorName,
            usb: usb, source: "IOKit · \(ioClass ?? "IOUSBHostDevice")",
            rawProperties: USBRegistryParser.evidence(from: props))
    }

    /// Depth-limited walk that stops at nested USB devices (children of hubs).
    private static func walkDescendants(_ entry: io_registry_entry_t, depth: Int, _ visit: (io_registry_entry_t) -> Void) {
        guard depth < 14 else { return }
        Registry.forEachChild(entry) { child in
            if Registry.conforms(child, "IOUSBHostDevice") { return }
            visit(child)
            walkDescendants(child, depth: depth + 1, visit)
        }
    }
}
#endif
