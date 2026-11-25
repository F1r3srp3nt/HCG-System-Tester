#if os(macOS)
import Foundation
import HCGCore

/// User preferences, persisted in UserDefaults.
struct AppSettings: Codable, Equatable {
    var privacy = PrivacySettings()
    /// Synthetic fixtures are opt-in and always labelled.
    var syntheticFixturesEnabled = false
    var hardwareDiscoveryEnabled = true
    /// Forces reduced motion in addition to the system setting.
    var reduceMotion = false
    var recordConnectionsInLaboratory = true
    var showDisconnectedDevices = true
    /// Per-installation salt for privacy-preserving device fingerprints.
    var fingerprintSalt = UUID().uuidString
    /// Identifies this installation in exported hcg.diagnostic-report/1 documents.
    var installationID = UUID().uuidString.lowercased()
    // Live Device Monitor
    var monitorEnabled = true
    /// Presence / host-query sampling interval (cheap IOKit re-reads).
    var monitorIntervalSeconds = 5.0
    /// Live CoreDevice response measurements for paired Apple devices (spawns devicectl).
    var monitorCoreDevice = true
    var coreDeviceIntervalSeconds = 60.0
    /// Periodic refresh of device intelligence (never starts pairing or prompts).
    var autoRefreshIntelligence = true
    var intelligenceRefreshSeconds = 120.0
    /// Mask UDID, ECID and serial numbers in the device workspace.
    var maskDeviceIdentifiers = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case privacy, syntheticFixturesEnabled, hardwareDiscoveryEnabled, reduceMotion, recordConnectionsInLaboratory, showDisconnectedDevices
        case fingerprintSalt, installationID, monitorEnabled, monitorIntervalSeconds, monitorCoreDevice, coreDeviceIntervalSeconds
        case autoRefreshIntelligence, intelligenceRefreshSeconds, maskDeviceIdentifiers
    }

    /// Tolerant decoding so settings saved by earlier versions keep their salt and installation ID.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        privacy = try c.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? d.privacy
        syntheticFixturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .syntheticFixturesEnabled) ?? d.syntheticFixturesEnabled
        hardwareDiscoveryEnabled = try c.decodeIfPresent(Bool.self, forKey: .hardwareDiscoveryEnabled) ?? d.hardwareDiscoveryEnabled
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        recordConnectionsInLaboratory = try c.decodeIfPresent(Bool.self, forKey: .recordConnectionsInLaboratory) ?? d.recordConnectionsInLaboratory
        showDisconnectedDevices = try c.decodeIfPresent(Bool.self, forKey: .showDisconnectedDevices) ?? d.showDisconnectedDevices
        fingerprintSalt = try c.decodeIfPresent(String.self, forKey: .fingerprintSalt) ?? d.fingerprintSalt
        installationID = try c.decodeIfPresent(String.self, forKey: .installationID) ?? d.installationID
        monitorEnabled = try c.decodeIfPresent(Bool.self, forKey: .monitorEnabled) ?? d.monitorEnabled
        monitorIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .monitorIntervalSeconds) ?? d.monitorIntervalSeconds
        monitorCoreDevice = try c.decodeIfPresent(Bool.self, forKey: .monitorCoreDevice) ?? d.monitorCoreDevice
        coreDeviceIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .coreDeviceIntervalSeconds) ?? d.coreDeviceIntervalSeconds
        autoRefreshIntelligence = try c.decodeIfPresent(Bool.self, forKey: .autoRefreshIntelligence) ?? d.autoRefreshIntelligence
        intelligenceRefreshSeconds = try c.decodeIfPresent(Double.self, forKey: .intelligenceRefreshSeconds) ?? d.intelligenceRefreshSeconds
        maskDeviceIdentifiers = try c.decodeIfPresent(Bool.self, forKey: .maskDeviceIdentifiers) ?? d.maskDeviceIdentifiers
    }

    static let defaultsKey = "com.hakmicapitalgroup.systemtester.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            let fresh = AppSettings()
            fresh.save()
            return fresh
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(HCGSystemTesterInfo.bundleIdentifier, isDirectory: true)
    }
    static var laboratoryFile: URL { supportDirectory.appendingPathComponent("laboratory.json") }
    static var auditFile: URL { supportDirectory.appendingPathComponent("audit.jsonl") }
    static var adaptersDirectory: URL { supportDirectory.appendingPathComponent("Adapters", isDirectory: true) }
    static var reportsDirectory: URL { supportDirectory.appendingPathComponent("Reports", isDirectory: true) }
}
#endif
