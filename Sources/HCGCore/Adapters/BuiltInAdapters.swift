import Foundation

/// First-party adapters shipped with System Tester 0.1.0.
public enum BuiltInAdapters {
    static let v010 = SemanticVersion(0, 1, 0)
    static let publisher = HCGSystemTesterInfo.publisher

    /// Builds an operation that maps 1:1 to a host operation.
    static func op(_ hostID: String) -> DiagnosticOperationDescriptor {
        guard let h = HostOperationCatalog.descriptor(hostID) else {
            preconditionFailure("Unknown host operation \(hostID)")
        }
        return DiagnosticOperationDescriptor(id: hostID, name: h.name, hostOperation: hostID, category: h.category,
                                             impact: h.impact, requiredCapabilities: h.requiredCapabilities, summary: h.summary,
                                             effects: h.effects, timeoutSeconds: max(30, h.estimatedDurationSeconds * 2))
    }

    static let disconnectError = AdapterErrorDescriptor(
        code: "device.disconnected", meaning: "The device left the bus during an operation.",
        recovery: "Reconnect the device and re-run; persistent drop-outs indicate cable, port or power problems.")

    public static let usbCore = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.usb-core", name: "USB Core", version: v010, publisher: publisher,
        summary: "Host-side, read-only diagnostics for every enumerated USB device: presence, identification, interfaces, link speed, firmware revision, stability and enumeration errors.",
        execution: .builtIn, deviceFamilies: DeviceCategory.allCases, connectionTypes: [.usb],
        protocols: ["usb.descriptor", "usb.hub"], match: DeviceMatchRules(),
        driverRequirements: [DriverRequirement(name: "IOUSBHostFamily", providedByMacOS: true)],
        permissions: [.readDeviceDescriptors],
        operations: ["host.presence", "host.identification", "host.interfaces", "host.protocol-validation", "host.link-speed",
                     "host.firmware-info", "host.enumeration-errors", "host.registry-latency", "host.presence-stability",
                     "host.presence-stability-extended"].map(op),
        lifecycle: ConnectionLifecycle(stages: [.discover, .identify, .diagnose]),
        errors: [disconnectError],
        healthChecks: [HealthCheckDescriptor(id: "usb.presence-health", hostOperation: "host.presence", intervalSeconds: 10)])

    public static let usbStorage = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.usb-storage", name: "USB Storage", version: v010, publisher: publisher,
        summary: "Reports the BSD disk and medium size published for USB mass-storage devices. Never mounts, reads or writes media.",
        execution: .builtIn, deviceFamilies: [.storage, .microcontroller, .camera, .smartphone],
        connectionTypes: [.usb], protocols: ["usb.msc"], match: DeviceMatchRules(interfaceClasses: [0x08]),
        driverRequirements: [DriverRequirement(name: "IOUSBMassStorageDriver / IOUSBAttachedSCSI", providedByMacOS: true)],
        permissions: [.readDeviceDescriptors, .readStorageMetadata],
        operations: [op("host.storage-info"), op("host.protocol-validation")],
        errors: [disconnectError])

    public static let usbSerial = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.usb-serial", name: "USB Serial", version: v010, publisher: publisher,
        summary: "Detects serial callout devices for CDC ACM and USB-serial bridges. Opening ports (functional communication) is planned and will require per-device authorisation.",
        execution: .builtIn, deviceFamilies: [.microcontroller, .robotics, .industrial],
        connectionTypes: [.usb], protocols: ["usb.cdc-acm", "usb.vendor-serial"], match: DeviceMatchRules(),
        hardwareRequirements: ["A data-capable USB cable"],
        driverRequirements: [
            DriverRequirement(name: "AppleUSBACM (CDC ACM)", providedByMacOS: true),
            DriverRequirement(name: "Apple FTDI / CP210x / CH34x drivers (DriverKit)", providedByMacOS: true, notes: "Older bridges may need a vendor driver; System Tester never installs drivers.")
        ],
        permissions: [.readDeviceDescriptors, .readSerialPortList],
        operations: [op("host.protocol-validation"), op("host.interfaces")],
        errors: [disconnectError,
                 AdapterErrorDescriptor(code: "serial.no-callout", meaning: "No /dev/cu.* device was published.",
                                        recovery: "The bridge may need a vendor driver, or the board is in bootloader mode.")])

    public static let hid = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.hid", name: "HID Inspector", version: v010, publisher: publisher,
        summary: "Descriptor-level checks for HID interfaces (keyboards, mice, controllers, security keys). Input is never captured.",
        execution: .builtIn, deviceFamilies: [.inputDevice, .gamingAccessory, .playStation, .xbox, .nintendo],
        connectionTypes: [.usb], protocols: ["usb.hid"], match: DeviceMatchRules(interfaceClasses: [0x03]),
        permissions: [.readDeviceDescriptors, .readHIDDescriptors],
        operations: [op("host.interfaces"), op("host.protocol-validation")])

    public static let thunderbolt = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.thunderbolt", name: "Thunderbolt Switch Inspector", version: v010, publisher: publisher,
        summary: "Read-only Thunderbolt / USB4 switch information.",
        execution: .builtIn, deviceFamilies: DeviceCategory.allCases, connectionTypes: [.thunderbolt],
        protocols: ["thunderbolt.registry"], match: DeviceMatchRules(),
        permissions: [.readThunderboltRegistry],
        operations: [op("host.presence"), op("host.thunderbolt-switch")])

    static func consoleResearch(id: String, name: String, family: DeviceCategory, match: DeviceMatchRules) -> AdapterManifest {
        AdapterManifest(
            id: id, name: name, version: v010, publisher: publisher,
            summary: "Research module: records which interfaces \(family.displayName) hardware actually exposes over each connection. Uses documented interfaces only and never bypasses authentication, DRM or firmware protections.",
            execution: .builtIn, deviceFamilies: [family], connectionTypes: [.usb], protocols: ["usb.descriptor", "usb.hid"],
            match: match,
            hardwareRequirements: ["Console accessories connect directly. Consoles themselves are USB hosts and need a documented network or developer interface."],
            permissions: [.readDeviceDescriptors],
            operations: [op("research.console-interfaces"), op("host.interfaces")],
            experimental: true)
    }

    public static let playStation = consoleResearch(id: "com.hakmicapitalgroup.adapter.playstation-research", name: "PlayStation Research",
                                                    family: .playStation, match: DeviceMatchRules(vendorIDs: [0x054C]))
    public static let xbox = consoleResearch(id: "com.hakmicapitalgroup.adapter.xbox-research", name: "Xbox Research",
                                             family: .xbox, match: DeviceMatchRules())
    public static let nintendo = consoleResearch(id: "com.hakmicapitalgroup.adapter.nintendo-research", name: "Nintendo Research",
                                                 family: .nintendo, match: DeviceMatchRules(vendorIDs: [0x057E]))

    /// Reference implementation of a device-family adapter (see docs/APPLE-ADAPTER.md).
    public static let appleDeviceIntelligence = AdapterManifest(
        id: AppleDeviceIntelligenceProvider.adapterID, name: "Apple Device Intelligence", version: SemanticVersion(0, 2, 0), publisher: publisher,
        summary: "Identifies iPhone and iPad over USB and retrieves model, OS, pairing, Developer Mode and service information through Xcode's CoreDevice (xcrun devicectl, JSON). Optional libimobiledevice adds battery and free space. Never bypasses Trust, passcodes, USB Restricted Mode or Activation Lock; never enables Developer Mode.",
        execution: .builtIn, deviceFamilies: [.smartphone, .tablet], connectionTypes: [.usb, .synthetic],
        protocols: ["usb.descriptor", "usb.ptp", "apple.usbmux", "apple.coredevice", "apple.lockdown"],
        match: DeviceMatchRules(vendorIDs: [0x05AC]),
        hardwareRequirements: ["Data-capable USB-C (or Lightning) cable", "Device unlocked for first pairing"],
        driverRequirements: [DriverRequirement(name: "usbmuxd + CoreDevice (Xcode 15 or later)", providedByMacOS: true, notes: "devicectl ships with Xcode."),
                             DriverRequirement(name: "libimobiledevice (optional)", providedByMacOS: false, notes: "User-installed; enables battery and free-space domains.")],
        permissions: [.readDeviceDescriptors],
        operations: (["host.presence", "host.interfaces", "host.link-speed"] + AppleDiagnostics.descriptors.map(\.id)).map(op),
        lifecycle: ConnectionLifecycle(stages: [.discover, .identify, .authorize, .diagnose], requiresExplicitAuthorization: false),
        errors: [disconnectError,
                 AdapterErrorDescriptor(code: "apple.not-paired", meaning: "The device has not trusted this Mac.", recovery: "Unlock the device, click Pair and tap Trust on the device."),
                 AdapterErrorDescriptor(code: "apple.locked", meaning: "The device is locked and cannot answer.", recovery: "Unlock the device and keep it awake."),
                 AdapterErrorDescriptor(code: "apple.no-devicectl", meaning: "Xcode's devicectl is not available.", recovery: "Install Xcode 15+ and select it with xcode-select.")],
        healthChecks: [HealthCheckDescriptor(id: "apple.presence-health", hostOperation: "host.presence", intervalSeconds: 10)])

    public static let android = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.android", name: "Android Devices", version: v010, publisher: publisher,
        summary: "Identifies Android phones by their ADB / MTP interfaces. Communication through adb is a planned integration and will require the user to approve this Mac on the phone.",
        execution: .builtIn, deviceFamilies: [.smartphone, .tablet], connectionTypes: [.usb],
        protocols: ["usb.descriptor", "android.adb", "usb.ptp"], match: DeviceMatchRules(),
        hardwareRequirements: ["USB debugging enabled on the phone for ADB"],
        driverRequirements: [DriverRequirement(name: "Android Platform Tools (adb)", providedByMacOS: false, notes: "Not bundled; planned optional integration.")],
        permissions: [.readDeviceDescriptors],
        operations: [op("host.identification"), op("host.interfaces")],
        experimental: true)

    public static let syntheticLab = AdapterManifest(
        id: "com.hakmicapitalgroup.adapter.synthetic-lab", name: "Synthetic Lab", version: v010, publisher: publisher,
        summary: "Runs the diagnostic engine against clearly labelled synthetic fixtures, including a state-changing fault-injection operation used to exercise the authorisation gate.",
        execution: .builtIn, deviceFamilies: DeviceCategory.allCases, connectionTypes: [.synthetic],
        protocols: ["synthetic.fixture"], match: DeviceMatchRules(),
        permissions: [.readDeviceDescriptors, .changeDeviceConfiguration],
        operations: ["host.presence", "host.identification", "host.interfaces", "host.protocol-validation", "host.link-speed",
                     "host.firmware-info", "host.storage-info", "host.enumeration-errors", "host.registry-latency",
                     "host.presence-stability", "synthetic.fault-injection"].map(op),
        lifecycle: ConnectionLifecycle(stages: [.discover, .identify, .authorize, .diagnose], requiresExplicitAuthorization: true),
        errors: [disconnectError])

    public static let all: [AdapterManifest] = [usbCore, usbStorage, usbSerial, hid, thunderbolt, playStation, xbox, nintendo,
                                                 appleDeviceIntelligence, android, syntheticLab]
}
