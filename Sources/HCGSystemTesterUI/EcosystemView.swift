#if os(macOS)
import SwiftUI
import HCGCore

struct EcosystemView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "HCG Ecosystem",
                          subtitle: "Integrations use existing HCG contracts only. System Tester is fully functional on its own.",
                          symbol: "circle.hexagongrid")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(HCGEcosystem.integrations) { integration in
                    IntegrationCard(integration: integration)
                }
            }
            DeviceFamiliesPanel()
            SharingPanel()
            NavigationContractPanel()
        }
        .workspacePage()
    }
}

/// Universal Device Intelligence: which families have real adapters, and which are only planned.
private struct DeviceFamiliesPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device intelligence families").font(.headline).foregroundStyle(Theme.text)
            Text("Support is claimed only where an adapter and compatibility tests exist.").font(.caption).foregroundStyle(Theme.dim)
            HStack(spacing: 8) {
                Label("Apple iPhone / iPad — implemented (CoreDevice + IOKit), awaiting physical verification", systemImage: "checkmark.seal.fill")
                    .font(.callout).foregroundStyle(Theme.success)
                Spacer()
                Text(model.toolchain?.summary ?? "Inspecting Xcode…").font(.caption).foregroundStyle(Theme.dim)
            }
            Label("Generic USB / Thunderbolt — host-side information and diagnostics", systemImage: "checkmark.circle").font(.callout).foregroundStyle(Theme.cyan)
            ForEach(PlannedDeviceFamily.all) { f in
                HStack {
                    Image(systemName: f.category.symbolName).foregroundStyle(Theme.dim).frame(width: 18)
                    Text(f.name).font(.callout).foregroundStyle(Theme.text)
                    Text(f.intendedInterfaces.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.dim)
                    Spacer()
                    Text(f.status.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(Theme.violet)
                }
            }
        }
        .glassPanel()
    }
}

/// Prepared exports for HCG Server (inventory) and HCG Sentinel (security findings). Nothing is sent.
private struct SharingPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var document: ExportDocument?
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prepared sharing (local files only)").font(.headline).foregroundStyle(Theme.text)
            Text("No HCG Server is paired and no HCG Connect client exists for System Tester, so nothing is transmitted. These exports use the formats those products will accept.")
                .font(.caption).foregroundStyle(Theme.dim)
            HStack {
                Button("Export device inventory (hcg.systemtester.inventory/1)…") { export({ try model.exportInventorySnapshot() }, name: "hcg-inventory") }
                Button("Export security findings for Sentinel (hcg.diagnostic-report/1)…") { export({ try model.exportSentinelFindings() }, name: "hcg-connection-security") }
            }
        }
        .glassPanel()
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: document?.filename ?? "export") { result in
            if case .failure(let e) = result { model.banner = "Export failed: \(e.localizedDescription)" }
        }
    }

    func export(_ make: () throws -> Data, name: String) {
        do {
            document = ExportDocument(data: try make(), filename: "\(name).json")
            exporting = true
        } catch {
            model.banner = "Export failed: \(error.localizedDescription)"
        }
    }
}

private struct IntegrationCard: View {
    @EnvironmentObject var model: AppModel
    let integration: EcosystemIntegration

    var body: some View {
        let status = model.ecosystemStatus(integration)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(integration.product).font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text(status.displayName.uppercased()).font(.caption2.weight(.heavy))
                    .foregroundStyle(status == .available ? Theme.success : (status == .planned || status == .awaitingContract ? Theme.violet : Theme.warning))
            }
            Text(integration.role).font(.caption).foregroundStyle(Theme.dim)
            Text(integration.contract).font(.caption2.monospaced()).foregroundStyle(Theme.cyan).textSelection(.enabled)
            ForEach(integration.details, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
            Text("CAPABILITIES").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim).padding(.top, 4)
            ForEach(integration.supported, id: \.self) { Text("◦ " + $0).font(.caption2).foregroundStyle(Theme.dim) }
            if integration.id == "hcg-terminal" {
                TerminalLinks()
            } else if integration.id == "hcg-sentinel" {
                SentinelLinks()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

private struct TerminalLinks: View {
    @EnvironmentObject var model: AppModel
    @State private var unleashed = false

    var body: some View {
        HStack {
            Toggle("Unleashed build", isOn: $unleashed).toggleStyle(.switch).controlSize(.small)
                .help("Uses the separate hcgterminal-unleashed:// scheme. Standard and Unleashed stay separate.")
            Menu("Open Terminal at…") {
                ForEach(TerminalDeepLink.destinations, id: \.self) { d in
                    Button(d) {
                        if let url = TerminalDeepLink.url(destination: d, variant: unleashed ? .unleashed : .standard) { model.openNavigationLink(url) }
                    }
                }
            }
            .frame(width: 200)
        }
    }
}

private struct SentinelLinks: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu("Open Sentinel at…") {
            ForEach(SentinelDeepLink.destinations, id: \.self) { d in
                Button(d) { if let url = SentinelDeepLink.url(destination: d) { model.openNavigationLink(url) } }
            }
        }
        .frame(width: 200)
    }
}

private struct NavigationContractPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System Tester navigation routes").font(.headline).foregroundStyle(Theme.text)
            Text("Other HCG apps (Nexus, Terminal) may open these links. They navigate only: queries, extra path segments and unknown routes are rejected, and nothing in a link is ever executed.")
                .font(.caption).foregroundStyle(Theme.dim)
            ForEach(SystemTesterRoute.allCases, id: \.self) { r in
                Text(r.url.absoluteString).font(.caption.monospaced()).foregroundStyle(Theme.cyan).textSelection(.enabled)
            }
        }
        .glassPanel()
    }
}
#endif
