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
