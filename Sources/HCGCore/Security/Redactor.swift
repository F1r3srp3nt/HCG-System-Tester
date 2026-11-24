import Foundation

/// User-controlled privacy settings for identifiers shown in the UI and written to exports.
public struct PrivacySettings: Codable, Hashable {
    public var redactSerialNumbers: Bool
    public var redactNetworkIdentifiers: Bool
    public var redactUserPaths: Bool
    public var redactHostName: Bool
    /// Hides serial numbers in the live interface as well (not only in exports).
    public var hideSerialNumbersInInterface: Bool

    public init(redactSerialNumbers: Bool = true, redactNetworkIdentifiers: Bool = true, redactUserPaths: Bool = true,
                redactHostName: Bool = true, hideSerialNumbersInInterface: Bool = false) {
        self.redactSerialNumbers = redactSerialNumbers
        self.redactNetworkIdentifiers = redactNetworkIdentifiers
        self.redactUserPaths = redactUserPaths
        self.redactHostName = redactHostName
        self.hideSerialNumbersInInterface = hideSerialNumbersInInterface
    }

    public static let standard = PrivacySettings()
}

/// Redacts sensitive data from diagnostic logs and reports.
///
/// Rules are compatible with HCG Device Link's `hcg.redaction/1` (credentials, tokens,
/// private keys, URL credentials) plus System Tester's identifier rules (serial numbers,
/// MAC/IP addresses, e-mail addresses, user home paths, host name).
public struct Redactor {
    public static let placeholder = "[REDACTED]"

    public var settings: PrivacySettings
    /// Exact sensitive values known at runtime (e.g. device serial numbers, host name).
    public var knownSecrets: [String: String]

    public init(settings: PrivacySettings = .standard, knownSecrets: [String: String] = [:]) {
        self.settings = settings
        self.knownSecrets = knownSecrets
    }

    /// Registers a device serial number so every occurrence is masked.
    public mutating func registerSerialNumber(_ serial: String?) {
        guard settings.redactSerialNumbers, let s = serial, s.count >= 4 else { return }
        knownSecrets[s] = "[REDACTED SERIAL]"
    }

    public mutating func registerHostName(_ name: String?) {
        guard settings.redactHostName, let n = name, n.count >= 3 else { return }
        knownSecrets[n] = "[REDACTED HOST]"
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error caught by tests.
        try! NSRegularExpression(pattern: pattern)
    }

    static let credentialRules: [(NSRegularExpression, String)] = [
        (regex(#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#), "[REDACTED PRIVATE KEY]"),
        (regex(#"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#), placeholder),
        (regex(#"(?i)\b(bearer|basic|digest)\s+(?=[A-Za-z0-9._~+/=-]*[0-9+/=])[A-Za-z0-9._~+/=-]{6,}"#), "$1 " + placeholder),
        (regex(#"([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s:@\[\]]+:[^/\s@\[\]]+@"#), "$1" + placeholder + "@"),
        (regex(#"(?i)("?(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization|cookie)"?\s*[:=]\s*"?)(?!\[REDACTED)[^"\s&,;]+"#), "$1" + placeholder)
    ]

    static let networkRules: [(NSRegularExpression, String)] = [
        (regex(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#), "[REDACTED EMAIL]"),
        (regex(#"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#), "[REDACTED MAC]"),
        (regex(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#), "[REDACTED IP]")
    ]

    static let pathRules: [(NSRegularExpression, String)] = [
        (regex(#"/Users/[^/\s]+"#), "/Users/[REDACTED]"),
        (regex(#"/home/[^/\s]+"#), "/home/[REDACTED]")
    ]

    static let serialRules: [(NSRegularExpression, String)] = [
        (regex(#"(?i)((?:serial(?: number)?|usb serial number|kUSBSerialNumberString|sn)\s*[:=]\s*"?)[A-Za-z0-9._-]{4,}"#), "$1[REDACTED SERIAL]")
    ]

    public func redact(_ text: String) -> String {
        var out = text
        // Longest first so overlapping values are fully masked.
        for (value, replacement) in knownSecrets.sorted(by: { $0.key.count > $1.key.count }) {
            out = out.replacingOccurrences(of: value, with: replacement)
        }
        var rules = Self.credentialRules
        if settings.redactNetworkIdentifiers { rules += Self.networkRules }
        if settings.redactUserPaths { rules += Self.pathRules }
        if settings.redactSerialNumbers { rules += Self.serialRules }
        for (re, template) in rules {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return out
    }

    public func redact(_ texts: [String]) -> [String] { texts.map { redact($0) } }

    /// Masks a serial number for display, keeping the last 2 characters.
    public static func maskSerial(_ serial: String) -> String {
        guard serial.count > 2 else { return "••" }
        return String(repeating: "•", count: min(8, serial.count - 2)) + serial.suffix(2)
    }

    /// Returns a copy of the device with sensitive raw properties removed or masked.
    public func redactDevice(_ device: DiscoveredDevice) -> DiscoveredDevice {
        var d = device
        if settings.redactSerialNumbers {
            if let s = d.usb?.serialNumber { d.usb?.serialNumber = "[REDACTED SERIAL] (" + Fingerprint.short(s) + ")" }
            for key in ["USB Serial Number", "kUSBSerialNumberString"] where d.rawProperties[key] != nil {
                d.rawProperties[key] = "[REDACTED SERIAL]"
            }
        }
        d.name = redact(d.name)
        d.rawProperties = d.rawProperties.mapValues { redact($0) }
        if settings.redactUserPaths, var usb = d.usb {
            usb.serialDevicePaths = usb.serialDevicePaths.map { redact($0) }
            d.usb = usb
        }
        return d
    }
}
