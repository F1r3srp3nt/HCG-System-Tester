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

final class ConnectivityHardwareTests: XCTestCase {
    func testOnlyPrivateLANHostsAreContacted() {
        for h in ["192.168.1.20", "10.0.0.5", "172.16.4.1", "172.31.255.254", "169.254.10.10"] { XCTAssertTrue(LocalNetworkPolicy.isPrivateHost(h), h) }
        for h in ["8.8.8.8", "172.32.0.1", "example.com", "192.168.1", "256.1.1.1", "ai.hakmicapitalgroup.com", ""] { XCTAssertFalse(LocalNetworkPolicy.isPrivateHost(h), h) }
    }

    func testSamsungInfoRefusesPublicHosts() async {
        let r = await ReadOnlyHTTP.samsungTVInfo(host: "8.8.8.8")
        XCTAssertNil(r.info)
        XCTAssertEqual(r.error, "Only private LAN addresses are queried.")
    }

    func testBonjourServiceTypesAreDeclaredInBothInfoPlists() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["App/Config/Info.plist", "Packaging/Info.plist"] {
            let data = try Data(contentsOf: root.appendingPathComponent(rel))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertNotNil(plist["NSBluetoothAlwaysUsageDescription"], rel)
            XCTAssertNotNil(plist["NSLocalNetworkUsageDescription"], rel)
            let declared = Set(plist["NSBonjourServices"] as? [String] ?? [])
            #if canImport(Network)
            XCTAssertEqual(declared, Set(BonjourBrowser.serviceTypes), rel)
            #endif
        }
    }
}
