import Foundation

/// System Tester's native report (`hcg.systemtester.report/1`).
public struct SystemTesterReport: Codable, Hashable, Identifiable {
    public static let schemaID = "hcg.systemtester.report/1"

    public struct DeviceSummary: Codable, Hashable {
        public var name: String
        public var key: String
        public var provenance: DataProvenance
        public var connectionType: ConnectionType
        public var status: DeviceStatus?
        public var category: DeviceCategory?
        public var profile: String?
        public var vendorID: String?
        public var productID: String?
        public var serialNumber: String?
        public var linkSpeed: String?
        public var firmwareRevision: String?
        public var layers: [LayerAssessment]
    }

    public var schema: String
    public var id: UUID
    public var title: String
    public var generatedAt: Date
    public var generator: String
    public var containsSyntheticData: Bool
    public var redactionApplied: Bool
    public var devices: [DeviceSummary]
    public var runs: [DiagnosticRun]
    public var notes: String
}

public enum ReportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case deviceLink

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON (hcg.systemtester.report/1)"
        case .deviceLink: return "HCG Device Link (hcg.diagnostic-report/1)"
        }
    }
    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json, .deviceLink: return "json"
        }
    }
}

public enum ReportGenerator {
    public static func make(title: String, runs: [DiagnosticRun], records: [DeviceRecord], redactor: Redactor,
                            notes: String = "", generatedAt: Date = Date()) -> SystemTesterReport {
        var r = redactor
        for rec in records { r.registerSerialNumber(rec.device.usb?.serialNumber) }
        let devices = records.map { rec -> SystemTesterReport.DeviceSummary in
            let d = r.redactDevice(rec.device)
            return SystemTesterReport.DeviceSummary(
                name: d.displayName, key: rec.stableKey, provenance: d.provenance, connectionType: d.connectionType,
                status: rec.status, category: rec.identification.category, profile: rec.identification.profileName,
                vendorID: d.usb?.vendorIDHex, productID: d.usb?.productIDHex, serialNumber: d.usb?.serialNumber,
                linkSpeed: d.usb?.speed?.displayName, firmwareRevision: d.usb?.firmwareRevision,
                layers: rec.assessment.layers.map { l in
                    LayerAssessment(layer: l.layer, state: l.state, reason: r.redact(l.reason), evidence: r.redact(l.evidence))
                })
        }
        let redactedRuns = runs.map { run -> DiagnosticRun in
            var copy = run
            copy.deviceName = r.redact(run.deviceName)
            copy.results = run.results.map { res in
                var x = res
                x.targetDeviceName = r.redact(res.targetDeviceName)
                x.summary = r.redact(res.summary)
                x.evidence = r.redact(res.evidence)
                x.limitations = r.redact(res.limitations)
                x.errors = r.redact(res.errors)
                x.recommendedNextAction = r.redact(res.recommendedNextAction)
                return x
            }
            return copy
        }
        let synthetic = runs.contains { $0.provenance.isSynthetic } || records.contains { $0.device.provenance.isSynthetic }
        return SystemTesterReport(schema: SystemTesterReport.schemaID, id: UUID(), title: r.redact(title), generatedAt: generatedAt,
                                  generator: "\(HCGSystemTesterInfo.productName) \(HCGSystemTesterInfo.version)",
                                  containsSyntheticData: synthetic, redactionApplied: true, devices: devices, runs: redactedRuns,
                                  notes: r.redact(notes))
    }

    public static func json(_ report: SystemTesterReport) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(report)
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    public static func markdown(_ report: SystemTesterReport) -> String {
        var lines: [String] = []
        lines.append("# \(report.title)")
        lines.append("")
        lines.append("- Generated: \(iso(report.generatedAt)) by \(report.generator)")
        lines.append("- Schema: `\(report.schema)`")
        lines.append("- Redaction: \(report.redactionApplied ? "applied" : "NOT applied")")
        if report.containsSyntheticData {
            lines.append("")
            lines.append("> **SYNTHETIC DATA PRESENT.** Results marked SYNTHETIC come from simulated fixtures and describe no real hardware.")
        }
        lines.append("")
        lines.append("## Devices")
        lines.append("")
        if report.devices.isEmpty { lines.append("_No devices in scope._") }
        for d in report.devices {
            lines.append("### \(d.name)\(d.provenance.isSynthetic ? " — SYNTHETIC" : "")")
            lines.append("")
            lines.append("| Field | Value |")
            lines.append("|---|---|")
            lines.append("| Status | \(d.status?.displayName ?? "—") |")
            lines.append("| Category | \(d.category?.displayName ?? "—") |")
            lines.append("| Profile | \(d.profile ?? "Unidentified") |")
            lines.append("| Connection | \(d.connectionType.displayName) |")
            lines.append("| VID / PID | \(d.vendorID ?? "—") / \(d.productID ?? "—") |")
            lines.append("| Serial | \(d.serialNumber ?? "—") |")
            lines.append("| Link speed | \(d.linkSpeed ?? "—") |")
            lines.append("| Firmware (bcdDevice) | \(d.firmwareRevision ?? "—") |")
            lines.append("| Provenance | \(d.provenance.displayName) |")
            lines.append("")
            lines.append("Connectivity layers:")
            lines.append("")
            for l in d.layers { lines.append("- **\(l.layer.displayName):** \(l.state.displayName) — \(l.reason)") }
            lines.append("")
        }
        lines.append("## Diagnostic runs")
        lines.append("")
        if report.runs.isEmpty { lines.append("_No diagnostic runs in scope._") }
        for run in report.runs {
            lines.append("### \(run.deviceName) — \(iso(run.startedAt))\(run.provenance.isSynthetic ? " — SYNTHETIC" : "")")
            lines.append("")
            lines.append("| Test | Category | Result | Summary |")
            lines.append("|---|---|---|---|")
            for r in run.results {
                lines.append("| \(r.testName) | \(r.category.displayName) | \(r.outcome.displayName) | \(r.summary.replacingOccurrences(of: "|", with: "\\|")) |")
            }
            lines.append("")
            for r in run.results {
                lines.append("#### \(r.testName) (`\(r.testID)`)")
                lines.append("")
                lines.append("- Target: \(r.targetDeviceName)")
                lines.append("- Type: \(r.category.displayName) · \(r.impact.displayName)")
                lines.append("- Started: \(iso(r.startedAt)) · Finished: \(iso(r.finishedAt))")
                lines.append("- Result: **\(r.outcome.displayName)** — \(r.summary)")
                if !r.measurements.isEmpty {
                    lines.append("- Measurements: " + r.measurements.map { "\($0.name) = \($0.formatted)\($0.provenance.isSynthetic ? " (SYNTHETIC)" : "")" }.joined(separator: "; "))
                }
                for e in r.evidence { lines.append("- Evidence: \(e)") }
                for l in r.limitations { lines.append("- Limitation: \(l)") }
                for e in r.errors { lines.append("- Error: \(e)") }
                lines.append("- Recommended next action: \(r.recommendedNextAction)")
                lines.append("")
            }
        }
        if !report.notes.isEmpty {
            lines.append("## Notes")
            lines.append("")
            lines.append(report.notes)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Converts to HCG Device Link's `hcg.diagnostic-report/1` so results can be shared through
    /// a paired HCG Server. Field names follow HCGDeviceLink/Report.swift (client 1.0.0).
    public static func deviceLinkReport(_ report: SystemTesterReport, installationID: String, deviceName: String) -> DeviceLinkDiagnosticReport {
        let all = report.runs.flatMap(\.results)
        let findings = all.filter { [.warning, .failed, .error, .aborted].contains($0.outcome) }.map { r in
            DeviceLinkDiagnosticReport.Finding(
                title: String((report.containsSyntheticData && r.provenance.isSynthetic ? "[SYNTHETIC] " : "") + r.testName + ": " + r.summary).prefix(200).description,
                severity: severity(r.outcome), confidence: "high", basis: r.provenance == .hardware ? "observed" : "synthetic",
                location: r.targetDeviceName, evidence: r.evidence + r.measurements.map { "\($0.name) = \($0.formatted)" },
                explanation: r.limitations.joined(separator: " "), remediation: r.recommendedNextAction)
        }
        let highest = findings.compactMap(\.severity).max { rank($0) < rank($1) }
        let status = all.contains { $0.outcome == .failed || $0.outcome == .error } ? "issues-found"
            : (findings.isEmpty ? "ok" : "warnings")
        var limitations = Array(Set(all.flatMap(\.limitations))).sorted()
        if report.containsSyntheticData { limitations.insert("Contains SYNTHETIC results that describe no real hardware.", at: 0) }
        return DeviceLinkDiagnosticReport(
            schema: DeviceLinkDiagnosticReport.schemaID, reportId: report.id.uuidString.lowercased(), kind: "systemtester.hardware-diagnostics",
            title: String(report.title.prefix(200)),
            origin: .init(app: HCGSystemTesterInfo.productName, appVersion: HCGSystemTesterInfo.version, installationId: installationID,
                          deviceName: deviceName, module: "diagnostic-engine", moduleVersion: HCGSystemTesterInfo.version),
            createdAt: report.runs.map(\.startedAt).min() ?? report.generatedAt, completedAt: report.runs.map(\.finishedAt).max(),
            sharedAt: nil, redaction: .init(policy: DeviceLinkDiagnosticReport.redactionPolicy, applied: true),
            summary: .init(status: status, highestSeverity: highest, findingCount: findings.count),
            scope: report.devices.map { "\($0.name) [\($0.connectionType.displayName)]\($0.provenance.isSynthetic ? " SYNTHETIC" : "")" },
            findings: findings,
            checks: all.map { .init(title: "\($0.testName) — \($0.targetDeviceName)", outcome: $0.outcome.rawValue, detail: $0.summary) },
            limitations: limitations,
            notTested: HostOperationCatalog.uncoveredCategories.map { "\($0.displayName): no host test in \(HCGSystemTesterInfo.version)" })
    }

    static func severity(_ o: DiagnosticOutcome) -> String? {
        switch o {
        case .failed, .error: return "high"
        case .aborted: return "medium"
        case .warning: return "low"
        default: return nil
        }
    }

    static func rank(_ s: String) -> Int { ["info": 0, "low": 1, "medium": 2, "high": 3, "critical": 4][s] ?? 0 }
}

/// Wire-compatible mirror of HCG Device Link's `DiagnosticReport` (`hcg.diagnostic-report/1`).
/// Kept local (not a package dependency) so System Tester builds without HCG Nexus.
public struct DeviceLinkDiagnosticReport: Codable, Hashable {
    public static let schemaID = "hcg.diagnostic-report/1"
    public static let redactionPolicy = "hcg.redaction/1"
    public static let maxBytes = 256 * 1024

    public struct Origin: Codable, Hashable {
        public var app: String
        public var appVersion: String
        public var installationId: String
        public var deviceName: String
        public var module: String?
        public var moduleVersion: String?
    }
    public struct Redaction: Codable, Hashable { public var policy: String; public var applied: Bool }
    public struct Summary: Codable, Hashable { public var status: String; public var highestSeverity: String?; public var findingCount: Int }
    public struct Finding: Codable, Hashable {
        public var title: String
        public var severity: String?
        public var confidence: String?
        public var basis: String?
        public var location: String?
        public var evidence: [String]
        public var explanation: String?
        public var remediation: String?
    }
    public struct Check: Codable, Hashable { public var title: String; public var outcome: String; public var detail: String? }

    public var schema: String
    public var reportId: String
    public var kind: String
    public var title: String
    public var origin: Origin
    public var createdAt: Date
    public var completedAt: Date?
    public var sharedAt: Date?
    public var redaction: Redaction
    public var summary: Summary
    public var scope: [String]
    public var findings: [Finding]
    public var checks: [Check]
    public var limitations: [String]
    public var notTested: [String]

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    /// Mirrors Device Link's `ReportValidator` so the user sees problems before anything is shared.
    public func problems() -> [String] {
        var out: [String] = []
        if schema != Self.schemaID { out.append("unsupported report schema") }
        if !redaction.applied || redaction.policy != Self.redactionPolicy { out.append("report is not marked redacted") }
        if title.isEmpty || title.count > 200 { out.append("title must be 1–200 characters") }
        if let data = try? encoded(), data.count > Self.maxBytes { out.append("report is larger than 256 KiB") }
        return out
    }
}
