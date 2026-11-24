import XCTest
@testable import HCGCore

final class StateMachineTests: XCTestCase {
    func testValidTransitions() throws {
        var m = DeviceStateMachine()
        try m.transition(to: .identified, reason: "profile")
        try m.transition(to: .diagnosticsAvailable, reason: "ops")
        try m.transition(to: .connected, reason: "exchanged data")
        try m.transition(to: .authenticated, reason: "authorised")
        try m.transition(to: .disconnected, reason: "unplugged")
        try m.transition(to: .detected, reason: "replugged")
        XCTAssertEqual(m.history.map(\.to), [.detected, .identified, .diagnosticsAvailable, .connected, .authenticated, .disconnected, .detected])
    }

    func testRecognitionCannotJumpToConnectedOrAuthenticated() {
        var m = DeviceStateMachine()
        XCTAssertThrowsError(try m.transition(to: .connected, reason: "name recognised"))
        XCTAssertThrowsError(try m.transition(to: .authenticated, reason: "id recognised"))
        var d = DeviceStateMachine(initial: .disconnected)
        XCTAssertThrowsError(try d.transition(to: .identified, reason: "must re-detect first"))
        XCTAssertEqual(d.status, .disconnected)
    }

    func testAdvanceFindsLegalPath() {
        var m = DeviceStateMachine(initial: .disconnected)
        m.advance(to: .diagnosticsAvailable, reason: "re-attached")
        XCTAssertEqual(m.status, .diagnosticsAvailable)
        XCTAssertEqual(m.history.first?.to, .disconnected)
        XCTAssertTrue(m.history.contains { $0.to == .detected })
        for pair in zip(m.history, m.history.dropFirst()) {
            XCTAssertTrue(DeviceStateMachine.canTransition(from: pair.0.to, to: pair.1.to))
        }
    }
}

final class InventoryTests: XCTestCase {
    func makeInventory() -> DeviceInventory { DeviceInventory(keySalt: "test") }

    func testMultipleDevicesAndHonestStatuses() {
        let inv = makeInventory()
        for d in [Fixtures.dualSense, Fixtures.sandisk, Fixtures.iphone, Fixtures.pixelADB, Fixtures.xboxController, Fixtures.hub, Fixtures.ch340BehindHub, Fixtures.mystery] {
            inv.apply(.attached(d))
        }
        XCTAssertEqual(inv.presentRecords.count, 8)
        // Nothing is "connected" just because it was recognised.
        XCTAssertFalse(inv.records.values.contains { $0.status == .connected || $0.status == .authenticated })
        XCTAssertEqual(inv.record(Fixtures.sandisk.id)?.status, .diagnosticsAvailable)
        XCTAssertEqual(inv.record(Fixtures.iphone.id)?.status, .adapterRequired)
        XCTAssertEqual(inv.record(Fixtures.pixelADB.id)?.status, .adapterRequired)
        XCTAssertEqual(inv.record(Fixtures.xboxController.id)?.status, .unsupported)
        // Unknown hardware: host diagnostics still apply but nothing is claimed.
        let mystery = inv.record(Fixtures.mystery.id)!
        XCTAssertFalse(mystery.identification.isIdentified)
        XCTAssertEqual(mystery.assessment.state(of: .functionalCommunication), .notVerified)
        XCTAssertEqual(mystery.assessment.state(of: .protocolCompatibility), .notVerified)
    }

    func testLayeredAssessmentForStorage() {
        let inv = makeInventory()
        inv.apply(.attached(Fixtures.sandisk))
        let r = inv.record(Fixtures.sandisk.id)!
        XCTAssertEqual(r.assessment.state(of: .physical), .verified)
        XCTAssertEqual(r.assessment.state(of: .enumeration), .verified)
        XCTAssertEqual(r.assessment.state(of: .protocolCompatibility), .verified)
        XCTAssertEqual(r.assessment.state(of: .authorization), .notApplicable)
        XCTAssertEqual(r.assessment.state(of: .functionalCommunication), .partial)
        XCTAssertEqual(r.assessment.limitingLayer?.layer, .functionalCommunication)
    }

    func testDisconnectAndReattachContinuesRecord() {
        let inv = makeInventory()
        inv.apply(.attached(Fixtures.sandisk))
        inv.apply(.detached(Fixtures.sandisk.id, at: Date()))
        XCTAssertEqual(inv.record(Fixtures.sandisk.id)?.status, .disconnected)
        XCTAssertEqual(inv.record(Fixtures.sandisk.id)?.assessment.state(of: .physical), .unavailable)
        // Re-plugged: new registry ID, same physical unit.
        var again = Fixtures.sandisk
        again.id = DeviceIdentifier("usb:test-sandisk-2")
        inv.apply(.attached(again))
        XCTAssertNil(inv.record(Fixtures.sandisk.id))
        let r = inv.record(again.id)!
        XCTAssertEqual(r.status, .diagnosticsAvailable)
        XCTAssertTrue(r.state.history.contains { $0.to == .disconnected })
        XCTAssertEqual(inv.events.map(\.kind), [.attached, .detached, .reattached])
    }

    func testFunctionalCommunicationRequiresEvidence() {
        let inv = makeInventory()
        inv.apply(.attached(Fixtures.ch340BehindHub))
        inv.recordFunctionalCommunication(Fixtures.ch340BehindHub.id, evidence: [])
        XCTAssertNotEqual(inv.record(Fixtures.ch340BehindHub.id)?.status, .connected)
        inv.recordFunctionalCommunication(Fixtures.ch340BehindHub.id, evidence: ["Echo test: 16 bytes round-trip"])
        XCTAssertEqual(inv.record(Fixtures.ch340BehindHub.id)?.status, .connected)
        inv.authorization.authorizeDevice(inv.record(Fixtures.ch340BehindHub.id)!.stableKey)
        inv.reevaluateAll()
        XCTAssertEqual(inv.record(Fixtures.ch340BehindHub.id)?.status, .authenticated)
    }

    func testTopologyFromDiscoveryOnly() {
        let inv = makeInventory()
        [Fixtures.hub, Fixtures.ch340BehindHub, Fixtures.sandisk].forEach { inv.apply(.attached($0)) }
        let synthetic = SyntheticDiscoveryBackend()
        synthetic.start { inv.apply($0) }
        let g = TopologyBuilder.build(records: inv.orderedRecords, hostName: "Test Mac")
        let ch340Node = "dev:" + Fixtures.ch340BehindHub.id.rawValue
        XCTAssertEqual(g.edges.first { $0.to == ch340Node }?.from, "dev:" + Fixtures.hub.id.rawValue)
        XCTAssertEqual(g.edges.first { $0.to == "dev:" + Fixtures.sandisk.id.rawValue }?.from, "bus:usb:2")
        XCTAssertNotNil(g.node("bus:synthetic"))
        XCTAssertEqual(g.edges.first { $0.to == "dev:" + SyntheticFixtures.controllerBehindHub.id.rawValue }?.from, "dev:" + SyntheticFixtures.hub.id.rawValue)
        // Synthetic nodes never hang off a hardware bus.
        for n in g.nodes where n.provenance == .synthetic && n.kind != .syntheticBus {
            var parent = g.edges.first { $0.to == n.id }?.from
            while let p = parent, p != "bus:synthetic" { parent = g.edges.first { $0.to == p }?.from }
            XCTAssertEqual(parent, "bus:synthetic")
        }
        // Every edge endpoint corresponds to an observed node.
        let ids = Set(g.nodes.map(\.id))
        XCTAssertTrue(g.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
    }

    func testSyntheticDevicesAreLabelled() {
        let inv = makeInventory()
        SyntheticDiscoveryBackend().start { inv.apply($0) }
        XCTAssertEqual(inv.presentRecords.count, SyntheticFixtures.all.count)
        for r in inv.presentRecords {
            XCTAssertEqual(r.device.provenance, .synthetic)
            XCTAssertTrue(r.device.displayName.hasPrefix("[SYNTHETIC]"))
            XCTAssertTrue(r.id.isSynthetic)
        }
    }
}
