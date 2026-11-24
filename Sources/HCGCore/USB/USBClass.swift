import Foundation

/// USB-IF base class codes (https://www.usb.org/defined-class-codes).
public enum USBClass: Hashable, CustomStringConvertible {
    case perInterface
    case audio
    case communications
    case hid
    case physical
    case image
    case printer
    case massStorage
    case hub
    case cdcData
    case smartCard
    case contentSecurity
    case video
    case personalHealthcare
    case audioVideo
    case billboard
    case typeCBridge
    case diagnostic
    case wirelessController
    case miscellaneous
    case applicationSpecific
    case vendorSpecific
    case other(UInt8)

    public init(code: UInt8) {
        switch code {
        case 0x00: self = .perInterface
        case 0x01: self = .audio
        case 0x02: self = .communications
        case 0x03: self = .hid
        case 0x05: self = .physical
        case 0x06: self = .image
        case 0x07: self = .printer
        case 0x08: self = .massStorage
        case 0x09: self = .hub
        case 0x0A: self = .cdcData
        case 0x0B: self = .smartCard
        case 0x0D: self = .contentSecurity
        case 0x0E: self = .video
        case 0x0F: self = .personalHealthcare
        case 0x10: self = .audioVideo
        case 0x11: self = .billboard
        case 0x12: self = .typeCBridge
        case 0xDC: self = .diagnostic
        case 0xE0: self = .wirelessController
        case 0xEF: self = .miscellaneous
        case 0xFE: self = .applicationSpecific
        case 0xFF: self = .vendorSpecific
        default: self = .other(code)
        }
    }

    public var code: UInt8 {
        switch self {
        case .perInterface: return 0x00
        case .audio: return 0x01
        case .communications: return 0x02
        case .hid: return 0x03
        case .physical: return 0x05
        case .image: return 0x06
        case .printer: return 0x07
        case .massStorage: return 0x08
        case .hub: return 0x09
        case .cdcData: return 0x0A
        case .smartCard: return 0x0B
        case .contentSecurity: return 0x0D
        case .video: return 0x0E
        case .personalHealthcare: return 0x0F
        case .audioVideo: return 0x10
        case .billboard: return 0x11
        case .typeCBridge: return 0x12
        case .diagnostic: return 0xDC
        case .wirelessController: return 0xE0
        case .miscellaneous: return 0xEF
        case .applicationSpecific: return 0xFE
        case .vendorSpecific: return 0xFF
        case .other(let c): return c
        }
    }

    public var name: String {
        switch self {
        case .perInterface: return "Defined per interface"
        case .audio: return "Audio"
        case .communications: return "Communications (CDC)"
        case .hid: return "Human Interface Device"
        case .physical: return "Physical"
        case .image: return "Still Image (PTP/MTP)"
        case .printer: return "Printer"
        case .massStorage: return "Mass Storage"
        case .hub: return "Hub"
        case .cdcData: return "CDC Data"
        case .smartCard: return "Smart Card"
        case .contentSecurity: return "Content Security"
        case .video: return "Video"
        case .personalHealthcare: return "Personal Healthcare"
        case .audioVideo: return "Audio/Video"
        case .billboard: return "USB-C Billboard"
        case .typeCBridge: return "USB-C Bridge"
        case .diagnostic: return "Diagnostic Device"
        case .wirelessController: return "Wireless Controller"
        case .miscellaneous: return "Miscellaneous"
        case .applicationSpecific: return "Application Specific"
        case .vendorSpecific: return "Vendor Specific"
        case .other(let c): return "Unassigned class " + Hex.format8(c)
        }
    }

    public var description: String { name }

    /// Human-readable function for a class/subclass/protocol triple.
    public static func describeInterface(classCode: UInt8, subclass: UInt8, protocolCode: UInt8) -> String {
        switch (classCode, subclass, protocolCode) {
        case (0x03, 0x01, 0x01): return "HID boot keyboard"
        case (0x03, 0x01, 0x02): return "HID boot mouse"
        case (0x03, _, _): return "Human Interface Device"
        case (0x02, 0x02, _): return "CDC ACM serial port"
        case (0x02, 0x06, _): return "CDC Ethernet (ECM)"
        case (0x02, 0x0D, _): return "CDC Network (NCM)"
        case (0x02, _, _): return "Communications control"
        case (0x0A, _, _): return "CDC data channel"
        case (0x06, 0x01, 0x01): return "Still image (PTP / MTP)"
        case (0x08, 0x06, 0x50): return "Mass storage (SCSI, bulk-only)"
        case (0x08, 0x06, 0x62): return "Mass storage (UAS)"
        case (0x08, _, _): return "Mass storage"
        case (0x01, 0x01, _): return "Audio control"
        case (0x01, 0x02, _): return "Audio streaming"
        case (0x01, 0x03, _): return "MIDI streaming"
        case (0x0E, 0x01, _): return "Video control"
        case (0x0E, 0x02, _): return "Video streaming"
        case (0x09, _, _): return "Hub"
        case (0xE0, 0x01, 0x01): return "Bluetooth radio"
        case (0xFE, 0x01, _): return "Device firmware upgrade (DFU)"
        case (0xFF, 0x42, 0x01): return "Android Debug Bridge (ADB) interface"
        case (0xFF, 0x5D, 0x01): return "Xbox-compatible controller (XInput)"
        case (0xFF, 0x47, 0xD0): return "Xbox One controller (GIP)"
        case (0xFF, 0xFE, 0x02): return "Apple mobile device (usbmuxd)"
        case (0xFF, _, _): return "Vendor-specific function"
        case (0x11, _, _): return "USB-C Billboard (alternate mode status)"
        case (0xDC, _, _): return "USB diagnostic"
        default: return USBClass(code: classCode).name
        }
    }
}
