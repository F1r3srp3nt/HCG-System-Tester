import Foundation

/// Where a piece of device data came from.
///
/// Every device, measurement and diagnostic result carries a provenance so that
/// real hardware observations can never be confused with synthetic fixtures.
public enum DataProvenance: String, Codable, CaseIterable, Hashable {
    /// Observed from a real operating-system discovery backend (e.g. IOKit).
    case hardware
    /// Fabricated by a synthetic fixture for testing. Always labelled in the UI and in reports.
    case synthetic
    /// Loaded from a previously saved profile or report; not live.
    case imported

    public var displayName: String {
        switch self {
        case .hardware: return "Real hardware"
        case .synthetic: return "SYNTHETIC"
        case .imported: return "Imported record"
        }
    }

    public var isSynthetic: Bool { self == .synthetic }
}
