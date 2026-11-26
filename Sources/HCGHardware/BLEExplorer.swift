#if canImport(CoreBluetooth) && os(macOS)
import Foundation
import CoreBluetooth
import HCGCore

/// Bluetooth LE discovery and read-only GATT inspection.
///
/// - Scanning starts only when the user asks, and stops on request.
/// - Connecting happens only after explicit approval for one peripheral.
/// - Only allow-listed Device Information and Battery characteristics are read; nothing is ever written.
/// - Requires running from an app bundle with NSBluetoothAlwaysUsageDescription (macOS terminates apps that
///   use Core Bluetooth without it), so `isUsable` is checked first.
public final class BLEExplorer: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public struct Peripheral: Hashable, Identifiable {
        public var id: UUID
        public var name: String
        public var rssi: Int
        public var serviceUUIDs: [String]
        public var manufacturer: String?
        public var connectable: Bool
        public var lastSeen: Date
    }

    public struct ReadResult: Hashable {
        public var connected: Bool
        public var services: [String]
        public var values: [String: String]
        public var errors: [String]
        public var durationMs: Double
    }

    public static var isUsable: Bool { Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil }

    public private(set) var peripherals: [UUID: Peripheral] = [:]
    public private(set) var stateDescription = "Not started"
    public private(set) var poweredOn: Bool?
    public private(set) var scanning = false
    public private(set) var connectedPeripheral: UUID?
    /// Called on the main queue whenever something changes.
    public var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var cbPeripherals: [UUID: CBPeripheral] = [:]
    private var wantScan = false
    private var pending: (id: UUID, started: UInt64, services: [String], values: [String: String], errors: [String],
                          remaining: Int, continuation: CheckedContinuation<ReadResult, Never>)?

    public override init() { super.init() }

    /// Creates the Core Bluetooth manager (this is when macOS asks for Bluetooth permission).
    public func activate() {
        guard Self.isUsable else {
            stateDescription = "Bluetooth needs the app bundle (run from Xcode or scripts/build-app.sh)."
            onChange?()
            return
        }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
    }

    public func startScan() {
        wantScan = true
        activate()
        if central?.state == .poweredOn { beginScan() }
    }

    public func stopScan() {
        wantScan = false
        central?.stopScan()
        scanning = false
        onChange?()
    }

    private func beginScan() {
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanning = true
        onChange?()
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: stateDescription = "Powered on"; poweredOn = true
        case .poweredOff: stateDescription = "Bluetooth is off"; poweredOn = false
        case .unauthorized: stateDescription = "Bluetooth access denied (System Settings › Privacy & Security › Bluetooth)"; poweredOn = false
        case .unsupported: stateDescription = "Bluetooth LE unsupported"; poweredOn = false
        case .resetting: stateDescription = "Resetting"
        default: stateDescription = "Unknown"
        }
        if central.state == .poweredOn && wantScan { beginScan() }
        onChange?()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { BLEAssignedNumbers.shortUUID($0.uuidString) }
        let mfr = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).flatMap(BLEAssignedNumbers.company(fromManufacturerData:))
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed BLE device"
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        cbPeripherals[peripheral.identifier] = peripheral
        peripherals[peripheral.identifier] = Peripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue, serviceUUIDs: services,
                                                        manufacturer: mfr, connectable: connectable, lastSeen: Date())
        onChange?()
    }

    /// Connects (after the user approved), reads allow-listed characteristics, then disconnects.
    public func readInformation(_ id: UUID, timeout: TimeInterval = 15) async -> ReadResult {
        await withCheckedContinuation { (c: CheckedContinuation<ReadResult, Never>) in
            // All Core Bluetooth state is touched on the main queue (the delegate queue).
            DispatchQueue.main.async {
                guard let central = self.central, let p = self.cbPeripherals[id] else {
                    c.resume(returning: ReadResult(connected: false, services: [], values: [:], errors: ["Peripheral not in range (scan first)."], durationMs: 0))
                    return
                }
                guard self.pending == nil else {
                    c.resume(returning: ReadResult(connected: false, services: [], values: [:], errors: ["Another read is in progress."], durationMs: 0))
                    return
                }
                self.pending = (id, DispatchTime.now().uptimeNanoseconds, [], [:], [], 0, c)
                p.delegate = self
                central.connect(p, options: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self = self, self.pending?.id == id else { return }
                    self.pending?.errors.append("Timed out after \(Int(timeout)) s.")
                    self.finish()
                }
            }
        }
    }

    public func disconnect() {
        if let id = connectedPeripheral, let p = cbPeripherals[id] { central?.cancelPeripheralConnection(p) }
    }

    private func finish() {
        guard let p = pending else { return }
        pending = nil
        let ms = Double(DispatchTime.now().uptimeNanoseconds - p.started) / 1_000_000
        if let cb = cbPeripherals[p.id] { central?.cancelPeripheralConnection(cb) }
        p.continuation.resume(returning: ReadResult(connected: !p.services.isEmpty || !p.values.isEmpty, services: p.services,
                                                    values: p.values, errors: p.errors, durationMs: ms))
        onChange?()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral.identifier
        onChange?()
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        pending?.errors.append("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        finish()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral == peripheral.identifier { connectedPeripheral = nil }
        if pending?.id == peripheral.identifier {
            pending?.errors.append("Disconnected by the peripheral\(error.map { ": \($0.localizedDescription)" } ?? "").")
            finish()
        }
        onChange?()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        pending?.services = services.map { BLEAssignedNumbers.shortUUID($0.uuid.uuidString) }
        let targets = services.filter { ["180A", "180F"].contains(BLEAssignedNumbers.shortUUID($0.uuid.uuidString)) }
        if let e = error { pending?.errors.append("Service discovery: \(e.localizedDescription)") }
        if targets.isEmpty { finish(); return }
        pending?.remaining = targets.count
        for s in targets { peripheral.discoverCharacteristics(nil, for: s) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let readable = (service.characteristics ?? []).filter {
            BLEAssignedNumbers.readAllowList.contains(BLEAssignedNumbers.shortUUID($0.uuid.uuidString)) && $0.properties.contains(.read)
        }
        pending?.remaining += readable.count - 1
        for c in readable { peripheral.readValue(for: c) }
        if (pending?.remaining ?? 0) <= 0 { finish() }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = BLEAssignedNumbers.shortUUID(characteristic.uuid.uuidString)
        if let e = error {
            pending?.errors.append("\(BLEAssignedNumbers.characteristics[key] ?? key): \(e.localizedDescription)")
        } else if let data = characteristic.value {
            pending?.values[key] = key == "2A19" ? "\(data.first.map(Int.init) ?? 0) %" : (String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? data.map { Hex.pad(UInt64($0), digits: 2) }.joined())
        }
        pending?.remaining -= 1
        if (pending?.remaining ?? 0) <= 0 { finish() }
    }
}
#endif
