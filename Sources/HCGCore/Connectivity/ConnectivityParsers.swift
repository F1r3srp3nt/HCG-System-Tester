import Foundation

/// SSDP (UPnP discovery) response parsing. Responses are HTTP-like header blocks.
public enum SSDPParser {
    public static let searchRequest = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"

    public static func headers(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n").flatMap({ $0.components(separatedBy: "\n") }).dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            let k = line[..<i].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, out[k] == nil { out[k] = v }
        }
        return out
    }

    /// Converts one response into an endpoint (grouped by USN device UUID). Returns nil for non-responses.
    public static func endpoint(fromResponse text: String, from address: String, at date: Date = Date()) -> ObservedEndpoint? {
        let first = text.components(separatedBy: "\n").first ?? ""
        guard first.uppercased().hasPrefix("HTTP/1.1 200") || first.uppercased().hasPrefix("NOTIFY") else { return nil }
        let h = headers(text)
        let usn = h["usn"] ?? address
        let uuid = usn.components(separatedBy: "::").first ?? usn
        var attrs: [String: String] = ["address": address, "serviceType": h["st"] ?? h["nt"] ?? "upnp"]
        if let s = h["server"] { attrs["server"] = s }
        if let l = h["location"] { attrs["location"] = l }
        // Some vendors identify themselves in SERVER (e.g. "Samsung-Linux/4.1 UPnP/1.0").
        if let s = h["server"]?.lowercased() {
            for vendor in ["samsung", "sony", "lg", "philips", "roku", "microsoft", "google", "amazon", "synology", "netgear", "tp-link", "fritz"] where s.contains(vendor) {
                attrs["manufacturer"] = vendor.capitalized
            }
        }
        return ObservedEndpoint(id: "ssdp:\(uuid)", transport: .ssdp, name: h["server"] ?? address, attributes: attrs,
                                sensitiveKeys: ["address", "location"], firstSeen: date, lastSeen: date, provenance: .hardware)
    }

    /// Minimal UPnP device-description reader: friendlyName, manufacturer, modelName, modelNumber.
    public static func deviceDescription(_ xml: String) -> [String: String] {
        var out: [String: String] = [:]
        for tag in ["friendlyName", "manufacturer", "modelName", "modelNumber", "modelDescription", "deviceType"] {
            guard let open = xml.range(of: "<\(tag)>"), let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { continue }
            let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value.count < 200 { out[tag] = value }
        }
        return out
    }
}

/// Samsung Tizen TV `GET http://<tv>:8001/api/v2/` response (community-documented, read-only).
public enum SamsungTVInfoParser {
    public static func parse(_ data: Data) -> [String: String]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let device = root["device"] as? [String: Any] ?? [:]
        var out: [String: String] = [:]
        func put(_ k: String, _ v: Any?) {
            switch v {
            case let s as String where !s.isEmpty: out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            default: break
            }
        }
        put("name", root["name"] ?? device["name"])
        put("type", root["type"] ?? device["type"])
        put("modelName", device["modelName"])
        put("model", device["model"])
        put("os", device["OS"])
        put("firmwareVersion", device["firmwareVersion"])
        put("resolution", device["resolution"])
        put("frameTVSupport", device["FrameTVSupport"])
        put("tokenAuthSupport", device["TokenAuthSupport"])
        put("networkType", device["networkType"])
        put("wifiMac", device["wifiMac"])
        put("id", device["id"] ?? root["id"])
        put("version", root["version"])
        return out.isEmpty ? nil : out
    }

    public static let sensitiveKeys = ["wifiMac", "id"]
}

/// HCG AI public handoff document (`/.well-known/hcg-ai-handoff.json`).
public struct HCGAIHandoffStatus: Codable, Hashable {
    public enum State: String, Codable { case notPublished, identityOnly, chatAvailable, unreachable, unexpected }
    public var state: State
    public var detail: String
    public var apiBaseURL: String?
    public var checkedAt: Date

    public static let url = "https://ai.hakmicapitalgroup.com/.well-known/hcg-ai-handoff.json"

    public static func parse(status: Int, data: Data, at date: Date = Date()) -> HCGAIHandoffStatus {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 404 {
            let reason = json?["reason"] as? String ?? "The native public OAuth client has not been issued."
            return HCGAIHandoffStatus(state: .notPublished, detail: reason, apiBaseURL: nil, checkedAt: date)
        }
        guard status == 200, let j = json, let api = j["api"] as? [String: Any] else {
            return HCGAIHandoffStatus(state: .unexpected, detail: "HTTP \(status): unexpected response.", apiBaseURL: nil, checkedAt: date)
        }
        let workflows = api["workflows"] as? [String: Any] ?? [:]
        let base = api["baseURL"] as? String
        if workflows["chat"] != nil {
            return HCGAIHandoffStatus(state: .chatAvailable, detail: "Chat workflow published. System Tester still needs its own native client registration before it can use it.", apiBaseURL: base, checkedAt: date)
        }
        return HCGAIHandoffStatus(state: .identityOnly, detail: "Handoff published without a chat workflow (central chat not available).", apiBaseURL: base, checkedAt: date)
    }
}

/// Bluetooth SIG assigned numbers used for labelling (subset).
public enum BLEAssignedNumbers {
    public static let services: [String: String] = [
        "1800": "Generic Access", "1801": "Generic Attribute", "180A": "Device Information", "180F": "Battery",
        "180D": "Heart Rate", "1809": "Health Thermometer", "181A": "Environmental Sensing", "1816": "Cycling Speed and Cadence",
        "1818": "Cycling Power", "1819": "Location and Navigation", "1810": "Blood Pressure", "1808": "Glucose", "FE95": "Xiaomi (member service)",
        "FD6F": "Exposure Notification", "FEAA": "Eddystone"
    ]
    public static let characteristics: [String: String] = [
        "2A29": "Manufacturer Name", "2A24": "Model Number", "2A25": "Serial Number", "2A27": "Hardware Revision",
        "2A26": "Firmware Revision", "2A28": "Software Revision", "2A19": "Battery Level", "2A00": "Device Name"
    ]
    /// Company identifiers (little-endian first two bytes of manufacturer data).
    public static let companies: [UInt16: String] = [
        0x004C: "Apple", 0x0006: "Microsoft", 0x0075: "Samsung", 0x00E0: "Google", 0x0059: "Nordic Semiconductor", 0x02E5: "Espressif",
        0x0157: "Huami", 0x038F: "Xiaomi", 0x012D: "Sony", 0x0087: "Garmin", 0x0171: "Amazon"
    ]
    /// The only characteristics System Tester reads (read-only allow-list).
    public static let readAllowList: Set<String> = ["2A29", "2A24", "2A25", "2A27", "2A26", "2A28", "2A19"]
    public static let sensitiveCharacteristics: Set<String> = ["2A25"]

    public static func shortUUID(_ uuid: String) -> String {
        let u = uuid.uppercased()
        if u.count == 36, u.hasPrefix("0000"), u.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            return String(u.dropFirst(4).prefix(4))
        }
        return u
    }

    public static func company(fromManufacturerData data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let id = UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
        return companies[id] ?? ("Company 0x" + Hex.pad(UInt64(id), digits: 4))
    }
}
