import Foundation

/// A small built-in table of well-known USB vendor IDs. It only names vendors;
/// it never implies that a device is supported.
public enum USBVendorDatabase {
    public static let vendors: [UInt16: String] = [
        0x03EB: "Microchip (Atmel)",
        0x03F0: "HP",
        0x0403: "FTDI",
        0x0409: "NEC",
        0x041E: "Creative",
        0x0424: "Microchip (SMSC)",
        0x045E: "Microsoft",
        0x046D: "Logitech",
        0x04B4: "Cypress / Infineon",
        0x04CA: "Lite-On",
        0x04E8: "Samsung",
        0x04F2: "Chicony",
        0x0483: "STMicroelectronics",
        0x054C: "Sony",
        0x056A: "Wacom",
        0x057E: "Nintendo",
        0x05AC: "Apple",
        0x05E3: "Genesys Logic",
        0x067B: "Prolific",
        0x0781: "SanDisk",
        0x07CA: "AVerMedia",
        0x0951: "Kingston",
        0x0BC2: "Seagate",
        0x0BDA: "Realtek",
        0x0B05: "ASUS",
        0x0FCE: "Sony Mobile",
        0x1050: "Yubico",
        0x1058: "Western Digital",
        0x10C4: "Silicon Labs",
        0x1209: "pid.codes (open hardware)",
        0x12D1: "Huawei",
        0x1532: "Razer",
        0x16C0: "Van Ooijen (V-USB / Teensy)",
        0x174C: "ASMedia",
        0x18D1: "Google",
        0x1915: "Nordic Semiconductor",
        0x1A40: "Terminus Technology",
        0x1A86: "WCH (QinHeng)",
        0x1B1C: "Corsair",
        0x1D6B: "Linux Foundation",
        0x1FC9: "NXP",
        0x2109: "VIA Labs",
        0x2341: "Arduino",
        0x239A: "Adafruit",
        0x22B8: "Motorola",
        0x2717: "Xiaomi",
        0x2A70: "OnePlus",
        0x2B24: "KeepKey",
        0x2E8A: "Raspberry Pi",
        0x2FE3: "Zephyr Project",
        0x303A: "Espressif",
        0x0E8D: "MediaTek",
        0x05C6: "Qualcomm",
        0x8087: "Intel",
        0x8086: "Intel"
    ]

    public static func name(for vendorID: UInt16?) -> String? {
        guard let id = vendorID else { return nil }
        return vendors[id]
    }
}
