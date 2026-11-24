import Foundation
@testable import HCGCore

/// Descriptor fixtures modelled on real IORegistry output (values are representative, not captured from a user's device).
enum Fixtures {
    static func usbDevice(_ key: String, vid: UInt16, pid: UInt16, product: String?, vendor: String? = nil, serial: String? = nil,
                          deviceClass: UInt8 = 0, bcdUSB: UInt16 = 0x0200, speed: USBSpeed? = .high, location: UInt32,
                          interfaces: [USBInterfaceInfo], bsd: [String] = [], serialPaths: [String] = []) -> DiscoveredDevice {
        DiscoveredDevice(
            id: DeviceIdentifier("usb:test-" + key), provenance: .hardware, connectionType: .usb,
            name: product ?? "Unnamed", manufacturer: vendor,
            usb: USBDeviceDescriptor(vendorID: vid, productID: pid, vendorName: vendor, productName: product, serialNumber: serial,
                                     deviceClass: deviceClass, bcdDevice: 0x0100, bcdUSB: bcdUSB, speed: speed, locationID: location,
                                     registryEntryID: 1, interfaces: interfaces, bsdNames: bsd, serialDevicePaths: serialPaths),
            source: "Test fixture (hardware-shaped)")
    }

    static let dualSense = usbDevice("dualsense", vid: 0x054C, pid: 0x0CE6, product: "DualSense Wireless Controller", vendor: "Sony Interactive Entertainment",
                                     speed: .full, location: 0x01100000,
                                     interfaces: [USBInterfaceInfo(number: 0, classCode: 0x01, subclassCode: 0x01, attachedServices: ["AppleUSBAudioDevice"]),
                                                  USBInterfaceInfo(number: 3, classCode: 0x03, attachedServices: ["AppleUserUSBHostHIDDevice"])])

    static let sandisk = usbDevice("sandisk", vid: 0x0781, pid: 0x5581, product: "Ultra", vendor: "SanDisk", serial: "4C530001230512345678",
                                   bcdUSB: 0x0320, speed: .superSpeed, location: 0x02100000,
                                   interfaces: [USBInterfaceInfo(number: 0, classCode: 0x08, subclassCode: 0x06, protocolCode: 0x50, attachedServices: ["IOUSBMassStorageDriverNub"])],
                                   bsd: ["disk4"])

    static let iphone = usbDevice("iphone", vid: 0x05AC, pid: 0x12A8, product: "iPhone", vendor: "Apple Inc.", serial: "00008110001234567890ABCD",
                                  location: 0x01200000,
                                  interfaces: [USBInterfaceInfo(number: 0, classCode: 0x06, subclassCode: 0x01, protocolCode: 0x01),
                                               USBInterfaceInfo(number: 1, classCode: 0xFF, subclassCode: 0xFE, protocolCode: 0x02)])

    static let pixelADB = usbDevice("pixel", vid: 0x18D1, pid: 0x4EE7, product: "Pixel 8", vendor: "Google",
                                    location: 0x01300000,
                                    interfaces: [USBInterfaceInfo(number: 0, classCode: 0x06, subclassCode: 0x01, protocolCode: 0x01),
                                                 USBInterfaceInfo(number: 1, classCode: 0xFF, subclassCode: 0x42, protocolCode: 0x01)])

    static let xboxController = usbDevice("xbox", vid: 0x045E, pid: 0x0B12, product: "Controller", vendor: "Microsoft",
                                          speed: .full, location: 0x01400000,
                                          interfaces: [USBInterfaceInfo(number: 0, classCode: 0xFF, subclassCode: 0x47, protocolCode: 0xD0)])

    static let hub = usbDevice("hub", vid: 0x05E3, pid: 0x0610, product: "USB2.1 Hub", vendor: "GenesysLogic", deviceClass: 0x09,
                               location: 0x01500000, interfaces: [USBInterfaceInfo(number: 0, classCode: 0x09, attachedServices: ["AppleUSB20Hub"])])

    static let ch340BehindHub = usbDevice("ch340", vid: 0x1A86, pid: 0x7523, product: "USB Serial", speed: .full, location: 0x01530000,
                                          interfaces: [USBInterfaceInfo(number: 0, classCode: 0xFF, subclassCode: 0x01, protocolCode: 0x02, attachedServices: ["AppleUSBCHCOM"])],
                                          serialPaths: ["/dev/cu.usbserial-1530"])

    static let mystery = usbDevice("mystery", vid: 0x9999, pid: 0x0001, product: nil, speed: .full, location: 0x01600000,
                                   interfaces: [USBInterfaceInfo(number: 0, classCode: 0xFF, subclassCode: 0x00, protocolCode: 0x00)])
}

/// Probe over a fixed set of devices, with controllable disappearance.
final class FixtureProbe: DeviceProbe {
    var devices: [DeviceIdentifier: DiscoveredDevice]
    var disappearAfterCalls: Int?
    private(set) var calls = 0

    init(_ devices: [DiscoveredDevice]) {
        var map: [DeviceIdentifier: DiscoveredDevice] = [:]
        for d in devices { map[d.id] = d }
        self.devices = map
    }

    func refresh(_ id: DeviceIdentifier) -> DiscoveredDevice? {
        calls += 1
        if let limit = disappearAfterCalls, calls > limit { return nil }
        return devices[id]
    }
}

func context(_ device: DiscoveredDevice, probe: DeviceProbe? = nil) -> DiagnosticContext {
    let engine = IdentificationEngine()
    return DiagnosticContext(device: device, identification: engine.identify(device), probe: probe ?? FixtureProbe([device]),
                             sleep: { _ in })
}
