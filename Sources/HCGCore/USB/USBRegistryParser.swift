import Foundation

/// Converts an IORegistry property dictionary (as returned by
/// `IORegistryEntryCreateCFProperties`) into a typed `USBDeviceDescriptor`.
///
/// Kept platform-neutral so the parsing logic is unit-tested without hardware.
public enum USBRegistryParser {
    public enum Key {
        public static let vendorID = "idVendor"
        public static let productID = "idProduct"
        public static let vendorNames = ["USB Vendor Name", "kUSBVendorString"]
        public static let productNames = ["USB Product Name", "kUSBProductString"]
        public static let serialNumbers = ["USB Serial Number", "kUSBSerialNumberString"]
        public static let deviceClass = "bDeviceClass"
        public static let deviceSubClass = "bDeviceSubClass"
        public static let deviceProtocol = "bDeviceProtocol"
        public static let bcdDevice = "bcdDevice"
        public static let bcdUSB = "bcdUSB"
        public static let speed = "Device Speed"
        public static let speedAlternates = ["USBSpeed", "UsbDeviceSpeed"]
        public static let locationID = "locationID"
        public static let configurationCount = "bNumConfigurations"
        public static let builtIn = "Built-In"
        public static let interfaceNumber = "bInterfaceNumber"
        public static let alternateSetting = "bAlternateSetting"
        public static let interfaceClass = "bInterfaceClass"
        public static let interfaceSubClass = "bInterfaceSubClass"
        public static let interfaceProtocol = "bInterfaceProtocol"
        public static let interfaceNames = ["USB Interface Name", "kUSBString"]
    }

    /// Keys copied into `DiscoveredDevice.rawProperties` as evidence.
    public static let evidenceKeys: [String] = [
        "idVendor", "idProduct", "USB Vendor Name", "USB Product Name", "kUSBVendorString", "kUSBProductString",
        "USB Serial Number", "kUSBSerialNumberString", "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol",
        "bcdDevice", "bcdUSB", "Device Speed", "locationID", "bNumConfigurations", "sessionID", "Built-In",
        "kUSBCurrentConfiguration", "IOClass", "UsbPowerSinkAllocation", "UsbPowerSourceAllocation"
    ]

    public static func parseDevice(properties: [String: Any], registryEntryID: UInt64?, ioClassName: String?,
                                   registryName: String? = nil) -> USBDeviceDescriptor {
        var d = USBDeviceDescriptor()
        d.vendorID = uint16(properties[Key.vendorID])
        d.productID = uint16(properties[Key.productID])
        d.vendorName = firstString(properties, Key.vendorNames)
        d.productName = firstString(properties, Key.productNames) ?? nonEmpty(registryName)
        d.serialNumber = firstString(properties, Key.serialNumbers)
        d.deviceClass = uint8(properties[Key.deviceClass])
        d.deviceSubClass = uint8(properties[Key.deviceSubClass])
        d.deviceProtocol = uint8(properties[Key.deviceProtocol])
        d.bcdDevice = uint16(properties[Key.bcdDevice])
        d.bcdUSB = uint16(properties[Key.bcdUSB])
        if let raw = int(properties[Key.speed]) ?? Key.speedAlternates.lazy.compactMap({ int(properties[$0]) }).first {
            d.speed = USBSpeed(rawValue: raw)
        }
        d.locationID = uint32(properties[Key.locationID])
        d.registryEntryID = registryEntryID
        d.configurationCount = int(properties[Key.configurationCount])
        d.ioClassName = ioClassName
        d.isBuiltIn = bool(properties[Key.builtIn]) ?? false
        return d
    }

    public static func parseInterface(properties: [String: Any], attachedServices: [String]) -> USBInterfaceInfo? {
        guard let cls = uint8(properties[Key.interfaceClass]) else { return nil }
        return USBInterfaceInfo(
            number: int(properties[Key.interfaceNumber]) ?? 0,
            alternateSetting: int(properties[Key.alternateSetting]) ?? 0,
            classCode: cls,
            subclassCode: uint8(properties[Key.interfaceSubClass]) ?? 0,
            protocolCode: uint8(properties[Key.interfaceProtocol]) ?? 0,
            name: firstString(properties, Key.interfaceNames),
            attachedServices: attachedServices
        )
    }

    /// Builds the evidence dictionary (stringified) from raw properties.
    public static func evidence(from properties: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for key in evidenceKeys {
            guard let value = properties[key] else { continue }
            out[key] = stringify(value)
        }
        return out
    }

    /// Produces the user-facing name: product string, else vendor + class, else a neutral label.
    public static func displayName(for d: USBDeviceDescriptor) -> String {
        if let p = nonEmpty(d.productName) { return p }
        let vendor = nonEmpty(d.vendorName) ?? USBVendorDatabase.name(for: d.vendorID)
        if let v = vendor { return "\(v) USB device" }
        return "Unnamed USB device \(d.vendorIDHex):\(d.productIDHex)"
    }

    // MARK: - Tolerant value conversion (NSNumber, Int, String, Data)

    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Int64: return Int(truncatingIfNeeded: v)
        case let v as UInt64: return Int(truncatingIfNeeded: v)
        case let v as UInt32: return Int(v)
        case let v as Int32: return Int(v)
        case let v as UInt16: return Int(v)
        case let v as UInt8: return Int(v)
        case let v as NSNumber: return v.intValue
        case let v as String:
            let t = v.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
            return Int(t)
        default: return nil
        }
    }

    public static func uint8(_ value: Any?) -> UInt8? { int(value).flatMap { UInt8(exactly: $0) } }
    public static func uint16(_ value: Any?) -> UInt16? { int(value).flatMap { UInt16(exactly: $0) } }
    public static func uint32(_ value: Any?) -> UInt32? {
        switch value {
        case let v as UInt32: return v
        case let v as NSNumber: return v.uint32Value
        default: return int(value).flatMap { UInt32(truncatingIfNeeded: $0) }
        }
    }

    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let v as Bool: return v
        case let v as NSNumber: return v.boolValue
        case let v as String: return ["yes", "true", "1"].contains(v.lowercased())
        default: return nil
        }
    }

    public static func firstString(_ properties: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = properties[key] as? String, let t = nonEmpty(s) { return t }
        }
        return nil
    }

    public static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    public static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let d as Data: return d.map { Hex.pad(UInt64($0), digits: 2) }.joined(separator: " ")
        case let n as NSNumber: return n.stringValue
        default: return String(describing: value)
        }
    }
}
