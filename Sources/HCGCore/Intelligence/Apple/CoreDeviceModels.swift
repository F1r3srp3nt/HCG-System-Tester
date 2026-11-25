import Foundation

/// A device as reported by Xcode's CoreDevice (`xcrun devicectl … --json-output`).
/// Parsing is tolerant: every field is optional and unknown fields are ignored.
public struct CoreDeviceRecord: Codable, Hashable {
    public struct Capability: Codable, Hashable { public var name: String; public var featureIdentifier: String }

    public var identifier: String?
    public var name: String?
    public var deviceType: String?
    public var marketingName: String?
    public var productType: String?
    public var hardwareModel: String?
    public var platform: String?
    public var reality: String?
    public var osVersion: String?
    public var osBuild: String?
    public var udid: String?
    public var serialNumber: String?
    public var ecid: String?
    public var internalStorageCapacity: Int64?
    public var cpuType: String?
    public var supportedDeviceFamilies: [Int]
    public var pairingState: String?
    public var transportType: String?
    public var tunnelState: String?
    public var authenticationType: String?
    public var isMobileDeviceOnly: Bool?
    public var lastConnectionDate: String?
    public var developerModeStatus: String?
    public var ddiServicesAvailable: Bool?
    public var bootState: String?
    public var visibilityClass: String?
    public var capabilities: [Capability]

    public var isPaired: Bool { pairingState?.lowercased() == "paired" }
    public var isWired: Bool { transportType?.lowercased() == "wired" }
    public var isNetwork: Bool { transportType?.lowercased() == "localnetwork" }

    /// UDID with separators removed, upper-cased — the form Apple devices use as their USB serial number.
    public var normalizedUDID: String? { udid.map(CoreDeviceRecord.normalize) }

    public static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: "").uppercased()
    }

    init(dict d: [String: Any]) {
        let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
        let dev = d["deviceProperties"] as? [String: Any] ?? [:]
        let conn = d["connectionProperties"] as? [String: Any] ?? [:]
        func str(_ m: [String: Any], _ k: String) -> String? {
            switch m[k] {
            case let s as String: return s.isEmpty ? nil : s
            case let n as NSNumber: return n.stringValue
            default: return nil
            }
        }
        identifier = str(d, "identifier")
        visibilityClass = str(d, "visibilityClass")
        name = str(dev, "name")
        osVersion = str(dev, "osVersionNumber")
        osBuild = str(dev, "osBuildUpdate")
        developerModeStatus = str(dev, "developerModeStatus")
        ddiServicesAvailable = dev["ddiServicesAvailable"] as? Bool
        bootState = str(dev, "bootState")
        deviceType = str(hw, "deviceType")
        marketingName = str(hw, "marketingName")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
        productType = str(hw, "productType")
        hardwareModel = str(hw, "hardwareModel")
        platform = str(hw, "platform")
        reality = str(hw, "reality")
        udid = str(hw, "udid")
        serialNumber = str(hw, "serialNumber")
        ecid = str(hw, "ecid")
        internalStorageCapacity = (hw["internalStorageCapacity"] as? NSNumber)?.int64Value
        cpuType = (hw["cpuType"] as? [String: Any]).flatMap { str($0, "name") }
        supportedDeviceFamilies = (hw["supportedDeviceFamilies"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        pairingState = str(conn, "pairingState")
        transportType = str(conn, "transportType")
        tunnelState = str(conn, "tunnelState")
        authenticationType = str(conn, "authenticationType")
        isMobileDeviceOnly = conn["isMobileDeviceOnly"] as? Bool
        lastConnectionDate = str(conn, "lastConnectionDate")
        capabilities = (d["capabilities"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = c["featureIdentifier"] as? String else { return nil }
            return Capability(name: (c["name"] as? String) ?? id, featureIdentifier: id)
        }
    }

    /// Fills gaps in `self` with values from a more detailed record of the same device.
    public func merged(with other: CoreDeviceRecord) -> CoreDeviceRecord {
        var m = self
        m.identifier = m.identifier ?? other.identifier
        m.name = other.name ?? m.name
        m.deviceType = other.deviceType ?? m.deviceType
        m.marketingName = other.marketingName ?? m.marketingName
        m.productType = other.productType ?? m.productType
        m.hardwareModel = other.hardwareModel ?? m.hardwareModel
        m.platform = other.platform ?? m.platform
        m.osVersion = other.osVersion ?? m.osVersion
        m.osBuild = other.osBuild ?? m.osBuild
        m.udid = other.udid ?? m.udid
        m.serialNumber = other.serialNumber ?? m.serialNumber
        m.ecid = other.ecid ?? m.ecid
        m.internalStorageCapacity = other.internalStorageCapacity ?? m.internalStorageCapacity
        m.cpuType = other.cpuType ?? m.cpuType
        m.pairingState = other.pairingState ?? m.pairingState
        m.transportType = other.transportType ?? m.transportType
        m.tunnelState = other.tunnelState ?? m.tunnelState
        m.developerModeStatus = other.developerModeStatus ?? m.developerModeStatus
        m.ddiServicesAvailable = other.ddiServicesAvailable ?? m.ddiServicesAvailable
        m.bootState = other.bootState ?? m.bootState
        if !other.capabilities.isEmpty { m.capabilities = other.capabilities }
        return m
    }
}

/// Parses devicectl JSON documents (`{"info": {...}, "result": {...}}` or `{"error": {...}}`).
public enum DevicectlOutput {
    public struct Document {
        public var outcome: String?
        public var jsonVersion: Int?
        public var devicectlVersion: String?
        public var result: Any?
        public var errorDescription: String?
        public var isSuccess: Bool { errorDescription == nil && (outcome == nil || outcome == "success") }
    }

    public static func parse(_ data: Data) -> Document? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let info = root["info"] as? [String: Any]
        var doc = Document(outcome: info?["outcome"] as? String,
                           jsonVersion: (info?["jsonVersion"] as? NSNumber)?.intValue,
                           devicectlVersion: info?["version"] as? String,
                           result: root["result"], errorDescription: nil)
        if let error = root["error"] {
            doc.errorDescription = localizedDescription(in: error) ?? "devicectl reported an error."
        }
        return doc
    }

    public static func devices(_ data: Data) -> [CoreDeviceRecord] {
        guard let doc = parse(data), let result = doc.result as? [String: Any] else { return [] }
        return (result["devices"] as? [[String: Any]] ?? []).map(CoreDeviceRecord.init(dict:))
    }

    /// `device info details` output: the result is the device itself (or wraps one).
    public static func deviceDetails(_ data: Data) -> CoreDeviceRecord? {
        guard let doc = parse(data), let result = doc.result as? [String: Any] else { return nil }
        if result["hardwareProperties"] != nil || result["deviceProperties"] != nil { return CoreDeviceRecord(dict: result) }
        if let device = result["device"] as? [String: Any] { return CoreDeviceRecord(dict: device) }
        if let first = (result["devices"] as? [[String: Any]])?.first { return CoreDeviceRecord(dict: first) }
        return nil
    }

    /// Flattens a result object into "key = value" pairs (used for lock state, whose schema is not documented).
    public static func flatResult(_ data: Data) -> [(String, String)] {
        guard let doc = parse(data), let result = doc.result as? [String: Any] else { return [] }
        return result.keys.sorted().compactMap { k in
            switch result[k] {
            case let b as Bool: return (k, b ? "true" : "false")
            case let n as NSNumber: return (k, n.stringValue)
            case let s as String: return (k, s)
            default: return nil
            }
        }
    }

    public static func apps(_ data: Data) -> [(name: String, bundleID: String, version: String?)] {
        guard let doc = parse(data), let result = doc.result as? [String: Any],
              let apps = result["apps"] as? [[String: Any]] else { return [] }
        return apps.compactMap { a -> (name: String, bundleID: String, version: String?)? in
            guard let id = a["bundleIdentifier"] as? String else { return nil }
            return ((a["name"] as? String) ?? id, id, a["bundleVersion"] as? String ?? a["version"] as? String)
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func localizedDescription(in value: Any) -> String? {
        if let d = value as? [String: Any] {
            if let s = d["NSLocalizedDescription"] as? String { return s }
            if let wrapped = d["NSLocalizedDescription"] as? [String: Any], let s = wrapped["string"] as? String { return s }
            for key in d.keys.sorted() {
                if let found = localizedDescription(in: d[key]!) { return found }
            }
        } else if let a = value as? [Any] {
            for v in a { if let found = localizedDescription(in: v) { return found } }
        }
        return nil
    }
}

/// `ideviceinfo -x` (libimobiledevice) prints XML property lists.
public enum LockdownOutput {
    public static func plist(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    public static func string(_ d: [String: Any], _ k: String) -> String? {
        switch d[k] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    public static func int64(_ d: [String: Any], _ k: String) -> Int64? { (d[k] as? NSNumber)?.int64Value }
}

/// Small, verifiable facts about Apple models, from Apple's published technical specifications.
/// Used only to explain connection limits; never to identify a device.
public enum AppleModelFacts {
    public struct Facts: Hashable { public var name: String; public var usbCapability: String; public var usbMaxSpeed: USBSpeed? }

    public static let table: [String: Facts] = [
        "iPhone15,4": Facts(name: "iPhone 15", usbCapability: "USB 2 (480 Mbit/s)", usbMaxSpeed: .high),
        "iPhone15,5": Facts(name: "iPhone 15 Plus", usbCapability: "USB 2 (480 Mbit/s)", usbMaxSpeed: .high),
        "iPhone16,1": Facts(name: "iPhone 15 Pro", usbCapability: "USB 3 (up to 10 Gbit/s) with a USB 3 cable", usbMaxSpeed: .superSpeedPlus),
        "iPhone16,2": Facts(name: "iPhone 15 Pro Max", usbCapability: "USB 3 (up to 10 Gbit/s) with a USB 3 cable", usbMaxSpeed: .superSpeedPlus),
        "iPhone17,1": Facts(name: "iPhone 16 Pro", usbCapability: "USB 3 (up to 10 Gbit/s) with a USB 3 cable", usbMaxSpeed: .superSpeedPlus),
        "iPhone17,2": Facts(name: "iPhone 16 Pro Max", usbCapability: "USB 3 (up to 10 Gbit/s) with a USB 3 cable", usbMaxSpeed: .superSpeedPlus),
        "iPhone17,3": Facts(name: "iPhone 16", usbCapability: "USB 2 (480 Mbit/s)", usbMaxSpeed: .high),
        "iPhone17,4": Facts(name: "iPhone 16 Plus", usbCapability: "USB 2 (480 Mbit/s)", usbMaxSpeed: .high),
        "iPad16,3": Facts(name: "iPad Pro 11-inch (M4)", usbCapability: "Thunderbolt / USB 4", usbMaxSpeed: nil),
        "iPad16,4": Facts(name: "iPad Pro 11-inch (M4)", usbCapability: "Thunderbolt / USB 4", usbMaxSpeed: nil),
        "iPad16,5": Facts(name: "iPad Pro 13-inch (M4)", usbCapability: "Thunderbolt / USB 4", usbMaxSpeed: nil),
        "iPad16,6": Facts(name: "iPad Pro 13-inch (M4)", usbCapability: "Thunderbolt / USB 4", usbMaxSpeed: nil)
    ]
}
