import XCTest
import HCGCore
@testable import HCGHardware

/// These tests talk to the real IORegistry of the machine running them. They never assume
/// a particular device is attached (CI runners have none), only that discovery behaves.
final class HardwareDiscoveryTests: XCTestCase {
    func testBackendsExistOnMacOS() {
        #if os(macOS)
        XCTAssertTrue(HostDiscovery.isHardwareDiscoverySupported)
        XCTAssertEqual(HostDiscovery.makeHardwareBackends().map(\.backendID), ["iokit.usb", "iokit.thunderbolt"])
        #endif
    }

    func testOneShotEnumerationProducesWellFormedHardwareRecords() {
        for d in HostDiscovery.enumerateUSBOnce() {
            XCTAssertEqual(d.provenance, .hardware)
            XCTAssertTrue(d.id.rawValue.hasPrefix("usb:"))
            XCTAssertFalse(d.name.isEmpty)
            XCTAssertFalse(d.displayName.contains("SYNTHETIC"))
        }
    }

    func testLiveBackendStartsAndStops() {
        #if os(macOS)
        let usb = IOKitUSBDiscovery()
        var statuses: [DiscoveryBackendStatus.State] = []
        var attached = 0
        usb.start { event in
            switch event {
            case .backendStatus(let s): statuses.append(s.state)
            case .attached: attached += 1
            case .detached: break
            }
        }
        XCTAssertEqual(statuses.last, .running, usb.status.detail)
        XCTAssertEqual(attached, usb.snapshot().count)
        for d in usb.snapshot() {
            XCTAssertEqual(usb.refresh(d.id)?.id, d.id, "Present devices can be re-read by registry ID")
        }
        XCTAssertNil(usb.refresh(DeviceIdentifier("usb:ffffffffffff")))
        usb.stop()
        XCTAssertEqual(usb.status.state, .stopped)
        #endif
    }

    func testHostInfo() {
        let info = HostInfo.current()
        XCTAssertFalse(info.name.isEmpty)
        XCTAssertGreaterThan(info.memoryBytes, 0)
    }
}
