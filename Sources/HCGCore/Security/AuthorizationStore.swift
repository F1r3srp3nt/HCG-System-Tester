import Foundation

/// A user's explicit grant of a privileged permission to one adapter for one device.
public struct PermissionGrant: Codable, Hashable {
    public var deviceKey: String
    public var adapterID: String
    public var permission: AdapterPermission
    public var grantedAt: Date
    public var expiresAt: Date?

    public init(deviceKey: String, adapterID: String, permission: AdapterPermission, grantedAt: Date = Date(), expiresAt: Date? = nil) {
        self.deviceKey = deviceKey
        self.adapterID = adapterID
        self.permission = permission
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }

    public func isValid(at date: Date = Date()) -> Bool { expiresAt.map { date < $0 } ?? true }
}

public enum PermissionDecision: Equatable {
    case granted
    case requiresUserGrant([AdapterPermission])
    case deniedUntrustedAdapter
    case deniedDisabledAdapter
    case deniedUndeclaredPermission([AdapterPermission])
}

/// Capability-based permission broker. Non-privileged permissions are implied for
/// trusted, enabled adapters; privileged permissions need an explicit per-device grant.
public final class AuthorizationStore {
    public private(set) var grants: [PermissionGrant]
    /// Devices the user explicitly authorised for sessions (beyond read-only discovery).
    public private(set) var authorizedDevices: Set<String>

    public init(grants: [PermissionGrant] = [], authorizedDevices: Set<String> = []) {
        self.grants = grants
        self.authorizedDevices = authorizedDevices
    }

    public func authorizeDevice(_ key: String) { authorizedDevices.insert(key) }
    public func revokeDevice(_ key: String) {
        authorizedDevices.remove(key)
        grants.removeAll { $0.deviceKey == key }
    }
    public func isDeviceAuthorized(_ key: String) -> Bool { authorizedDevices.contains(key) }

    public func grant(_ g: PermissionGrant) {
        grants.removeAll { $0.deviceKey == g.deviceKey && $0.adapterID == g.adapterID && $0.permission == g.permission }
        grants.append(g)
    }

    public func revoke(deviceKey: String, adapterID: String, permission: AdapterPermission) {
        grants.removeAll { $0.deviceKey == deviceKey && $0.adapterID == adapterID && $0.permission == permission }
    }

    public func decision(for adapter: RegisteredAdapter, deviceKey: String, requested: [AdapterPermission], at date: Date = Date()) -> PermissionDecision {
        guard adapter.trust != .untrusted else { return .deniedUntrustedAdapter }
        guard adapter.enabled else { return .deniedDisabledAdapter }
        let notDeclared = requested.filter { !adapter.manifest.permissions.contains($0) }
        if !notDeclared.isEmpty { return .deniedUndeclaredPermission(notDeclared) }
        let missing = requested.filter { p in
            p.isPrivileged && !grants.contains { $0.deviceKey == deviceKey && $0.adapterID == adapter.manifest.id && $0.permission == p && $0.isValid(at: date) }
        }
        if !missing.isEmpty { return .requiresUserGrant(missing) }
        if requested.contains(where: \.isPrivileged) && !isDeviceAuthorized(deviceKey) {
            return .requiresUserGrant(requested.filter(\.isPrivileged))
        }
        return .granted
    }
}
