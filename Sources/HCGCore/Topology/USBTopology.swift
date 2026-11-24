import Foundation

/// Helpers for reasoning about USB topology from the IOKit `locationID`.
///
/// `locationID` is 0xBBPPPPPP: the top byte is the bus/controller number and each
/// following nibble is a port number along the path from the root hub
/// (0 terminates the path). Example: 0x14120000 = bus 0x14 → port 1 → port 2.
public enum USBTopology {
    public static func portPath(locationID: UInt32) -> [Int] {
        var path: [Int] = []
        for index in 0..<6 {
            let shift = UInt32(20 - index * 4)
            let nibble = Int((locationID >> shift) & 0xF)
            if nibble == 0 { break }
            path.append(nibble)
        }
        return path
    }

    public static func depth(locationID: UInt32) -> Int { portPath(locationID: locationID).count }

    /// The locationID of the upstream hub port, or nil when the device sits on the root hub.
    public static func parentLocationID(of locationID: UInt32) -> UInt32? {
        let d = depth(locationID: locationID)
        guard d > 1 else { return nil }
        let shift = UInt32(20 - (d - 1) * 4)
        return locationID & ~(UInt32(0xF) << shift)
    }

    public static func busNumber(locationID: UInt32) -> Int { Int(locationID >> 24) }
}
