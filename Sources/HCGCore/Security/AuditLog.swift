import Foundation

public struct AuditEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var actor: String
    public var operation: String
    public var impact: OperationImpact
    public var target: String
    public var targetKey: String
    public var decision: String
    public var outcome: String
    public var provenance: DataProvenance

    public init(id: UUID = UUID(), timestamp: Date = Date(), actor: String, operation: String, impact: OperationImpact,
                target: String, targetKey: String, decision: String, outcome: String, provenance: DataProvenance) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.operation = operation
        self.impact = impact
        self.target = target
        self.targetKey = targetKey
        self.decision = decision
        self.outcome = outcome
        self.provenance = provenance
    }
}

/// Append-only audit trail of diagnostic operations and authorisation decisions.
public final class AuditLog {
    private let lock = NSLock()
    private var storage: [AuditEntry] = []
    public let fileURL: URL?
    public var onAppend: ((AuditEntry) -> Void)?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            storage = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .compactMap { try? Self.decoder.decode(AuditEntry.self, from: Data($0.utf8)) }
        }
    }

    public var entries: [AuditEntry] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public func record(_ entry: AuditEntry) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
        if let url = fileURL, let line = try? Self.encoder.encode(entry) {
            appendLine(line + Data("\n".utf8), to: url)
        }
        onAppend?(entry)
    }

    private func appendLine(_ data: Data, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: data)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
