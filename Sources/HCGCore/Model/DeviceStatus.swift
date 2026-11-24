import Foundation

/// Lifecycle status of a system as seen by HCG System Tester.
///
/// The states are deliberately conservative: a recognised name or USB identifier
/// only ever yields `.identified`. `.connected` requires verified functional
/// communication, and `.authenticated` additionally requires verified authorisation.
public enum DeviceStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case detected
    case identified
    case diagnosticsAvailable
    case adapterRequired
    case unsupported
    case connected
    case authenticated
    case disconnected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .detected: return "Detected"
        case .identified: return "Identified"
        case .diagnosticsAvailable: return "Diagnostics available"
        case .adapterRequired: return "Adapter required"
        case .unsupported: return "Unsupported"
        case .connected: return "Connected"
        case .authenticated: return "Authenticated"
        case .disconnected: return "Disconnected"
        }
    }

    public var meaning: String {
        switch self {
        case .detected:
            return "The host saw the device, but it has not been identified yet."
        case .identified:
            return "Descriptors were matched to a device profile. No communication has been verified."
        case .diagnosticsAvailable:
            return "Read-only, host-side diagnostics can run. Functional communication with the device has not been verified."
        case .adapterRequired:
            return "The device was identified, but communicating with it needs a hardware or software adapter that is not installed."
        case .unsupported:
            return "No supported protocol or adapter exists for this device on this connection."
        case .connected:
            return "Data was exchanged with the device through a supported protocol."
        case .authenticated:
            return "Functional communication is established within an authorised session."
        case .disconnected:
            return "The device is no longer present on any discovery backend."
        }
    }

    public var isPresent: Bool { self != .disconnected }

    public var symbolName: String {
        switch self {
        case .detected: return "dot.radiowaves.up.forward"
        case .identified: return "person.text.rectangle"
        case .diagnosticsAvailable: return "stethoscope"
        case .adapterRequired: return "puzzlepiece.extension"
        case .unsupported: return "nosign"
        case .connected: return "link"
        case .authenticated: return "checkmark.shield"
        case .disconnected: return "bolt.slash"
        }
    }
}

public struct StatusTransitionError: Error, Equatable, CustomStringConvertible {
    public let from: DeviceStatus
    public let to: DeviceStatus
    public var description: String { "Invalid status transition \(from.rawValue) → \(to.rawValue)" }
}

public struct StatusChange: Codable, Hashable {
    public var from: DeviceStatus?
    public var to: DeviceStatus
    public var at: Date
    public var reason: String
}

/// Enforces the allowed lifecycle transitions so that, for example, a device can
/// never jump from `.detected` straight to `.authenticated`.
public struct DeviceStateMachine: Codable, Hashable {
    public private(set) var status: DeviceStatus
    public private(set) var history: [StatusChange]

    public static let allowedTransitions: [DeviceStatus: Set<DeviceStatus>] = [
        .detected: [.identified, .diagnosticsAvailable, .adapterRequired, .unsupported, .disconnected],
        .identified: [.diagnosticsAvailable, .adapterRequired, .unsupported, .connected, .disconnected],
        .diagnosticsAvailable: [.identified, .adapterRequired, .unsupported, .connected, .disconnected],
        .adapterRequired: [.identified, .diagnosticsAvailable, .unsupported, .connected, .disconnected],
        .unsupported: [.identified, .diagnosticsAvailable, .adapterRequired, .disconnected],
        .connected: [.authenticated, .diagnosticsAvailable, .identified, .disconnected],
        .authenticated: [.connected, .diagnosticsAvailable, .disconnected],
        .disconnected: [.detected]
    ]

    public init(initial: DeviceStatus = .detected, at date: Date = Date(), reason: String = "Discovered") {
        self.status = initial
        self.history = [StatusChange(from: nil, to: initial, at: date, reason: reason)]
    }

    public static func canTransition(from: DeviceStatus, to: DeviceStatus) -> Bool {
        from == to || (allowedTransitions[from]?.contains(to) ?? false)
    }

    /// Moves to `next`, throwing when the transition is not permitted.
    public mutating func transition(to next: DeviceStatus, at date: Date = Date(), reason: String) throws {
        guard next != status else { return }
        guard Self.canTransition(from: status, to: next) else {
            throw StatusTransitionError(from: status, to: next)
        }
        history.append(StatusChange(from: status, to: next, at: date, reason: reason))
        status = next
    }

    /// Moves towards `target` through legal intermediate states (e.g. disconnected → detected → identified).
    public mutating func advance(to target: DeviceStatus, at date: Date = Date(), reason: String) {
        if target == status { return }
        if Self.canTransition(from: status, to: target) {
            try? transition(to: target, at: date, reason: reason)
            return
        }
        // Breadth-first search for the shortest legal path.
        var queue: [[DeviceStatus]] = [[status]]
        var seen: Set<DeviceStatus> = [status]
        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard let last = path.last else { continue }
            for next in (Self.allowedTransitions[last] ?? []).sorted(by: { $0.rawValue < $1.rawValue }) where !seen.contains(next) {
                let newPath = path + [next]
                if next == target {
                    for step in newPath.dropFirst() {
                        try? transition(to: step, at: date, reason: step == target ? reason : "Intermediate: \(reason)")
                    }
                    return
                }
                seen.insert(next)
                queue.append(newPath)
            }
        }
    }
}
