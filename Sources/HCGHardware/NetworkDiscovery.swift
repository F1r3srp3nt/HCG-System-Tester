import Foundation
import HCGCore
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Wi-Fi / LAN discovery: DNS-SD browsing and one-shot SSDP search. Started only by the user.
public enum LocalNetworkPolicy {
    public static var hasUsageDescription: Bool { Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") != nil }

    /// Only RFC 1918 / link-local IPv4 hosts are contacted for UPnP descriptions and vendor info.
    public static func isPrivateHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

#if canImport(Network)
public final class BonjourBrowser {
    public static let serviceTypes = ["_airplay._tcp", "_raop._tcp", "_googlecast._tcp", "_hap._tcp", "_matter._tcp", "_matterc._udp", "_meshcop._udp",
                                      "_device-info._tcp", "_ssh._tcp", "_workstation._tcp", "_ipp._tcp", "_smb._tcp", "_companion-link._tcp",
                                      "_mqtt._tcp", "_http._tcp", "_spotify-connect._tcp"]
    static let sensitiveTXT: Set<String> = ["deviceid", "pk", "pi", "psi", "gid", "id", "serialnumber", "sn", "mac", "macaddress", "bid", "rpmrtid"]

    private var browsers: [NWBrowser] = []
    public private(set) var running = false
    public var onEndpoint: ((ObservedEndpoint) -> Void)?
    public var onState: ((String) -> Void)?

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        for type in Self.serviceTypes {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: NWParameters())
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed(let e) = state { self?.onState?("\(type): \(e)") }
                if case .waiting(let e) = state { self?.onState?("\(type): waiting — \(e) (check Local Network permission)") }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                for r in results { if let e = Self.endpoint(r, type: type) { self?.onEndpoint?(e) } }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        onState?("Browsing \(Self.serviceTypes.count) service types")
    }

    public func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        running = false
        onState?("Stopped")
    }

    static func endpoint(_ r: NWBrowser.Result, type: String) -> ObservedEndpoint? {
        guard case let .service(name, _, domain, _) = r.endpoint else { return nil }
        var attrs: [String: String] = ["serviceType": type, "domain": domain]
        var sensitive: [String] = []
        if case let .bonjour(txt) = r.metadata {
            for (k, v) in txt.dictionary {
                let key = k.lowercased()
                switch key {
                case "md", "model", "am", "modelname": attrs["model"] = v
                case "manufacturer", "mf", "vendor": attrs["manufacturer"] = v
                default:
                    guard attrs.count < 24, v.count < 120 else { continue }
                    attrs["txt.\(key)"] = v
                    if sensitiveTXT.contains(key) { sensitive.append("txt.\(key)") }
                }
            }
        }
        return ObservedEndpoint(id: "bonjour:\(type):\(name)", transport: .bonjour, name: name, attributes: attrs, sensitiveKeys: sensitive, provenance: .hardware)
    }
}

/// Set once on a serial queue; lets a callback resume a continuation exactly once.
final class OnceFlag {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Host network interfaces (for the Hardware Requirements Center).
public enum HostNetwork {
    public struct Interface: Hashable { public var name: String; public var type: String; public var hasAddress: Bool }

    public static func interfaces() async -> [Interface] {
        await withCheckedContinuation { (c: CheckedContinuation<[Interface], Never>) in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                let addressed = addressedInterfaceNames()
                let list = path.availableInterfaces.map { i -> Interface in
                    let type: String
                    switch i.type {
                    case .wifi: type = "Wi-Fi"
                    case .wiredEthernet: type = "Ethernet"
                    case .cellular: type = "Cellular"
                    case .loopback: type = "Loopback"
                    default: type = "Other"
                    }
                    return Interface(name: i.name, type: type, hasAddress: addressed.contains(i.name))
                }
                monitor.cancel()
                c.resume(returning: list)
            }
            monitor.start(queue: DispatchQueue(label: "hcg.path"))
        }
    }

    static func addressedInterfaceNames() -> Set<String> {
        var names: Set<String> = []
        #if canImport(Darwin)
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return names }
        defer { freeifaddrs(ifap) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let c = cursor {
            let flags = Int32(c.pointee.ifa_flags)
            if let addr = c.pointee.ifa_addr, (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                let family = Int32(addr.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 { names.insert(String(cString: c.pointee.ifa_name)) }
            }
            cursor = c.pointee.ifa_next
        }
        #endif
        return names
    }
}
#endif

/// One-shot SSDP discovery (standard M-SEARCH to 239.255.255.250:1900). Read-only.
public enum SSDPDiscovery {
    public static func search(timeout: TimeInterval = 3) async -> [ObservedEndpoint] {
        await withCheckedContinuation { (c: CheckedContinuation<[ObservedEndpoint], Never>) in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: searchBlocking(timeout: timeout)) }
        }
    }

    static func searchBlocking(timeout: TimeInterval) -> [ObservedEndpoint] {
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(1900).bigEndian
        dest.sin_addr.s_addr = inet_addr("239.255.255.250")
        let message = Array(SSDPParser.searchRequest.utf8)
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, message, message.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        var found: [String: ObservedEndpoint] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        let capacity = 8192
        var buffer = [UInt8](repeating: 0, count: capacity)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &from) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, raw.baseAddress, capacity, 0, $0, &len) }
                }
            }
            guard n > 0 else { continue }
            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            let address = String(cString: inet_ntoa(from.sin_addr))
            if let e = SSDPParser.endpoint(fromResponse: text, from: address) {
                if var existing = found[e.id] {
                    existing.attributes.merge(e.attributes) { a, _ in a }
                    found[e.id] = existing
                } else {
                    found[e.id] = e
                }
            }
        }
        return Array(found.values)
        #else
        return []
        #endif
    }

    /// Reads UPnP device descriptions (private LAN hosts only) to learn manufacturer and model.
    public static func enrich(_ endpoints: [ObservedEndpoint]) async -> [ObservedEndpoint] {
        var out: [ObservedEndpoint] = []
        for var e in endpoints {
            if let loc = e.attributes["location"], let url = URL(string: loc), let host = url.host, LocalNetworkPolicy.isPrivateHost(host),
               url.scheme == "http" {
                var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
                req.httpMethod = "GET"
                if let (data, _) = try? await URLSession.shared.data(for: req) {
                    let d = SSDPParser.deviceDescription(String(decoding: data.prefix(200_000), as: UTF8.self))
                    if let m = d["manufacturer"] { e.attributes["manufacturer"] = m }
                    if let m = d["modelName"] { e.attributes["model"] = m }
                    if let f = d["friendlyName"] { e.name = f }
                    if let n = d["modelNumber"] { e.attributes["modelNumber"] = n }
                    if let t = d["deviceType"] { e.attributes["deviceType"] = t }
                }
            }
            out.append(e)
        }
        return out
    }
}

/// Read-only vendor and HCG service queries (explicit user actions).
public enum ReadOnlyHTTP {
    /// Samsung Tizen TV device info: GET http://<private-ip>:8001/api/v2/
    public static func samsungTVInfo(host: String) async -> (info: [String: String]?, error: String?, durationMs: Double) {
        guard LocalNetworkPolicy.isPrivateHost(host), let url = URL(string: "http://\(host):8001/api/v2/") else {
            return (nil, "Only private LAN addresses are queried.", 0)
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4))
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            guard (response as? HTTPURLResponse)?.statusCode == 200, let info = SamsungTVInfoParser.parse(data) else {
                return (nil, "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): no device information.", ms)
            }
            return (info, nil, ms)
        } catch {
            return (nil, error.localizedDescription, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }
    }

    /// Public HCG AI handoff document. Sends no device data.
    public static func hcgAIHandoff() async -> HCGAIHandoffStatus {
        guard let url = URL(string: HCGAIHandoffStatus.url) else { return HCGAIHandoffStatus(state: .unexpected, detail: "Invalid URL", apiBaseURL: nil, checkedAt: Date()) }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10))
            return HCGAIHandoffStatus.parse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return HCGAIHandoffStatus(state: .unreachable, detail: error.localizedDescription, apiBaseURL: nil, checkedAt: Date())
        }
    }
}
