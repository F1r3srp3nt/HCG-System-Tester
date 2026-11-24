import Foundation
import HCGCore
#if canImport(Darwin)
import Darwin
#endif

/// Entry point for the platform's real discovery backends.
public enum HostDiscovery {
    /// Real hardware backends available on this platform. Empty where IOKit does not exist.
    public static func makeHardwareBackends() -> [DeviceDiscoveryBackend] {
        #if canImport(IOKit)
        return [IOKitUSBDiscovery(), IOKitThunderboltDiscovery()]
        #else
        return []
        #endif
    }

    public static var isHardwareDiscoverySupported: Bool {
        #if canImport(IOKit)
        return true
        #else
        return false
        #endif
    }

    /// One-shot USB enumeration (no notifications).
    public static func enumerateUSBOnce() -> [DiscoveredDevice] {
        #if canImport(IOKit)
        return IOKitUSBDiscovery.enumerateOnce()
        #else
        return []
        #endif
    }
}

/// Facts about the host Mac, shown as the root of the Connection Visualizer.
public struct HostInfo: Codable, Hashable {
    public var name: String
    public var modelIdentifier: String
    public var chip: String
    public var memoryBytes: UInt64
    public var osVersion: String
    public var architecture: String

    public static func current() -> HostInfo {
        let process = ProcessInfo.processInfo
        #if os(macOS)
        let name = Host.current().localizedName ?? process.hostName
        #else
        let name = process.hostName
        #endif
        #if arch(arm64)
        let arch = "arm64 (Apple silicon)"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        return HostInfo(name: name, modelIdentifier: sysctlString("hw.model") ?? "Unknown model",
                        chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown chip",
                        memoryBytes: process.physicalMemory, osVersion: process.operatingSystemVersionString, architecture: arch)
    }

    static func sysctlString(_ name: String) -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }
}
