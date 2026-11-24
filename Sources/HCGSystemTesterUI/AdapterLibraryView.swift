#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import HCGCore

struct AdapterLibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: String?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeader(title: "Adapter Library",
                              subtitle: "Interchangeable hardware and protocol modules. Imported adapters are declarative, start untrusted and never run until you approve them.",
                              symbol: "puzzlepiece.extension")
                Button { importing = true } label: { Label("Import manifest…", systemImage: "square.and.arrow.down") }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.adapters) { a in
                        AdapterRow(adapter: a, selected: selected == a.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = a.id }
                    }
                }
                .frame(width: 360)
                .glassPanel(padding: 10)
                if let id = selected ?? model.adapters.first?.id, let a = model.adapters.first(where: { $0.id == id }) {
                    AdapterDetail(adapter: a).frame(maxWidth: .infinity)
                }
            }
        }
        .workspacePage()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let entry = try model.importAdapter(data: data)
                    selected = entry.id
                    model.banner = "Imported \(entry.manifest.name). It is untrusted and disabled until you review and approve it."
                } catch {
                    model.banner = "Import refused: \(error)"
                }
            case .failure(let error):
                model.banner = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct AdapterRow: View {
    let adapter: RegisteredAdapter
    let selected: Bool

    var body: some View {
        HStack {
            Image(systemName: adapter.origin == .builtIn ? "shippingbox.fill" : "shippingbox")
                .foregroundStyle(adapter.trust == .untrusted ? Theme.warning : Theme.cyan)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(adapter.manifest.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text)
                    if adapter.manifest.experimental { Text("EXPERIMENTAL").font(.caption2.weight(.heavy)).foregroundStyle(Theme.violet) }
                }
                Text("v\(adapter.manifest.version.description) · \(adapter.trust.displayName)").font(.caption2).foregroundStyle(Theme.dim)
            }
            Spacer()
            Circle().fill(adapter.enabled ? Theme.success : Theme.dim).frame(width: 8, height: 8)
                .accessibilityLabel(adapter.enabled ? "Enabled" : "Disabled")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.cyan.opacity(0.15) : .clear))
    }
}

struct AdapterDetail: View {
    @EnvironmentObject var model: AppModel
    let adapter: RegisteredAdapter

    var body: some View {
        let m = adapter.manifest
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(m.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                Text("v\(m.version.description)").foregroundStyle(Theme.dim)
                Spacer()
                if adapter.trust == .untrusted {
                    Button("Review & approve") { model.approveAdapter(m.id) }
                        .buttonStyle(.borderedProminent).tint(Theme.warning.opacity(0.8))
                        .disabled(adapter.validationIssues.contains { $0.severity == .error })
                } else if adapter.origin != .builtIn {
                    Toggle("Enabled", isOn: Binding(get: { adapter.enabled }, set: { model.setAdapterEnabled(m.id, $0) }))
                }
                if adapter.origin != .builtIn {
                    Button(role: .destructive) { model.removeAdapter(m.id) } label: { Label("Remove", systemImage: "trash") }
                }
            }
            Text(m.summary).font(.callout).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            Group {
                KeyValueRow(key: "Identifier", value: m.id, monospaced: true)
                KeyValueRow(key: "Publisher", value: m.publisher)
                KeyValueRow(key: "Origin / trust", value: "\(adapter.origin.rawValue) · \(adapter.trust.displayName)")
                KeyValueRow(key: "Execution model", value: m.execution == .builtIn ? "Built-in (first-party, compiled)" : "Declarative (host operations only)")
                KeyValueRow(key: "Device families", value: m.deviceFamilies.count == DeviceCategory.allCases.count ? "All" : m.deviceFamilies.map(\.displayName).joined(separator: ", "))
            }
            Group {
                KeyValueRow(key: "Connections", value: m.connectionTypes.map(\.displayName).joined(separator: ", "))
                KeyValueRow(key: "Protocols", value: m.protocols.joined(separator: ", "))
                KeyValueRow(key: "Permissions", value: m.permissions.map { $0.displayName + ($0.isPrivileged ? " (privileged)" : "") }.joined(separator: "; "))
                KeyValueRow(key: "Lifecycle", value: m.lifecycle.stages.map(\.rawValue).joined(separator: " → ") + (m.lifecycle.requiresExplicitAuthorization ? " · explicit authorisation" : ""))
                KeyValueRow(key: "Compatibility", value: "\(m.compatibility.platforms.joined(separator: ", ")) · host ≥ \(m.compatibility.minimumHostVersion.description)")
            }
            if !m.hardwareRequirements.isEmpty || !m.driverRequirements.isEmpty {
                DetailList(title: "Requirements", items: m.hardwareRequirements + m.driverRequirements.map { "\($0.name)\($0.providedByMacOS ? " (provided by macOS)" : " (not provided by macOS)") \($0.notes)" }, color: Theme.text)
            }
            Text("OPERATIONS").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
            ForEach(m.operations) { op in
                HStack(alignment: .top) {
                    Image(systemName: op.category.symbolName).foregroundStyle(Theme.cyan).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(op.name)  ·  \(op.impact.displayName)").font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("→ host operation \(op.hostOperation)").font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                    }
                }
            }
            if !m.errors.isEmpty {
                DetailList(title: "Error handling", items: m.errors.map { "\($0.code): \($0.meaning) — \($0.recovery)" }, color: Theme.dim)
            }
            if !m.healthChecks.isEmpty {
                DetailList(title: "Health checks", items: m.healthChecks.map { "\($0.id) every \(Int($0.intervalSeconds)) s via \($0.hostOperation)" }, color: Theme.dim)
            }
            ValidationList(issues: adapter.validationIssues)
        }
        .glassPanel()
    }
}

struct ValidationList: View {
    let issues: [ValidationIssue]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("VALIDATION").font(.caption2.weight(.heavy)).foregroundStyle(Theme.dim)
            if issues.isEmpty {
                Label("Manifest is valid", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(Theme.success)
            }
            ForEach(issues) { i in
                Label("\(i.path): \(i.message)", systemImage: i.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(i.severity == .error ? Theme.danger : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
