#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import HCGCore

struct ReportsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    @State private var title = "HCG System Tester diagnostic report"
    @State private var exportFormat: ReportFormat = .markdown
    @State private var exportDocument: ExportDocument?
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Reports",
                          subtitle: "Redacted exports in Markdown, JSON (hcg.systemtester.report/1) or HCG Device Link (hcg.diagnostic-report/1).",
                          symbol: "doc.richtext")
            HStack {
                TextField("Report title", text: $title).frame(maxWidth: 420)
                Button("Generate from this session's runs") {
                    let stored = model.generateReport(title: title, runs: model.recentRuns, deviceIDs: model.presentRecords.map(\.id))
                    selected = stored.id
                }
                .disabled(model.recentRuns.isEmpty && model.presentRecords.isEmpty)
                Button("Inventory snapshot") {
                    let stored = model.generateReport(title: "Inventory snapshot", runs: [], deviceIDs: model.presentRecords.map(\.id))
                    selected = stored.id
                }
                .disabled(model.presentRecords.isEmpty)
            }
            .glassPanel(padding: 12)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.reports.isEmpty {
                        Text("No reports yet. Generate one above or from a Laboratory session.").font(.caption).foregroundStyle(Theme.dim)
                    }
                    ForEach(model.reports) { r in
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(Theme.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.report.title).font(.callout).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(Formatters.dateTime.string(from: r.report.generatedAt)) · \(r.report.runs.count) run(s)").font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if r.report.containsSyntheticData { ProvenanceBadge(provenance: .synthetic) }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected == r.id ? Theme.cyan.opacity(0.15) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selected = r.id }
                    }
                }
                .frame(width: 320)
                .glassPanel(padding: 10)

                if let id = selected ?? model.reports.first?.id, let stored = model.reports.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("Format", selection: $exportFormat) {
                                ForEach(ReportFormat.allCases) { Text($0.displayName).tag($0) }
                            }
                            .frame(maxWidth: 420)
                            Button { export(stored) } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                            Button("Copy Markdown") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(stored.markdown, forType: .string)
                            }
                        }
                        Text("Redaction applied: serial numbers, user paths, network identifiers and credentials per your privacy settings. Synthetic results are labelled.")
                            .font(.caption2).foregroundStyle(Theme.dim)
                        ScrollView {
                            Text(stored.markdown)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 420)
                        .background(Theme.obsidian.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .glassPanel()
                    .frame(maxWidth: .infinity)
                }
            }
            AuditPanel()
        }
        .workspacePage()
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportFormat == .markdown ? .plainText : .json,
                      defaultFilename: exportDocument?.filename ?? "report") { result in
            if case .failure(let e) = result { model.banner = "Export failed: \(e.localizedDescription)" }
        }
    }

    func export(_ stored: StoredReport) {
        do {
            let data = try model.export(stored, format: exportFormat)
            let stamp = ISO8601DateFormatter().string(from: stored.report.generatedAt).replacingOccurrences(of: ":", with: "-")
            exportDocument = ExportDocument(data: data, filename: "hcg-systemtester-\(stamp).\(exportFormat.fileExtension)")
            exporting = true
        } catch {
            model.banner = error.localizedDescription
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    var filename: String

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        filename = configuration.file.filename ?? "report"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct AuditPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audit trail").font(.headline).foregroundStyle(Theme.text)
            Text("Every diagnostic operation, authorisation and adapter decision is appended to audit.jsonl in Application Support.")
                .font(.caption).foregroundStyle(Theme.dim)
            if model.auditEntries.isEmpty {
                Text("No audited operations yet.").font(.caption).foregroundStyle(Theme.dim)
            }
            ForEach(model.auditEntries.suffix(15).reversed()) { e in
                HStack {
                    Text(Formatters.dateTime.string(from: e.timestamp)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim).frame(width: 150, alignment: .leading)
                    Text(e.operation).font(.caption.monospaced()).foregroundStyle(Theme.cyan).frame(width: 220, alignment: .leading)
                    Text(e.decision).font(.caption).foregroundStyle(e.decision == "denied" ? Theme.warning : Theme.success).frame(width: 110, alignment: .leading)
                    Text(e.target).font(.caption).foregroundStyle(Theme.text).lineLimit(1)
                    if e.provenance.isSynthetic { Text("SYN").font(.caption2.weight(.heavy)).foregroundStyle(Theme.synthetic) }
                    Spacer()
                    Text(e.outcome).font(.caption2).foregroundStyle(Theme.dim)
                }
            }
        }
        .glassPanel()
    }
}
#endif
