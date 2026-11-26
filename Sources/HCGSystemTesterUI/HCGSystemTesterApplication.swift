#if os(macOS)
import SwiftUI
import HCGCore

/// The HCG System Tester application. Launched by the Xcode app target (`AppMain`) and by
/// the SwiftPM executable (`swift run HCGSystemTester`).
public struct HCGSystemTesterApplication: App {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        WindowGroup(HCGSystemTesterInfo.productName, id: "workspace") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .onAppear {
                    model.startIfNeeded()
                    if SnapshotDriver.isActive { SnapshotDriver.run(model: model) }
                }
                .onOpenURL { model.handleIncoming($0) }
        }
        .defaultSize(width: 1480, height: 920)
        .commands { WorkspaceCommands(model: model) }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 720, height: 640)
                .preferredColorScheme(.dark)
        }
    }
}

struct WorkspaceCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Workspace") {
            ForEach(WorkspaceSection.workspaceSections) { section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(section.shortcut, modifiers: section.shortcutModifiers)
            }
        }
        CommandMenu("Connectivity") {
            ForEach(WorkspaceSection.connectivitySections) { section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(section.shortcut, modifiers: section.shortcutModifiers)
            }
        }
        CommandMenu("Devices") {
            Button("Run Read-Only Diagnostics on Selection") {
                if let r = model.selectedRecord, r.device.isPresent { model.runDefaultSuite(on: r) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(model.selectedRecord?.device.isPresent != true)
            Button("Restart Hardware Discovery") { model.restartDiscovery() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Clear Disconnected Devices") { model.clearDisconnected() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            ZStack(alignment: .top) {
                SectionContent(section: model.section)
                    .id(model.section)
                if let banner = model.banner {
                    BannerView(text: banner) { model.banner = nil }
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle(model.section.title)
        .background(WorkspaceBackground())
    }
}

struct SectionContent: View {
    let section: WorkspaceSection

    var body: some View {
        switch section {
        case .commandCenter: CommandCenterView()
        case .connectedSystems: ConnectedSystemsView()
        case .liveMonitor: LiveMonitorView()
        case .visualizer: VisualizerView()
        case .usbInspector: USBInspectorView()
        case .diagnostics: DiagnosticsView()
        case .laboratory: LaboratoryView()
        case .adapterLibrary: AdapterLibraryView()
        case .developerStudio: DeveloperStudioView()
        case .ecosystem: EcosystemView()
        case .reports: ReportsView()
        case .settings: SettingsView()
        default: ConnectivitySectionHost(section: section)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: Binding<WorkspaceSection?>(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            Section {
                ForEach(WorkspaceSection.workspaceSections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .badge(badge(for: section))
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HCG SYSTEM TESTER").font(.caption.weight(.heavy)).foregroundStyle(Theme.accentGradient)
                    Text("v\(HCGSystemTesterInfo.version) · \(HCGSystemTesterInfo.realm)").font(.caption2).foregroundStyle(Theme.dim)
                }
                .padding(.bottom, 6)
            }
            Section("Universal Connectivity") {
                ForEach(WorkspaceSection.connectivitySections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            Section("Live") {
                LiveDiscoveryIndicator()
            }
        }
        .listStyle(.sidebar)
    }

    func badge(for section: WorkspaceSection) -> Int {
        switch section {
        case .connectedSystems: return model.presentRecords.count
        case .liveMonitor: return model.presentRecords.filter { model.snapshot($0.id)?.state.needsUserAttention == true }.count
        case .diagnostics: return model.activeRuns.count
        case .reports: return model.reports.count
        default: return 0
        }
    }
}

struct LiveDiscoveryIndicator: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.backendStatuses) { s in
                HStack(spacing: 6) {
                    Circle().fill(s.state == .running ? Theme.success : (s.state == .failed ? Theme.danger : Theme.dim))
                        .frame(width: 7, height: 7)
                    Text(s.displayName).font(.caption)
                    if s.provenance == .synthetic { ProvenanceBadge(provenance: .synthetic) }
                }
                .help(s.detail)
            }
            if model.backendStatuses.isEmpty {
                Text("Discovery not started").font(.caption).foregroundStyle(Theme.dim)
            }
            Text("\(model.hardwareRecords.count) real device(s) present").font(.caption2).foregroundStyle(Theme.dim)
        }
    }
}

struct BannerView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.cyan)
            Text(text).font(.callout).foregroundStyle(Theme.text)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.4)))
        .shadow(radius: 10)
    }
}
#endif
