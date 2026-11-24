import Foundation

public struct ValidationIssue: Codable, Hashable, Identifiable, CustomStringConvertible {
    public enum Severity: String, Codable, Hashable { case error, warning }
    public var severity: Severity
    public var path: String
    public var message: String

    public var id: String { "\(severity.rawValue):\(path):\(message)" }
    public var description: String { "[\(severity.rawValue)] \(path): \(message)" }

    public init(_ severity: Severity, _ path: String, _ message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public enum AdapterOrigin: String, Codable, Hashable {
    case builtIn
    case imported
    case developerStudio
}

/// Validates adapter manifests before they can be registered.
public enum ManifestValidator {
    static let idPattern = try! NSRegularExpression(pattern: #"^[a-z0-9]+(\.[a-z0-9-]+){2,}$"#)
    static let opIDPattern = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9.-]{1,63}$"#)

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    public static func validate(_ m: AdapterManifest, origin: AdapterOrigin, hostVersion: SemanticVersion = SemanticVersion(string: HCGSystemTesterInfo.version)!) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ path: String, _ msg: String) { issues.append(ValidationIssue(.error, path, msg)) }
        func warning(_ path: String, _ msg: String) { issues.append(ValidationIssue(.warning, path, msg)) }

        if m.schema != AdapterManifest.currentSchema { error("schema", "Unsupported schema \"\(m.schema)\"; expected \(AdapterManifest.currentSchema).") }
        if !matches(idPattern, m.id) { error("id", "Must be a lowercase reverse-DNS identifier such as com.example.adapter.widget.") }
        if m.name.trimmingCharacters(in: .whitespaces).isEmpty || m.name.count > 80 { error("name", "Must be 1–80 characters.") }
        if m.publisher.trimmingCharacters(in: .whitespaces).isEmpty { error("publisher", "Publisher is required.") }
        if m.deviceFamilies.isEmpty { error("deviceFamilies", "Declare at least one device family.") }
        if m.connectionTypes.isEmpty { error("connectionTypes", "Declare at least one connection type.") }

        // Imported adapters can never claim to be compiled into the host.
        if m.execution == .builtIn && origin != .builtIn {
            error("execution", "Only first-party adapters compiled into System Tester may use the builtIn execution model. Imported adapters must be declarative.")
        }
        if origin != .builtIn && m.id.hasPrefix("com.hakmicapitalgroup.") {
            error("id", "The com.hakmicapitalgroup namespace is reserved for first-party adapters.")
        }

        let known = ProtocolCatalog.knownIDs
        for (i, p) in m.protocols.enumerated() where !known.contains(p) {
            error("protocols[\(i)]", "Unknown protocol \"\(p)\". Protocols must come from the System Tester protocol catalog.")
        }
        if m.match.isEmpty && origin != .builtIn {
            error("match", "Imported adapters must declare match rules so they never apply to every device.")
        }
        for (i, t) in m.match.interfaceTriples.enumerated() {
            let parts = t.split(separator: ".")
            if parts.count != 3 || parts.contains(where: { $0.count != 2 || UInt8($0, radix: 16) == nil }) {
                error("match.interfaceTriples[\(i)]", "Must be written CC.SS.PP in hexadecimal, e.g. FF.42.01.")
            }
        }

        // Operations
        var seenOps = Set<String>()
        for (i, op) in m.operations.enumerated() {
            let path = "operations[\(i)]"
            if !matches(opIDPattern, op.id) { error("\(path).id", "Operation IDs are 2–64 lowercase characters, digits, dots or dashes.") }
            if !seenOps.insert(op.id).inserted { error("\(path).id", "Duplicate operation ID \"\(op.id)\".") }
            guard let host = HostOperationCatalog.descriptor(op.hostOperation) else {
                error("\(path).hostOperation", "\"\(op.hostOperation)\" is not a host-implemented operation. Adapters cannot supply their own code.")
                continue
            }
            if op.impact < host.impact {
                error("\(path).impact", "Declared impact \(op.impact.rawValue) understates the host operation's impact (\(host.impact.rawValue)).")
            }
            if op.impact != .readOnly && (op.effects ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                error("\(path).effects", "Non read-only operations must describe their effects for the authorisation prompt.")
            }
            if op.impact == .stateChanging {
                if !m.permissions.contains(.changeDeviceConfiguration) {
                    error("\(path).impact", "State-changing operations require the changeDeviceConfiguration permission.")
                }
                if !m.lifecycle.requiresExplicitAuthorization {
                    error("lifecycle.requiresExplicitAuthorization", "Must be true when any operation is state-changing.")
                }
            }
            if op.timeoutSeconds <= 0 || op.timeoutSeconds > 600 { error("\(path).timeoutSeconds", "Must be between 0 and 600 seconds.") }
            let missingCaps = host.requiredCapabilities.filter { !op.requiredCapabilities.contains($0) }
            if !missingCaps.isEmpty {
                warning("\(path).requiredCapabilities", "Host operation also requires: \(missingCaps.map(\.rawValue).joined(separator: ", ")).")
            }
        }
        if m.operations.isEmpty { warning("operations", "The adapter declares no diagnostic operations.") }

        // Permissions
        if Set(m.permissions).count != m.permissions.count { warning("permissions", "Duplicate permissions.") }
        if m.permissions.contains(.changeDeviceConfiguration) && !m.operations.contains(where: { $0.impact == .stateChanging }) {
            warning("permissions", "changeDeviceConfiguration is requested but no operation is state-changing. Request only what you use.")
        }
        if m.permissions.contains(.networkConnect) && !m.connectionTypes.contains(where: { [.localNetwork, .ethernet, .remoteAuthenticated, .manufacturerAPI].contains($0) }) {
            error("permissions", "networkConnect requires a network connection type.")
        }

        // Configuration
        var seenKeys = Set<String>()
        for (i, f) in m.configuration.fields.enumerated() {
            let path = "configuration.fields[\(i)]"
            if !seenKeys.insert(f.key).inserted { error("\(path).key", "Duplicate key \"\(f.key)\".") }
            if f.secret && f.defaultValue != nil { error("\(path).defaultValue", "Secret fields may not have default values.") }
            if f.secret && !m.permissions.contains(.useStoredCredential) { error("\(path).secret", "Secret fields require the useStoredCredential permission.") }
            if f.type == .choice && (f.choices ?? []).isEmpty { error("\(path).choices", "Choice fields need at least one choice.") }
            if let d = f.defaultValue, let problem = f.problem(with: d) { error("\(path).defaultValue", "Default is invalid: \(problem).") }
            if let lo = f.minimum, let hi = f.maximum, lo > hi { error("\(path)", "minimum is greater than maximum.") }
        }

        // Compatibility
        if !m.compatibility.platforms.contains("macOS") { error("compatibility.platforms", "This host only runs macOS adapters.") }
        if m.compatibility.minimumHostVersion > hostVersion {
            error("compatibility.minimumHostVersion", "Requires System Tester \(m.compatibility.minimumHostVersion); this is \(hostVersion).")
        }

        // Health checks & lifecycle
        for (i, h) in m.healthChecks.enumerated() {
            guard let host = HostOperationCatalog.descriptor(h.hostOperation) else {
                error("healthChecks[\(i)].hostOperation", "\"\(h.hostOperation)\" is not a host-implemented operation.")
                continue
            }
            if host.impact != .readOnly { error("healthChecks[\(i)]", "Health checks must be read-only.") }
            if h.intervalSeconds < 5 { error("healthChecks[\(i)].intervalSeconds", "Health checks may not run more often than every 5 seconds.") }
        }
        if m.lifecycle.stages.first != .discover { warning("lifecycle.stages", "Lifecycles normally start with discover.") }
        if m.permissions.contains(where: \.isPrivileged) && !m.lifecycle.stages.contains(.authorize) {
            error("lifecycle.stages", "Adapters requesting privileged permissions must include an authorize stage.")
        }

        // Contributed profiles
        for (i, p) in m.profiles.enumerated() {
            if p.match.isEmpty { error("profiles[\(i)].match", "Profiles need match rules.") }
            if origin != .builtIn && !p.id.hasPrefix(m.id) { warning("profiles[\(i)].id", "Profile IDs should be prefixed with the adapter ID.") }
        }
        return issues
    }

    public static func isValid(_ m: AdapterManifest, origin: AdapterOrigin) -> Bool {
        !validate(m, origin: origin).contains { $0.severity == .error }
    }
}
