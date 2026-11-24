import Foundation

/// Integration status of a sibling HCG product, based on the contracts that exist today.
/// Nothing here invents endpoints, credentials or URL schemes.
public struct EcosystemIntegration: Hashable, Identifiable {
    public enum Status: String, Hashable {
        case available
        case notInstalled
        case notConfigured
        case awaitingContract
        case planned

        public var displayName: String {
            switch self {
            case .available: return "Available"
            case .notInstalled: return "Not installed on this Mac"
            case .notConfigured: return "Not configured"
            case .awaitingContract: return "Awaiting contract"
            case .planned: return "Planned"
            }
        }
    }

    public var id: String
    public var product: String
    public var role: String
    public var status: Status
    public var contract: String
    public var details: [String]
    public var supported: [String]
    public var urlScheme: String?

    public init(id: String, product: String, role: String, status: Status, contract: String, details: [String], supported: [String], urlScheme: String? = nil) {
        self.id = id
        self.product = product
        self.role = role
        self.status = status
        self.contract = contract
        self.details = details
        self.supported = supported
        self.urlScheme = urlScheme
    }
}

public enum HCGEcosystem {
    /// The baseline catalogue. The app refines `.notInstalled`/`.available` at runtime by asking
    /// Launch Services whether a handler for the product's URL scheme exists.
    public static let integrations: [EcosystemIntegration] = [
        EcosystemIntegration(
            id: "hcg-server", product: "HCG Server", role: "Hosting, pairing and remote diagnostic processing",
            status: .notConfigured, contract: "HCG Device Link hcg.devicelink/1 · reports hcg.diagnostic-report/1 · redaction hcg.redaction/1",
            details: [
                "Pairing uses a host-issued invitation code (hcg1-…) and a P-256 installation key; requests are signed and sent over pinned TLS 1.3.",
                "System Tester already exports hcg.diagnostic-report/1, the format Device Link carries.",
                "Not paired: no HCG Server has been authorised on this Mac.",
                "The minimal System Tester hosting experiment on HCG Server is a separate workload and is left untouched."
            ],
            supported: ["Export hcg.diagnostic-report/1 (now)", "Discover / pair with an authorised server (planned)",
                        "Synchronise diagnostic results (planned)", "Service health monitoring (planned)"]),
        EcosystemIntegration(
            id: "hcg-terminal", product: "HCG Terminal", role: "Operator console",
            status: .notInstalled, contract: "Navigation deep links hcgterminal://open/<destination> (Standard) and hcgterminal-unleashed://open/<destination> (Unleashed)",
            details: [
                "Deep links carry exactly one destination and no query — navigation only, never commands.",
                "System Tester never sends commands to Terminal and never forwards text from devices or manifests.",
                "HCG Terminal currently ships for iOS/iPadOS; on a Mac it is only reachable if a macOS build registers its scheme."
            ],
            supported: TerminalDeepLink.destinations.map { "Open Terminal › \($0)" },
            urlScheme: TerminalDeepLink.standardScheme),
        EcosystemIntegration(
            id: "hcg-sentinel", product: "HCG Sentinel", role: "Defensive security analysis",
            status: .notInstalled, contract: "Navigation deep links hcgsentinel://open/<destination>; findings via hcg.diagnostic-report/1 files",
            details: [
                "Sentinel has no inbound API for findings from other apps yet; System Tester exports findings as hcg.diagnostic-report/1 for import or Device Link sharing.",
                "Sentinel remains responsible for security analysis; System Tester only supplies evidence."
            ],
            supported: SentinelDeepLink.destinations.map { "Open Sentinel › \($0)" },
            urlScheme: SentinelDeepLink.scheme),
        EcosystemIntegration(
            id: "hcg-nexus", product: "HCG Nexus", role: "Ecosystem integration hub",
            status: .awaitingContract, contract: "HCG Interchange Protocol v1 (HIP)",
            details: [
                "HIP v1's product registry is compiled into Nexus and is currently iOS-only with no System Tester entry.",
                "System Tester publishes its status through its own navigation scheme (hcgsystemtester://open/<section>) and stays fully functional without Nexus."
            ],
            supported: ["Availability & version (when registered)", "Connected hardware summary (planned)", "Navigation routes: " + SystemTesterRoute.allCases.map(\.rawValue).joined(separator: ", ")]),
        EcosystemIntegration(
            id: "hcg-connect", product: "HCG Connect", role: "Central identity, licensing and permissions",
            status: .notConfigured, contract: "hcg-connect configuration (contractVersion, clientId, issuer, redirect URIs, scopes) · OAuth 2 PKCE public client",
            details: [
                "No HCG Connect client has been issued for System Tester; each product needs its own client.",
                "Native apps use a loopback redirect (127.0.0.1) and PKCE; no client secret is ever embedded.",
                "System Tester is fully usable locally without signing in."
            ],
            supported: ["Sign-in (after client registration)", "Licensing & feature permissions (planned)", "Workspace selection (planned)"]),
        EcosystemIntegration(
            id: "hcg-signal-contractor", product: "HCG Signal Contractor", role: "Signal measurement and external hardware capabilities",
            status: .awaitingContract, contract: "Proposed shared spec: hcg.adapter-manifest/1 + hcg.systemtester.report/1 device summaries",
            details: [
                "Signal Contractor has no published hardware schema yet. System Tester's adapter manifest is offered as the shared adapter specification so discovery is not duplicated."
            ],
            supported: ["Exchange device identifiers & capabilities (proposed)", "Exchange authorised diagnostic results (proposed)"]),
        EcosystemIntegration(
            id: "hcg-executable-maker", product: "HCG Executable Maker", role: "Building and packaging",
            status: .available, contract: "SwiftPM package + AppPackaging.json (hcg-app-packaging/1)",
            details: ["Executable Maker builds System Tester from Package.swift (product HCGSystemTester). Publication stays manual."],
            supported: ["Package the app", "Package approved adapter projects (planned)"])
    ]
}

/// Builds HCG Terminal navigation links. Only allow-listed destinations are possible.
public enum TerminalDeepLink {
    public static let standardScheme = "hcgterminal"
    public static let unleashedScheme = "hcgterminal-unleashed"
    public static let destinations = ["dashboard", "files", "hosts", "builds", "artifacts", "console", "tools", "diagnostics", "capabilities", "settings", "about"]

    public enum Variant { case standard, unleashed }

    public static func url(destination: String, variant: Variant = .standard) -> URL? {
        guard destinations.contains(destination) else { return nil }
        let scheme = variant == .standard ? standardScheme : unleashedScheme
        return URL(string: "\(scheme)://open/\(destination)")
    }
}

public enum SentinelDeepLink {
    public static let scheme = "hcgsentinel"
    public static let destinations = ["dashboard", "network", "networkCheck", "securityLab", "bluetooth", "radio", "requests", "capabilities", "settings"]

    public static func url(destination: String) -> URL? {
        guard destinations.contains(destination) else { return nil }
        return URL(string: "\(scheme)://open/\(destination)")
    }
}

/// System Tester's own inbound navigation routes (`hcgsystemtester://open/<route>`).
/// Navigation only: queries, fragments, extra path segments and unknown routes are rejected,
/// and nothing received through a URL is ever executed.
public enum SystemTesterRoute: String, CaseIterable, Hashable {
    case commandCenter = "command-center"
    case connectedSystems = "connected-systems"
    case visualizer
    case diagnostics
    case laboratory
    case adapterLibrary = "adapters"
    case developerStudio = "studio"
    case ecosystem
    case reports
    case settings

    public static let scheme = "hcgsystemtester"

    public static func parse(_ url: URL) -> SystemTesterRoute? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "open",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1 else { return nil }
        return SystemTesterRoute(rawValue: String(parts[0]))
    }

    public var url: URL { URL(string: "\(Self.scheme)://open/\(rawValue)")! }
}
