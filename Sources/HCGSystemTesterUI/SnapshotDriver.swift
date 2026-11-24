#if os(macOS)
import AppKit
import SwiftUI
import HCGCore

/// Renders every workspace section to PNG files and quits. Used by CI and for documentation:
///
///     "HCG System Tester.app/Contents/MacOS/HCGSystemTester" --hcg-snapshot /path/to/dir
///
/// Snapshot mode turns on labelled synthetic fixtures *in memory only* (settings are not saved), runs the
/// read-only suite on one synthetic device and one real device if present, and never touches anything else.
@MainActor
enum SnapshotDriver {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--hcg-snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static var isActive: Bool { outputDirectory != nil }

    static func run(model: AppModel) {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model.enableSyntheticFixturesForSnapshot()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                window.setContentSize(NSSize(width: 1480, height: 920))
                window.center()
            }
            let target = model.presentRecords.first { $0.device.provenance.isSynthetic && $0.device.name.contains("USB 3 SSD") }
                ?? model.presentRecords.first
            for section in WorkspaceSection.allCases {
                model.section = section
                if section == .connectedSystems || section == .diagnostics { model.selectedDeviceID = target?.id }
                if section == .diagnostics, let t = target {
                    model.runDefaultSuite(on: t)
                    if let real = model.hardwareRecords.first { model.runDefaultSuite(on: real) }
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                }
                if section == .reports {
                    model.generateReport(title: "Snapshot report", runs: model.recentRuns, deviceIDs: model.presentRecords.map(\.id))
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                capture(name: String(format: "%02ld-%@", (WorkspaceSection.allCases.firstIndex(of: section) ?? 0) + 1, section.rawValue), into: dir)
            }
            let summary = model.records.map { "\($0.device.displayName)\t\($0.status.displayName)\t\($0.device.provenance.rawValue)" }.joined(separator: "\n")
            try? summary.write(to: dir.appendingPathComponent("devices.tsv"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    static func capture(name: String, into dir: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(name + ".png"))
        }
    }
}
#endif
