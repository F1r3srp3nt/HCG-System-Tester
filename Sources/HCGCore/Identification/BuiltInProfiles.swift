import Foundation

/// First-party device profiles. Facts here are limited to what is publicly
/// documented or directly observable from USB descriptors.
public enum BuiltInProfiles {
    public static let all: [DeviceProfile] = consoles + mobile + serialAndMicrocontrollers + classBased + thunderbolt

    // MARK: Gaming

    static let consoleHostLimitation =
        "Game consoles act as USB hosts. Their USB ports power and talk to accessories; they do not present a diagnostic device interface to a computer. Connecting a Mac directly to a console's USB port (host to host) is not expected to enumerate."

    public static let consoles: [DeviceProfile] = [
        DeviceProfile(
            id: "sony.dualsense", name: "Sony DualSense wireless controller", category: .playStation,
            family: "PlayStation 5 accessories",
            match: DeviceMatchRules(vendorIDs: [0x054C], productIDs: [0x0CE6, 0x0DF2]),
            exposedProtocols: ["usb.descriptor", "usb.hid", "usb.audio"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.playstation-research"],
            knownLimitations: [
                "This is the controller, not the console. Only the controller's USB HID/audio functions are visible.",
                consoleHostLimitation
            ],
            notes: "DualSense enumerates as a USB HID game controller with an audio function.",
            priority: 100),
        DeviceProfile(
            id: "sony.dualshock4", name: "Sony DualShock 4 controller", category: .playStation,
            family: "PlayStation 4 accessories",
            match: DeviceMatchRules(vendorIDs: [0x054C], productIDs: [0x05C4, 0x09CC]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.playstation-research"],
            knownLimitations: ["This is the controller, not the console.", consoleHostLimitation],
            priority: 100),
        DeviceProfile(
            id: "sony.generic", name: "Sony USB device", category: .playStation, family: "Sony",
            match: DeviceMatchRules(vendorIDs: [0x054C]),
            exposedProtocols: ["usb.descriptor"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.playstation-research"],
            knownLimitations: ["Sony vendor ID only — the specific product is not profiled.", consoleHostLimitation],
            priority: 20),
        DeviceProfile(
            id: "microsoft.xbox-controller", name: "Xbox controller", category: .xbox, family: "Xbox accessories",
            match: DeviceMatchRules(vendorIDs: [0x045E], productIDs: [0x028E, 0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B12]),
            exposedProtocols: ["usb.descriptor", "usb.vendor-gip"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.xbox-research"],
            knownLimitations: [
                "This is the controller, not the console.",
                "Xbox One/Series controllers use Microsoft's vendor-specific GIP protocol over USB. macOS supports them through the Game Controller framework; descriptor-level diagnostics only here.",
                consoleHostLimitation
            ],
            priority: 100),
        DeviceProfile(
            id: "microsoft.xbox-gip", name: "Xbox-compatible controller (GIP/XInput)", category: .xbox, family: "Xbox accessories",
            match: DeviceMatchRules(interfaceTriples: ["FF.47.D0", "FF.5D.01"]),
            exposedProtocols: ["usb.descriptor", "usb.vendor-gip"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.xbox-research"],
            knownLimitations: ["Identified by its Xbox-style interface; may be a third-party controller.", consoleHostLimitation],
            priority: 60),
        DeviceProfile(
            id: "nintendo.pro-controller", name: "Nintendo Switch Pro Controller", category: .nintendo, family: "Nintendo Switch accessories",
            match: DeviceMatchRules(vendorIDs: [0x057E], productIDs: [0x2009]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            knownLimitations: ["This is the controller, not the console.", consoleHostLimitation],
            priority: 100),
        DeviceProfile(
            id: "nintendo.generic", name: "Nintendo USB device", category: .nintendo, family: "Nintendo",
            match: DeviceMatchRules(vendorIDs: [0x057E]),
            exposedProtocols: ["usb.descriptor"],
            knownLimitations: ["Nintendo vendor ID only — the specific product is not profiled."],
            priority: 20)
    ]

    // MARK: Phones and tablets

    public static let mobile: [DeviceProfile] = [
        DeviceProfile(
            id: "apple.iphone", name: "Apple iPhone", category: .smartphone, family: "Apple mobile devices",
            match: DeviceMatchRules(vendorIDs: [0x05AC], nameContains: ["iPhone"]),
            exposedProtocols: ["usb.descriptor", "usb.ptp", "apple.usbmux", "apple.coredevice"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.apple-device-intelligence"],
            knownLimitations: [
                "Model, OS and service information need the iPhone to trust this Mac (Trust This Computer / pairing) and Xcode's devicectl.",
                "System Tester never bypasses the passcode, pairing, USB Restricted Mode or Activation Lock."
            ],
            priority: 90),
        DeviceProfile(
            id: "apple.ipad", name: "Apple iPad", category: .tablet, family: "Apple mobile devices",
            match: DeviceMatchRules(vendorIDs: [0x05AC], nameContains: ["iPad"]),
            exposedProtocols: ["usb.descriptor", "usb.ptp", "apple.usbmux", "apple.coredevice"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.apple-device-intelligence"],
            knownLimitations: ["Model, OS and service information need the iPad to trust this Mac and Xcode's devicectl."],
            priority: 90),
        DeviceProfile(
            id: "android.adb", name: "Android device (USB debugging enabled)", category: .smartphone, family: "Android",
            match: DeviceMatchRules(interfaceTriples: ["FF.42.01"]),
            exposedProtocols: ["usb.descriptor", "android.adb"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.android"],
            knownLimitations: [
                "An ADB interface is present. Communication requires the user to accept this Mac's RSA key on the phone.",
                "System Tester does not bundle adb; the Android adapter is a planned integration."
            ],
            priority: 70),
        DeviceProfile(
            id: "mobile.mtp", name: "Phone or tablet (MTP/PTP file transfer)", category: .smartphone, family: "Mobile devices",
            match: DeviceMatchRules(vendorIDs: [0x04E8, 0x18D1, 0x22B8, 0x12D1, 0x2717, 0x2A70, 0x0FCE, 0x0E8D, 0x05C6], interfaceClasses: [0x06]),
            exposedProtocols: ["usb.descriptor", "usb.ptp"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.android"],
            knownLimitations: ["macOS has no built-in MTP client; file access needs a dedicated MTP adapter."],
            priority: 60),
        DeviceProfile(
            id: "mobile.vendor", name: "Mobile device (vendor match)", category: .smartphone, family: "Mobile devices",
            match: DeviceMatchRules(vendorIDs: [0x04E8, 0x18D1, 0x22B8, 0x12D1, 0x2717, 0x2A70, 0x0FCE]),
            exposedProtocols: ["usb.descriptor"],
            knownLimitations: ["Matched by vendor only; may be a phone in charge-only mode or another product from the same vendor."],
            priority: 15)
    ]

    // MARK: Serial & microcontrollers

    public static let serialAndMicrocontrollers: [DeviceProfile] = [
        DeviceProfile(
            id: "mcu.arduino", name: "Arduino board", category: .microcontroller, family: "Arduino",
            match: DeviceMatchRules(vendorIDs: [0x2341, 0x2A03]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-acm"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            priority: 80),
        DeviceProfile(
            id: "mcu.espressif", name: "Espressif ESP32 (native USB)", category: .microcontroller, family: "Espressif",
            match: DeviceMatchRules(vendorIDs: [0x303A]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-acm"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            priority: 80),
        DeviceProfile(
            id: "mcu.raspberrypi", name: "Raspberry Pi microcontroller (RP2040/RP2350)", category: .microcontroller, family: "Raspberry Pi",
            match: DeviceMatchRules(vendorIDs: [0x2E8A]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-acm", "usb.msc"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            knownLimitations: ["In BOOTSEL mode the board appears as a mass-storage drive (RPI-RP2) instead of a serial port."],
            priority: 80),
        DeviceProfile(
            id: "mcu.adafruit", name: "Adafruit board", category: .microcontroller, family: "Adafruit",
            match: DeviceMatchRules(vendorIDs: [0x239A]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-acm"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            priority: 80),
        DeviceProfile(
            id: "serial.bridge", name: "USB-to-serial bridge", category: .microcontroller, family: "Serial bridges (FTDI / CP210x / CH34x / PL2303)",
            match: DeviceMatchRules(vendorIDs: [0x0403, 0x10C4, 0x1A86, 0x067B]),
            exposedProtocols: ["usb.descriptor", "usb.vendor-serial"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            knownLimitations: [
                "The bridge chip is identified, not the board behind it.",
                "Some bridges (older CH34x/PL2303) need a vendor driver; System Tester never installs drivers."
            ],
            priority: 70),
        DeviceProfile(
            id: "serial.cdc-acm", name: "USB CDC serial device", category: .microcontroller, family: "CDC ACM",
            match: DeviceMatchRules(interfaceTriples: ["02.02.00", "02.02.01", "02.02.02", "02.02.FF"]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-acm"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-serial"],
            priority: 40)
    ]

    // MARK: Class-based (generic)

    public static let classBased: [DeviceProfile] = [
        DeviceProfile(
            id: "generic.hub", name: "USB hub", category: .usbInfrastructure, family: "Hubs", role: .usbHub,
            match: DeviceMatchRules(deviceClasses: [0x09]),
            exposedProtocols: ["usb.descriptor", "usb.hub"],
            knownLimitations: ["Hubs are infrastructure: devices behind them appear as their children in the topology."],
            priority: 30),
        DeviceProfile(
            id: "generic.storage", name: "USB mass-storage device", category: .storage, family: "Mass storage",
            match: DeviceMatchRules(interfaceClasses: [0x08]),
            exposedProtocols: ["usb.descriptor", "usb.msc"],
            recommendedAdapters: ["com.hakmicapitalgroup.adapter.usb-storage"],
            knownLimitations: ["Health data (SMART) is generally not available through USB bridges on macOS."],
            priority: 30),
        DeviceProfile(
            id: "generic.ethernet", name: "USB network adapter", category: .networkEquipment, family: "USB Ethernet",
            match: DeviceMatchRules(interfaceTriples: ["02.06.00", "02.0D.00"]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-ncm"],
            priority: 35),
        DeviceProfile(
            id: "realtek.ethernet", name: "Realtek USB Ethernet adapter", category: .networkEquipment, family: "USB Ethernet",
            match: DeviceMatchRules(vendorIDs: [0x0BDA], productIDs: [0x8153, 0x8156, 0x8152]),
            exposedProtocols: ["usb.descriptor", "usb.cdc-ncm"],
            priority: 90),
        DeviceProfile(
            id: "generic.bluetooth", name: "USB Bluetooth radio", category: .networkEquipment, family: "Bluetooth",
            match: DeviceMatchRules(interfaceTriples: ["E0.01.01"]),
            exposedProtocols: ["usb.descriptor"],
            knownLimitations: ["macOS manages Bluetooth radios itself; third-party dongles are often unsupported on Apple silicon."],
            priority: 35),
        DeviceProfile(
            id: "generic.billboard", name: "USB-C alternate-mode device (Billboard)", category: .usbInfrastructure, family: "USB-C",
            match: DeviceMatchRules(interfaceClasses: [0x11]),
            exposedProtocols: ["usb.descriptor"],
            knownLimitations: ["A Billboard interface usually means a USB-C alternate mode (e.g. DisplayPort) was offered; it may indicate the mode was not entered."],
            priority: 25),
        DeviceProfile(
            id: "yubico.key", name: "Yubico security key", category: .inputDevice, family: "Security keys",
            match: DeviceMatchRules(vendorIDs: [0x1050]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            knownLimitations: ["System Tester never reads credentials from security keys."],
            priority: 80),
        DeviceProfile(
            id: "generic.keyboard", name: "USB keyboard", category: .inputDevice, family: "HID",
            match: DeviceMatchRules(interfaceTriples: ["03.01.01"]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            knownLimitations: ["Keystrokes are never captured. HID diagnostics are descriptor-level only."],
            priority: 25),
        DeviceProfile(
            id: "generic.mouse", name: "USB pointing device", category: .inputDevice, family: "HID",
            match: DeviceMatchRules(interfaceTriples: ["03.01.02"]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            priority: 25),
        DeviceProfile(
            id: "generic.hid", name: "USB HID device", category: .inputDevice, family: "HID",
            match: DeviceMatchRules(interfaceClasses: [0x03]),
            exposedProtocols: ["usb.descriptor", "usb.hid"],
            priority: 10),
        DeviceProfile(
            id: "generic.audio", name: "USB audio device", category: .audio, family: "USB Audio",
            match: DeviceMatchRules(interfaceClasses: [0x01]),
            exposedProtocols: ["usb.descriptor", "usb.audio"],
            priority: 20),
        DeviceProfile(
            id: "generic.video", name: "USB video device (UVC)", category: .camera, family: "USB Video",
            match: DeviceMatchRules(interfaceClasses: [0x0E]),
            exposedProtocols: ["usb.descriptor", "usb.uvc"],
            knownLimitations: ["System Tester does not open camera streams."],
            priority: 22),
        DeviceProfile(
            id: "generic.still-image", name: "Camera (PTP still image)", category: .camera, family: "PTP",
            match: DeviceMatchRules(interfaceClasses: [0x06]),
            exposedProtocols: ["usb.descriptor", "usb.ptp"],
            priority: 12),
        DeviceProfile(
            id: "generic.printer", name: "USB printer", category: .industrial, family: "Printers",
            match: DeviceMatchRules(interfaceClasses: [0x07]),
            exposedProtocols: ["usb.descriptor"],
            priority: 20),
        DeviceProfile(
            id: "generic.smartcard", name: "Smart-card reader", category: .inputDevice, family: "CCID",
            match: DeviceMatchRules(interfaceClasses: [0x0B]),
            exposedProtocols: ["usb.descriptor"],
            knownLimitations: ["Card contents are never read."],
            priority: 20)
    ]

    public static let thunderbolt: [DeviceProfile] = [
        DeviceProfile(
            id: "thunderbolt.device", name: "Thunderbolt / USB4 device", category: .usbInfrastructure, family: "Thunderbolt",
            match: DeviceMatchRules(connectionTypes: [.thunderbolt]),
            exposedProtocols: ["thunderbolt.registry"],
            knownLimitations: ["Only switch-level registry data is read. PCIe and DisplayPort tunnels are not inspected."],
            priority: 10)
    ]
}
