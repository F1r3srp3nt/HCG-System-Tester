import Foundation

/// Per-device report: identity, sourced intelligence fields, connection ladder, compatibility and
/// diagnostic results (`hcg.systemtester.device-report/1`). Sensitive identifiers are redacted by default.
public struct DeviceIntelligenceReport: Codable, Hashable {
    public static let schemaID = "hcg.systemtester.device-report/1"

    public enum Kind: String, Codable, CaseIterable, Identifiable {
        case deviceInformation, compatibility, diagnostics
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .deviceInformation: return "Device information report"
            case .compatibility: return "Compatibility report"
            case .diagnostics: return "Diagnostic results"
            }
        }
    }

    public var schema: String
    public var kind: Kind
    public var generatedAt: Date
    public var generator: String
    public var sensitiveIdentifiersIncluded: Bool
    public var containsSyntheticData: Bool
    public var deviceName: String
    public var deviceKey: String
    public var status: DeviceStatus
    public var category: DeviceCategory
    public var profile: String?
    public var intelligence: IntelligenceSnapshot?
    public var layers: [LayerAssessment]
    public var adapters: [AdapterCompatibility]
    public var limitations: [String]
    public var runs: [DiagnosticRun]

    public static func make(kind: Kind, record: DeviceRecord, snapshot: IntelligenceSnapshot?, runs: [DiagnosticRun],
                            includeSensitive: Bool = false, privacy: PrivacySettings = .standard, at: Date = Date()) -> DeviceIntelligenceReport {
        var r = Redactor(settings: privacy)
        if !includeSensitive {
            r.registerSerialNumber(record.device.usb?.serialNumber)
            for f in snapshot?.fields ?? [] where f.sensitive { r.registerSerialNumber(f.value) }
        }
        let snap = includeSensitive ? snapshot : snapshot?.redacted(r)
        let deviceRuns = runs.filter { $0.deviceKey == record.stableKey }.map { run -> DiagnosticRun in
            guard !includeSensitive else { return run }
            var copy = run
            copy.results = run.results.map { res in
                var x = res
                x.summary = r.redact(res.summary)
                x.evidence = r.redact(res.evidence)
                x.limitations = r.redact(res.limitations)
                x.errors = r.redact(res.errors)
                return x
            }
            return copy
        }
        let limitations = (snapshot?.limitations ?? []) + record.identification.knownLimitations
        return DeviceIntelligenceReport(
            schema: schemaID, kind: kind, generatedAt: at, generator: "\(HCGSystemTesterInfo.productName) \(HCGSystemTesterInfo.version)",
            sensitiveIdentifiersIncluded: includeSensitive,
            containsSyntheticData: record.device.provenance.isSynthetic || deviceRuns.contains { $0.provenance.isSynthetic },
            deviceName: r.redact(record.device.displayName), deviceKey: record.stableKey, status: record.status,
            category: record.identification.category, profile: record.identification.profileName,
            intelligence: kind == .diagnostics ? nil : snap,
            layers: record.assessment.layers.map { LayerAssessment(layer: $0.layer, state: $0.state, reason: r.redact($0.reason), evidence: r.redact($0.evidence)) },
            adapters: kind == .deviceInformation ? [] : record.compatibility,
            limitations: r.redact(limitations),
            runs: kind == .compatibility ? [] : deviceRuns)
    }

    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public func markdown() -> String {
        var l: [String] = ["# \(kind.displayName): \(deviceName)", ""]
        l.append("- Generated: \(ReportGenerator.iso(generatedAt)) by \(generator)")
        l.append("- Schema: `\(schema)`")
        l.append("- Sensitive identifiers: \(sensitiveIdentifiersIncluded ? "INCLUDED (handle with care)" : "redacted")")
        l.append("- Status: \(status.displayName) · \(category.displayName)\(profile.map { " · \($0)" } ?? "")")
        if containsSyntheticData { l += ["", "> **SYNTHETIC DATA.** This report describes a simulated fixture, not real hardware."] }
        if let s = intelligence {
            l += ["", "## Connection state", "", "**\(s.state.number). \(s.state.displayName)** — \(s.stateReason)", "", "Next action: \(s.nextAction.title)", ""]
            for step in s.ladder { l.append("- [\(step.reached ? "x" : " ")] \(step.state.displayName)\(step.evidence.map { " — \($0)" } ?? "")") }
            for group in IntelligenceGroup.allCases {
                let fields = s.fields(in: group)
                guard !fields.isEmpty else { continue }
                l += ["", "## \(group.displayName)", "", "| Field | Value | Source |", "|---|---|---|"]
                for f in fields {
                    let v = (f.value ?? "Unavailable: \(f.unavailableReason ?? "")").replacingOccurrences(of: "|", with: "\\|")
                    l.append("| \(f.label) | \(v) | \(f.source.description.replacingOccurrences(of: "|", with: "\\|")) |")
                }
            }
            if !s.services.isEmpty {
                l += ["", "## Services", ""]
                for sv in s.services { l.append("- \(sv.name) (`\(sv.identifier)`) — \(sv.available ? "available" : "unavailable") · \(sv.source.description)") }
            }
            if let c = s.correlation { l += ["", "Correlation: \(c)"] }
        }
        l += ["", "## Connectivity layers", ""]
        for layer in layers { l.append("- **\(layer.layer.displayName):** \(layer.state.displayName) — \(layer.reason)") }
        if !adapters.isEmpty {
            l += ["", "## Adapter compatibility", ""]
            for a in adapters { l.append("- \(a.adapterName): \(a.status.rawValue) — \(a.availableOperations.count) operation(s)\(a.reasons.isEmpty ? "" : " · " + a.reasons.joined(separator: "; "))") }
        }
        if !limitations.isEmpty {
            l += ["", "## Limitations", ""]
            for x in limitations { l.append("- \(x)") }
        }
        if !runs.isEmpty {
            l += ["", "## Diagnostic results", ""]
            for run in runs {
                l.append("### Run \(ReportGenerator.iso(run.startedAt))\(run.provenance.isSynthetic ? " — SYNTHETIC" : "")")
                l.append("")
                for r in run.results {
                    l.append("- **\(r.testName)** (`\(r.testID)`): \(r.outcome.displayName) — \(r.summary)")
                    for m in r.measurements { l.append("  - \(m.name): \(m.formatted)\(m.provenance.isSynthetic ? " (SYNTHETIC)" : "")") }
                    for e in r.evidence.prefix(6) { l.append("  - Evidence: \(e)") }
                    for x in r.limitations { l.append("  - Limitation: \(x)") }
                }
                l.append("")
            }
        }
        return l.joined(separator: "\n")
    }
}

/// Authorized device inventory prepared for sharing with an HCG Server (`hcg.systemtester.inventory/1`).
/// Built locally; System Tester does not send it anywhere until Device Link pairing exists.
public struct DeviceInventorySnapshot: Codable, Hashable {
    public static let schemaID = "hcg.systemtester.inventory/1"
    public struct Entry: Codable, Hashable {
        public var key: String
        public var name: String
        public var category: DeviceCategory
        public var status: DeviceStatus
        public var connection: ConnectionType
        public var intelligenceState: IntelligenceState?
        public var model: String?
        public var osVersion: String?
        public var provenance: DataProvenance
    }
    public var schema: String
    public var generatedAt: Date
    public var installationID: String
    public var appVersion: String
    public var devices: [Entry]

    public static func make(records: [DeviceRecord], snapshots: [DeviceIdentifier: IntelligenceSnapshot], installationID: String,
                            redactor: Redactor = Redactor(), at: Date = Date()) -> DeviceInventorySnapshot {
        DeviceInventorySnapshot(schema: schemaID, generatedAt: at, installationID: installationID, appVersion: HCGSystemTesterInfo.version,
            devices: records.filter(\.device.isPresent).map { r in
                let s = snapshots[r.id]
                return Entry(key: r.stableKey, name: redactor.redact(r.device.displayName), category: r.identification.category, status: r.status,
                             connection: r.device.connectionType, intelligenceState: s?.state,
                             model: s?.value("apple.marketingName") ?? r.identification.profileName, osVersion: s?.value("apple.osVersion"),
                             provenance: r.device.provenance)
            })
    }
}

/// Defensive findings for HCG Sentinel, expressed as `hcg.diagnostic-report/1` findings.
public enum ConnectionSecurityFindings {
    /// A complete `hcg.diagnostic-report/1` document of kind `systemtester.connection-security`.
    public static func report(records: [DeviceRecord], snapshots: [DeviceIdentifier: IntelligenceSnapshot], adapters: [RegisteredAdapter],
                              installationID: String, deviceName: String, redactor: Redactor = Redactor()) -> DeviceLinkDiagnosticReport {
        let found = findings(records: records, snapshots: snapshots, adapters: adapters).map { f -> DeviceLinkDiagnosticReport.Finding in
            var x = f
            x.title = redactor.redact(f.title)
            x.location = f.location.map { redactor.redact($0) }
            return x
        }
        let base = ReportGenerator.make(title: "Connection security findings", runs: [], records: records.filter(\.device.isPresent), redactor: redactor)
        var link = ReportGenerator.deviceLinkReport(base, installationID: installationID, deviceName: deviceName)
        link.kind = "systemtester.connection-security"
        link.findings = found
        let highest = found.compactMap(\.severity).max { ReportGenerator.rank($0) < ReportGenerator.rank($1) }
        link.summary = DeviceLinkDiagnosticReport.Summary(status: found.isEmpty ? "ok" : "findings", highestSeverity: highest, findingCount: found.count)
        return link
    }

    public static func findings(records: [DeviceRecord], snapshots: [DeviceIdentifier: IntelligenceSnapshot], adapters: [RegisteredAdapter]) -> [DeviceLinkDiagnosticReport.Finding] {
        var out: [DeviceLinkDiagnosticReport.Finding] = []
        for r in records where r.device.isPresent {
            guard let s = snapshots[r.id] else { continue }
            let basis = r.device.provenance == .hardware ? "observed" : "synthetic"
            if s.value("apple.developerMode")?.lowercased() == "enabled" {
                out.append(.init(title: "Developer Mode is enabled on \(r.device.displayName)", severity: "low", confidence: "high", basis: basis,
                                 location: r.device.displayName, evidence: ["CoreDevice deviceProperties.developerModeStatus = enabled"],
                                 explanation: "Developer Mode allows installing and debugging development apps. Keep it off when not developing.",
                                 remediation: "On the device: Settings › Privacy & Security › Developer Mode (only if you no longer need it)."))
            }
            if s.state == .pairingAvailable || s.value("apple.pairingState").map({ $0.lowercased() != "paired" }) == true {
                out.append(.init(title: "\(r.device.displayName) is connected but not paired", severity: "info", confidence: "high", basis: basis,
                                 location: r.device.displayName, evidence: ["CoreDevice pairingState = \(s.value("apple.pairingState") ?? "unknown")"],
                                 explanation: "The device does not trust this Mac, so no device data can be read. This is the expected safe default.",
                                 remediation: nil))
            }
        }
        for a in adapters where a.trust == .untrusted {
            out.append(.init(title: "Untrusted adapter stored: \(a.manifest.name)", severity: "info", confidence: "high", basis: "configuration",
                             location: a.manifest.id, evidence: ["Imported, not approved, never executed"], explanation: nil,
                             remediation: "Review and approve it in the Adapter Library, or remove it."))
        }
        return out
    }
}
