#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import HCGCore

/// A draft adapter project. Drafts are data only and are validated, tested against
/// synthetic fixtures, versioned and exported — never executed as code.
struct StudioProject: Codable, Identifiable, Hashable {
    var id = UUID()
    var manifest: AdapterManifest
    var versions: [String] = []
    var log: [String] = []
    var updatedAt = Date()
}

@MainActor
final class StudioStore: ObservableObject {
    @Published var projects: [StudioProject] = []
    private var url: URL { AppPaths.supportDirectory.appendingPathComponent("studio-projects.json") }

    init() {
        if let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([StudioProject].self, from: data) { projects = p }
    }

    func save() {
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(projects) { try? data.write(to: url, options: .atomic) }
    }

    @discardableResult
    func create(name: String) -> StudioProject {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let manifest = AdapterManifest(
            id: "com.example.adapter.\(slug.isEmpty ? "draft" : slug)", name: name, version: SemanticVersion(0, 1, 0), publisher: "Your name",
            summary: "Describe what this adapter identifies and diagnoses.", deviceFamilies: [.unknown], connectionTypes: [.usb],
            protocols: ["usb.descriptor"], match: DeviceMatchRules(vendorIDs: [0xF00D]),
            permissions: [.readDeviceDescriptors],
            operations: [DiagnosticOperationDescriptor(id: "presence", name: "Presence", hostOperation: "host.presence", category: .connectionHealth, summary: "Confirms the device is enumerated.")])
        var p = StudioProject(manifest: manifest)
        p.log.append(stamp("Created project from the declarative template."))
        projects.insert(p, at: 0)
        save()
        return p
    }

    func update(_ p: StudioProject) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        var copy = p
        copy.updatedAt = Date()
        projects[i] = copy
        save()
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    func stamp(_ s: String) -> String { "[\(Formatters.time.string(from: Date()))] \(s)" }
}

struct DeveloperStudioView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var store = StudioStore()
    @State private var selection: UUID?
    @State private var newName = ""
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Adapter Developer Studio",
                          subtitle: "Create, edit, validate and test declarative adapters against synthetic fixtures. Nothing here runs untrusted code.",
                          symbol: "hammer")
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("New adapter name", text: $newName)
                        Button("Create") {
                            selection = store.create(name: newName.isEmpty ? "Untitled Adapter" : newName).id
                            newName = ""
                        }
                    }
                    Button { importing = true } label: { Label("Import manifest into Studio…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.link)
                    Divider().opacity(0.2)
                    if store.projects.isEmpty {
                        Text("No projects yet.").font(.caption).foregroundStyle(Theme.dim)
                    }
                    ForEach(store.projects) { p in
                        HStack {
                            Image(systemName: "doc.badge.gearshape").foregroundStyle(Theme.violet)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.manifest.name).font(.callout).foregroundStyle(Theme.text)
                                Text("v\(p.manifest.version.description) · \(p.manifest.id)").font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selection == p.id ? Theme.violet.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selection = p.id }
                    }
                }
                .frame(width: 300)
                .glassPanel(padding: 12)

                if let id = selection, let project = store.projects.first(where: { $0.id == id }) {
                    StudioEditor(project: project, store: store).id(project.id)
                        .frame(maxWidth: .infinity)
                } else {
                    EmptyStateView(symbol: "hammer", title: "Create or select an adapter project",
                                   message: "Adapters declare device families, match rules, protocols, permissions and diagnostic operations. Operations map to host-implemented tests only, so an adapter can never run arbitrary code on your Mac.")
                        .glassPanel()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .workspacePage()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let m = try AdapterManifest.decode(Data(contentsOf: url))
                var p = StudioProject(manifest: m)
                p.log.append(store.stamp("Imported from \(url.lastPathComponent). Not executed."))
                store.projects.insert(p, at: 0)
                store.save()
                selection = p.id
            } catch {
                model.banner = "Not a valid adapter manifest: \(error.localizedDescription)"
            }
        }
    }
}

private enum StudioTab: String, CaseIterable, Identifiable {
    case manifest = "Manifest"
    case profiles = "Device profiles"
    case json = "JSON"
    case test = "Test & validate"
    var id: String { rawValue }
}

private struct StudioEditor: View {
    @EnvironmentObject var model: AppModel
    @State var project: StudioProject
    @ObservedObject var store: StudioStore
    @State private var tab: StudioTab = .manifest
    @State private var jsonText = ""
    @State private var jsonError: String?
    @State private var exporting = false
    @State private var testResults: [DiagnosticRun] = []
    @State private var running = false

    var issues: [ValidationIssue] { ManifestValidator.validate(project.manifest, origin: .developerStudio) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(project.manifest.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Text("v\(project.manifest.version.description)").foregroundStyle(Theme.dim)
                Spacer()
                Menu("Version") {
                    Button("Bump patch") { bump(0, 0, 1) }
                    Button("Bump minor") { bump(0, 1, 0) }
                    Button("Bump major") { bump(1, 0, 0) }
                }
                .frame(width: 100)
                Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button("Send to Adapter Library") { sendToLibrary() }
                    .disabled(issues.contains { $0.severity == .error })
                    .help("Registers a copy as an untrusted, disabled adapter. You approve it in the Adapter Library.")
                Button(role: .destructive) { store.delete(project.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete project")
            }
            Picker("", selection: $tab) {
                ForEach(StudioTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .manifest: ManifestForm(manifest: $project.manifest)
            case .profiles: ProfileEditor(manifest: $project.manifest)
            case .json: jsonEditor
            case .test: testPanel
            }
            ValidationList(issues: issues)
            DetailList(title: "Test log", items: Array(project.log.suffix(20)), color: Theme.dim)
        }
        .glassPanel()
        .onChange(of: project) { _, newValue in store.update(newValue) }
        .onChange(of: tab) { _, newTab in
            if newTab == .json, let data = try? project.manifest.encoded() { jsonText = String(decoding: data, as: UTF8.self) }
        }
        .fileExporter(isPresented: $exporting, document: ManifestDocument(manifest: project.manifest),
                      contentType: .json, defaultFilename: "\(project.manifest.id)-\(project.manifest.version.description).json") { result in
            if case .success(let url) = result { project.log.append(store.stamp("Exported to \(url.lastPathComponent).")) }
        }
    }

    var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $jsonText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .background(Theme.obsidian.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Apply JSON") {
                    do {
                        project.manifest = try AdapterManifest.decode(Data(jsonText.utf8))
                        jsonError = nil
                        project.log.append(store.stamp("Applied JSON edits."))
                    } catch {
                        jsonError = String(describing: error)
                    }
                }
                if let e = jsonError { Text(e).font(.caption).foregroundStyle(Theme.danger).lineLimit(3) }
            }
        }
    }

    var testPanel: some View {
        let registry = AdapterRegistry(builtIns: [])
        let entry = try? registry.register(project.manifest, origin: .developerStudio)
        let fixtures = SyntheticFixtures.all
        return VStack(alignment: .leading, spacing: 10) {
            Text("Compatibility validation").font(.headline).foregroundStyle(Theme.text)
            Text("Match rules are evaluated against labelled synthetic fixtures and against the devices connected now (metadata only — nothing is executed on real hardware).")
                .font(.caption).foregroundStyle(Theme.dim)
            if entry == nil {
                Text("Fix validation errors to evaluate compatibility.").font(.caption).foregroundStyle(Theme.warning)
            } else {
                ForEach(fixtures + model.hardwareRecords.map(\.device)) { device in
                    let ident = model.identification.identify(device)
                    let matched = project.manifest.match.evaluate(device) != nil
                    HStack {
                        Image(systemName: matched ? "checkmark.circle.fill" : "circle").foregroundStyle(matched ? Theme.success : Theme.dim)
                        Text(device.displayName).font(.caption).foregroundStyle(Theme.text)
                        ProvenanceBadge(provenance: device.provenance)
                        Spacer()
                        Text(ident.category.displayName).font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
            }
            Divider().opacity(0.2)
            Text("Diagnostic operation testing (synthetic fixtures only)").font(.headline).foregroundStyle(Theme.text)
            HStack {
                Button(running ? "Running…" : "Run operations on matching synthetic fixtures") { runSyntheticTests() }
                    .disabled(running || entry == nil)
                Text("State-changing operations are skipped unless they target the Synthetic Lab fault injector.").font(.caption2).foregroundStyle(Theme.dim)
            }
            ForEach(testResults) { run in
                VStack(alignment: .leading, spacing: 4) {
                    RunSummary(run: run)
                    ForEach(run.results) { r in
                        HStack { OutcomeBadge(outcome: r.outcome); Text("\(r.testName): \(r.summary)").font(.caption).foregroundStyle(Theme.text) }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.navyHigh.opacity(0.4)))
            }
        }
    }

    func bump(_ major: Int, _ minor: Int, _ patch: Int) {
        let v = project.manifest.version
        project.versions.append(v.description)
        if major > 0 { project.manifest.version = SemanticVersion(v.major + 1, 0, 0) }
        else if minor > 0 { project.manifest.version = SemanticVersion(v.major, v.minor + 1, 0) }
        else { project.manifest.version = SemanticVersion(v.major, v.minor, v.patch + 1) }
        project.log.append(store.stamp("Version \(v.description) → \(project.manifest.version.description)."))
    }

    func sendToLibrary() {
        do {
            let data = try project.manifest.encoded()
            let entry = try model.importAdapter(data: data, origin: .developerStudio)
            project.log.append(store.stamp("Registered \(entry.manifest.id) v\(entry.manifest.version.description) in the Adapter Library (untrusted, disabled)."))
            model.banner = "Sent to the Adapter Library. Review and approve it there before it can be used."
        } catch {
            project.log.append(store.stamp("Registration refused: \(error)"))
        }
    }

    func runSyntheticTests() {
        running = true
        let manifest = project.manifest
        let backend = SyntheticDiscoveryBackend()
        let engine = DiagnosticEngine()
        let ident = model.identification
        let targets = SyntheticFixtures.all.filter { manifest.match.evaluate($0) != nil }
        project.log.append(store.stamp("Testing \(manifest.operations.count) operation(s) on \(targets.count) matching synthetic fixture(s)."))
        Task { @MainActor in
            var runs: [DiagnosticRun] = []
            for device in targets {
                let ctx = DiagnosticContext(device: device, identification: ident.identify(device), probe: backend, sleep: { _ in })
                runs.append(await engine.run(testIDs: manifest.operations.map(\.hostOperation), context: ctx, authorization: .readOnly))
            }
            testResults = runs
            running = false
            project.log.append(store.stamp(targets.isEmpty ? "No synthetic fixture matches these rules." : "Completed \(runs.count) synthetic run(s)."))
        }
    }
}

private struct ManifestForm: View {
    @Binding var manifest: AdapterManifest
    @State private var vendorText = ""
    @State private var productText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                LabeledContent("Identifier") { TextField("com.example.adapter.widget", text: $manifest.id) }
                LabeledContent("Name") { TextField("Name", text: $manifest.name) }
                LabeledContent("Publisher") { TextField("Publisher", text: $manifest.publisher) }
                LabeledContent("Summary") { TextField("Summary", text: $manifest.summary, axis: .vertical).lineLimit(2...4) }
                Toggle("Experimental", isOn: $manifest.experimental)
            }
            Group {
                LabeledContent("Vendor IDs (hex, comma-separated)") {
                    TextField("0x054C, 0x057E", text: $vendorText).onSubmit { manifest.match.vendorIDs = parseHex(vendorText) }
                }
                LabeledContent("Product IDs (hex)") {
                    TextField("0x0CE6", text: $productText).onSubmit { manifest.match.productIDs = parseHex(productText) }
                }
            }
            MultiToggle(title: "Device families", all: DeviceCategory.allCases, selected: $manifest.deviceFamilies) { $0.displayName }
            MultiToggle(title: "Connection types", all: ConnectionType.allCases, selected: $manifest.connectionTypes) { $0.displayName }
            MultiToggle(title: "Protocols", all: ProtocolCatalog.all.map(\.id), selected: $manifest.protocols) { $0 }
            MultiToggle(title: "Permissions", all: AdapterPermission.allCases, selected: $manifest.permissions) { $0.displayName + ($0.isPrivileged ? " ⚠︎" : "") }
            OperationsEditor(manifest: $manifest)
        }
        .onAppear {
            vendorText = manifest.match.vendorIDs.map(Hex.format16).joined(separator: ", ")
            productText = manifest.match.productIDs.map(Hex.format16).joined(separator: ", ")
        }
    }

    func parseHex(_ text: String) -> [UInt16] {
        text.split(separator: ",").compactMap { Hex.parse16(String($0)) }
    }
}

private struct MultiToggle<Item: Hashable>: View {
    let title: String
    let all: [Item]
    @Binding var selected: [Item]
    let label: (Item) -> String

    var body: some View {
        DisclosureGroup("\(title) (\(selected.count))") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(all, id: \.self) { item in
                    Toggle(label(item), isOn: Binding(
                        get: { selected.contains(item) },
                        set: { on in
                            if on { if !selected.contains(item) { selected.append(item) } } else { selected.removeAll { $0 == item } }
                        }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
    }
}

private struct OperationsEditor: View {
    @Binding var manifest: AdapterManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPERATIONS → HOST OPERATIONS").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
            ForEach(Array(manifest.operations.enumerated()), id: \.element.id) { index, op in
                HStack {
                    Text(op.name).font(.caption).foregroundStyle(Theme.text)
                    Text(op.hostOperation).font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                    Text(op.impact.displayName).font(.caption2).foregroundStyle(op.impact == .readOnly ? Theme.success : Theme.warning)
                    Spacer()
                    Button { manifest.operations.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(op.name)")
                }
            }
            Menu("Add host operation") {
                ForEach(HostOperationCatalog.descriptors) { d in
                    Button("\(d.name) (\(d.impact.displayName))") {
                        var opID = d.id.replacingOccurrences(of: "host.", with: "")
                        while manifest.operations.contains(where: { $0.id == opID }) { opID += "-2" }
                        manifest.operations.append(DiagnosticOperationDescriptor(
                            id: opID, name: d.name, hostOperation: d.id, category: d.category, impact: d.impact,
                            requiredCapabilities: d.requiredCapabilities, summary: d.summary, effects: d.effects))
                    }
                }
            }
            .frame(width: 220)
        }
    }
}

private struct ProfileEditor: View {
    @Binding var manifest: AdapterManifest
    @State private var name = ""
    @State private var category: DeviceCategory = .unknown
    @State private var vendor = ""
    @State private var product = ""
    @State private var limitation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device profiles contributed by this adapter are used by the identification engine once the adapter is approved.")
                .font(.caption).foregroundStyle(Theme.dim)
            ForEach(manifest.profiles) { p in
                HStack {
                    Text(p.name).font(.callout).foregroundStyle(Theme.text)
                    Text(p.category.displayName).font(.caption).foregroundStyle(Theme.dim)
                    Text(p.match.vendorIDs.map(Hex.format16).joined(separator: ",") + " / " + p.match.productIDs.map(Hex.format16).joined(separator: ","))
                        .font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                    Spacer()
                    Button { manifest.profiles.removeAll { $0.id == p.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Divider().opacity(0.2)
            TextField("Profile name", text: $name)
            Picker("Category", selection: $category) {
                ForEach(DeviceCategory.allCases) { Text($0.displayName).tag($0) }
            }
            HStack {
                TextField("Vendor ID (hex)", text: $vendor)
                TextField("Product IDs (hex, comma-separated)", text: $product)
            }
            TextField("Known limitation (shown verbatim to users)", text: $limitation)
            Button("Add profile") {
                guard let v = Hex.parse16(vendor), !name.isEmpty else { return }
                let pids = product.split(separator: ",").compactMap { Hex.parse16(String($0)) }
                let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
                manifest.profiles.append(DeviceProfile(
                    id: "\(manifest.id).\(slug)", name: name, category: category, family: manifest.name,
                    match: DeviceMatchRules(vendorIDs: [v], productIDs: pids),
                    exposedProtocols: manifest.protocols, recommendedAdapters: [manifest.id],
                    knownLimitations: limitation.isEmpty ? [] : [limitation], priority: 85))
                name = ""; vendor = ""; product = ""; limitation = ""
            }
        }
    }
}

struct ManifestDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var manifest: AdapterManifest

    init(manifest: AdapterManifest) { self.manifest = manifest }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        manifest = try AdapterManifest.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try manifest.encoded())
    }
}
#endif
