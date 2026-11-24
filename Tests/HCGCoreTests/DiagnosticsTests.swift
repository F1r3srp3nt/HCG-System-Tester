import XCTest
@testable import HCGCore

final class DiagnosticsTests: XCTestCase {
    func testEveryResultCarriesRequiredFields() async {
        let engine = DiagnosticEngine()
        let ctx = context(Fixtures.sandisk)
        let suite = engine.defaultSuite(for: Fixtures.sandisk, identification: ctx.identification)
        XCTAssertTrue(suite.contains("host.storage-info"))
        XCTAssertFalse(suite.contains("host.presence-stability-extended"), "Extended tests are not in the default suite")
        let run = await engine.run(testIDs: suite, context: ctx)
        XCTAssertEqual(run.results.count, suite.count)
        for r in run.results {
            XCTAssertFalse(r.testID.isEmpty)
            XCTAssertEqual(r.targetDeviceID, Fixtures.sandisk.id)
            XCTAssertLessThanOrEqual(r.startedAt, r.finishedAt)
            XCTAssertFalse(r.summary.isEmpty)
            XCTAssertFalse(r.recommendedNextAction.isEmpty)
            XCTAssertEqual(r.provenance, .hardware)
            XCTAssertNotEqual(r.outcome, .error, "\(r.testID): \(r.errors)")
        }
        let latency = run.results.first { $0.testID == "host.registry-latency" }!
        XCTAssertTrue(latency.measurements.contains { $0.unit == "ms" })
        XCTAssertTrue(latency.limitations.contains { $0.contains("NOT a round trip") })
    }

    func testLinkSpeedDetectsDegradedLink() async {
        let ctx = context(SyntheticFixtures.degradedSSD)
        let out = try? await LinkSpeedTest().run(ctx)
        XCTAssertEqual(out?.outcome, .warning)
        XCTAssertEqual(out?.measurements.first?.provenance, .synthetic)
        let fine = try? await LinkSpeedTest().run(context(Fixtures.sandisk))
        XCTAssertEqual(fine?.outcome, .passed)
    }

    func testDisconnectionDuringTestsAbortsRemainingTests() async {
        let probe = FixtureProbe([Fixtures.sandisk])
        probe.disappearAfterCalls = 3
        let engine = DiagnosticEngine()
        let ctx = context(Fixtures.sandisk, probe: probe)
        let run = await engine.run(testIDs: ["host.presence", "host.registry-latency", "host.interfaces", "host.firmware-info"], context: ctx)
        XCTAssertEqual(run.results[0].outcome, .passed)
        XCTAssertEqual(run.results[1].outcome, .aborted)
        XCTAssertTrue(run.results[1].errors.first?.contains("disconnected") ?? false)
        XCTAssertEqual(run.results[2].outcome, .aborted)
        XCTAssertEqual(run.results[3].outcome, .aborted)
        XCTAssertEqual(run.worstOutcome, .aborted)
    }

    func testStabilityRecordsDropOutsWithSyntheticBackend() async {
        let backend = SyntheticDiscoveryBackend()
        let device = SyntheticFixtures.serialBoard
        var polls = 0
        let ctx = DiagnosticContext(device: device, identification: IdentificationEngine().identify(device), probe: backend,
                                    sleep: { _ in
                                        polls += 1
                                        if polls == 5 { backend.injectDisconnect(device.id) }
                                        if polls == 8 { backend.restore(device.id) }
                                    })
        let out = try? await PresenceStabilityTest().run(ctx)
        XCTAssertEqual(out?.outcome, .failed)
        XCTAssertEqual(out?.measurements.first { $0.name == "Drop-outs" }?.value, 3)
    }

    func testAuthorisationGate() async {
        let backend = SyntheticDiscoveryBackend()
        let device = SyntheticFixtures.flashDrive
        let log = AuditLog()
        let engine = DiagnosticEngine(auditLog: log)
        let ctx = DiagnosticContext(device: device, identification: IdentificationEngine().identify(device), probe: backend, sleep: { _ in })
        var run = await engine.run(testIDs: ["synthetic.fault-injection", "host.presence-stability-extended"], context: ctx)
        XCTAssertEqual(run.results.map(\.outcome), [.skipped, .skipped])
        XCTAssertEqual(log.entries.map(\.decision), ["denied", "denied"])

        run = await engine.run(testIDs: ["synthetic.fault-injection"], context: ctx,
                               authorization: DiagnosticAuthorization(authorizedStateChangingTests: ["synthetic.fault-injection"]))
        XCTAssertEqual(run.results.first?.outcome, .passed)
        XCTAssertEqual(log.entries.last?.decision, "permitted")
        XCTAssertNotNil(backend.refresh(device.id), "Fixture restored after injection")
    }

    func testFaultInjectionNeverAppliesToHardware() async {
        let engine = DiagnosticEngine()
        let ctx = context(Fixtures.sandisk)
        let run = await engine.run(testIDs: ["synthetic.fault-injection"], context: ctx,
                                   authorization: DiagnosticAuthorization(authorizedStateChangingTests: ["synthetic.fault-injection"]))
        XCTAssertEqual(run.results.first?.outcome, .notSupported)
    }

    func testUnsupportedAndInapplicableTests() async {
        let engine = DiagnosticEngine()
        let ctx = context(Fixtures.mystery)
        let run = await engine.run(testIDs: ["host.storage-info", "research.console-interfaces", "host.identification", "nope.unknown"], context: ctx)
        XCTAssertEqual(run.results.map(\.outcome), [.notSupported, .notSupported, .warning, .error])
        let ids = engine.applicableTests(for: Fixtures.dualSense, identification: IdentificationEngine().identify(Fixtures.dualSense)).map(\.id)
        XCTAssertTrue(ids.contains("research.console-interfaces"))
    }

    func testHostCatalogCoversSpecifiedCategories() {
        let uncovered = HostOperationCatalog.uncoveredCategories
        XCTAssertEqual(uncovered, [.hardwareHealth], "Only hardware health lacks a host test in 0.1.0")
    }
}

final class ReportAndRedactionTests: XCTestCase {
    func testRedactsSensitiveData() {
        var r = Redactor()
        r.registerSerialNumber("4C530001230512345678")
        let text = "serial 4C530001230512345678 at /Users/alice/Desktop mac 3c:22:fb:12:34:56 ip 192.168.1.20 mail a.b@example.com Bearer abc123def456 password=hunter2 Serial Number: XYZ98765"
        let out = r.redact(text)
        for secret in ["4C530001230512345678", "alice", "3c:22:fb:12:34:56", "192.168.1.20", "a.b@example.com", "abc123def456", "hunter2", "XYZ98765"] {
            XCTAssertFalse(out.contains(secret), "\(secret) leaked: \(out)")
        }
        XCTAssertTrue(out.contains("Bearer [REDACTED]"))
        XCTAssertEqual(Redactor.maskSerial("ABCDEF12"), "••••••12")
    }

    func testRedactionRespectsSettings() {
        let r = Redactor(settings: PrivacySettings(redactSerialNumbers: false, redactNetworkIdentifiers: false, redactUserPaths: false, redactHostName: false))
        XCTAssertEqual(r.redact("ip 10.0.0.1 path /Users/bob"), "ip 10.0.0.1 path /Users/bob")
        XCTAssertEqual(r.redact("token=abcdef"), "token=[REDACTED]", "Credentials are always redacted")
    }

    func testReportGenerationMarksSyntheticAndRedacts() async throws {
        let inv = DeviceInventory(keySalt: "t")
        inv.apply(.attached(Fixtures.sandisk))
        let backend = SyntheticDiscoveryBackend(fixtures: [SyntheticFixtures.flashDrive])
        backend.start { inv.apply($0) }
        let engine = DiagnosticEngine()
        var runs: [DiagnosticRun] = []
        for rec in inv.presentRecords {
            let probe: DeviceProbe = rec.device.provenance == .synthetic ? backend : FixtureProbe([rec.device])
            let ctx = DiagnosticContext(device: rec.device, identification: rec.identification, probe: probe, deviceKey: rec.stableKey, sleep: { _ in })
            runs.append(await engine.run(testIDs: engine.defaultSuite(for: rec.device, identification: rec.identification), context: ctx))
        }
        let report = ReportGenerator.make(title: "Bench test", runs: runs, records: inv.presentRecords, redactor: Redactor())
        XCTAssertTrue(report.containsSyntheticData)
        let md = ReportGenerator.markdown(report)
        XCTAssertTrue(md.contains("SYNTHETIC DATA PRESENT"))
        XCTAssertFalse(md.contains("4C530001230512345678"))
        let json = String(decoding: try ReportGenerator.json(report), as: UTF8.self)
        XCTAssertFalse(json.contains("4C530001230512345678"))
        XCTAssertTrue(json.contains(SystemTesterReport.schemaID))

        let link = ReportGenerator.deviceLinkReport(report, installationID: "install-1", deviceName: "Bench Mac")
        XCTAssertEqual(link.schema, "hcg.diagnostic-report/1")
        XCTAssertEqual(link.redaction.policy, "hcg.redaction/1")
        XCTAssertEqual(link.problems(), [])
        XCTAssertEqual(link.checks.count, runs.flatMap(\.results).count)
        XCTAssertTrue(link.limitations.first?.contains("SYNTHETIC") ?? false)
        let encoded = String(decoding: try link.encoded(), as: UTF8.self)
        for key in ["\"reportId\"", "\"origin\"", "\"installationId\"", "\"findingCount\"", "\"notTested\""] {
            XCTAssertTrue(encoded.contains(key), key)
        }
    }

    func testLaboratoryPersistsAndComparesOverTime() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hcg-lab-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("lab.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lab = DeviceLaboratory(fileURL: url)
        let inv = DeviceInventory(keySalt: "t")
        inv.apply(.attached(Fixtures.sandisk))
        let rec = inv.presentRecords[0]
        lab.observe(rec, event: "attached")
        lab.recordCompatibility(rec, notes: "Front-left port")
        let session = lab.createSession(title: "Cable comparison")
        let engine = DiagnosticEngine()
        for _ in 0..<2 {
            let ctx = DiagnosticContext(device: rec.device, identification: rec.identification, probe: FixtureProbe([rec.device]), deviceKey: rec.stableKey, sleep: { _ in })
            lab.append(await engine.run(testIDs: ["host.link-speed", "host.registry-latency"], context: ctx), to: session.id)
        }
        XCTAssertEqual(lab.series(deviceKey: rec.stableKey, measurement: "Negotiated link rate").count, 2)
        XCTAssertTrue(lab.measurementNames(deviceKey: rec.stableKey).contains("Mean query latency"))
        XCTAssertFalse(lab.comparison(deviceKeys: [rec.stableKey]).isEmpty)

        let reloaded = DeviceLaboratory(fileURL: url)
        XCTAssertEqual(reloaded.sessions.first?.runs.count, 2)
        XCTAssertEqual(reloaded.profile(rec.stableKey)?.compatibility.first?.notes, "Front-left port")
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("4C530001230512345678"),
                       "Lab storage is keyed by fingerprint, never raw serial")
    }

    func testAuditLogPersists() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hcg-audit-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = AuditLog(fileURL: url)
        log.record(AuditEntry(actor: "user", operation: "host.presence", impact: .readOnly, target: "x", targetKey: "k", decision: "permitted", outcome: "passed", provenance: .hardware))
        log.record(AuditEntry(actor: "user", operation: "host.link-speed", impact: .readOnly, target: "x", targetKey: "k", decision: "permitted", outcome: "passed", provenance: .hardware))
        XCTAssertEqual(AuditLog(fileURL: url).entries.map(\.operation), ["host.presence", "host.link-speed"])
    }
}

final class EcosystemTests: XCTestCase {
    func testInboundRoutesAreNavigationOnly() {
        XCTAssertEqual(SystemTesterRoute.parse(URL(string: "hcgsystemtester://open/diagnostics")!), .diagnostics)
        XCTAssertNil(SystemTesterRoute.parse(URL(string: "hcgsystemtester://open/diagnostics?run=rm%20-rf")!))
        XCTAssertNil(SystemTesterRoute.parse(URL(string: "hcgsystemtester://open/diagnostics/extra")!))
        XCTAssertNil(SystemTesterRoute.parse(URL(string: "hcgsystemtester://exec/diagnostics")!))
        XCTAssertNil(SystemTesterRoute.parse(URL(string: "hcgsystemtester://open/shell")!))
        XCTAssertNil(SystemTesterRoute.parse(URL(string: "other://open/diagnostics")!))
        for route in SystemTesterRoute.allCases { XCTAssertEqual(SystemTesterRoute.parse(route.url), route) }
    }

    func testOutboundDeepLinksAreAllowListed() {
        XCTAssertEqual(TerminalDeepLink.url(destination: "diagnostics")?.absoluteString, "hcgterminal://open/diagnostics")
        XCTAssertEqual(TerminalDeepLink.url(destination: "console", variant: .unleashed)?.absoluteString, "hcgterminal-unleashed://open/console")
        XCTAssertNil(TerminalDeepLink.url(destination: "console?cmd=ls"))
        XCTAssertNil(SentinelDeepLink.url(destination: "../etc"))
        XCTAssertEqual(SentinelDeepLink.url(destination: "capabilities")?.absoluteString, "hcgsentinel://open/capabilities")
    }

    func testCapabilityRegistryIsHonest() {
        XCTAssertEqual(ConnectionCapabilityRegistry.capability(for: .usb)?.support, .live)
        XCTAssertEqual(ConnectionCapabilityRegistry.capability(for: .bluetooth)?.support, .planned)
        XCTAssertFalse(ConnectionCapabilityRegistry.capability(for: .usb)?.verifiableLayers.contains(.functionalCommunication) ?? true)
        XCTAssertEqual(ProtocolCatalog.descriptor("homekit")?.support, .unavailable)
    }
}
