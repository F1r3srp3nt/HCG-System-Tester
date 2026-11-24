#if os(macOS)
import SwiftUI
import AppKit
import HCGCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Settings", subtitle: "Discovery, privacy, accessibility and data.", symbol: "gearshape")
            VStack(alignment: .leading, spacing: 10) {
                Text("Discovery").font(.headline).foregroundStyle(Theme.text)
                Toggle("Real hardware discovery (IOKit, read-only)", isOn: $model.settings.hardwareDiscoveryEnabled)
                Toggle("Synthetic fixtures (always labelled SYNTHETIC)", isOn: $model.settings.syntheticFixturesEnabled)
                Text("Synthetic fixtures run on a separate, clearly marked bus and never replace real discovery.").font(.caption).foregroundStyle(Theme.dim)
                Toggle("Keep disconnected devices in the list", isOn: $model.settings.showDisconnectedDevices)
                Toggle("Record connections in the Device Laboratory", isOn: $model.settings.recordConnectionsInLaboratory)
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 10) {
                Text("Privacy").font(.headline).foregroundStyle(Theme.text)
                Toggle("Mask serial numbers in the interface", isOn: $model.settings.privacy.hideSerialNumbersInInterface)
                Toggle("Redact serial numbers in reports and logs", isOn: $model.settings.privacy.redactSerialNumbers)
                Toggle("Redact network identifiers (IP, MAC, e-mail)", isOn: $model.settings.privacy.redactNetworkIdentifiers)
                Toggle("Redact user paths (/Users/…)", isOn: $model.settings.privacy.redactUserPaths)
                Toggle("Redact this Mac's name", isOn: $model.settings.privacy.redactHostName)
                Text("Credentials, tokens and private keys are always redacted. The Device Laboratory keys devices by a salted fingerprint, never the raw serial number.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 10) {
                Text("Accessibility").font(.headline).foregroundStyle(Theme.text)
                Toggle("Reduce motion (in addition to the system setting)", isOn: $model.settings.reduceMotion)
                Text("All sections are reachable with ⌘1 … ⌘0. ⇧⌘D runs read-only diagnostics on the selected device.").font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 10) {
                Text("Data").font(.headline).foregroundStyle(Theme.text)
                KeyValueRow(key: "Application Support", value: AppPaths.supportDirectory.path, monospaced: true)
                KeyValueRow(key: "Installation ID", value: model.settings.installationID, monospaced: true)
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory]) }
                    Button("Reset Device Laboratory…", role: .destructive) { confirmReset = true }
                }
            }
            .glassPanel()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(HCGSystemTesterInfo.productName) \(HCGSystemTesterInfo.version) (\(HCGSystemTesterInfo.build))").font(.callout).foregroundStyle(Theme.text)
                Text("\(HCGSystemTesterInfo.publisher) · \(HCGSystemTesterInfo.bundleIdentifier) · \(HCGSystemTesterInfo.realm)").font(.caption).foregroundStyle(Theme.dim)
                Text("Read-only discovery. No drivers are installed, no administrator privileges are requested, and connected devices are never modified.")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            .glassPanel()
        }
        .workspacePage()
        .confirmationDialog("Reset the Device Laboratory?", isPresented: $confirmReset) {
            Button("Delete profiles, sessions and history", role: .destructive) { model.laboratory.reset() }
        } message: {
            Text("This permanently deletes saved device profiles, diagnostic sessions and compatibility evidence on this Mac.")
        }
    }
}
#endif
