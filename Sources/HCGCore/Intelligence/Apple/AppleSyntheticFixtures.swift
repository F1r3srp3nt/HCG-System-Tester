import Foundation

/// Labelled synthetic Apple fixtures: a fake iPhone on the synthetic bus and a command runner that
/// answers devicectl commands with fixture JSON. Used for demos, CI snapshots and tests. Every
/// value is obviously fictional and every record is marked SYNTHETIC.
public enum AppleSyntheticFixtures {
    public static let udid = "SYNTHETIC-0000-IPHONE16PROMAX"
    public static let coreDeviceID = "SYNTHETIC-COREDEVICE-0001"

    public static let iPhone = DiscoveredDevice(
        id: .synthetic("iphone"), provenance: .synthetic, connectionType: .synthetic,
        name: "[SYNTHETIC] iPhone", manufacturer: "Apple Inc.",
        usb: USBDeviceDescriptor(vendorID: 0x05AC, productID: 0x12A8, vendorName: "Apple Inc.", productName: "iPhone",
                                 serialNumber: CoreDeviceRecord.normalize(udid), deviceClass: 0, bcdDevice: 0x1700, bcdUSB: 0x0320,
                                 speed: .high, locationID: 0xFE500000, interfaces: [
                                    USBInterfaceInfo(number: 0, classCode: 0x06, subclassCode: 0x01, protocolCode: 0x01, attachedServices: []),
                                    USBInterfaceInfo(number: 1, classCode: 0xFF, subclassCode: 0xFE, protocolCode: 0x02, attachedServices: ["AppleUSBHostUsbmux (synthetic)"]),
                                    USBInterfaceInfo(number: 2, classCode: 0x02, subclassCode: 0x0D, protocolCode: 0x00, attachedServices: ["AppleUSBNCMControl (synthetic)"])
                                 ]),
        source: "Synthetic fixture backend", rawProperties: ["fixture": "iphone"])

    public static func listJSON(paired: Bool) -> String {
        """
        {
          "info": { "outcome": "success", "jsonVersion": 2, "version": "synthetic" },
          "result": { "devices": [ \(deviceJSON(paired: paired)) ] }
        }
        """
    }

    public static func detailsJSON() -> String {
        """
        { "info": { "outcome": "success", "jsonVersion": 2 }, "result": \(deviceJSON(paired: true)) }
        """
    }

    static func deviceJSON(paired: Bool) -> String {
        """
        {
          "capabilities": [
            { "featureIdentifier": "com.apple.coredevice.feature.connectdevice", "name": "Connect to Device" },
            { "featureIdentifier": "com.apple.coredevice.feature.listapps", "name": "List Applications" },
            { "featureIdentifier": "com.apple.coredevice.feature.getdeviceinfo", "name": "Get Device Info" }
          ],
          "connectionProperties": {
            "authenticationType": "manualPairing", "isMobileDeviceOnly": false, "pairingState": "\(paired ? "paired" : "unpaired")",
            "transportType": "wired", "tunnelState": "disconnected", "lastConnectionDate": "2026-11-25T09:00:00.000Z"
          },
          "deviceProperties": {
            "bootState": "booted", "ddiServicesAvailable": false, "developerModeStatus": "disabled",
            "name": "[SYNTHETIC] iPhone", "osBuildUpdate": "SYN0001", "osVersionNumber": "99.0"
          },
          "hardwareProperties": {
            "cpuType": { "name": "arm64e", "subType": 2, "type": 16777228 },
            "deviceType": "iPhone", "ecid": 1234, "hardwareModel": "SYN00AP", "internalStorageCapacity": 256000000000,
            "marketingName": "[SYNTHETIC] iPhone 16 Pro Max", "platform": "iOS", "productType": "iPhone17,2", "reality": "physical",
            "serialNumber": "SYNTHETICSN", "udid": "\(udid)"
          },
          "identifier": "\(coreDeviceID)",
          "visibilityClass": "default"
        }
        """
    }
}

/// Answers the Apple adapter's fixed command set with fixture data. Never runs anything.
public final class SyntheticAppleRunner: CommandRunner {
    public var paired: Bool
    public var hasXcode: Bool
    public private(set) var invocations: [[String]] = []
    private let lock = NSLock()

    public init(paired: Bool = true, hasXcode: Bool = true) {
        self.paired = paired
        self.hasXcode = hasXcode
    }

    public func isExecutable(atPath path: String) -> Bool { false }

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        lock.lock(); invocations.append([executable] + arguments); let paired = self.paired; let xcode = hasXcode; lock.unlock()
        func ok(_ s: String = "") -> CommandResult { CommandResult(exitCode: 0, stdout: Data(s.utf8), durationSeconds: 0.042) }
        func write(_ json: String) -> CommandResult {
            if let i = arguments.firstIndex(of: "--json-output"), i + 1 < arguments.count {
                FileManager.default.createFile(atPath: arguments[i + 1], contents: Data(json.utf8))
            }
            return ok()
        }
        if executable.hasSuffix("xcode-select") { return xcode ? ok("/Applications/Xcode.app/Contents/Developer\n") : ok("/Library/Developer/CommandLineTools\n") }
        guard xcode else { return CommandResult(exitCode: 72, stderr: Data("xcrun: error: unable to find utility \"devicectl\"".utf8)) }
        if arguments == ["--find", "devicectl"] { return ok("/Applications/Xcode.app/Contents/Developer/usr/bin/devicectl\n") }
        if arguments == ["devicectl", "--version"] { return ok("synthetic\n") }
        if arguments.last == "--help" { return ok("SUBCOMMANDS:\n  details\n  lockState\n  apps\n  pair\n") }
        if arguments.starts(with: ["devicectl", "list", "devices"]) { return write(AppleSyntheticFixtures.listJSON(paired: paired)) }
        if arguments.starts(with: ["devicectl", "device", "info", "details"]) {
            return paired ? write(AppleSyntheticFixtures.detailsJSON())
                : write(#"{"error":{"code":1,"userInfo":{"NSLocalizedDescription":{"string":"The device is not paired."}}}}"#)
        }
        if arguments.starts(with: ["devicectl", "device", "info", "lockState"]) {
            return write(#"{"info":{"outcome":"success"},"result":{"passcodeRequired":true,"unlockedSinceBoot":true}}"#)
        }
        if arguments.starts(with: ["devicectl", "device", "info", "apps"]) {
            return write(#"{"info":{"outcome":"success"},"result":{"apps":[{"name":"[SYNTHETIC] Sample App","bundleIdentifier":"com.example.synthetic","bundleVersion":"1"}]}}"#)
        }
        if arguments.starts(with: ["devicectl", "manage", "pair"]) {
            lock.lock(); self.paired = true; lock.unlock()
            return write(#"{"info":{"outcome":"success"},"result":{}}"#)
        }
        return CommandResult(exitCode: 64, stderr: Data("unsupported synthetic command".utf8))
    }
}
