import XCTest
@testable import HCGCore

final class DiscoveryParsingTests: XCTestCase {
    func testParsesIORegistryStyleDictionary() {
        let props: [String: Any] = [
            "idVendor": NSNumber(value: 0x0781), "idProduct": NSNumber(value: 0x5581),
            "USB Vendor Name": "SanDisk", "USB Product Name": " Ultra ", "USB Serial Number": "4C530001230512345678",
            "bDeviceClass": NSNumber(value: 0), "bcdDevice": NSNumber(value: 0x0100), "bcdUSB": NSNumber(value: 0x0320),
            "Device Speed": NSNumber(value: 3), "locationID": NSNumber(value: UInt32(0x14100000)), "bNumConfigurations": 1,
            "Built-In": false
        ]
        let d = USBRegistryParser.parseDevice(properties: props, registryEntryID: 0x1000001AB, ioClassName: "IOUSBHostDevice")
        XCTAssertEqual(d.vendorID, 0x0781)
        XCTAssertEqual(d.productID, 0x5581)
        XCTAssertEqual(d.productName, "Ultra")
        XCTAssertEqual(d.vendorName, "SanDisk")
        XCTAssertEqual(d.speed, .superSpeed)
        XCTAssertEqual(d.locationID, 0x14100000)
        XCTAssertEqual(d.busNumber, 0x14)
        XCTAssertEqual(d.portPath, [1])
        XCTAssertEqual(d.firmwareRevision, "1.00")
        XCTAssertEqual(d.usbSpecification, "3.20")
        XCTAssertEqual(d.vendorIDHex, "0x0781")
        XCTAssertFalse(d.isBuiltIn)
    }

    func testToleratesLegacyKeysStringsAndMissingValues() {
        let props: [String: Any] = ["idVendor": "0x054c", "kUSBProductString": "Wireless Controller", "Device Speed": 99]
        let d = USBRegistryParser.parseDevice(properties: props, registryEntryID: nil, ioClassName: nil, registryName: "Ignored")
        XCTAssertEqual(d.vendorID, 0x054C)
        XCTAssertNil(d.productID)
        XCTAssertEqual(d.productName, "Wireless Controller")
        XCTAssertNil(d.speed, "Unknown speed codes must not be guessed")
        XCTAssertEqual(USBRegistryParser.displayName(for: USBDeviceDescriptor(vendorID: 0x054C)), "Sony USB device")
        XCTAssertEqual(USBRegistryParser.displayName(for: USBDeviceDescriptor(vendorID: 0x9999, productID: 1)), "Unnamed USB device 0x9999:0x0001")
    }

    func testRegistryNameFallbackAndInterfaceParsing() {
        let d = USBRegistryParser.parseDevice(properties: [:], registryEntryID: 7, ioClassName: nil, registryName: "USB2.1 Hub")
        XCTAssertEqual(d.productName, "USB2.1 Hub")
        let i = USBRegistryParser.parseInterface(properties: ["bInterfaceNumber": 2, "bInterfaceClass": 3, "bInterfaceSubClass": 1, "bInterfaceProtocol": 1],
                                                 attachedServices: ["AppleUserUSBHostHIDDevice"])
        XCTAssertEqual(i?.number, 2)
        XCTAssertEqual(i?.functionDescription, "HID boot keyboard")
        XCTAssertTrue(i?.hasDriver ?? false)
        XCTAssertNil(USBRegistryParser.parseInterface(properties: [:], attachedServices: []))
    }

    func testEvidenceStringifiesDataAndNumbers() {
        let ev = USBRegistryParser.evidence(from: ["idVendor": NSNumber(value: 1452), "sessionID": Data([0xDE, 0xAD]), "ignored": 1])
        XCTAssertEqual(ev["idVendor"], "1452")
        XCTAssertEqual(ev["sessionID"], "DE AD")
        XCTAssertNil(ev["ignored"])
    }

    func testTopologyMath() {
        XCTAssertEqual(USBTopology.portPath(locationID: 0x14120000), [1, 2])
        XCTAssertEqual(USBTopology.parentLocationID(of: 0x14120000), 0x14100000)
        XCTAssertNil(USBTopology.parentLocationID(of: 0x14100000))
        XCTAssertEqual(USBTopology.portPath(locationID: 0x01234500), [2, 3, 4, 5])
        XCTAssertEqual(USBTopology.parentLocationID(of: 0x01234500), 0x01234000)
    }

    func testSpeedAndBCDHelpers() {
        XCTAssertEqual(USBSpeed.maximumSupported(bcdUSB: 0x0200), .high)
        XCTAssertEqual(USBSpeed.maximumSupported(bcdUSB: 0x0300), .superSpeed)
        XCTAssertEqual(USBSpeed.maximumSupported(bcdUSB: 0x0320), .superSpeed, "bcdUSB 3.2 does not imply Gen 2")
        XCTAssertEqual(USBSpeed.maximumSupported(bcdUSB: 0x0110), .full)
        XCTAssertEqual(Hex.bcdVersion(0x0210), "2.10")
        XCTAssertEqual(Hex.bcdVersion(0x0101), "1.01")
        XCTAssertEqual(Hex.parse16("0x054C"), 0x054C)
        XCTAssertEqual(Hex.parse16("2341"), 0x2341)
    }

    func testStableKeyNeverContainsRawSerial() {
        let key = Fixtures.sandisk.stableKey(salt: "s")
        XCTAssertFalse(key.contains("4C530001230512345678"))
        XCTAssertTrue(key.hasPrefix("0x0781:0x5581:sn-"))
        XCTAssertEqual(key, Fixtures.sandisk.stableKey(salt: "s"))
        XCTAssertNotEqual(key, Fixtures.sandisk.stableKey(salt: "other"))
    }
}
