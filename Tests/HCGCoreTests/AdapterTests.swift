import XCTest
@testable import HCGCore

final class AdapterTests: XCTestCase {
    func testBuiltInManifestsAreValid() {
        for m in BuiltInAdapters.all {
            let errors = ManifestValidator.validate(m, origin: .builtIn).filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty, "\(m.id): \(errors)")
        }
    }

    func sampleManifest() -> AdapterManifest {
        AdapterManifest(
            id: "com.example.adapter.widget", name: "Widget", version: SemanticVersion(1, 0, 0), publisher: "Example",
            summary: "Test", deviceFamilies: [.robotics], connectionTypes: [.usb], protocols: ["usb.descriptor"],
            match: DeviceMatchRules(vendorIDs: [0x9999]), permissions: [.readDeviceDescriptors],
            operations: [DiagnosticOperationDescriptor(id: "widget.presence", name: "Presence", hostOperation: "host.presence",
                                                       category: .connectionHealth, summary: "Presence")])
    }

    func testImportedManifestRoundTripsWithHexIdentifiers() throws {
        let json = """
        {"schema":"hcg.adapter-manifest/1","id":"com.example.adapter.widget","name":"Widget","version":"1.2.3","publisher":"Example",
         "deviceFamilies":["robotics"],"connectionTypes":["usb"],"protocols":["usb.descriptor"],
         "match":{"vendorIDs":["0x9999"],"productIDs":[1]},"permissions":["readDeviceDescriptors"],
         "operations":[{"id":"widget.presence","name":"Presence","hostOperation":"host.presence","category":"connectionHealth",
                        "impact":"readOnly","requiredCapabilities":[],"summary":"Presence","timeoutSeconds":10}]}
        """
        let registry = AdapterRegistry()
        let entry = try registry.importManifest(data: Data(json.utf8))
        XCTAssertEqual(entry.manifest.version, SemanticVersion(1, 2, 3))
        XCTAssertEqual(entry.manifest.match.vendorIDs, [0x9999])
        XCTAssertEqual(entry.trust, .untrusted)
        XCTAssertFalse(entry.enabled, "Imported adapters are never enabled automatically")
        let reencoded = try AdapterManifest.decode(try entry.manifest.encoded())
        XCTAssertEqual(reencoded, entry.manifest)
    }

    func testValidatorRejectsUnsafeManifests() {
        var m = sampleManifest()
        m.execution = .builtIn
        XCTAssertTrue(ManifestValidator.validate(m, origin: .imported).contains { $0.path == "execution" && $0.severity == .error })

        m = sampleManifest()
        m.operations[0].hostOperation = "shell.exec"
        XCTAssertTrue(ManifestValidator.validate(m, origin: .imported).contains { $0.path == "operations[0].hostOperation" })

        m = sampleManifest()
        m.operations[0].hostOperation = "synthetic.fault-injection"
        m.operations[0].impact = .readOnly
        let issues = ManifestValidator.validate(m, origin: .imported)
        XCTAssertTrue(issues.contains { $0.path == "operations[0].impact" }, "Understated impact must be rejected")

        m = sampleManifest()
        m.configuration = ConfigurationSchema(fields: [ConfigField(key: "token", label: "Token", type: .string, defaultValue: "abc", secret: true)])
        let cfg = ManifestValidator.validate(m, origin: .imported)
        XCTAssertTrue(cfg.contains { $0.path == "configuration.fields[0].defaultValue" })
        XCTAssertTrue(cfg.contains { $0.path == "configuration.fields[0].secret" })

        m = sampleManifest()
        m.id = "com.hakmicapitalgroup.adapter.fake"
        XCTAssertTrue(ManifestValidator.validate(m, origin: .imported).contains { $0.path == "id" })

        m = sampleManifest()
        m.match = DeviceMatchRules()
        XCTAssertTrue(ManifestValidator.validate(m, origin: .imported).contains { $0.path == "match" })

        m = sampleManifest()
        m.protocols = ["made.up"]
        XCTAssertTrue(ManifestValidator.validate(m, origin: .imported).contains { $0.path == "protocols[0]" })

        XCTAssertTrue(ManifestValidator.isValid(sampleManifest(), origin: .imported))
    }

    func testConfigurationSchemaValidation() {
        let schema = ConfigurationSchema(fields: [
            ConfigField(key: "baud", label: "Baud", type: .integer, required: true, minimum: 300, maximum: 3_000_000),
            ConfigField(key: "parity", label: "Parity", type: .choice, defaultValue: "none", choices: ["none", "even", "odd"])
        ])
        XCTAssertEqual(schema.validate(["baud": "115200"]), [])
        XCTAssertFalse(schema.validate([:]).isEmpty)
        XCTAssertFalse(schema.validate(["baud": "12"]).isEmpty)
        XCTAssertFalse(schema.validate(["baud": "9600", "parity": "mark"]).isEmpty)
        XCTAssertFalse(schema.validate(["baud": "9600", "unknown": "x"]).isEmpty)
    }

    func testCompatibilityAndApprovalFlow() throws {
        let registry = AdapterRegistry()
        let engine = IdentificationEngine()
        let storage = Fixtures.sandisk
        let compat = registry.compatibility(for: storage, identification: engine.identify(storage))
        XCTAssertEqual(compat.first { $0.adapterID == BuiltInAdapters.usbStorage.id }?.status, .compatible)
        XCTAssertTrue(compat.contains { $0.adapterID == BuiltInAdapters.usbCore.id })
        XCTAssertFalse(compat.contains { $0.adapterID == BuiltInAdapters.playStation.id })

        try registry.register(sampleManifest(), origin: .imported)
        let mystery = Fixtures.mystery
        var c = registry.compatibility(for: mystery, identification: engine.identify(mystery))
        XCTAssertEqual(c.first { $0.adapterID == "com.example.adapter.widget" }?.status, .notExecutable)
        try registry.approve("com.example.adapter.widget")
        c = registry.compatibility(for: mystery, identification: engine.identify(mystery))
        XCTAssertEqual(c.first { $0.adapterID == "com.example.adapter.widget" }?.status, .compatible)

        var older = sampleManifest()
        older.version = SemanticVersion(0, 9, 0)
        XCTAssertThrowsError(try registry.register(older, origin: .imported))
        XCTAssertThrowsError(try registry.register(BuiltInAdapters.usbCore, origin: .imported))
        XCTAssertThrowsError(try registry.remove(BuiltInAdapters.usbCore.id))
    }

    func testPermissionHandling() throws {
        let registry = AdapterRegistry()
        var m = sampleManifest()
        m.connectionTypes = [.usb]
        m.permissions = [.readDeviceDescriptors, .openSerialPort]
        m.lifecycle = ConnectionLifecycle(stages: [.discover, .identify, .authorize, .open, .diagnose, .close])
        try registry.register(m, origin: .imported)
        let store = AuthorizationStore()
        let key = "0x9999:0x0001:loc-1"

        XCTAssertEqual(store.decision(for: registry.adapter(m.id)!, deviceKey: key, requested: [.readDeviceDescriptors]), .deniedUntrustedAdapter)
        try registry.approve(m.id)
        let a = registry.adapter(m.id)!
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.readDeviceDescriptors]), .granted)
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.openSerialPort]), .requiresUserGrant([.openSerialPort]))
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.changeDeviceConfiguration]), .deniedUndeclaredPermission([.changeDeviceConfiguration]), "Undeclared permissions are refused")
        store.grant(PermissionGrant(deviceKey: key, adapterID: m.id, permission: .openSerialPort))
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.openSerialPort]), .requiresUserGrant([.openSerialPort]), "Device must also be authorised")
        store.authorizeDevice(key)
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.openSerialPort]), .granted)
        let expired = PermissionGrant(deviceKey: key, adapterID: m.id, permission: .openSerialPort, expiresAt: Date(timeIntervalSinceNow: -1))
        store.grant(expired)
        XCTAssertEqual(store.decision(for: a, deviceKey: key, requested: [.openSerialPort]), .requiresUserGrant([.openSerialPort]))
        store.revokeDevice(key)
        XCTAssertFalse(store.isDeviceAuthorized(key))
    }
}
