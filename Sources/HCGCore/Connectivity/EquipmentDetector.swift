import Foundation

/// Facts about this Mac used to detect equipment. Gathered by the app; pure logic here (testable).
public struct HostFacts {
    public var bluetoothPoweredOn: Bool?
    public var activeNetworkInterfaces: [String]
    public var usbDevices: [DiscoveredDevice]
    public var toolchain: AppleToolchainStatus?
    public var existingPaths: Set<String>

    public init(bluetoothPoweredOn: Bool? = nil, activeNetworkInterfaces: [String] = [], usbDevices: [DiscoveredDevice] = [],
                toolchain: AppleToolchainStatus? = nil, existingPaths: Set<String> = []) {
        self.bluetoothPoweredOn = bluetoothPoweredOn
        self.activeNetworkInterfaces = activeNetworkInterfaces
        self.usbDevices = usbDevices
        self.toolchain = toolchain
        self.existingPaths = existingPaths
    }

    public static let probedPaths = ["/Applications/PS Remote Play.app", "/Applications/Arduino IDE.app", "/opt/homebrew/bin/arduino-cli",
                                     "/usr/local/bin/arduino-cli", "/opt/homebrew/bin/ros2", "/opt/ros", "/opt/homebrew/bin/mosquitto_sub",
                                     "/usr/local/bin/mosquitto_sub"]
}

public enum EquipmentDetector {
    public static func detect(_ f: HostFacts, at date: Date = Date()) -> [String: EquipmentStatus] {
        var out: [String: EquipmentStatus] = [:]
        func set(_ id: String, _ a: EquipmentAvailability, _ why: String) { out[id] = EquipmentStatus(a, why, at: date) }
        let hw = f.usbDevices.filter { $0.provenance == .hardware && $0.isPresent }

        switch f.bluetoothPoweredOn {
        case .some(true): set("interface.bluetooth", .detected, "Core Bluetooth reports the controller powered on.")
        case .some(false): set("interface.bluetooth", .missing, "Bluetooth is off or access was denied (System Settings › Bluetooth / Privacy).")
        case .none: break
        }
        if !f.activeNetworkInterfaces.isEmpty {
            set("interface.wifi-or-ethernet", .detected, "Active interface(s): " + f.activeNetworkInterfaces.joined(separator: ", "))
        }
        if hw.contains(where: { $0.usb != nil }) {
            set("cable.usbc-data", .detected, "Inferred: \(hw.filter { $0.usb != nil }.count) USB device(s) enumerated, so a data-capable link exists. Cable speed is inferred per device from the negotiated link.")
        }
        if hw.contains(where: { $0.thunderbolt != nil }) { set("cable.thunderbolt", .detected, "Inferred: a Thunderbolt switch is connected.") }
        if let t = f.toolchain {
            if t.hasDevicectl { set("software.xcode", .detected, t.summary) } else { set("software.xcode", .missing, t.problems.first ?? "devicectl not found.") }
            if let p = t.ideviceinfoPath { set("software.libimobiledevice", .detected, p) }
        }
        if f.existingPaths.contains("/Applications/PS Remote Play.app") { set("software.ps-remote-play", .detected, "/Applications/PS Remote Play.app") }
        if let p = ["/Applications/Arduino IDE.app", "/opt/homebrew/bin/arduino-cli", "/usr/local/bin/arduino-cli"].first(where: f.existingPaths.contains) {
            set("software.arduino-cli", .detected, p)
        }
        if let p = ["/opt/homebrew/bin/ros2", "/opt/ros"].first(where: f.existingPaths.contains) { set("software.ros2", .detected, p) }
        if let p = ["/opt/homebrew/bin/mosquitto_sub", "/usr/local/bin/mosquitto_sub"].first(where: f.existingPaths.contains) { set("software.mqtt-client", .detected, p) }
        if let bridge = hw.first(where: { [0x10C4, 0x0403, 0x1A86, 0x067B].contains($0.usb?.vendorID ?? 0) }) {
            set("adapter.usb-ttl-3v3", .detected, "USB-serial bridge present (\(bridge.displayName)). Logic voltage cannot be verified by software.")
        }
        if let reader = hw.first(where: { $0.usb?.allClassCodes.contains(0x0B) ?? false }) {
            set("reader.nfc", .detected, "Smart-card (CCID) reader present: \(reader.displayName). NFC capability not verified.")
        }
        return out
    }
}
