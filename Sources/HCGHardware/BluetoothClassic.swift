#if canImport(IOBluetooth) && os(macOS)
import Foundation
import IOBluetooth
import HCGCore

/// Read-only list of Bluetooth Classic devices already paired with this Mac (pairing stays in System Settings).
public enum BluetoothClassicInventory {
    public static func pairedDevices() -> [ObservedEndpoint] {
        guard BLEExplorer.isUsable else { return [] }
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        return devices.map { d in
            let address = d.addressString ?? "unknown"
            return ObservedEndpoint(id: "bt-classic:\(address)", transport: .bluetoothClassic, name: d.name ?? "Bluetooth device",
                                    attributes: ["address": address, "connected": d.isConnected() ? "yes" : "no",
                                                 "classOfDevice": Hex.format32(UInt32(d.classOfDevice))],
                                    sensitiveKeys: ["address"], provenance: .hardware)
        }
    }
}
#endif
