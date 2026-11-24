import XCTest
@testable import HCGCore

final class IdentificationTests: XCTestCase {
    let engine = IdentificationEngine()

    func testIdentifiesControllerNotConsole() {
        let r = engine.identify(Fixtures.dualSense)
        XCTAssertEqual(r.profileID, "sony.dualsense")
        XCTAssertEqual(r.category, .playStation)
        XCTAssertEqual(r.confidence, .high)
        XCTAssertTrue(r.knownLimitations.contains { $0.contains("not the console") })
        XCTAssertTrue(r.exposedProtocols.contains("usb.hid"))
    }

    func testIdentifiesStorageByInterfaceClass() {
        let r = engine.identify(Fixtures.sandisk)
        XCTAssertEqual(r.profileID, "generic.storage")
        XCTAssertEqual(r.category, .storage)
        XCTAssertTrue(r.exposedProtocols.contains("usb.msc"))
    }

    func testIdentifiesPhones() {
        XCTAssertEqual(engine.identify(Fixtures.iphone).profileID, "apple.iphone")
        let pixel = engine.identify(Fixtures.pixelADB)
        XCTAssertEqual(pixel.profileID, "android.adb")
        XCTAssertEqual(pixel.category, .smartphone)
        XCTAssertTrue(pixel.exposedProtocols.contains("android.adb"))
        XCTAssertFalse(pixel.alternatives.isEmpty, "Lower-ranked matches are reported for transparency")
    }

    func testIdentifiesHubAndSerialBridge() {
        let hub = engine.identify(Fixtures.hub)
        XCTAssertEqual(hub.profileID, "generic.hub")
        XCTAssertEqual(hub.role, .usbHub)
        XCTAssertEqual(engine.identify(Fixtures.ch340BehindHub).profileID, "serial.bridge")
    }

    func testUnknownDeviceIsNotGivenCapabilities() {
        let r = engine.identify(Fixtures.mystery)
        XCTAssertNil(r.profileID)
        XCTAssertEqual(r.category, .unknown)
        XCTAssertEqual(r.confidence, .none)
        XCTAssertFalse(r.isIdentified)
        XCTAssertTrue(r.recommendedAdapters.isEmpty)
    }

    func testAdapterContributedProfileTakesPart() {
        let e = IdentificationEngine()
        e.register(DeviceProfile(id: "x.mystery", name: "Mystery Widget", category: .robotics, family: "Widgets",
                                 match: DeviceMatchRules(vendorIDs: [0x9999], productIDs: [0x0001]), priority: 100))
        XCTAssertEqual(e.identify(Fixtures.mystery).profileID, "x.mystery")
    }
}
