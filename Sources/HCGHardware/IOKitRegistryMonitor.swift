#if canImport(IOKit)
import Foundation
import IOKit
import HCGCore

/// Thin, safe wrapper around IOKit matching notifications for one registry class.
///
/// - Uses public IOKit APIs only (`IOServiceAddMatchingNotification`, `IORegistryEntryCreateCFProperties`).
/// - Read-only: it never opens a device, claims an interface or sends a request.
/// - Needs no administrator privileges and no entitlements.
final class IOKitRegistryMonitor {
    typealias Builder = (io_registry_entry_t, UInt64) -> DiscoveredDevice?

    let className: String
    let queue: DispatchQueue
    private let build: Builder
    private let makeID: (UInt64) -> DeviceIdentifier

    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var handler: ((DiscoveryEvent) -> Void)?
    private var known: [UInt64: DiscoveredDevice] = [:]
    /// Delays (seconds) at which a newly attached device is re-read, because drivers,
    /// disks and serial nodes are published asynchronously after enumeration.
    var settleDelays: [Double] = [0.75, 2.5, 6]

    init(className: String, queueLabel: String, makeID: @escaping (UInt64) -> DeviceIdentifier, build: @escaping Builder) {
        self.className = className
        self.queue = DispatchQueue(label: queueLabel)
        self.makeID = makeID
        self.build = build
    }

    deinit {
        if let p = port { IONotificationPortDestroy(p) }
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
    }

    /// Starts notifications. Returns an error description when IOKit refuses.
    func start(handler: @escaping (DiscoveryEvent) -> Void) -> String? {
        queue.sync { startOnQueue(handler) }
    }

    func stop() {
        queue.sync {
            if let p = port { IONotificationPortDestroy(p) }
            port = nil
            if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
            if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
            let ids = Array(known.keys)
            known.removeAll()
            let h = handler
            handler = nil
            ids.forEach { h?(.detached(makeID($0), at: Date())) }
        }
    }

    var isRunning: Bool { queue.sync { port != nil } }

    private func startOnQueue(_ handler: @escaping (DiscoveryEvent) -> Void) -> String? {
        guard port == nil else { return nil }
        guard let p = IONotificationPortCreate(kIOMainPortDefault) else {
            return "IONotificationPortCreate failed."
        }
        IONotificationPortSetDispatchQueue(p, queue)
        port = p
        self.handler = handler

        guard let addMatch = IOServiceMatching(className), let removeMatch = IOServiceMatching(className) else {
            return "IOServiceMatching(\(className)) returned nil."
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let added: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon = refcon else { return }
            Unmanaged<IOKitRegistryMonitor>.fromOpaque(refcon).takeUnretainedValue().drainAdded(iterator)
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon = refcon else { return }
            Unmanaged<IOKitRegistryMonitor>.fromOpaque(refcon).takeUnretainedValue().drainRemoved(iterator)
        }

        // Each call consumes one reference to its matching dictionary.
        var kr = IOServiceAddMatchingNotification(p, kIOFirstMatchNotification, addMatch, added, refcon, &addedIterator)
        guard kr == KERN_SUCCESS else { return "IOServiceAddMatchingNotification (first match) failed: \(kr)" }
        kr = IOServiceAddMatchingNotification(p, kIOTerminatedNotification, removeMatch, removed, refcon, &removedIterator)
        guard kr == KERN_SUCCESS else { return "IOServiceAddMatchingNotification (terminated) failed: \(kr)" }

        // Draining arms the notifications and delivers devices that are already present.
        drainAdded(addedIterator)
        drainRemoved(removedIterator)
        return nil
    }

    private func drainAdded(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, let device = build(service, entryID) {
                known[entryID] = device
                handler?(.attached(device))
                scheduleSettleReads(entryID)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func drainRemoved(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, known.removeValue(forKey: entryID) != nil {
                handler?(.detached(makeID(entryID), at: Date()))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func scheduleSettleReads(_ entryID: UInt64) {
        for delay in settleDelays {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, let previous = self.known[entryID], let fresh = self.read(entryID) else { return }
                var updated = fresh
                updated.firstSeen = previous.firstSeen
                if updated.usb != previous.usb || updated.thunderbolt != previous.thunderbolt || updated.name != previous.name {
                    self.known[entryID] = updated
                    self.handler?(.attached(updated))
                }
            }
        }
    }

    /// Re-reads one registry entry by ID. Thread-safe (IOKit lookups are).
    func read(_ entryID: UInt64) -> DiscoveredDevice? {
        guard let matching = IORegistryEntryIDMatching(entryID) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return build(service, entryID)
    }

    func snapshot() -> [DiscoveredDevice] {
        queue.sync { Array(known.values) }
    }
}

/// Read-only helpers over the IORegistry.
enum Registry {
    static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() else { return [:] }
        return (dict as NSDictionary) as? [String: Any] ?? [:]
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func name(_ entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    static func className(_ entry: io_registry_entry_t) -> String? {
        guard let cf = IOObjectCopyClass(entry)?.takeRetainedValue() else { return nil }
        return cf as String
    }

    static func conforms(_ entry: io_registry_entry_t, _ cls: String) -> Bool {
        IOObjectConformsTo(entry, cls) != 0
    }

    /// Direct children in the IOService plane. The caller must not release the returned entries;
    /// `body` receives each child and the child is released afterwards.
    static func forEachChild(_ entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            body(child)
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
    }
}
#endif
