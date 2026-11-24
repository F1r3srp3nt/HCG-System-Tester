#if os(macOS)
import SwiftUI
import HCGCore

/// The HCG scientific-instrument palette: obsidian, deep navy, electric cyan, violet, metal.
enum Theme {
    static let obsidian = Color(red: 0.035, green: 0.039, blue: 0.055)
    static let navy = Color(red: 0.047, green: 0.075, blue: 0.145)
    static let navyHigh = Color(red: 0.075, green: 0.11, blue: 0.2)
    static let cyan = Color(red: 0.0, green: 0.86, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.4, blue: 1.0)
    static let metal = Color(red: 0.68, green: 0.72, blue: 0.8)
    static let text = Color(red: 0.9, green: 0.94, blue: 1.0)
    static let dim = Color(red: 0.55, green: 0.62, blue: 0.74)
    static let success = Color(red: 0.25, green: 0.95, blue: 0.62)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.25)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.42)
    static let synthetic = Color(red: 1.0, green: 0.45, blue: 0.85)

    static let background = LinearGradient(colors: [obsidian, navy.opacity(0.92), obsidian],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentGradient = LinearGradient(colors: [cyan, violet], startPoint: .leading, endPoint: .trailing)
    static let metalGradient = LinearGradient(colors: [metal.opacity(0.55), metal.opacity(0.12), metal.opacity(0.4)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(for status: DeviceStatus) -> Color {
        switch status {
        case .authenticated: return success
        case .connected: return cyan
        case .diagnosticsAvailable: return Color(red: 0.4, green: 0.78, blue: 1.0)
        case .identified: return violet
        case .detected: return metal
        case .adapterRequired: return warning
        case .unsupported: return danger.opacity(0.85)
        case .disconnected: return dim.opacity(0.6)
        }
    }

    static func color(for outcome: DiagnosticOutcome) -> Color {
        switch outcome {
        case .passed: return success
        case .warning: return warning
        case .failed, .error: return danger
        case .aborted: return Color.orange
        case .notSupported, .skipped: return dim
        }
    }

    static func color(for state: LayerState) -> Color {
        switch state {
        case .verified: return success
        case .partial: return warning
        case .notVerified: return dim
        case .unavailable: return danger
        case .notApplicable: return metal.opacity(0.5)
        }
    }

    static func color(for support: SupportLevel) -> Color {
        switch support {
        case .live: return success
        case .partial: return cyan
        case .planned: return violet
        case .requiresAdapter: return warning
        case .unavailable: return danger
        }
    }

    static func symbol(for outcome: DiagnosticOutcome) -> String {
        switch outcome {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .aborted: return "bolt.slash.fill"
        case .notSupported: return "minus.circle"
        case .skipped: return "forward.end.circle"
        }
    }

    static func symbol(for state: LayerState) -> String {
        switch state {
        case .verified: return "checkmark.seal.fill"
        case .partial: return "circle.lefthalf.filled"
        case .notVerified: return "circle.dashed"
        case .unavailable: return "xmark.circle"
        case .notApplicable: return "minus.circle"
        }
    }
}

/// Glass panel with a metallic hairline border.
struct GlassPanel: ViewModifier {
    var padding: CGFloat = 16
    var glow: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Theme.navy.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.metalGradient, lineWidth: 0.8))
            .shadow(color: (glow ?? .clear).opacity(0.35), radius: glow == nil ? 0 : 14)
    }
}

extension View {
    func glassPanel(padding: CGFloat = 16, glow: Color? = nil) -> some View {
        modifier(GlassPanel(padding: padding, glow: glow))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol = symbol {
                Image(systemName: symbol).foregroundStyle(Theme.accentGradient).font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                if let subtitle = subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(Theme.dim)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct StatusBadge: View {
    let status: DeviceStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(Theme.color(for: status))
            .background(Theme.color(for: status).opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.color(for: status).opacity(0.45), lineWidth: 0.7))
            .help(status.meaning)
            .accessibilityLabel("Status: \(status.displayName). \(status.meaning)")
    }
}

struct ProvenanceBadge: View {
    let provenance: DataProvenance

    var body: some View {
        if provenance == .synthetic {
            Label("SYNTHETIC", systemImage: "flask.fill")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(Theme.synthetic)
                .background(Theme.synthetic.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.synthetic.opacity(0.6), lineWidth: 0.7))
                .help("Simulated fixture. This is not real hardware.")
                .accessibilityLabel("Synthetic data, not real hardware")
        } else if provenance == .hardware {
            Label("REAL HARDWARE", systemImage: "cpu")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(Theme.cyan)
                .background(Theme.cyan.opacity(0.1), in: Capsule())
                .help("Observed from macOS hardware discovery (IOKit).")
        } else {
            Label("IMPORTED", systemImage: "tray.and.arrow.down")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(Theme.metal)
                .background(Theme.metal.opacity(0.1), in: Capsule())
        }
    }
}

struct OutcomeBadge: View {
    let outcome: DiagnosticOutcome
    var body: some View {
        Label(outcome.displayName, systemImage: Theme.symbol(for: outcome))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.color(for: outcome))
            .accessibilityLabel("Result: \(outcome.displayName)")
    }
}

struct SupportBadge: View {
    let support: SupportLevel
    var body: some View {
        Text(support.displayName.uppercased())
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(Theme.color(for: support))
            .background(Theme.color(for: support).opacity(0.13), in: Capsule())
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color = Theme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.dim)
                Spacer()
            }
            Text(value).font(.system(size: 30, weight: .light, design: .rounded)).foregroundStyle(Theme.text)
                .monospacedDigit()
            if let detail = detail {
                Text(detail).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(padding: 14, glow: tint)
        .accessibilityElement(children: .combine)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(Theme.dim).frame(width: 170, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

/// A placeholder for empty states that explains *why* something is empty.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .thin)).foregroundStyle(Theme.accentGradient)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text(message).font(.callout).foregroundStyle(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}

/// Root background for every workspace pane.
struct WorkspaceBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.cyan.opacity(0.08), .clear], center: .topTrailing, startRadius: 10, endRadius: 600)
            RadialGradient(colors: [Theme.violet.opacity(0.08), .clear], center: .bottomLeading, startRadius: 10, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard scrolling page layout for a workspace section.
    func workspacePage() -> some View {
        ScrollView {
            self.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(WorkspaceBackground())
    }
}

enum Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}
#endif
