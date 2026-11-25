import Foundation

public struct MonitorSample: Codable, Hashable, Identifiable {
    public var id: UUID
    public var at: Date
    public var present: Bool
    public var latencyMs: Double?
    /// e.g. "IOKit registry re-read" or "devicectl device info details".
    public var source: String
    public var provenance: DataProvenance

    public init(at: Date = Date(), present: Bool, latencyMs: Double?, source: String, provenance: DataProvenance) {
        self.id = UUID()
        self.at = at
        self.present = present
        self.latencyMs = latencyMs
        self.source = source
        self.provenance = provenance
    }
}

public struct MonitorStats: Hashable {
    public var connectedSince: Date?
    public var uptimeSeconds: Double
    public var samples: Int
    public var availabilityPercent: Double?
    public var dropouts: Int
    public var latencyBySource: [String: (min: Double, mean: Double, max: Double, last: Double, count: Int)]

    public static func == (l: MonitorStats, r: MonitorStats) -> Bool {
        l.connectedSince == r.connectedSince && l.samples == r.samples && l.dropouts == r.dropouts
    }
    public func hash(into h: inout Hasher) { h.combine(samples); h.combine(dropouts) }
}

/// Live measurements per physical unit (stable key). Only real samples are stored; nothing is interpolated.
public final class LiveMonitor {
    public var maxSamples = 720
    public private(set) var series: [String: [MonitorSample]] = [:]
    public private(set) var connectedSince: [String: Date] = [:]
    public private(set) var dropouts: [String: Int] = [:]

    public init() {}

    public func connected(key: String, at: Date = Date()) {
        if connectedSince[key] == nil { connectedSince[key] = at }
    }

    public func disconnected(key: String, at: Date = Date()) {
        connectedSince[key] = nil
        dropouts[key, default: 0] += 1
        record(MonitorSample(at: at, present: false, latencyMs: nil, source: "Disconnect event", provenance: .hardware), key: key)
    }

    public func record(_ s: MonitorSample, key: String) {
        series[key, default: []].append(s)
        if series[key]!.count > maxSamples { series[key]!.removeFirst(series[key]!.count - maxSamples) }
    }

    public func samples(key: String) -> [MonitorSample] { series[key] ?? [] }

    public func stats(key: String, now: Date = Date()) -> MonitorStats {
        let s = samples(key: key)
        let presence = s.filter { $0.source != "Disconnect event" }
        let available = presence.isEmpty ? nil : Double(presence.filter(\.present).count) / Double(presence.count) * 100
        var bySource: [String: (min: Double, mean: Double, max: Double, last: Double, count: Int)] = [:]
        for source in Set(s.compactMap { $0.latencyMs == nil ? nil : $0.source }) {
            let values = s.filter { $0.source == source }.compactMap(\.latencyMs)
            guard !values.isEmpty else { continue }
            bySource[source] = (values.min()!, values.reduce(0, +) / Double(values.count), values.max()!, values.last!, values.count)
        }
        let since = connectedSince[key]
        return MonitorStats(connectedSince: since, uptimeSeconds: since.map { now.timeIntervalSince($0) } ?? 0, samples: s.count,
                            availabilityPercent: available, dropouts: dropouts[key] ?? 0, latencyBySource: bySource)
    }

    public func reset(key: String) {
        series[key] = nil
        dropouts[key] = nil
    }
}
