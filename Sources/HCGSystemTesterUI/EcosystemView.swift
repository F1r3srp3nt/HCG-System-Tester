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
            NavigationContractPanel()
        }
        .workspacePage()
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
