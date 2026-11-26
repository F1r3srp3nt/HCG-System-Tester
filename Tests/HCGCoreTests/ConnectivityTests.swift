import XCTest
@testable import HCGCore

final class ConnectivityKnowledgeTests: XCTestCase {
    func testCategoriesAndProfilesAreComplete() {
        XCTAssertEqual(ConnectivityCategory.allCases.count, 25)
        let ids = Set(EncyclopediaData.all.map(\.id))
        for required in ["sony.playstation5", "samsung.smart-tv", "audi.r8", "johndeere.tractor", "agri.isobus-generic", "robotics.industrial-arm",
                         "robotics.ros2", "dji.drone", "raspberrypi.sbc", "arduino.board", "espressif.esp32", "apple.iphone-ipad", "apple.mac",
                         "microsoft.windows-pc", "linux.computer", "ble.sensor-generic", "smarthome.matter-hap"] {
            XCTAssertTrue(ids.contains(required), required)
        }
        for p in EncyclopediaData.all {
            XCTAssertEqual(ProfileValidator.problems(p), [], p.id)
            XCTAssertFalse(p.allFacts.contains { $0.source == .hcgVerified }, "\(p.id): built-in research profiles claim no physical verification")
            XCTAssertFalse(p.allFacts.contains { $0.source == .aiSuggestion }, "\(p.id): no unlabelled AI content")
        }
    }

    func testProtocolRegistryDeclaresEverything() {
        let ids = Set(UniversalProtocolRegistry.all.map(\.id))
        for required in ["usb", "thunderbolt", "bluetooth.classic", "bluetooth.le", "wifi", "ethernet", "nfc", "serial", "uart", "can", "obd2", "j1939",
                         "isobus", "modbus", "opcua", "mqtt", "ros2", "hdmi.cec", "matter", "thread", "sdr.receive", "manufacturer.api"] {
            XCTAssertTrue(ids.contains(required), required)
        }
        for p in UniversalProtocolRegistry.all {
            XCTAssertFalse(p.summary.isEmpty, p.id)
            // Every protocol touching vehicles, machines, robots or drones states its safety boundary.
            if !Set(p.supportedCategories).isDisjoint(with: [.vehicle, .agriculturalMachinery, .roboticArm, .drone]) && p.id != "manufacturer.api" && p.id != "usb" {
                XCTAssertFalse(p.safetyNotes.isEmpty, "\(p.id) needs safety notes")
            }
        }
        XCTAssertEqual(UniversalProtocolRegistry.protocolInfo("vehicle.control")?.validation, .prohibited)
        XCTAssertEqual(UniversalProtocolRegistry.protocolInfo("sdr.receive")?.owner, "HCG Signal Contractor")
        for e in EquipmentCatalog.all { XCTAssertFalse(e.requiredSpecifications.isEmpty, e.id) }
    }

    func testUserProfileJSONIsTolerantAndValidated() throws {
        let json = #"{"id":"acme.widget","category":"iot","manufacturer":"Acme","productFamily":"Widget","match":{"usbVendorIDs":["0x1234"]},"connectionMethods":[{"id":"usb","title":"USB","protocolID":"usb","requiredEquipment":["cable.usbc-data"],"requiredSoftware":[],"permissions":[],"steps":[],"safety":"readOnly","source":"communityReported"}]}"#
        let p = try JSONDecoder().decode(EncyclopediaProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.match.usbVendorIDs, [0x1234])
        XCTAssertEqual(ProfileValidator.problems(p), [])
        var bad = p
        bad.connectionMethods[0].protocolID = "telepathy"
        XCTAssertFalse(ProfileValidator.problems(bad).isEmpty)
        var fake = p
        fake.protocols = [SourcedFact("Works perfectly", .hcgVerified)]
        XCTAssertFalse(ProfileValidator.problems(fake).isEmpty, "User profiles cannot self-certify")
    }

    func testEndpointMatching() {
        let profiles = EncyclopediaData.all
        let tv = SSDPParser.endpoint(fromResponse: "HTTP/1.1 200 OK\r\nSERVER: Samsung-Linux/4.1, UPnP/1.0, Samsung UPnP SDK/1.0\r\nST: urn:dial-multiscreen-org:service:dial:1\r\nUSN: uuid:abc-123::urn:dial\r\nLOCATION: http://192.168.1.20:7678/dmr\r\n\r\n", from: "192.168.1.20")!
        XCTAssertEqual(tv.attributes["manufacturer"], "Samsung")
        XCTAssertEqual(EndpointMatcher.match(tv, profiles: profiles).first?.profileID, "samsung.smart-tv")

        let mac = ObservedEndpoint(id: "b:1", transport: .bonjour, name: "Studio", attributes: ["serviceType": "_device-info._tcp", "model": "Mac15,8"], provenance: .hardware)
        XCTAssertEqual(EndpointMatcher.match(mac, profiles: profiles).first?.profileID, "apple.mac")

        let sensor = ObservedEndpoint(id: "ble:1", transport: .ble, name: "Thermo", attributes: ["serviceUUIDs": "181A,180F"], provenance: .hardware)
        XCTAssertEqual(EndpointMatcher.match(sensor, profiles: profiles).first?.profileID, "ble.sensor-generic")

        let matter = ObservedEndpoint(id: "b:2", transport: .bonjour, name: "Plug", attributes: ["serviceType": "_matterc._udp"], provenance: .hardware)
        XCTAssertEqual(EndpointMatcher.match(matter, profiles: profiles).first?.profileID, "smarthome.matter-hap")

        let unknown = ObservedEndpoint(id: "b:3", transport: .bonjour, name: "Printer", attributes: ["serviceType": "_ipp._tcp"], provenance: .hardware)
        XCTAssertTrue(EndpointMatcher.match(unknown, profiles: profiles).isEmpty, "Transport alone never matches a profile")

        let iphone = ObservedEndpoint.fromUSB(usbIPhone())
        XCTAssertEqual(EndpointMatcher.match(iphone, profiles: profiles).first?.profileID, "apple.iphone-ipad")
    }

    func testParsers() {
        let xml = "<root><device><friendlyName>[TV] Living Room</friendlyName><manufacturer>Samsung Electronics</manufacturer><modelName>QE65S95C</modelName></device></root>"
        XCTAssertEqual(SSDPParser.deviceDescription(xml)["modelName"], "QE65S95C")
        let info = SamsungTVInfoParser.parse(Data(#"{"device":{"modelName":"QE65S95CATXXU","OS":"Tizen","FrameTVSupport":"false","wifiMac":"aa:bb:cc:dd:ee:ff","id":"uuid:1"},"name":"[TV] Samsung","type":"Samsung SmartTV","version":"2.0.25"}"#.utf8))
        XCTAssertEqual(info?["modelName"], "QE65S95CATXXU")
        XCTAssertEqual(info?["os"], "Tizen")
        XCTAssertTrue(SamsungTVInfoParser.sensitiveKeys.contains("wifiMac"))

        let notPublished = HCGAIHandoffStatus.parse(status: 404, data: Data(#"{"status":"not_published","reason":"The native public OAuth client has not been issued and registered centrally."}"#.utf8))
        XCTAssertEqual(notPublished.state, .notPublished)
        let identity = HCGAIHandoffStatus.parse(status: 200, data: Data(#"{"handoffVersion":1,"api":{"baseURL":"https://ai.example/api","workflows":{}}}"#.utf8))
        XCTAssertEqual(identity.state, .identityOnly)
        let chat = HCGAIHandoffStatus.parse(status: 200, data: Data(#"{"api":{"workflows":{"chat":{"path":"/chat/completions"}}}}"#.utf8))
        XCTAssertEqual(chat.state, .chatAvailable)

        XCTAssertEqual(BLEAssignedNumbers.shortUUID("0000180A-0000-1000-8000-00805F9B34FB"), "180A")
        XCTAssertEqual(BLEAssignedNumbers.company(fromManufacturerData: Data([0x4C, 0x00, 0x10])), "Apple")
        XCTAssertFalse(BLEAssignedNumbers.readAllowList.contains("2A06"), "Alert Level (writable) is never touched")
    }
}

final class RoadmapAndGapTests: XCTestCase {
    func env(_ evidence: [ConnectivityEvidence] = [], owned: [String] = []) -> RoadmapEnvironment {
        var eq: [String: EquipmentStatus] = [:]
        for e in owned { eq[e] = EquipmentStatus(.declaredOwned, "test") }
        return RoadmapEnvironment(equipment: eq, implementedDrivers: RoadmapEngine.builtInDrivers, evidence: evidence)
    }

    func testResearchProfilesStartWithRequirementsNotClaims() {
        let (audi, _, blockers) = RoadmapEngine.evaluate(profile: EncyclopediaData.audiR8, env: env())
        XCTAssertEqual(audi, .adapterDevelopmentRequired)
        XCTAssertFalse(blockers.isEmpty)
        let (sensor, _, _) = RoadmapEngine.evaluate(profile: EncyclopediaData.bleSensor, env: env())
        XCTAssertEqual(sensor, .hardwareRequired, "Bluetooth controller not yet detected")
        let (ready, _, _) = RoadmapEngine.evaluate(profile: EncyclopediaData.bleSensor, env: env(owned: ["interface.bluetooth"]))
        XCTAssertEqual(ready, .readyForConnection)
    }

    func testEvidenceDrivesStatesAndSyntheticDoesNot() {
        let p = EncyclopediaData.appleMobile
        let base = env(owned: ["cable.usbc-data", "software.xcode"])
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: base).0, .readyForConnection)

        let synthetic = ConnectivityEvidence(kind: .connectionAttempt, outcome: .success, profileID: p.id, endpointName: "[SYNTHETIC] iPhone", summary: "fixture", provenance: .synthetic, source: "test")
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: env([synthetic], owned: ["cable.usbc-data", "software.xcode"])).0, .readyForConnection,
                       "Synthetic evidence never moves the roadmap")

        let discovered = ConnectivityEvidence(kind: .discovered, outcome: .observed, profileID: p.id, endpointName: "iPhone", summary: "IOKit", provenance: .hardware, source: "IOKit")
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: env([discovered])).0, .deviceDiscovered)
        let ok = ConnectivityEvidence(kind: .connectionAttempt, outcome: .success, profileID: p.id, endpointName: "iPhone", summary: "devicectl details", provenance: .hardware, source: "CoreDevice")
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: env([discovered, ok])).0, .connectionEstablished)
        let partial = ConnectivityEvidence(kind: .diagnostics, outcome: .partial, profileID: p.id, endpointName: "iPhone", summary: "8/11", provenance: .hardware, source: "Diagnostics", testsPassed: 8, testsApplicable: 11)
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: env([discovered, ok, partial])).0, .diagnosticsPartiallyVerified)
        let full = ConnectivityEvidence(kind: .diagnostics, outcome: .success, profileID: p.id, endpointName: "iPhone", summary: "11/11", provenance: .hardware, source: "Diagnostics", testsPassed: 11, testsApplicable: 11)
        XCTAssertEqual(RoadmapEngine.evaluate(profile: p, env: env([discovered, ok, partial, full])).0, .diagnosticsFullyVerified)
    }

    func testManualDecisionsAndHistory() {
        let roadmap = DevelopmentRoadmap()
        let p = EncyclopediaData.appleMobile
        let discovered = ConnectivityEvidence(kind: .discovered, outcome: .observed, profileID: p.id, endpointName: "iPhone", summary: "IOKit", provenance: .hardware, source: "IOKit")
        roadmap.recompute(profiles: [p], protocols: [], env: env([discovered]))
        let id = "device.\(p.id)"
        XCTAssertEqual(roadmap.items[id]?.state, .deviceDiscovered)
        XCTAssertNotNil(roadmap.decide(id, state: .compatibilityValidated, note: "looks fine"), "Discovery never validates compatibility")
        XCTAssertNotNil(roadmap.decide(id, state: .connectionEstablished, note: "trust me"), "Evidence states cannot be set manually")
        XCTAssertNil(roadmap.decide(id, state: .blocked, note: "Waiting for cable"))
        XCTAssertEqual(roadmap.items[id]?.state, .blocked)
        XCTAssertTrue(roadmap.items[id]?.history.last?.reason.contains("Manual decision") ?? false)
        XCTAssertFalse(roadmap.items[id]?.history.last?.automatic ?? true)
        roadmap.clearDecision(id)
        XCTAssertEqual(roadmap.items[id]?.state, .deviceDiscovered)

        // Validation allowed only with full evidence.
        let ok = ConnectivityEvidence(kind: .connectionAttempt, outcome: .success, profileID: p.id, endpointName: "iPhone", summary: "ok", provenance: .hardware, source: "x")
        let full = ConnectivityEvidence(kind: .diagnostics, outcome: .success, profileID: p.id, endpointName: "iPhone", summary: "11/11", provenance: .hardware, source: "x", testsPassed: 11, testsApplicable: 11)
        roadmap.recompute(profiles: [p], protocols: [], env: env([discovered, ok, full]))
        XCTAssertNil(roadmap.decide(id, state: .compatibilityValidated, note: "Verified on iPhone 16 Pro Max"))
        XCTAssertGreaterThanOrEqual(roadmap.items[id]?.history.filter(\.automatic).count ?? 0, 2, "Automatic transitions are recorded")
    }

    func testEvidencePersistsAcrossDisconnectAndRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hcg-conn-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ConnectivityStore(fileURL: url)
        store.record(ConnectivityEvidence(kind: .connectionAttempt, outcome: .success, profileID: "apple.iphone-ipad", endpointName: "iPhone", summary: "ok", provenance: .hardware, source: "x"))
        store.recomputeRoadmap(detected: [:])
        XCTAssertEqual(store.roadmap.items["device.apple.iphone-ipad"]?.state, .connectionEstablished)
        let reopened = ConnectivityStore(fileURL: url)
        XCTAssertEqual(reopened.state.evidence.count, 1)
        XCTAssertEqual(reopened.roadmap.items["device.apple.iphone-ipad"]?.state, .connectionEstablished, "Historical evidence survives disconnects and restarts")
    }

    func testGapAnalysisAndDependencies() {
        let all = GapAnalyzer.all(profiles: EncyclopediaData.all, env: env())
        let audi = all.filter { $0.profileIDs.contains("audi.r8") }
        XCTAssertTrue(audi.contains { $0.kind == .missingProtocolImplementation && $0.id == "gap.protocol.obd2" })
        XCTAssertTrue(audi.contains { $0.kind == .missingDiagnosticInterface && $0.id == "gap.equipment.interface.obd2" })
        XCTAssertTrue(audi.contains { $0.kind == .safetyReview })
        XCTAssertTrue(audi.contains { $0.kind == .missingInformation })
        let obd = all.first { $0.id == "gap.protocol.obd2" }!
        XCTAssertTrue(obd.dependsOn.contains("gap.equipment.interface.obd2"))
        XCTAssertTrue(obd.dependsOn.contains { $0.hasPrefix("gap.safety.") }, "Vehicle adapters depend on a safety review")
        // Deduplicated across profiles: one CAN interface requirement shared by Deere and generic ISOBUS.
        XCTAssertEqual(all.filter { $0.id == "gap.equipment.interface.usb-can" }.count, 1)
        XCTAssertTrue(all.first { $0.id == "gap.equipment.interface.usb-can" }!.profileIDs.count >= 2)
        // Ordering puts dependencies first.
        let order = GapAnalyzer.topologicalOrder(all).map(\.id)
        XCTAssertLessThan(order.firstIndex(of: "gap.equipment.interface.obd2")!, order.firstIndex(of: "gap.protocol.obd2")!)
        // Priorities are adjustable.
        XCTAssertEqual(GapAnalyzer.all(profiles: EncyclopediaData.all, env: env(), priorities: ["gap.protocol.obd2": 1]).first { $0.id == "gap.protocol.obd2" }?.priority, 1)
        // Implemented, satisfied methods generate no adapter gaps.
        XCTAssertFalse(GapAnalyzer.requirements(for: EncyclopediaData.bleSensor, env: env(owned: ["interface.bluetooth"])).contains { $0.kind == .missingAdapter || $0.kind == .missingProtocolImplementation })
    }

    func testLifeOSExportIsStableAndValid() throws {
        let all = GapAnalyzer.all(profiles: EncyclopediaData.all, env: env())
        let selected = all.filter { $0.id == "gap.protocol.obd2" }
        let doc = LifeOSQuestExporter.document(for: selected, all: all)
        XCTAssertEqual(doc["format"] as? String, "hcg.lifeos.backlog")
        XCTAssertEqual(doc["schemaVersion"] as? Int, 2)
        let quests = doc["quests"] as! [[String: Any]]
        let keys = quests.compactMap { $0["key"] as? String }
        XCTAssertEqual(Set(keys).count, keys.count, "No duplicate keys")
        XCTAssertTrue(keys.contains("hcg.systemtester.gap.protocol.obd2"))
        XCTAssertTrue(keys.contains("hcg.systemtester.gap.equipment.interface.obd2"), "Dependencies included so dependsOn resolves")
        for q in quests {
            XCTAssertNil(q["xpReward"], "No XP is set")
            XCTAssertNotEqual(q["status"] as? String, "completed")
            for dep in q["dependsOn"] as? [String] ?? [] { XCTAssertTrue(keys.contains(dep), dep) }
            if (q["kind"] as? String) == "quest" { XCTAssertEqual(q["parent"] as? String, LifeOSQuestExporter.epicKey) }
        }
        // Same input → same keys (idempotent re-import).
        let again = (LifeOSQuestExporter.document(for: selected, all: all)["quests"] as! [[String: Any]]).compactMap { $0["key"] as? String }
        XCTAssertEqual(Set(again), Set(keys))
        XCTAssertNoThrow(try LifeOSQuestExporter.json(for: selected, all: all))
    }

    func testConnectionStudioPlans() {
        let ready = ConnectionStudio.plan(profile: EncyclopediaData.bleSensor, env: env(owned: ["interface.bluetooth"]))
        XCTAssertTrue(ready.canAttempt)
        XCTAssertEqual(ready.steps.count, 14)
        XCTAssertEqual(ready.steps.first { $0.kind == .approval }?.status, .pending, "Never attempts without explicit approval")
        let audi = ConnectionStudio.plan(profile: EncyclopediaData.audiR8, env: env())
        XCTAssertFalse(audi.canAttempt)
        XCTAssertTrue(audi.blockedReason?.contains("No System Tester adapter") ?? false)
        XCTAssertFalse(audi.developmentNeeded.isEmpty, "Explains exactly what must be developed")
        let done = ConnectionStudio.plan(profile: EncyclopediaData.bleSensor, env: env(owned: ["interface.bluetooth"]), approved: true,
                                         lastResult: ConnectionAttemptResult(outcome: .failure, summary: "Timed out", errors: ["Peripheral did not respond"], provenance: .hardware))
        XCTAssertEqual(done.steps.first { $0.kind == .handshake }?.status, .blocked, "Failures are shown, never disguised")
    }

    func testAssistantLabelsSourcesAndIsNotAI() {
        let a = RuleBasedConnectionAssistant()
        XCTAssertFalse(a.isAI)
        let all = GapAnalyzer.all(profiles: EncyclopediaData.all, env: env())
        let answer = a.answer("How do I connect it and what do I need?", profile: EncyclopediaData.audiR8, env: env(), gaps: all)
        XCTAssertTrue(answer.statements.contains { $0.text.contains("No physical HCG evidence") })
        XCTAssertFalse(answer.statements.contains { $0.source == .hcgVerified })
        XCTAssertFalse(answer.statements.contains { $0.source == .aiSuggestion })
        let request = RuleBasedConnectionAssistant.researchRequest(profile: EncyclopediaData.audiR8, gaps: all, question: "")
        XCTAssertTrue(request.contains("manual transfer"))
    }
}

final class EquipmentDetectorTests: XCTestCase {
    func testDetectsOnlyWhatIsEvidenced() {
        let none = EquipmentDetector.detect(HostFacts())
        XCTAssertTrue(none.isEmpty, "No facts, no detections — nothing is assumed")

        var bridge = usbIPhone()
        bridge.id = DeviceIdentifier("usb:cp210x")
        bridge.name = "CP2102N USB to UART Bridge"
        bridge.usb?.vendorID = 0x10C4
        let eq = EquipmentDetector.detect(HostFacts(bluetoothPoweredOn: false, activeNetworkInterfaces: ["en0 (Wi-Fi)"], usbDevices: [usbIPhone(), bridge],
                                                    existingPaths: ["/opt/homebrew/bin/arduino-cli"]))
        XCTAssertEqual(eq["interface.bluetooth"]?.availability, .missing)
        XCTAssertEqual(eq["interface.wifi-or-ethernet"]?.availability, .detected)
        XCTAssertEqual(eq["cable.usbc-data"]?.availability, .detected)
        XCTAssertEqual(eq["adapter.usb-ttl-3v3"]?.availability, .detected)
        XCTAssertEqual(eq["software.arduino-cli"]?.availability, .detected)
        XCTAssertNil(eq["interface.obd2"], "Vehicle interfaces are never inferred")
        XCTAssertNil(eq["software.ps-remote-play"])
    }

    func testSyntheticDevicesDoNotCountAsEquipment() {
        var d = usbIPhone()
        d.provenance = .synthetic
        XCTAssertNil(EquipmentDetector.detect(HostFacts(usbDevices: [d]))["cable.usbc-data"])
    }

    func testRoutesIncludeConnectivitySections() {
        for r in ["connectivity", "encyclopedia", "connection-studio", "connected-devices", "protocols", "hardware-requirements", "roadmap", "gaps", "compatibility", "assistant", "history"] {
            XCTAssertNotNil(SystemTesterRoute.parse(URL(string: "hcgsystemtester://open/\(r)")!), r)
        }
        XCTAssertNotNil(HCGEcosystem.integrations.first { $0.id == "hcg-ai" })
        XCTAssertEqual(HCGEcosystem.integrations.first { $0.id == "hcg-vanguard" }?.status, .awaitingContract)
    }
}
